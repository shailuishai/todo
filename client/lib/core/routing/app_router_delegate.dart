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

  AppRoutePath _getAppropriatePathForCurrentState(AppRoutePath? intendedPath) {
    debugPrint("[RouterDelegate] _getAppropriatePathForCurrentState: Intended: ${intendedPath?.runtimeType}, Current: ${_currentPathConfig.runtimeType}, isLoggedIn: ${authState.isLoggedIn}");

    if (!authState.initialAuthCheckCompleted) {
      return const LoadingPath();
    }

    if (intendedPath is LandingPath) {
      return const LandingPath();
    }

    if (intendedPath is OAuthCallbackPath) {
      return intendedPath;
    }

    if (authState.isLoggedIn) {
      if (authState.pendingInviteToken != null) {
        return JoinTeamByTokenPath(authState.pendingInviteToken!);
      }

      if (intendedPath is AuthPath) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }

      if (intendedPath != null) {
        if (intendedPath is! AuthPath) {
          return intendedPath;
        }
      }

      if (_currentPathConfig is AuthPath || _currentPathConfig is LoadingPath || _currentPathConfig is OAuthCallbackPath) {
        return const HomeSubPath(AppRouteSegments.allTasks);
      }

      return _currentPathConfig;
    }
    else {
      if (intendedPath is OAuthCallbackPath) {
        return intendedPath;
      }
      if (intendedPath is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(intendedPath.token);
        return const AuthPath();
      }
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
            // Возвращаемся на главную страницу по умолчанию
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
    if (path is TaskDetailPath || path is TeamDetailPath || (path is HomeSubPath && path.subRoute != AppRouteSegments.teams && path.subRoute != AppRouteSegments.allTasks && path.subRoute != AppRouteSegments.settings)) {
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
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return SynchronousFuture(true);
    }

    // Если навигатор не может сделать pop, проверяем, можем ли мы вернуться на предыдущий "главный" экран
    if (_previousPathBeforeTaskDetail != null) {
      _currentPathConfig = _previousPathBeforeTaskDetail!;
      _previousPathBeforeTaskDetail = null;
      notifyListeners();
      return SynchronousFuture(true);
    }

    return SynchronousFuture(false);
  }

  bool canPop() {
    return (navigatorKey.currentState?.canPop() ?? false) || _previousPathBeforeTaskDetail != null;
  }

  @override
  void dispose() {
    authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }
}