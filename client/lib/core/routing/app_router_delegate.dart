import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/team_model.dart';
import 'app_route_path.dart';
import 'app_pages.dart';
import '../../auth_state.dart';
import '../../team_provider.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey;
  final AuthState authState;
  final TeamProvider teamProvider;

  AppRoutePath _currentPathConfig;
  AppRoutePath? _previousPathBeforeTaskDetail;
  AppRoutePath? _parsedPathFromUrlWhileLoading;

  AppRouterDelegate({required this.authState, required this.teamProvider})
      : navigatorKey = GlobalKey<NavigatorState>(),
        _currentPathConfig = const LoadingPath() {
    authState.addListener(_onAuthStateChanged);
    debugPrint("[RouterDelegate] Initialized. Current path: LoadingPath.");

    // Если к моменту инициализации делегата, authState уже все проверил.
    if (authState.initialAuthCheckCompleted) {
      _currentPathConfig = _getAppropriatePathForCurrentState(null)!;
      debugPrint("[RouterDelegate] Constructor: Auth already completed. Initial path set to: ${_currentPathConfig.runtimeType}");
      if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
        Future.microtask(() => _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath));
      }
    }
  }

  // Главная функция принятия решений о пути на основе текущего состояния.
  AppRoutePath? _getAppropriatePathForCurrentState(AppRoutePath? intendedPath) {
    debugPrint("[RouterDelegate] _getAppropriatePathForCurrentState: Intended: ${intendedPath?.runtimeType}, Current: ${_currentPathConfig.runtimeType}, isLoggedIn: ${authState.isLoggedIn}");

    // Если пользователь залогинен
    if (authState.isLoggedIn) {
      // 1. Обрабатываем токен приглашения в приоритете
      if (authState.pendingInviteToken != null) {
        return JoinTeamByTokenPath(authState.pendingInviteToken!);
      }
      // 2. Если пытаются попасть на страницы для неавторизованных, редиректим на home
      if (intendedPath is AuthPath || (intendedPath is LandingPath && kIsWeb)) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }
      // 3. Если это валидный путь для залогиненного, используем его
      if (intendedPath is HomePath || intendedPath is HomeSubPath || intendedPath is TeamDetailPath || intendedPath is TaskDetailPath || intendedPath is JoinTeamProcessingPath) {
        return intendedPath;
      }
      // 4. Если мы пришли с Loading, Auth или Landing, но intendedPath не задан - идем на home
      if (_currentPathConfig is LoadingPath || _currentPathConfig is AuthPath || _currentPathConfig is LandingPath) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }
      // 5. В остальных случаях, если intendedPath невалиден, остаемся на текущем пути
      return _currentPathConfig;
    }
    // Если пользователь НЕ залогинен
    else {
      // 1. Если пришли с токеном, сохраняем его и идем на Auth
      if (intendedPath is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(intendedPath.token);
        return const AuthPath();
      }
      // 2. Разрешаем только Auth и Landing (для веба)
      if (intendedPath is AuthPath || (intendedPath is LandingPath && kIsWeb)) {
        return intendedPath;
      }
      // 3. Все остальные пути ведут на Landing (веб) или Auth (мобильные)
      return kIsWeb ? const LandingPath() : const AuthPath();
    }
  }


  void _onAuthStateChanged() {
    debugPrint("[RouterDelegate] Auth state changed. LoggedIn: ${authState.isLoggedIn}, CheckCompleted: ${authState.initialAuthCheckCompleted}");

    if (!authState.initialAuthCheckCompleted) {
      // Если по какой-то причине проверка сбросилась, показываем загрузку
      _currentPathConfig = const LoadingPath();
      notifyListeners();
      return;
    }

    // Если был запарсен URL пока шла проверка, используем его
    final pathFromUrl = _parsedPathFromUrlWhileLoading;
    _parsedPathFromUrlWhileLoading = null; // Используем его только один раз

    _currentPathConfig = _getAppropriatePathForCurrentState(pathFromUrl)!;

    if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
      // Немедленно начинаем обработку токена
      _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath);
    } else {
      notifyListeners();
    }
  }

  @override
  AppRoutePath get currentConfiguration => _currentPathConfig;

  @override
  Widget build(BuildContext context) {
    debugPrint("[RouterDelegate.build] Building navigator for path: ${_currentPathConfig.runtimeType}");
    final pages = buildPagesForPath(_currentPathConfig, authState);

    return Navigator(
      key: navigatorKey,
      pages: pages,
      onPopPage: (route, result) {
        if (!route.didPop(result)) {
          return false;
        }

        if (_currentPathConfig is TaskDetailPath) {
          _currentPathConfig = _previousPathBeforeTaskDetail ?? const HomeSubPath(AppRouteSegments.allTasks);
          _previousPathBeforeTaskDetail = null;
        } else if (_currentPathConfig is TeamDetailPath) {
          _currentPathConfig = const HomeSubPath(AppRouteSegments.teams);
        } else if (_currentPathConfig is JoinTeamProcessingPath) {
          _currentPathConfig = const HomeSubPath(AppRouteSegments.teams);
        } else {
          // Для других случаев pop, если это возможно, RouterDelegate сам обработает.
          // Если мы хотим кастомную логику, то здесь нужно определить предыдущий путь.
          // Пока что этого достаточно.
          return false;
        }

        notifyListeners();
        return true;
      },
    );
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    debugPrint("[RouterDelegate] setNewRoutePath received: ${configuration.runtimeType}");

    if (!authState.initialAuthCheckCompleted) {
      // Если аутентификация еще не проверена, сохраняем запрошенный путь
      _parsedPathFromUrlWhileLoading = configuration;
      // Если в URL есть токен, сохраняем его сразу
      if (configuration is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(configuration.token);
      }
      debugPrint("[RouterDelegate] Auth check pending. Stashed path: ${configuration.runtimeType}");
      return;
    }

    // AuthState уже известен, принимаем решение немедленно
    _currentPathConfig = _getAppropriatePathForCurrentState(configuration)!;

    // Если это путь с токеном и пользователь залогинен, обрабатываем его
    if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
      await _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath);
    } else {
      notifyListeners();
    }
  }

  void navigateTo(AppRoutePath path) {
    // Внутренняя навигация, setNewRoutePath не вызывается платформой, а нами.
    setNewRoutePath(path);
  }

  Future<void> _handleJoinTeamByTokenPath(JoinTeamByTokenPath path) async {
    debugPrint("[RouterDelegate] Handling JoinTeamByTokenPath: ${path.token}");

    // Переключаемся на экран загрузки
    _currentPathConfig = const JoinTeamProcessingPath();
    notifyListeners();

    // Даем Flutter перестроиться
    await Future.delayed(Duration.zero);

    Team? joinedTeam;
    String? joinError;
    try {
      joinedTeam = await teamProvider.joinTeamByToken(path.token);
      authState.clearPendingInviteToken();

      if (joinedTeam != null) {
        _currentPathConfig = TeamDetailPath(joinedTeam.teamId);
      } else {
        joinError = teamProvider.error ?? "Не удалось присоединиться к команде.";
        _currentPathConfig = const HomeSubPath(AppRouteSegments.teams);
      }
    } catch (e) {
      authState.clearPendingInviteToken();
      joinError = "Ошибка: ${e.toString()}";
      _currentPathConfig = const HomeSubPath(AppRouteSegments.teams);
    }

    // Показываем SnackBar с результатом
    final currentContext = navigatorKey.currentContext;
    if (currentContext != null && currentContext.mounted) {
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(
          content: Text(joinedTeam != null ? 'Вы успешно присоединились к команде "${joinedTeam.name}"!' : 'Ошибка: $joinError'),
          backgroundColor: joinedTeam != null ? Colors.green : Theme.of(currentContext).colorScheme.error,
        ),
      );
    }

    notifyListeners();
  }

  @override
  Future<bool> popRoute() {
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) {
      return SynchronousFuture(false);
    }

    if (_currentPathConfig is LandingPath && kIsWeb && !navigator.canPop()) {
      return SynchronousFuture(false);
    }
    if (_currentPathConfig is AuthPath && !kIsWeb && !navigator.canPop()) {
      return SynchronousFuture(false);
    }
    if (authState.isLoggedIn && (_currentPathConfig is HomePath || _currentPathConfig is HomeSubPath) && !navigator.canPop()){
      return SynchronousFuture(false);
    }

    AppRoutePath newPathAfterPop;

    if (_currentPathConfig is TaskDetailPath) {
      newPathAfterPop = _previousPathBeforeTaskDetail ??
          (authState.isLoggedIn
              ? const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true)
              : (kIsWeb ? const LandingPath() : const AuthPath()));
      _previousPathBeforeTaskDetail = null;
    } else if (_currentPathConfig is TeamDetailPath) {
      newPathAfterPop = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
    } else if (_currentPathConfig is JoinTeamProcessingPath) {
      newPathAfterPop = authState.isLoggedIn
          ? const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true)
          : (kIsWeb ? const LandingPath() : const AuthPath());
    } else if (_currentPathConfig is AuthPath && kIsWeb) {
      newPathAfterPop = const LandingPath();
    } else if (navigator.canPop()) { // Если есть что pop'ать в системном навигаторе
      navigator.pop();
      // После navigator.pop() текущая страница удалена из стека pages Navigator'а.
      // _currentPathConfig должен быть обновлен на основе того, что теперь наверху.
      // Это сложно сделать здесь без доступа к внутренностям Navigator'а или pages.
      // Поэтому, если мы делаем системный pop, мы должны доверять, что build()
      // и buildPagesForPath() затем правильно отразят новое состояние.
      // Чтобы это сработало, notifyListeners() должен быть вызван, чтобы build() перестроился.
      // Но кто обновит _currentPathConfig?
      // Это проблема. onPopPage в Navigator'е должен обновлять _currentPathConfig.
      // Если мы не хотим полагаться на onPopPage, мы должны сами вычислить предыдущий путь.
      // Пока что, для системного pop, мы не будем менять _currentPathConfig здесь,
      // а положимся на onPopPage, который вызовет notifyListeners.
      debugPrint("AppRouterDelegate.popRoute: System pop executed. _currentPathConfig might be stale until next build triggered by onPopPage's notifyListeners.");
      return SynchronousFuture(true); // Мы обработали запрос на pop
    }
    else { // Больше некуда идти назад по нашей логике, и системный навигатор тоже не может
      return SynchronousFuture(false);
    }

    setNewRoutePath(newPathAfterPop); // Вызываем setNewRoutePath для обновления и уведомления
    return SynchronousFuture(true);
  }


  bool canPop() {
    if (_currentPathConfig is LandingPath && kIsWeb && !(navigatorKey.currentState?.canPop() ?? false) ) {
      return false;
    }
    if (_currentPathConfig is AuthPath && !kIsWeb && !(navigatorKey.currentState?.canPop() ?? false) ) {
      return false;
    }
    if (authState.isLoggedIn && (_currentPathConfig is HomePath || _currentPathConfig is HomeSubPath) && !(navigatorKey.currentState?.canPop() ?? false)){
      return false;
    }
    if (_currentPathConfig is TaskDetailPath ||
        _currentPathConfig is TeamDetailPath ||
        _currentPathConfig is JoinTeamProcessingPath ||
        (_currentPathConfig is AuthPath && kIsWeb)
    ) {
      return true;
    }
    return navigatorKey.currentState?.canPop() ?? false;
  }

  @override
  void dispose() {
    authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  MaterialPage _createPage(Widget child, ValueKey key, String name, {Object? arguments}) {
    return MaterialPage(
      child: child,
      key: key,
      name: name,
      arguments: arguments,
    );
  }
}