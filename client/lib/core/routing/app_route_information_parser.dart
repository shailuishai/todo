// lib/core/routing/app_route_information_parser.dart
import 'package:flutter/material.dart';
import 'app_route_path.dart';
import 'app_pages.dart';

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(RouteInformation routeInformation) async {
    final uri = Uri.parse(routeInformation.uri.toString());
    debugPrint("[AppRouteInformationParser] Parsing URI: $uri");

    // Если путь пустой, это может быть запрос на лендинг или на дефолтную страницу после логина.
    // AppRouterDelegate решит, что показать, в зависимости от статуса аутентификации.
    // Пока что, для парсера, пустой путь -> LandingPath.
    if (uri.pathSegments.isEmpty || uri.path == '/') {
      debugPrint("[AppRouteInformationParser] URI is empty or root, returning LandingPath");
      return const LandingPath();
    }

    final firstSegment = uri.pathSegments.first;

    // <<< ОБРАБОТКА ПУТИ ЛЕНДИНГА >>>
    if (firstSegment == AppRouteSegments.landing) {
      debugPrint("[AppRouteInformationParser] Parsed LandingPath");
      return const LandingPath();
    }

    if (firstSegment == AppRouteSegments.auth) {
      debugPrint("[AppRouteInformationParser] Parsed AuthPath");
      return const AuthPath();
    }

    if (firstSegment == AppRouteSegments.home) {
      if (uri.pathSegments.length == 1) {
        debugPrint("[AppRouteInformationParser] Parsed HomeSubPath (default for /home): ${AppRouteSegments.allTasks}");
        return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      }
      if (uri.pathSegments.length == 2) {
        final subRouteSegment = uri.pathSegments[1];
        bool showRightSidebar = true;

        if ([
          AppRouteSegments.settings,
          AppRouteSegments.trash,
        ].contains(subRouteSegment)) {
          showRightSidebar = false;
        }

        if (subRouteSegment == AppRouteSegments.teams || subRouteSegment == AppRouteSegments.calendar) {
          showRightSidebar = true;
        }

        final validHomeSubRoutes = [
          AppRouteSegments.settings, AppRouteSegments.allTasks, AppRouteSegments.personalTasks,
          AppRouteSegments.teams, AppRouteSegments.trash, AppRouteSegments.calendar,
        ];

        if (validHomeSubRoutes.contains(subRouteSegment)) {
          debugPrint("[AppRouteInformationParser] Parsed HomeSubPath: $subRouteSegment, showRightSidebar: $showRightSidebar");
          return HomeSubPath(subRouteSegment, showRightSidebar: showRightSidebar);
        }
        debugPrint("[AppRouteInformationParser] Invalid HomeSubPath segment: $subRouteSegment, returning default allTasks");
        return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      }
      debugPrint("[AppRouteInformationParser] Too many segments for /home, returning default allTasks");
      return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
    }

    if (firstSegment == AppRouteSegments.task) {
      if (uri.pathSegments.length == 2) {
        final taskId = uri.pathSegments[1];
        debugPrint("[AppRouteInformationParser] Parsed TaskDetailPath with ID: $taskId");
        return TaskDetailPath(taskId);
      }
    }

    if (firstSegment == AppRouteSegments.team) {
      if (uri.pathSegments.length == 2) {
        final teamId = uri.pathSegments[1];
        debugPrint("[AppRouteInformationParser] Parsed TeamDetailPath with ID: $teamId");
        return TeamDetailPath(teamId);
      }
    }

    if (firstSegment == AppRouteSegments.joinTeam) {
      if (uri.pathSegments.length == 2) {
        final token = uri.pathSegments[1];
        if (token.isNotEmpty) {
          debugPrint("[AppRouteInformationParser] Parsed JoinTeamByTokenPath with token: $token");
          return JoinTeamByTokenPath(token);
        }
      }
      debugPrint("[AppRouteInformationParser] Invalid JoinTeamByTokenPath, token missing or malformed URI: $uri. Returning LandingPath.");
      return const LandingPath();
    }

    if (firstSegment == AppRouteSegments.processingInvite) {
      debugPrint("[AppRouteInformationParser] Parsed JoinTeamProcessingPath");
      return const JoinTeamProcessingPath();
    }

    debugPrint("[AppRouteInformationParser] URI not matched ($uri), returning LandingPath as default for unknown.");
    return const LandingPath(); // Для всех неопознанных путей показываем лендинг
  }

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) {
    if (configuration is LandingPath) { // <<< ВОССТАНОВЛЕНИЕ ДЛЯ ЛЕНДИНГА >>>
      return RouteInformation(uri: Uri.parse(AppRoutes.landing));
    }
    if (configuration is AuthPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.auth));
    }
    if (configuration is HomePath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.homeSub(AppRouteSegments.allTasks)));
    }
    if (configuration is HomeSubPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.homeSub(configuration.subRoute)));
    }
    if (configuration is TaskDetailPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.taskDetail(configuration.taskId)));
    }
    if (configuration is TeamDetailPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.teamDetail(configuration.teamId)));
    }
    if (configuration is JoinTeamByTokenPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.joinTeamByToken(configuration.token)));
    }
    if (configuration is JoinTeamProcessingPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.processingInvite));
    }
    if (configuration is UnknownPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.landing)); // Неизвестные пути ведут на лендинг
    }
    debugPrint("[AppRouteInformationParser] restoreRouteInformation: Unknown configuration type: ${configuration.runtimeType}");
    return null;
  }
}