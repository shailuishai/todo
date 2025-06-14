// lib/core/routing/app_pages.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../screens/auth_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/oauth_callback_screen.dart';
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
  // ИЗМЕНЕНИЕ: НОВЫЙ СЕГМЕНТ ДЛЯ КОЛЛБЭКА
  static const String oauth = 'oauth';
  static const String callback = 'callback';
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

  // ИЗМЕНЕНИЕ: НОВЫЙ РОУТ ДЛЯ КОЛЛБЭКА
  static String oAuthCallback(String provider) => '/${AppRouteSegments.oauth}/${AppRouteSegments.callback}/$provider';
}


List<Page<dynamic>> buildPagesForPath(AppRoutePath path, AuthState authState) {
  final List<Page<dynamic>> pages = [];
  debugPrint("[buildPagesForPath] Building pages for path: ${path.runtimeType}, isLoggedIn: ${authState.isLoggedIn}");

  // Кейс 1: LoadingPath - всегда только страница загрузки
  if (path is LoadingPath || !authState.initialAuthCheckCompleted) {
    pages.add(_createPage(const Scaffold(body: Center(child: CircularProgressIndicator())), const ValueKey('InitialLoadingPage'), '/app-loading'));
    return pages;
  }

  // ИЗМЕНЕНИЕ: Добавлена обработка OAuth путей
  if (path is OAuthCallbackPath) {
    pages.add(_createPage(
        OAuthCallbackScreen(provider: path.provider),
        ValueKey('OAuthCallbackPage-${path.provider}'),
        AppRoutes.oAuthCallback(path.provider)
    ));
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
  String homeSubRouteForBase = AppRouteSegments.allTasks;
  bool homeShowRightSidebarForBase = true;
  String? teamIdToShowForHomePage;
  String? taskIdToShowForHomePage;

  if (path is HomeSubPath) {
    homeSubRouteForBase = path.subRoute;
    homeShowRightSidebarForBase = path.showRightSidebar;
  } else if (path is HomePath) {
    // defaults
  } else if (path is TeamDetailPath) {
    homeSubRouteForBase = AppRouteSegments.teams;
    teamIdToShowForHomePage = path.teamId;
    homeShowRightSidebarForBase = true;
  } else if (path is TaskDetailPath || path is JoinTeamProcessingPath || path is JoinTeamByTokenPath) {
    // defaults
  }

  pages.add(_createPage(
      HomePage(
        initialSubRoute: homeSubRouteForBase,
        showRightSidebarInitially: homeShowRightSidebarForBase,
        teamIdToShow: teamIdToShowForHomePage,
      ),
      ValueKey('HomePage-$homeSubRouteForBase-${teamIdToShowForHomePage ?? 'no-team'}'),
      teamIdToShowForHomePage != null ? AppRoutes.teamDetail(teamIdToShowForHomePage) : AppRoutes.homeSub(homeSubRouteForBase)
  ));

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