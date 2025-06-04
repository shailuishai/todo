// lib/core/routing/app_router_delegate.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/team_model.dart'; // Используется в _handleJoinTeamByTokenPath
import '../../screens/auth_screen.dart';
import '../../screens/landing_screen.dart';
import 'app_route_path.dart';
import 'app_pages.dart'; // buildPagesForPath теперь здесь
import '../../auth_state.dart';
import '../../team_provider.dart';
// Экраны импортируются в app_pages.dart или используются через buildPagesForPath

class LoadingPath extends AppRoutePath {
  const LoadingPath();
}

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey;
  final AuthState authState;
  final TeamProvider teamProvider;

  AppRoutePath _currentPathConfig;
  AppRoutePath? _previousPathBeforeTaskDetail;
  AppRoutePath? _parsedPathFromUrlDuringLoading;

  AppRouterDelegate({required this.authState, required this.teamProvider})
      : navigatorKey = GlobalKey<NavigatorState>(),
        _currentPathConfig = const LoadingPath() {
    authState.addListener(_onAuthStateChanged);
    debugPrint("AppRouterDelegate Initialized: currentPathConfig=LoadingPath. Waiting for authState.initialAuthCheckCompleted.");
    if (authState.initialAuthCheckCompleted) {
      _currentPathConfig = _determineAppropriatePath(null); // Передаем null, т.к. _parsedPathFromUrlDuringLoading еще не установлен
      debugPrint("AppRouterDelegate Constructor: Auth already completed. Initial path set to: ${_currentPathConfig.runtimeType}");
      if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
        Future.microtask(() => _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath));
      }
    }
  }

  AppRoutePath _determineAppropriatePath(AppRoutePath? parsedPathFromUrl) {
    // Если parsedPathFromUrl не null, используем его, иначе _parsedPathFromUrlDuringLoading
    final AppRoutePath? pathFromUrl = parsedPathFromUrl ?? _parsedPathFromUrlDuringLoading;
    debugPrint("AppRouterDelegate._determineAppropriatePath: Determining path. Current _currentPathConfig: ${_currentPathConfig.runtimeType}, isLoggedIn: ${authState.isLoggedIn}, pathFromUrl: ${pathFromUrl?.runtimeType}, pendingInviteToken: ${authState.pendingInviteToken}");

    AppRoutePath determinedPath;

    if (pathFromUrl != null) {
      debugPrint("AppRouterDelegate._determineAppropriatePath: Processing pathFromUrl: ${pathFromUrl.runtimeType}");
      if (pathFromUrl is LandingPath && kIsWeb) {
        determinedPath = pathFromUrl;
      } else if (pathFromUrl is LandingPath && !kIsWeb) {
        determinedPath = const AuthPath();
      } else if (!authState.isLoggedIn) {
        if (pathFromUrl is AuthPath || pathFromUrl is JoinTeamByTokenPath) {
          if (pathFromUrl is JoinTeamByTokenPath) authState.setPendingInviteToken(pathFromUrl.token);
          determinedPath = const AuthPath();
        } else {
          determinedPath = kIsWeb ? const LandingPath() : const AuthPath();
        }
      } else { // Пользователь залогинен
        if (pathFromUrl is AuthPath || (pathFromUrl is LandingPath && kIsWeb)) {
          determinedPath = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        } else if (authState.pendingInviteToken != null && pathFromUrl is! JoinTeamByTokenPath && pathFromUrl is! JoinTeamProcessingPath) {
          determinedPath = JoinTeamByTokenPath(authState.pendingInviteToken!);
        } else {
          determinedPath = pathFromUrl; // Используем парсенный путь
        }
      }
    } else { // pathFromUrl is null, _parsedPathFromUrlDuringLoading тоже был null
      if (authState.isLoggedIn) {
        if (authState.pendingInviteToken != null && _currentPathConfig is! JoinTeamProcessingPath && _currentPathConfig is! JoinTeamByTokenPath) {
          determinedPath = JoinTeamByTokenPath(authState.pendingInviteToken!);
        } else if ((_currentPathConfig is AuthPath) || (_currentPathConfig is LandingPath && kIsWeb) || _currentPathConfig is LoadingPath || _currentPathConfig is UnknownPath) {
          determinedPath = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        } else {
          determinedPath = _currentPathConfig;
        }
      } else {
        if ((_currentPathConfig is AuthPath) || (_currentPathConfig is LandingPath && kIsWeb)) {
          determinedPath = _currentPathConfig;
        } else {
          determinedPath = kIsWeb ? const LandingPath() : const AuthPath();
        }
      }
    }
    debugPrint("AppRouterDelegate._determineAppropriatePath: Path resolved to: ${determinedPath.runtimeType}");
    return determinedPath;
  }

  void _onAuthStateChanged() {
    debugPrint("AppRouterDelegate._onAuthStateChanged: AuthState changed. initialAuthCheckCompleted=${authState.initialAuthCheckCompleted}, isLoggedIn=${authState.isLoggedIn}, pendingInviteToken=${authState.pendingInviteToken}, currentPathConfig before: ${_currentPathConfig.runtimeType}");

    if (!authState.initialAuthCheckCompleted) {
      if (_currentPathConfig is! LoadingPath) {
        _currentPathConfig = const LoadingPath();
        notifyListeners();
        debugPrint("AppRouterDelegate._onAuthStateChanged: Auth not complete. Set to LoadingPath.");
      }
      return;
    }

    AppRoutePath newPathDetermined = _determineAppropriatePath(null); // Передаем null, т.к. URL не менялся, а только authState
    if (_parsedPathFromUrlDuringLoading != null && newPathDetermined.runtimeType == _parsedPathFromUrlDuringLoading.runtimeType) {
      // Если _determineAppropriatePath вернул _parsedPathFromUrlDuringLoading, очищаем его.
      // Это для случая, когда _onAuthStateChanged вызывается после того, как URL был запарсен, но до того, как _parsedPathFromUrlDuringLoading был использован.
      _parsedPathFromUrlDuringLoading = null;
    }


    if (_currentPathConfig is LandingPath && newPathDetermined is LandingPath && kIsWeb) {
      debugPrint("AppRouterDelegate._onAuthStateChanged: Staying on LandingPage (web) as new path is also LandingPath.");
      if (_currentPathConfig is LoadingPath) {
        _currentPathConfig = newPathDetermined;
        notifyListeners();
      }
      return;
    }

    bool pathActuallyNeedsUpdate = _currentPathConfig.runtimeType != newPathDetermined.runtimeType;
    if (!pathActuallyNeedsUpdate) {
      // ... (логика сравнения содержимого pathActuallyNeedsUpdate остается той же)
      if (newPathDetermined is HomeSubPath && _currentPathConfig is HomeSubPath) {
        pathActuallyNeedsUpdate = !((newPathDetermined).subRoute == (_currentPathConfig as HomeSubPath).subRoute &&
            (newPathDetermined).showRightSidebar == (_currentPathConfig as HomeSubPath).showRightSidebar);
      } else if (newPathDetermined is TaskDetailPath && _currentPathConfig is TaskDetailPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).taskId != (_currentPathConfig as TaskDetailPath).taskId;
      } else if (newPathDetermined is TeamDetailPath && _currentPathConfig is TeamDetailPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).teamId != (_currentPathConfig as TeamDetailPath).teamId;
      } else if (newPathDetermined is JoinTeamByTokenPath && _currentPathConfig is JoinTeamByTokenPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).token != (_currentPathConfig as JoinTeamByTokenPath).token;
      }
    }

    if (pathActuallyNeedsUpdate) {
      debugPrint("AppRouterDelegate._onAuthStateChanged: Path effectively changing from ${_currentPathConfig.runtimeType} to ${newPathDetermined.runtimeType}");
      _currentPathConfig = newPathDetermined;

      if ((_currentPathConfig is AuthPath || _currentPathConfig is LandingPath) && _previousPathBeforeTaskDetail != null) {
        _previousPathBeforeTaskDetail = null;
      }

      if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
        _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath);
      } else {
        notifyListeners();
      }
    } else {
      debugPrint("AppRouterDelegate._onAuthStateChanged: Path effectively not changed. Current is ${_currentPathConfig.runtimeType}, proposed new was ${newPathDetermined.runtimeType}");
    }
  }

  @override
  AppRoutePath get currentConfiguration => _currentPathConfig;

  @override
  Widget build(BuildContext context) {
    List<Page<dynamic>> pages;
    // Этот debugPrint очень важен для отладки стека страниц
    debugPrint("AppRouterDelegate.build: START. currentPathConfig=${_currentPathConfig.runtimeType}, authState.isLoggedIn=${authState.isLoggedIn}, authState.initialAuthCheckCompleted=${authState.initialAuthCheckCompleted}");

    // ВАЖНО: Передаем _currentPathConfig, который УЖЕ должен быть актуализирован через _onAuthStateChanged или setNewRoutePath
    pages = buildPagesForPath(_currentPathConfig, authState);

    if (pages.isEmpty) {
      debugPrint("AppRouterDelegate.build: CRITICAL - pages list was empty. Defaulting to ${kIsWeb ? 'Landing' : 'Auth'}. Current path: ${_currentPathConfig.runtimeType}");
      pages.add(_createPage(
          kIsWeb ? const LandingScreen() : AuthScreen(pendingInviteToken: authState.pendingInviteToken),
          ValueKey(kIsWeb ? 'FallbackLandingPage' : 'FallbackAuthPage'),
          kIsWeb ? AppRoutes.landing : AppRoutes.auth
      ));
    }
    debugPrint("AppRouterDelegate.build: END. Pages count: ${pages.length}. Last page key: ${pages.last.key}, Current URL config from path: ${_currentPathConfig.runtimeType}");

    return Navigator(
      key: navigatorKey,
      pages: List.unmodifiable(pages),
      onPopPage: (route, result) {
        // ... (логика onPopPage) ...
        if (!route.didPop(result)) {
          return false;
        }
        debugPrint("AppRouterDelegate.onPopPage: Popping page ${route.settings.name}. Current path before pop: ${_currentPathConfig.runtimeType}");

        AppRoutePath newPathAfterPop;

        if (pages.length == 1) { // Была единственная страница, и мы ее "убрали" (хотя Navigator этого не позволит, если canPop false)
          if ((_currentPathConfig is LandingPath && kIsWeb) ||
              (_currentPathConfig is AuthPath && !kIsWeb && !authState.isLoggedIn) ||
              ((_currentPathConfig is HomeSubPath || _currentPathConfig is HomePath) && authState.isLoggedIn)
          ) {
            debugPrint("AppRouterDelegate.onPopPage: Attempting to pop the only/root page (${_currentPathConfig.runtimeType}). Denied by framework or custom canPop.");
            return false;
          }
        }

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
        } else if (pages.length > 1) {
          // Пытаемся восстановить путь из предыдущей страницы в стеке (которая теперь верхняя)
          final previousPage = pages[pages.length - 2]; // Страница до той, что была удалена
          // Эта логика восстановления пути по имени страницы не очень надежна.
          // Лучше, если setNewRoutePath будет правильно устанавливать _currentPathConfig.
          // onPopPage Navigator'а УЖЕ изменил `pages`.
          // Мы должны здесь определить, какому AppRoutePath соответствует новая ВЕРХНЯЯ страница.
          // Это сложно без обратного маппинга Page -> AppRoutePath.

          // Временное упрощение: если мы не знаем, куда идти, идем на дефолтный
          if (authState.isLoggedIn) {
            newPathAfterPop = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
          } else {
            newPathAfterPop = kIsWeb ? const LandingPath() : const AuthPath();
          }
          debugPrint("AppRouterDelegate.onPopPage: Fallback after pop. New path: ${newPathAfterPop.runtimeType}");

        } else { // Осталась одна страница (или 0, что не должно быть)
          newPathAfterPop = authState.isLoggedIn
              ? const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true)
              : (kIsWeb ? const LandingPath() : const AuthPath());
          debugPrint("AppRouterDelegate.onPopPage: Popped to last page. New path: ${newPathAfterPop.runtimeType}");
        }

        _currentPathConfig = newPathAfterPop;
        notifyListeners();
        return true;
      },
    );
  }

  Future<void> _handleJoinTeamByTokenPath(JoinTeamByTokenPath path) async {
    // ... (без изменений)
    debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Processing token ${path.token}");

    _currentPathConfig = const JoinTeamProcessingPath();
    notifyListeners();

    await Future.delayed(Duration.zero);

    Team? joinedTeam;
    String? joinError;

    try {
      joinedTeam = await teamProvider.joinTeamByToken(path.token);
      authState.clearPendingInviteToken();

      if (joinedTeam != null) {
        debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Successfully joined team ${joinedTeam.teamId}. Navigating to team details.");
        _currentPathConfig = TeamDetailPath(joinedTeam.teamId);
      } else {
        joinError = teamProvider.error ?? "Не удалось присоединиться к команде. Токен недействителен или срок его действия истек.";
        debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Failed to join team. Error: $joinError. Navigating to teams list.");
        _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
      }
    } catch (e) {
      authState.clearPendingInviteToken();
      joinError = "Неизвестная ошибка при присоединении к команде: $e";
      debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Exception during join: $joinError. Navigating to teams list.");
      _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
    }

    final currentContext = navigatorKey.currentContext;
    if (currentContext != null && currentContext.mounted) {
      if (joinedTeam != null) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Вы успешно присоединились к команде "${joinedTeam.name}"!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (joinError != null) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Ошибка присоединения: $joinError'),
            backgroundColor: Theme.of(currentContext).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
        if(teamProvider.error != null) teamProvider.clearError();
      }
    }
    notifyListeners();
  }


  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    debugPrint("[AppRouterDelegate.setNewRoutePath] Received new configuration: ${configuration.runtimeType}");

    // 1. Если это LandingPath и веб, устанавливаем его и выходим.
    if (configuration is LandingPath && kIsWeb) {
      if (!(_currentPathConfig is LandingPath)) {
        _currentPathConfig = const LandingPath();
        _parsedPathFromUrlDuringLoading = null; // Очищаем, так как путь установлен
        debugPrint("AppRouterDelegate.setNewRoutePath: Path set to LandingPath (web). Notifying.");
        notifyListeners();
      } else {
        debugPrint("AppRouterDelegate.setNewRoutePath: Path already LandingPath (web). No notification.");
        _parsedPathFromUrlDuringLoading = null; // Все равно очищаем
      }
      return;
    }
    // Если это LandingPath, но не веб, перенаправляем на AuthPath
    if (configuration is LandingPath && !kIsWeb) {
      if (!(_currentPathConfig is AuthPath)) {
        _currentPathConfig = const AuthPath();
        _parsedPathFromUrlDuringLoading = null;
        debugPrint("AppRouterDelegate.setNewRoutePath: LandingPath on non-web, redirecting to AuthPath. Notifying.");
        notifyListeners();
      }
      return;
    }

    // 2. Если authState еще не инициализирован, сохраняем путь и выходим
    if (!authState.initialAuthCheckCompleted) {
      _parsedPathFromUrlDuringLoading = configuration; // Сохраняем для _determineAppropriatePath
      if (configuration is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(configuration.token);
      }
      // _currentPathConfig остается LoadingPath
      debugPrint("AppRouterDelegate.setNewRoutePath: Auth loading. Stored requested path: ${configuration.runtimeType} in _parsedPathFromUrlDuringLoading. Current is LoadingPath.");
      return;
    }

    // AuthState уже инициализирован.
    // Определяем новый путь на основе configuration и текущего состояния authState.
    AppRoutePath newPath = configuration;

    if (authState.isLoggedIn) {
      // Если залогинен и пытается попасть на Auth или Landing (веб) -> Home
      if ((configuration is AuthPath) || (configuration is LandingPath && kIsWeb)) {
        newPath = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        debugPrint("AppRouterDelegate.setNewRoutePath: User logged in, received ${configuration.runtimeType}. Redirecting to Home.");
      }
      // Если есть pendingInviteToken и configuration еще не путь его обработки
      else if (authState.pendingInviteToken != null && configuration is! JoinTeamByTokenPath && configuration is! JoinTeamProcessingPath) {
        newPath = JoinTeamByTokenPath(authState.pendingInviteToken!);
        debugPrint("AppRouterDelegate.setNewRoutePath: User logged in, has pending invite. Path set to JoinTeamByTokenPath.");
      }
      // Иначе, если configuration это JoinTeamByTokenPath, он будет обработан ниже
    } else { // Не залогинен
      // Если пытается попасть не на Auth и не на Landing (веб) -> редирект
      if (configuration is! AuthPath && !(configuration is LandingPath && kIsWeb)) {
        if (configuration is JoinTeamByTokenPath) { // Если это Join-токен, сохраняем и идем на Auth
          authState.setPendingInviteToken(configuration.token);
          newPath = const AuthPath();
          debugPrint("AppRouterDelegate.setNewRoutePath: User NOT logged in, received JoinTeamByTokenPath. Stored token. Redirecting to Auth.");
        } else { // Для всех других путей - на Landing (веб) или Auth (натив)
          newPath = kIsWeb ? const LandingPath() : const AuthPath();
          debugPrint("AppRouterDelegate.setNewRoutePath: User NOT logged in, received ${configuration.runtimeType}. Redirecting to ${newPath.runtimeType}.");
        }
      }
      // Если configuration уже AuthPath или LandingPath (веб), то newPath не меняется
    }

    // Обработка JoinTeamByTokenPath, если newPath стал им
    if (newPath is JoinTeamByTokenPath && authState.isLoggedIn) {
      await _handleJoinTeamByTokenPath(newPath);
      return;
    }

    // Сохранение предыдущего пути для TaskDetail
    if (newPath is TaskDetailPath && _currentPathConfig is! TaskDetailPath) {
      if (_currentPathConfig is HomePath || _currentPathConfig is HomeSubPath || _currentPathConfig is TeamDetailPath) {
        _previousPathBeforeTaskDetail = _currentPathConfig;
      }
    }

    bool configActuallyChanged = _currentPathConfig.runtimeType != newPath.runtimeType;
    if (!configActuallyChanged) {
      // ... (логика сравнения содержимого такая же)
      if (newPath is HomeSubPath && _currentPathConfig is HomeSubPath) {
        final currentCasted = _currentPathConfig as HomeSubPath;
        final newCasted = newPath;
        configActuallyChanged = !((currentCasted.subRoute == newCasted.subRoute && currentCasted.showRightSidebar == newCasted.showRightSidebar));
      } else if (newPath is TaskDetailPath && _currentPathConfig is TaskDetailPath) {
        configActuallyChanged = (_currentPathConfig as TaskDetailPath).taskId != newPath.taskId;
      } else if (newPath is TeamDetailPath && _currentPathConfig is TeamDetailPath) {
        configActuallyChanged = (_currentPathConfig as TeamDetailPath).teamId != newPath.teamId;
      }
    }

    if (configActuallyChanged) {
      _currentPathConfig = newPath;
      debugPrint("AppRouterDelegate.setNewRoutePath: END. Path changed to ${_currentPathConfig.runtimeType}. Notifying listeners.");
      notifyListeners();
    } else {
      debugPrint("AppRouterDelegate.setNewRoutePath: END. Path effectively NOT changed. Current: ${_currentPathConfig.runtimeType}, New (after processing): ${newPath.runtimeType}. No notification.");
    }
    _parsedPathFromUrlDuringLoading = null; // Очищаем здесь, так как setNewRoutePath вызвался когда authState.initialAuthCheckCompleted = true
  }

  void navigateTo(AppRoutePath path) {
    setNewRoutePath(path);
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