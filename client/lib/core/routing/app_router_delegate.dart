// lib/core/routing/app_router_delegate.dart
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

    if (authState.initialAuthCheckCompleted) {
      _currentPathConfig = _getAppropriatePathForCurrentState(null);
      debugPrint("[RouterDelegate] Constructor: Auth already completed. Initial path set to: ${_currentPathConfig.runtimeType}");
      if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
        Future.microtask(() => _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath));
      }
    }
  }

  // Главная функция принятия решений о пути на основе текущего состояния.
  AppRoutePath _getAppropriatePathForCurrentState(AppRoutePath? intendedPath) {
    debugPrint("[RouterDelegate] _getAppropriatePathForCurrentState: Intended: ${intendedPath?.runtimeType}, Current: ${_currentPathConfig.runtimeType}, isLoggedIn: ${authState.isLoggedIn}");

    // Если authState еще не завершил проверку, всегда показываем загрузку.
    if (!authState.initialAuthCheckCompleted) {
      return const LoadingPath();
    }

    // Если это коллбэк OAuth, он всегда должен обрабатываться, независимо от статуса логина.
    if (intendedPath is OAuthCallbackPath) {
      return intendedPath;
    }

    // Если пользователь залогинен
    if (authState.isLoggedIn) {
      // 1. Обрабатываем токен приглашения в приоритете
      if (authState.pendingInviteToken != null) {
        return JoinTeamByTokenPath(authState.pendingInviteToken!);
      }
      // 2. Если пытаются попасть на страницы для неавторизованных, редиректим на home
      if (intendedPath is AuthPath || intendedPath is LandingPath || intendedPath is OAuthCallbackPath) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }
      // 3. Если это валидный путь для залогиненного, используем его
      if (intendedPath is HomePath || intendedPath is HomeSubPath || intendedPath is TeamDetailPath || intendedPath is TaskDetailPath || intendedPath is JoinTeamProcessingPath) {
        return intendedPath!;
      }
      // 4. Если мы пришли с Loading, Auth, Landing или OAuthCallback, но intendedPath не задан - идем на home
      if (_currentPathConfig is LoadingPath || _currentPathConfig is AuthPath || _currentPathConfig is LandingPath || _currentPathConfig is OAuthCallbackPath) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }
      // 5. В остальных случаях, если intendedPath невалиден, остаемся на текущем пути
      return _currentPathConfig;
    }
    // Если пользователь НЕ залогинен
    else {
      // 1. Если это коллбэк OAuth, разрешаем его
      if (intendedPath is OAuthCallbackPath) {
        return intendedPath;
      }
      // 2. Если пришли с токеном приглашения, сохраняем его и идем на Auth
      if (intendedPath is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(intendedPath.token);
        return const AuthPath();
      }
      // 3. В вебе разрешаем явно посетить страницу лендинга
      if (kIsWeb && intendedPath is LandingPath) {
        return const LandingPath();
      }
      // 4. Все остальные пути ведут на страницу аутентификации.
      return const AuthPath();
    }
  }


  void _onAuthStateChanged() {
    debugPrint("[RouterDelegate] Auth state changed. LoggedIn: ${authState.isLoggedIn}, CheckCompleted: ${authState.initialAuthCheckCompleted}");

    if (!authState.initialAuthCheckCompleted) {
      _currentPathConfig = const LoadingPath();
      notifyListeners();
      return;
    }

    final pathFromUrl = _parsedPathFromUrlWhileLoading;
    _parsedPathFromUrlWhileLoading = null;

    _currentPathConfig = _getAppropriatePathForCurrentState(pathFromUrl ?? _currentPathConfig);

    if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
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

        if (pages.length > 1) {
          if (_currentPathConfig is TaskDetailPath) {
            _currentPathConfig = _previousPathBeforeTaskDetail ?? const HomeSubPath(AppRouteSegments.allTasks);
            _previousPathBeforeTaskDetail = null;
          } else if (_currentPathConfig is TeamDetailPath) {
            _currentPathConfig = const HomeSubPath(AppRouteSegments.teams);
          } else {
            _currentPathConfig = const HomeSubPath(AppRouteSegments.allTasks);
          }
          notifyListeners();
          return true;
        }

        return false;
      },
    );
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    debugPrint("[RouterDelegate] setNewRoutePath received: ${configuration.runtimeType}");

    if (!authState.initialAuthCheckCompleted) {
      _parsedPathFromUrlWhileLoading = configuration;
      if (configuration is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(configuration.token);
      }
      debugPrint("[RouterDelegate] Auth check pending. Stashed path: ${configuration.runtimeType}");
      return;
    }

    _currentPathConfig = _getAppropriatePathForCurrentState(configuration);

    if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
      await _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath);
    } else {
      notifyListeners();
    }
  }

  void navigateTo(AppRoutePath path) {
    if (path is TaskDetailPath) {
      _previousPathBeforeTaskDetail = _currentPathConfig;
    }
    setNewRoutePath(path);
  }

  Future<void> _handleJoinTeamByTokenPath(JoinTeamByTokenPath path) async {
    debugPrint("[RouterDelegate] Handling JoinTeamByTokenPath: ${path.token}");

    _currentPathConfig = const JoinTeamProcessingPath();
    notifyListeners();

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
    return navigator.maybePop();
  }

  bool canPop() {
    return navigatorKey.currentState?.canPop() ?? false;
  }

  @override
  void dispose() {
    authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }
}