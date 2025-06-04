// lib/core/routing/app_pages.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../screens/auth_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/task_detail_screen.dart';
import '../../screens/join_team_landing_screen.dart';
import '../../screens/landing_screen.dart';
import 'app_route_path.dart';
import '../../auth_state.dart';

class AppRouteSegments {
  static const String landing = 'welcome';
  static const String auth = 'auth';
  static const String home = 'home';
  static const String settings = 'settings';
  static const String allTasks = 'all-tasks';
  static const String personalTasks = 'personal-tasks';
  static const String teams = 'teams';
  static const String team = 'team';
  static const String trash = 'trash';
  static const String calendar = 'calendar';
  static const String task = 'task';
  static const String joinTeam = 'join-team';
  static const String processingInvite = 'processing-invite';
}

class AppRoutes {
  static const String landing = '/${AppRouteSegments.landing}';
  static const String auth = '/${AppRouteSegments.auth}';
  static const String home = '/${AppRouteSegments.home}';

  static String homeSub(String subSegment) => '${home}/$subSegment';
  static final String settings = homeSub(AppRouteSegments.settings);
  static final String allTasks = homeSub(AppRouteSegments.allTasks);
  static final String personalTasks = homeSub(AppRouteSegments.personalTasks);
  static final String teams = homeSub(AppRouteSegments.teams);
  static final String trash = homeSub(AppRouteSegments.trash);
  static final String calendar = homeSub(AppRouteSegments.calendar);

  static String taskDetail(String taskId) => '/${AppRouteSegments.task}/$taskId';
  static String teamDetail(String teamId) => '/${AppRouteSegments.team}/$teamId';

  static String joinTeamByToken(String token) => '/${AppRouteSegments.joinTeam}/$token';
  static const String processingInvite = '/${AppRouteSegments.processingInvite}';
}


List<Page<dynamic>> buildPagesForPath(AppRoutePath path, AuthState authState) {
  final List<Page<dynamic>> pages = [];
  debugPrint("[buildPagesForPath] Building pages for path: ${path.runtimeType}, isLoggedIn: ${authState.isLoggedIn}");

  // Кейс 1: LoadingPath - всегда только страница загрузки
  if (path is LoadingPath || !authState.initialAuthCheckCompleted) {
    pages.add(_createPage(const Scaffold(body: Center(child: CircularProgressIndicator())), const ValueKey('InitialLoadingPage'), '/app-loading'));
    return pages;
  }

  // Кейс 2: LandingPath - всегда только страница лендинга (только для веб)
  if (path is LandingPath && kIsWeb) {
    pages.add(_createPage(const LandingScreen(), const ValueKey('LandingPage'), AppRoutes.landing));
    return pages;
  }

  // Кейс 3: Пользователь не авторизован (и это не LandingPath для веб)
  if (!authState.isLoggedIn) {
    pages.add(_createPage(AuthScreen(pendingInviteToken: authState.pendingInviteToken), const ValueKey('AuthPage'), AppRoutes.auth));
    return pages;
  }

  // Кейс 4: Пользователь авторизован
  // Базовая страница - HomePage. Ее параметры зависят от текущего пути.
  String homeSubRouteForBase = AppRouteSegments.allTasks;
  bool homeShowRightSidebarForBase = true;
  String? teamIdToShowForHomePage; // Для отображения TeamDetailScreen внутри HomePage
  String? taskIdToShowForHomePage; // Для отображения TaskDetailScreen внутри HomePage (если вы решите вернуть это)

  if (path is HomeSubPath) {
    homeSubRouteForBase = path.subRoute;
    homeShowRightSidebarForBase = path.showRightSidebar;
  } else if (path is HomePath) {
    // homeSubRouteForBase и homeShowRightSidebarForBase остаются дефолтными
  } else if (path is TeamDetailPath) {
    // Если мы на TeamDetailPath, HomePage должен содержать этот TeamDetailScreen
    homeSubRouteForBase = AppRouteSegments.teams; // Логично, что основа - список команд
    teamIdToShowForHomePage = path.teamId;
    homeShowRightSidebarForBase = true; // TeamDetailScreen имеет свой правый сайдбар
  } else if (path is TaskDetailPath || path is JoinTeamProcessingPath || path is JoinTeamByTokenPath) {
    // Для этих "верхних" страниц, HomePage под ними будет дефолтным
    // (allTasks), или можно использовать _previousPathBeforeTaskDetail, если он есть.
    // Но AppRouterDelegate уже передает _previousPathBeforeTaskDetail через _currentPathConfig
    // так что здесь мы можем просто полагаться на то, что если path это TaskDetailPath,
    // то HomePage будет построен на основе того, что было до TaskDetailPath.
    // Эта логика сложна для buildPagesForPath, лучше если AppRouterDelegate сам передаст сюда
    // УЖЕ СКОРРЕКТИРОВАННЫЙ базовый путь для HomePage, если это TaskDetail.
    // Пока что, если это не HomeSubPath, HomePath или TeamDetailPath, HomePage будет дефолтным.
    // Это значит, что если мы зашли на /task/123, то HomePage будет /home/all-tasks
  }

  pages.add(_createPage(
      HomePage(
        initialSubRoute: homeSubRouteForBase,
        showRightSidebarInitially: homeShowRightSidebarForBase,
        teamIdToShow: teamIdToShowForHomePage,
        // taskIdToShow: taskIdToShowForHomePage, // Если TaskDetail будет частью HomePage
      ),
      ValueKey('HomePage-$homeSubRouteForBase-${teamIdToShowForHomePage ?? 'no-team'}'),
      // URL для HomePage здесь не так критичен, т.к. фактический URL будет от _currentPathConfig
      // Но для согласованности, если это teamId, то путь к команде
      teamIdToShowForHomePage != null ? AppRoutes.teamDetail(teamIdToShowForHomePage) : AppRoutes.homeSub(homeSubRouteForBase)
  ));

  // Добавляем дочерние страницы поверх HomePage
  if (path is TaskDetailPath) {
    pages.add(_createPage(
        TaskDetailScreen(taskId: path.taskId),
        ValueKey('TaskDetailPage-${path.taskId}'),
        AppRoutes.taskDetail(path.taskId)
    ));
  } else if (path is JoinTeamProcessingPath) {
    pages.add(_createPage(
        const JoinTeamLandingScreen(),
        const ValueKey('JoinTeamProcessingPage'),
        AppRoutes.processingInvite
    ));
  }
  // TeamDetailPath уже обработан тем, что teamIdToShowForHomePage передается в HomePage.

  // Если после всех этих проверок pages все еще пуст (очень маловероятно для залогиненного пользователя)
  if (pages.isEmpty) {
    debugPrint("[buildPagesForPath] CRITICAL - Logged in user, but pages list is empty for path: ${path.runtimeType}. Defaulting to Home.");
    pages.add(_createPage(
        const HomePage(initialSubRoute: AppRouteSegments.allTasks, showRightSidebarInitially: true),
        const ValueKey('FallbackLoggedInHomePage'),
        AppRoutes.home
    ));
  }

  return pages;
}


MaterialPage _createPage(Widget child, ValueKey key, String name, {Object? arguments}) {
  return MaterialPage(
    child: child,
    key: key,
    name: name,
    arguments: arguments,
  );
}