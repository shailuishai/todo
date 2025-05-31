// lib/core/routing/app_router_delegate.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/team_model.dart';
import 'app_route_path.dart';
import 'app_pages.dart';
import '../../auth_state.dart';
import '../../team_provider.dart'; // <<< ДОБАВЛЕН ИМПОРТ TEAMPROVIDER >>>
import '../../screens/auth_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/task_detail_screen.dart';
import '../../screens/join_team_landing_screen.dart'; // <<< ИМПОРТ ЭКРАНА ЗАГЛУШКИ >>>


class LoadingPath extends AppRoutePath {
  const LoadingPath();
}

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey;
  final AuthState authState;
  final TeamProvider teamProvider; // <<< ДОБАВЛЕНО ПОЛЕ TEAMPROVIDER >>>


  AppRoutePath _currentPathConfig;
  AppRoutePath? _previousPathBeforeTaskDetail;
  AppRoutePath? _parsedPathFromUrlDuringLoading;

  AppRouterDelegate({required this.authState, required this.teamProvider}) // <<< ОБНОВЛЕН КОНСТРУКТОР >>>
      : navigatorKey = GlobalKey<NavigatorState>(),
        _currentPathConfig = !authState.initialAuthCheckCompleted
            ? const LoadingPath()
            : (authState.isLoggedIn
            ? const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true)
            : const AuthPath()) {
    authState.addListener(_onAuthStateChanged);
    debugPrint("AppRouterDelegate Initialized: initialAuthCheckCompleted=${authState.initialAuthCheckCompleted}, isLoggedIn=${authState.isLoggedIn}, currentPathConfig=${_currentPathConfig.runtimeType}");
  }

  void _onAuthStateChanged() {
    debugPrint("AppRouterDelegate._onAuthStateChanged: AuthState changed. initialAuthCheckCompleted=${authState.initialAuthCheckCompleted}, isLoggedIn=${authState.isLoggedIn}, pendingInviteToken=${authState.pendingInviteToken}");

    if (!authState.initialAuthCheckCompleted) {
      if (_currentPathConfig is! LoadingPath) {
        _currentPathConfig = const LoadingPath();
        notifyListeners();
      }
      return;
    }

    AppRoutePath newPathDetermined;
    if (!authState.isLoggedIn) {
      // Если пользователь не залогинен, и есть pendingInviteToken,
      // AuthScreen должен будет его показать. AuthPath уже содержит этот токен.
      newPathDetermined = const AuthPath();
      _previousPathBeforeTaskDetail = null; // Сбрасываем, т.к. вышли из системы
    } else { // Пользователь залогинен
      if (authState.pendingInviteToken != null && _currentPathConfig is! JoinTeamByTokenPath && _currentPathConfig is! JoinTeamProcessingPath) {
        // Если есть pendingInviteToken, и мы еще не в процессе его обработки,
        // значит, пользователь только что залогинился. Переходим к обработке токена.
        debugPrint("AppRouterDelegate._onAuthStateChanged: Logged in WITH pendingInviteToken '${authState.pendingInviteToken}'. Setting path to JoinTeamByTokenPath for processing.");
        newPathDetermined = JoinTeamByTokenPath(authState.pendingInviteToken!);
        // Токен будет очищен в _handleJoinTeamByTokenPath
      } else if (_parsedPathFromUrlDuringLoading != null &&
          (_parsedPathFromUrlDuringLoading is HomePath ||
              _parsedPathFromUrlDuringLoading is HomeSubPath ||
              _parsedPathFromUrlDuringLoading is TaskDetailPath ||
              _parsedPathFromUrlDuringLoading is TeamDetailPath ||
              _parsedPathFromUrlDuringLoading is JoinTeamByTokenPath || // <<< УЧИТЫВАЕМ PARSED JOIN_TEAM_TOKEN_PATH >>>
              _parsedPathFromUrlDuringLoading is JoinTeamProcessingPath )) {
        newPathDetermined = _parsedPathFromUrlDuringLoading!;
        _parsedPathFromUrlDuringLoading = null; // Используем один раз
        debugPrint("AppRouterDelegate._onAuthStateChanged: Using _parsedPathFromUrlDuringLoading: ${newPathDetermined.runtimeType}");
      }
      else if (_currentPathConfig is HomePath || // Остаемся на текущем валидном пути, если он уже установлен
          _currentPathConfig is HomeSubPath ||
          _currentPathConfig is TaskDetailPath ||
          _currentPathConfig is TeamDetailPath ||
          _currentPathConfig is JoinTeamByTokenPath || // Может быть, если обработка уже идет
          _currentPathConfig is JoinTeamProcessingPath) {
        newPathDetermined = _currentPathConfig;
        debugPrint("AppRouterDelegate._onAuthStateChanged: Staying on current valid path: ${newPathDetermined.runtimeType}");
      }
      else { // Дефолтный путь, если ничего не подошло
        newPathDetermined = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        debugPrint("AppRouterDelegate._onAuthStateChanged: Defaulting to AllTasks path.");
      }
    }
    _parsedPathFromUrlDuringLoading = null; // Очищаем в любом случае после первой проверки


    // Сравниваем новый определенный путь с текущим, чтобы избежать лишних notifyListeners
    bool pathActuallyNeedsUpdate = true;
    if (newPathDetermined.runtimeType == _currentPathConfig.runtimeType) {
      // Сравнение содержимого путей, если типы совпадают
      if (newPathDetermined is HomeSubPath && _currentPathConfig is HomeSubPath) {
        pathActuallyNeedsUpdate = !((newPathDetermined).subRoute == (_currentPathConfig as HomeSubPath).subRoute &&
            (newPathDetermined).showRightSidebar == (_currentPathConfig as HomeSubPath).showRightSidebar);
      } else if (newPathDetermined is TaskDetailPath && _currentPathConfig is TaskDetailPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).taskId != (_currentPathConfig as TaskDetailPath).taskId;
      } else if (newPathDetermined is TeamDetailPath && _currentPathConfig is TeamDetailPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).teamId != (_currentPathConfig as TeamDetailPath).teamId;
      } else if (newPathDetermined is JoinTeamByTokenPath && _currentPathConfig is JoinTeamByTokenPath) {
        pathActuallyNeedsUpdate = (newPathDetermined).token != (_currentPathConfig as JoinTeamByTokenPath).token;
      } else if (newPathDetermined is AuthPath && _currentPathConfig is AuthPath) {
        pathActuallyNeedsUpdate = false; // AuthPath не имеет параметров
      } else if (newPathDetermined is HomePath && _currentPathConfig is HomePath) {
        pathActuallyNeedsUpdate = false; // HomePath не имеет параметров
      } else if (newPathDetermined is LoadingPath && _currentPathConfig is LoadingPath) {
        pathActuallyNeedsUpdate = false;
      } else if (newPathDetermined is UnknownPath && _currentPathConfig is UnknownPath) {
        pathActuallyNeedsUpdate = false;
      } else if (newPathDetermined is JoinTeamProcessingPath && _currentPathConfig is JoinTeamProcessingPath) {
        pathActuallyNeedsUpdate = false;
      }
    }

    // Если мы выходим из LoadingPath, всегда нужно обновить
    if (_currentPathConfig is LoadingPath && newPathDetermined is! LoadingPath) {
      pathActuallyNeedsUpdate = true;
    }


    if (pathActuallyNeedsUpdate) {
      debugPrint("AppRouterDelegate._onAuthStateChanged: Path changing from ${_currentPathConfig.runtimeType} to ${newPathDetermined.runtimeType}");
      _currentPathConfig = newPathDetermined;

      // Если мы перешли на AuthPath (например, после логаута), сбрасываем _previousPathBeforeTaskDetail
      if (_currentPathConfig is AuthPath && _previousPathBeforeTaskDetail != null) {
        _previousPathBeforeTaskDetail = null;
      }

      // Если новый путь - это JoinTeamByTokenPath, и пользователь залогинен, обрабатываем его немедленно
      // Это важно, чтобы обработка произошла сразу после того, как пользователь залогинился,
      // и AuthState установил pendingInviteToken, который был затем преобразован в JoinTeamByTokenPath.
      if (_currentPathConfig is JoinTeamByTokenPath && authState.isLoggedIn) {
        // Отдельный вызов, так как setNewRoutePath может быть вызван системой (например, при старте с URL)
        // а _onAuthStateChanged - при изменении состояния логина.
        // _handleJoinTeamByTokenPath должен быть вызван, если мы УЖЕ залогинены и получили этот путь.
        _handleJoinTeamByTokenPath(_currentPathConfig as JoinTeamByTokenPath);
      } else {
        notifyListeners(); // В остальных случаях просто уведомляем об изменении пути
      }
    } else {
      debugPrint("AppRouterDelegate._onAuthStateChanged: Path effectively not changed. Current is ${_currentPathConfig.runtimeType}, proposed new was ${newPathDetermined.runtimeType}");
      // Если путь не изменился, но есть pendingInviteToken и пользователь залогинен,
      // это может означать, что _currentPathConfig уже был JoinTeamByTokenPath или JoinTeamProcessingPath.
      // В этом случае _handleJoinTeamByTokenPath уже должен был быть вызван или будет вызван через setNewRoutePath.
    }
  }


  @override
  AppRoutePath get currentConfiguration => _currentPathConfig;

  @override
  Widget build(BuildContext context) {
    List<Page<dynamic>> pages = [];
    debugPrint("AppRouterDelegate.build: START. currentPathConfig=${_currentPathConfig.runtimeType}, authState.isLoggedIn=${authState.isLoggedIn}, authState.initialAuthCheckCompleted=${authState.initialAuthCheckCompleted}, _previousPathBeforeTaskDetail=${_previousPathBeforeTaskDetail?.runtimeType}, pendingInviteToken=${authState.pendingInviteToken}");

    if (!authState.initialAuthCheckCompleted || _currentPathConfig is LoadingPath) {
      pages.add(_createPage(const Scaffold(body: Center(child: CircularProgressIndicator())), const ValueKey('InitialLoadingPage'), '/app-loading'));
    } else if (!authState.isLoggedIn) {
      // Передаем pendingInviteToken в AuthScreen
      pages.add(_createPage(AuthScreen(pendingInviteToken: authState.pendingInviteToken), const ValueKey('AuthPage'), AppRoutes.auth));
    } else { // Пользователь залогинен
      String homeSubRouteForBase = AppRouteSegments.allTasks;
      bool homeShowRightSidebarForBase = true;
      String? teamIdForHomePage;
      // String? taskIdForHomePage; // Убрали, TaskDetailScreen будет отдельной страницей

      // Определяем, какой HomePage должен быть "под" TaskDetailScreen или JoinTeamProcessingScreen
      AppRoutePath basePathForHomePageDeterminer = _currentPathConfig; // По умолчанию берем текущий путь

      if (_currentPathConfig is TaskDetailPath) {
        // Если мы на TaskDetailPath, базовым путем для HomePage будет _previousPathBeforeTaskDetail
        // или дефолтный путь, если _previousPathBeforeTaskDetail не установлен.
        basePathForHomePageDeterminer = _previousPathBeforeTaskDetail ?? const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        debugPrint("AppRouterDelegate.build: Current is TaskDetailPath. Base for HomePage will be: ${basePathForHomePageDeterminer.runtimeType}");
      } else if (_currentPathConfig is JoinTeamProcessingPath || _currentPathConfig is JoinTeamByTokenPath) {
        // Если мы в процессе присоединения или только что получили токен,
        // фоном может быть любая страница HomePage, например, список команд или все задачи.
        // Для JoinTeamProcessingPath, вероятно, лучше показывать дефолтный HomePage.
        // JoinTeamByTokenPath - это "действенный" путь, который переключится на JoinTeamProcessingPath,
        // так что базовый HomePage здесь тоже дефолтный.
        basePathForHomePageDeterminer = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        debugPrint("AppRouterDelegate.build: Current is JoinTeam(Processing/ByToken)Path. Base for HomePage will be: ${basePathForHomePageDeterminer.runtimeType}");
      }


      if (basePathForHomePageDeterminer is HomeSubPath) {
        homeSubRouteForBase = basePathForHomePageDeterminer.subRoute;
        homeShowRightSidebarForBase = basePathForHomePageDeterminer.showRightSidebar;
      } else if (basePathForHomePageDeterminer is HomePath) {
        homeSubRouteForBase = AppRouteSegments.allTasks; // Дефолт для HomePath
      } else if (basePathForHomePageDeterminer is TeamDetailPath) {
        teamIdForHomePage = basePathForHomePageDeterminer.teamId;
        homeSubRouteForBase = AppRouteSegments.teams; // Логично, что HomePage будет на разделе команд
        homeShowRightSidebarForBase = true; // TeamDetailScreen имеет свой правый сайдбар
      }
      // Если basePathForHomePageDeterminer это TaskDetailPath (например, при прямом заходе на /task/ID),
      // то homeSubRouteForBase останется дефолтным (allTasks).

      // Добавляем HomePage всегда, если пользователь залогинен и это не экран Auth
      // За исключением случая, когда мы на экране JoinTeamProcessingPath - тогда HomePage является подложкой
      if (_currentPathConfig is! AuthPath) { // AuthPath обрабатывается выше
        debugPrint("AppRouterDelegate.build: Adding HomePage. initialSubRoute=$homeSubRouteForBase, teamIdToShow=$teamIdForHomePage");
        pages.add(_createPage(
            HomePage(
              initialSubRoute: homeSubRouteForBase,
              showRightSidebarInitially: homeShowRightSidebarForBase,
              teamIdToShow: teamIdForHomePage,
              // taskIdToShow: null, // Убрали, TaskDetailScreen будет отдельным
            ),
            // Ключ должен быть уникальным для разных состояний HomePage
            ValueKey('HomePage-$homeSubRouteForBase-${teamIdForHomePage ?? 'no-team'}'),
            // URL для HomePage здесь не так критичен, т.к. фактический URL будет от _currentPathConfig
            AppRoutes.homeSub(homeSubRouteForBase)
        ));
      }


      // Если текущий путь это TaskDetailPath, добавляем TaskDetailScreen поверх HomePage
      if (_currentPathConfig is TaskDetailPath) {
        final taskDetailPath = _currentPathConfig as TaskDetailPath;
        debugPrint("AppRouterDelegate.build: Current is TaskDetailPath. Adding TaskDetailScreen for taskId: ${taskDetailPath.taskId}");
        pages.add(_createPage(
            TaskDetailScreen(taskId: taskDetailPath.taskId),
            ValueKey('TaskDetailPage-${taskDetailPath.taskId}'),
            AppRoutes.taskDetail(taskDetailPath.taskId)
        ));
      } else if (_currentPathConfig is JoinTeamProcessingPath) {
        debugPrint("AppRouterDelegate.build: Current is JoinTeamProcessingPath. Adding JoinTeamLandingScreen.");
        // HomePage уже добавлен выше как базовый слой
        pages.add(_createPage(
            const JoinTeamLandingScreen(),
            const ValueKey('JoinTeamProcessingPage'),
            AppRoutes.processingInvite
        ));
      }
      // Для JoinTeamByTokenPath - страницы не добавляются, это триггер для действия.
      // Для TeamDetailPath - он встраивается в HomePage, который уже добавлен.
    }

    if (pages.isEmpty) { // Фоллбек, если стек пуст (например, если LoadingPath и initialAuthCheck еще false)
      pages.add(_createPage(const Scaffold(body: Center(child: Text("Ошибка роутинга или загрузка..."))), const ValueKey('ErrorOrLoadingPage'), '/error-or-loading'));
    }
    debugPrint("AppRouterDelegate.build: END. Pages count: ${pages.length}. Last page key: ${pages.isNotEmpty ? pages.last.key : 'N/A'}, Current URL config: ${_currentPathConfig.runtimeType}");

    return Navigator(
      key: navigatorKey,
      pages: List.unmodifiable(pages),
      onPopPage: (route, result) {
        if (!route.didPop(result)) {
          return false;
        }
        debugPrint("AppRouterDelegate.onPopPage: Popping page. Current path before pop: ${_currentPathConfig.runtimeType}");

        // Если мы на TaskDetailPath И он был последним в стеке (т.е. отдельная страница)
        if (_currentPathConfig is TaskDetailPath && pages.length > 1 && pages.last.name == AppRoutes.taskDetail((_currentPathConfig as TaskDetailPath).taskId)) {
          if (_previousPathBeforeTaskDetail != null) { // Восстанавливаем предыдущий путь
            _currentPathConfig = _previousPathBeforeTaskDetail!;
            debugPrint("AppRouterDelegate.onPopPage: Popped TaskDetail. Restored to _previousPath: ${_currentPathConfig.runtimeType}");
          } else { // Или на дефолтный, если предыдущего нет
            _currentPathConfig = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
            debugPrint("AppRouterDelegate.onPopPage: Popped TaskDetail. No _previousPath. Restored to default HomeSubPath.");
          }
          _previousPathBeforeTaskDetail = null; // Очищаем после использования
          notifyListeners();
          return true;
        }

        if (_currentPathConfig is TeamDetailPath) { // Если мы на TeamDetailPath (внутри HomePage)
          // "Назад" с TeamDetailPath должен вернуть к списку команд
          _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true); // Убедимся, что правый сайдбар для TeamsScreen активен
          debugPrint("AppRouterDelegate.onPopPage: Popped from TeamDetail. Going to Teams list.");
          notifyListeners();
          return true;
        }

        // Если мы на JoinTeamProcessingPath
        if (_currentPathConfig is JoinTeamProcessingPath) {
          // После обработки приглашения (успешной или нет), "назад" должен вести на список команд
          // или на предыдущую страницу, если она известна. Пока - на список команд.
          _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
          debugPrint("AppRouterDelegate.onPopPage: Popped from JoinTeamProcessing. Going to Teams list.");
          notifyListeners();
          return true;
        }

        // Если это был pop со страницы, которая была единственной поверх HomePage
        // (например, TaskDetailScreen или JoinTeamProcessingScreen, добавленные в pages)
        // то _currentPathConfig должен обновиться на путь HomePage.
        // Логика onPopPage Navigator'а удалит последнюю страницу из `pages`.
        // Мы должны обновить `_currentPathConfig`, чтобы он соответствовал новой вершине стека.
        // Пример: были [HomePage, TaskScreen], стал [HomePage].
        // _currentPathConfig должен стать путем для HomePage.

        if (pages.length > 1) { // Если после pop'а осталась хотя бы одна страница (т.е. был стек из >1 страницы)
          final newTopPage = pages[pages.length - 2]; // Страница, которая станет верхней
          // Пытаемся восстановить AppRoutePath из ValueKey или имени страницы
          // Это грубая логика, лучше иметь более надежный способ маппинга Page -> AppRoutePath
          if (newTopPage.key is ValueKey) {
            final keyString = (newTopPage.key as ValueKey).value.toString();
            if (keyString.startsWith('HomePage-')) {
              final parts = keyString.split('-');
              if (parts.length >= 2) { // HomePage-subRoute или HomePage-subRoute-teamId
                final subRoute = parts[1];
                // Определяем showRightSidebar на основе subRoute
                bool showSidebar = true;
                if ([AppRouteSegments.settings, AppRouteSegments.trash].contains(subRoute)) {
                  showSidebar = false;
                } else if ([AppRouteSegments.teams, AppRouteSegments.calendar, AppRouteSegments.allTasks, AppRouteSegments.personalTasks].contains(subRoute)) {
                  showSidebar = true;
                }

                if (parts.length == 3 && parts[2] != 'no-team' && parts[2] != 'main') { // Это TeamDetailPath, встроенный в HomePage
                  _currentPathConfig = TeamDetailPath(parts[2]);
                  debugPrint("AppRouterDelegate.onPopPage: Restored path to TeamDetailPath embedded in HomePage: $subRoute, teamId: ${parts[2]}");
                } else { // Это обычный HomeSubPath
                  _currentPathConfig = HomeSubPath(subRoute, showRightSidebar: showSidebar);
                  debugPrint("AppRouterDelegate.onPopPage: Restored path to HomeSubPath: $subRoute, showSidebar: $showSidebar");
                }
                notifyListeners();
                return true;
              }
            }
          }
        } else if (pages.length == 1 && pages.first.key.toString().contains('HomePage')) {
          // Если остался только HomePage, устанавливаем для него путь
          final keyString = (pages.first.key as ValueKey).value.toString();
          final parts = keyString.split('-');
          if (parts.length >= 2) {
            final subRoute = parts[1];
            bool showSidebar = true;
            if ([AppRouteSegments.settings, AppRouteSegments.trash].contains(subRoute)) {
              showSidebar = false;
            } else if ([AppRouteSegments.teams, AppRouteSegments.calendar, AppRouteSegments.allTasks, AppRouteSegments.personalTasks].contains(subRoute)) {
              showSidebar = true;
            }
            _currentPathConfig = HomeSubPath(subRoute, showRightSidebar: showSidebar);
            debugPrint("AppRouterDelegate.onPopPage: Restored path to single HomePage: $subRoute, showSidebar: $showSidebar");
            notifyListeners();
            return true;
          }
        }


        debugPrint("AppRouterDelegate.onPopPage: Standard pop, no specific handling or unhandled. Current path: ${_currentPathConfig.runtimeType}");
        return false; // Если не обработали, позволяем Navigator'у сделать это
      },
    );
  }

  // <<< МЕТОД ДЛЯ ОБРАБОТКИ ПРИСОЕДИНЕНИЯ К КОМАНДЕ ПО ТОКЕНУ >>>
  Future<void> _handleJoinTeamByTokenPath(JoinTeamByTokenPath path) async {
    debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Processing token ${path.token}");

    // Устанавливаем временный путь, чтобы показать экран загрузки
    // Убедимся, что это не вызовет рекурсию с _onAuthStateChanged
    if (_currentPathConfig is! JoinTeamProcessingPath) {
      _currentPathConfig = const JoinTeamProcessingPath();
      notifyListeners(); // Показываем экран загрузки JoinTeamLandingScreen
    }

    // Даем UI время обновиться перед началом долгой операции
    await Future.delayed(Duration.zero); // Позволяет UI перерисоваться перед выполнением тяжелой операции

    Team? joinedTeam;
    String? joinError;

    try {
      joinedTeam = await teamProvider.joinTeamByToken(path.token);
      // Очищаем pendingInviteToken из AuthState после успешной или неуспешной попытки
      authState.clearPendingInviteToken();

      if (joinedTeam != null) {
        debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Successfully joined team ${joinedTeam.teamId}. Navigating to team details.");
        _currentPathConfig = TeamDetailPath(joinedTeam.teamId);
      } else {
        // Ошибка уже должна быть в teamProvider.error
        joinError = teamProvider.error ?? "Не удалось присоединиться к команде. Токен недействителен или срок его действия истек.";
        debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Failed to join team. Error: $joinError. Navigating to teams list.");
        _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true); // Возвращаем на список команд
      }
    } catch (e) {
      authState.clearPendingInviteToken(); // Очищаем токен в случае исключения
      joinError = "Неизвестная ошибка при присоединении к команде: $e";
      debugPrint("AppRouterDelegate._handleJoinTeamByTokenPath: Exception during join: $joinError. Navigating to teams list.");
      _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
    }

    // Показываем SnackBar с результатом, если есть контекст
    // Это лучше делать здесь, так как мы управляем навигацией
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
        if(teamProvider.error != null) teamProvider.clearError(); // Очищаем ошибку в провайдере после показа
      }
    }

    notifyListeners(); // Обновляем UI после завершения операции (переход на TeamDetailPath или TeamsScreen)
  }


  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    debugPrint("[AppRouterDelegate.setNewRoutePath] START. Received new configuration: ${configuration.runtimeType} "
        "(details: ${configuration is HomeSubPath ? configuration.subRoute : (configuration is TaskDetailPath ? configuration.taskId : (configuration is TeamDetailPath ? configuration.teamId : (configuration is JoinTeamByTokenPath ? configuration.token : 'N/A')))})"
        " Current: ${_currentPathConfig.runtimeType}, Auth Initialized: ${authState.initialAuthCheckCompleted}");

    // Если authState еще не инициализирован (initialAuthCheckCompleted = false),
    // и пришел НЕ LoadingPath, сохраняем конфигурацию для последующей обработки.
    if (!authState.initialAuthCheckCompleted && configuration is! LoadingPath) {
      _parsedPathFromUrlDuringLoading = configuration;
      // Если это JoinTeamByTokenPath, сохраняем токен в AuthState
      if (configuration is JoinTeamByTokenPath) {
        authState.setPendingInviteToken(configuration.token);
        debugPrint("AppRouterDelegate.setNewRoutePath: Auth loading. Stored JoinTeamByTokenPath's token '${configuration.token}' in AuthState.");
      } else {
        // authState.clearPendingInviteToken(); // Не очищаем, если это не JoinTeamByTokenPath, он может быть уже установлен
        debugPrint("AppRouterDelegate.setNewRoutePath: Auth loading. Stored requested path: ${_parsedPathFromUrlDuringLoading?.runtimeType}. Current display path (should be LoadingPath): ${_currentPathConfig.runtimeType}.");
      }
      // Не меняем _currentPathConfig на LoadingPath здесь, это делает _onAuthStateChanged
      // и _currentPathConfig уже должен быть LoadingPath.
      // Если нет, то _onAuthStateChanged исправит.
      return; // Выходим, т.к. authState еще не готов
    }


    // Обработка JoinTeamByTokenPath:
    if (configuration is JoinTeamByTokenPath) {
      if (!authState.isLoggedIn) {
        // Пользователь не залогинен, но есть токен. Сохраняем токен и редиректим на AuthScreen.
        debugPrint("AppRouterDelegate.setNewRoutePath: JoinTeamByTokenPath received, user NOT logged in. Storing token '${configuration.token}', redirecting to Auth.");
        authState.setPendingInviteToken(configuration.token);
        _currentPathConfig = const AuthPath(); // Устанавливаем AuthPath для отображения экрана логина
      } else {
        // Пользователь залогинен, обрабатываем токен немедленно.
        debugPrint("AppRouterDelegate.setNewRoutePath: JoinTeamByTokenPath received, user IS logged in. Calling _handleJoinTeamByTokenPath for token '${configuration.token}'.");
        // _handleJoinTeamByTokenPath сам вызовет notifyListeners после завершения.
        // Здесь мы НЕ устанавливаем _currentPathConfig = configuration,
        // т.к. _handleJoinTeamByTokenPath сам определит конечный путь.
        await _handleJoinTeamByTokenPath(configuration);
        // После _handleJoinTeamByTokenPath, _currentPathConfig будет обновлен.
        // Нет необходимости вызывать notifyListeners() здесь еще раз, если _handleJoinTeamByTokenPath это сделал.
      }
      // notifyListeners() вызывается внутри _handleJoinTeamByTokenPath или если _currentPathConfig изменился на AuthPath.
      // Если _currentPathConfig установился на AuthPath, вызываем notifyListeners
      if (_currentPathConfig is AuthPath && configuration is JoinTeamByTokenPath && !authState.isLoggedIn) {
        notifyListeners();
      }
      return; // Обработка JoinTeamByTokenPath завершена здесь
    }

    // Предотвращаем "зацикливание" на JoinTeamProcessingPath, если пришла другая конфигурация
    // и _currentPathConfig все еще JoinTeamProcessingPath (например, если обработка токена завершилась,
    // но setNewRoutePath вызван до того, как _onAuthStateChanged успел переключить путь).
    if (_currentPathConfig is JoinTeamProcessingPath && configuration is! JoinTeamProcessingPath) {
      debugPrint("AppRouterDelegate.setNewRoutePath: Exiting JoinTeamProcessingPath to ${configuration.runtimeType}.");
      // _currentPathConfig будет обновлен ниже, если configuration действительно отличается от того,
      // на который переключился _handleJoinTeamByTokenPath
    }


    // Управление _previousPathBeforeTaskDetail
    if (configuration is TaskDetailPath && _currentPathConfig is! TaskDetailPath) {
      // Проверяем, чтобы не сохранять TaskDetailPath как предыдущий для самого себя
      // или JoinTeam(Processing/ByToken)Path как предыдущий, так как они временные.
      if (_currentPathConfig is HomePath || _currentPathConfig is HomeSubPath || _currentPathConfig is TeamDetailPath) {
        _previousPathBeforeTaskDetail = _currentPathConfig;
        debugPrint("AppRouterDelegate.setNewRoutePath: Navigating TO TaskDetail. Saved _previousPath: ${_previousPathBeforeTaskDetail?.runtimeType}");
      } else if (_currentPathConfig is LoadingPath && _parsedPathFromUrlDuringLoading != null &&
          _parsedPathFromUrlDuringLoading is! TaskDetailPath &&
          _parsedPathFromUrlDuringLoading is! JoinTeamProcessingPath &&
          _parsedPathFromUrlDuringLoading is! JoinTeamByTokenPath){
        // Если загрузка, и парсенный путь не TaskDetail и не пути обработки приглашения, то его и сохраняем
        _previousPathBeforeTaskDetail = _parsedPathFromUrlDuringLoading;
        debugPrint("AppRouterDelegate.setNewRoutePath: Navigating TO TaskDetail (from loading). Saved _previousPath (from parsed): ${_previousPathBeforeTaskDetail?.runtimeType}");
      }
    }
    // _previousPathBeforeTaskDetail сбрасывается в popRoute или при логауте

    // Сравниваем новую конфигурацию с текущей (после возможной обработки JoinTeamByTokenPath)
    bool configActuallyChanged = true;
    if (configuration.runtimeType == _currentPathConfig.runtimeType) {
      // Если типы одинаковы, сравниваем содержимое
      if (configuration is HomeSubPath && _currentPathConfig is HomeSubPath) {
        final currentCasted = _currentPathConfig as HomeSubPath;
        final newCasted = configuration;
        configActuallyChanged = !(currentCasted.subRoute == newCasted.subRoute && currentCasted.showRightSidebar == newCasted.showRightSidebar);
      } else if (configuration is TaskDetailPath && _currentPathConfig is TaskDetailPath) {
        configActuallyChanged = (_currentPathConfig as TaskDetailPath).taskId != configuration.taskId;
      } else if (configuration is TeamDetailPath && _currentPathConfig is TeamDetailPath) {
        configActuallyChanged = (_currentPathConfig as TeamDetailPath).teamId != configuration.teamId;
        // JoinTeamByTokenPath уже обработан выше и не должен попадать сюда в configuration.
        // Если _currentPathConfig это JoinTeamByTokenPath, а configuration другой - это изменение.
      } else if (configuration is AuthPath && _currentPathConfig is AuthPath) {
        configActuallyChanged = false;
      } else if (configuration is HomePath && _currentPathConfig is HomePath) {
        configActuallyChanged = false;
      } else if (configuration is UnknownPath && _currentPathConfig is UnknownPath) {
        configActuallyChanged = false;
      } else if (configuration is LoadingPath && _currentPathConfig is LoadingPath) {
        configActuallyChanged = false;
      } else if (configuration is JoinTeamProcessingPath && _currentPathConfig is JoinTeamProcessingPath) {
        configActuallyChanged = false; // Если мы уже на экране загрузки, не меняем
      }
    }
    // Если _currentPathConfig был JoinTeamProcessingPath, а новая configuration другая - это изменение.
    // Это уже покрывается сравнением runtimeType.


    if (configActuallyChanged) {
      _currentPathConfig = configuration;
      if (configuration is! LoadingPath) { // Если мы вышли из состояния Loading
        _parsedPathFromUrlDuringLoading = null; // Очищаем сохраненный путь
      }
      debugPrint("AppRouterDelegate.setNewRoutePath: END. Path changed to ${_currentPathConfig.runtimeType}. Notifying listeners.");
      notifyListeners();
    } else {
      debugPrint("AppRouterDelegate.setNewRoutePath: END. Path NOT changed by this call. Current: ${_currentPathConfig.runtimeType}, New: ${configuration.runtimeType}. No notification.");
    }
  }

  void navigateTo(AppRoutePath path) {
    // setNewRoutePath асинхронный, но здесь мы вызываем его синхронно.
    // Это нормально, т.к. изменения состояния (_currentPathConfig и notifyListeners)
    // будут применены в текущем event loop или запланированы.
    setNewRoutePath(path);
  }

  @override
  Future<bool> popRoute() {
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint("AppRouterDelegate.popRoute: NavigatorKey is null. Returning false.");
      return SynchronousFuture(false); // Используем SynchronousFuture для синхронного возврата
    }

    debugPrint("AppRouterDelegate.popRoute: Attempting to pop. Current path: ${_currentPathConfig.runtimeType}, _previousPath: ${_previousPathBeforeTaskDetail?.runtimeType}");

    // Сначала проверяем нашу кастомную логику "возврата"
    if (_currentPathConfig is TaskDetailPath) {
      if (_previousPathBeforeTaskDetail != null) {
        _currentPathConfig = _previousPathBeforeTaskDetail!;
        _previousPathBeforeTaskDetail = null; // Очищаем после использования
        debugPrint("AppRouterDelegate.popRoute (custom logic for TaskDetail): Restored to _previousPath: ${_currentPathConfig.runtimeType}");
      } else {
        // Если нет _previousPathBeforeTaskDetail, но мы на TaskDetailPath,
        // это может быть прямой заход. "Назад" может означать переход на дефолтный экран.
        _currentPathConfig = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
        debugPrint("AppRouterDelegate.popRoute (custom logic for TaskDetail, no previous path): Going to default Home.");
      }
      notifyListeners();
      return SynchronousFuture(true);
    }

    if (_currentPathConfig is TeamDetailPath) { // Если мы на TeamDetailPath (внутри HomePage)
      _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
      _previousPathBeforeTaskDetail = null; // На всякий случай, если был установлен
      debugPrint("AppRouterDelegate.popRoute (custom logic for TeamDetail): Going to Teams list.");
      notifyListeners();
      return SynchronousFuture(true);
    }

    // Если мы на JoinTeamProcessingPath
    if (_currentPathConfig is JoinTeamProcessingPath) {
      // После обработки приглашения (успешной или нет), "назад" должен вести на список команд
      _currentPathConfig = const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
      _previousPathBeforeTaskDetail = null;
      notifyListeners();
      return SynchronousFuture(true);
    }

    // Если нет кастомной логики выше, и навигатор не может сделать pop, то мы не можем обработать.
    if (!navigator.canPop()) {
      debugPrint("AppRouterDelegate.popRoute: Navigator cannot pop and no custom logic applied. Returning false.");
      return SynchronousFuture(false);
    }

    // Если навигатор МОЖЕТ сделать pop (т.е. в его стеке > 1 страницы, как [HomePage, TaskDetailScreen])
    // Мы позволяем ему это сделать. onPopPage должен будет обработать обновление _currentPathConfig.
    debugPrint("AppRouterDelegate.popRoute: Navigator can pop. Calling navigator.pop(). System will handle state via onPopPage.");
    navigator.pop();
    // Важно: после вызова navigator.pop(), мы уже не должны здесь менять _currentPathConfig или вызывать notifyListeners().
    // Это задача onPopPage. Мы просто сообщаем системе, что pop-запрос был обработан (инициирован).
    return SynchronousFuture(true);
  }


  bool canPop() {
    // Если текущий путь - TaskDetailPath, и есть предыдущий путь для возврата, ИЛИ
    // если текущий путь - TeamDetailPath (возврат к списку команд).
    if (_currentPathConfig is TaskDetailPath) {
      return _previousPathBeforeTaskDetail != null || (navigatorKey.currentState?.canPop() ?? false);
    }
    if (_currentPathConfig is TeamDetailPath) {
      return true; // Всегда можем вернуться к списку команд
    }
    if (_currentPathConfig is JoinTeamProcessingPath) {
      return true; // Можем вернуться со страницы обработки
    }
    // Для других случаев смотрим, может ли сам Navigator сделать pop
    // Это обычно означает, что в стеке pages > 1 страница.
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
      name: name, // Имя маршрута важно для Navigator 2.0
      arguments: arguments,
    );
  }
}