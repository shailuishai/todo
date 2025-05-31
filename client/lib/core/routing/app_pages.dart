// lib/core/routing/app_pages.dart
import 'package:flutter/material.dart';
import '../../screens/auth_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/task_detail_screen.dart';
import '../../screens/join_team_landing_screen.dart'; // <<< ИМПОРТ НОВОГО ЭКРАНА-ЗАГЛУШКИ
import 'app_route_path.dart';
import '../../auth_state.dart';

class AppRouteSegments {
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
  static const String joinTeam = 'join-team'; // <<< НОВЫЙ СЕГМЕНТ
  static const String processingInvite = 'processing-invite'; // <<< НОВЫЙ СЕГМЕНТ ДЛЯ ЭКРАНА ЗАГЛУШКИ
}

class AppRoutes {
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

  // <<< НОВЫЙ МАРШРУТ ДЛЯ ПРИСОЕДИНЕНИЯ К КОМАНДЕ ПО ТОКЕНУ >>>
  static String joinTeamByToken(String token) => '/${AppRouteSegments.joinTeam}/$token';
  // <<< МАРШРУТ К ЭКРАНУ ЗАГЛУШКЕ >>>
  static const String processingInvite = '/${AppRouteSegments.processingInvite}';
}


List<Page<dynamic>> buildPagesForPath(AppRoutePath path, AuthState authState) {
  final List<Page<dynamic>> pages = [];

  if (!authState.isLoggedIn) {
    // Передаем pendingInviteToken в AuthScreen, если он есть
    pages.add(_createPage(AuthScreen(pendingInviteToken: authState.pendingInviteToken), const ValueKey('AuthPage'), AppRoutes.auth));
  } else {
    // Залогиненный пользователь
    if (path is AuthPath && authState.isLoggedIn) { // Редирект на главную, если залогинен и пытается попасть на /auth
      pages.add(_createPage(
          const HomePage(initialSubRoute: AppRouteSegments.allTasks, showRightSidebarInitially: true),
          const ValueKey('HomePage-RedirectFromAuth'),
          AppRoutes.homeSub(AppRouteSegments.allTasks)
      ));
    } else if (path is HomeSubPath) {
      pages.add(_createPage(
          HomePage(initialSubRoute: path.subRoute, showRightSidebarInitially: path.showRightSidebar),
          ValueKey('HomePage-${path.subRoute}-${path.showRightSidebar}'),
          AppRoutes.homeSub(path.subRoute)
      ));
    } else if (path is HomePath) { // Общий /home, перенаправляем на дефолтный подраздел
      pages.add(_createPage(
          const HomePage(initialSubRoute: AppRouteSegments.allTasks, showRightSidebarInitially: true),
          const ValueKey('HomePage-Default'),
          AppRoutes.homeSub(AppRouteSegments.allTasks)
      ));
    } else if (path is TaskDetailPath) {
      // AppRouterDelegate.build обеспечит наличие HomePage под этой страницей
      pages.add(_createPage(
          TaskDetailScreen(taskId: path.taskId),
          ValueKey('TaskDetailPage-${path.taskId}'),
          AppRoutes.taskDetail(path.taskId)
      ));
    } else if (path is JoinTeamProcessingPath) { // <<< ОБРАБОТЧИК ДЛЯ ЭКРАНА ЗАГЛУШКИ >>>
      pages.add(_createPage(
          const JoinTeamLandingScreen(),
          const ValueKey('JoinTeamProcessingPage'),
          AppRoutes.processingInvite
      ));
    }
    // Для TeamDetailPath страница не добавляется здесь, т.к. он встраивается в HomePage.
    // Для JoinTeamByTokenPath страница не добавляется здесь, т.к. это "действенный" путь, обрабатываемый делегатом.
    else {
      // Если HomePage еще не добавлен (например, при прямом заходе на /task/ID или /team/ID, JoinTeamProcessingPath)
      // и список страниц пуст, добавим HomePage как базовый.
      if (pages.isEmpty) {
        pages.add(_createPage(
            const HomePage(initialSubRoute: AppRouteSegments.allTasks, showRightSidebarInitially: true),
            const ValueKey('HomePage-DefaultUnknownOrBase'),
            AppRoutes.homeSub(AppRouteSegments.allTasks)
        ));
      }
    }
  }


  if (pages.isEmpty) {
    // Фоллбек, если ничего не подошло (не должно происходить при корректной логике)
    // Передаем pendingInviteToken в AuthScreen, если он есть
    pages.add(_createPage(AuthScreen(pendingInviteToken: authState.pendingInviteToken), const ValueKey('FallbackAuthPage'), AppRoutes.auth));
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