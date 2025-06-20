// lib/core/routing/app_route_information_parser.dart
import 'package:flutter/material.dart';
import 'app_route_path.dart';
import 'app_pages.dart';

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(RouteInformation routeInformation) async {
    final uri = Uri.parse(routeInformation.uri.toString());
    debugPrint("[AppRouteInformationParser] Parsing URI: $uri");

    if (uri.pathSegments.isEmpty || uri.path == '/') {
      debugPrint("[AppRouteInformationParser] URI is empty or root, returning LandingPath");
      return const LandingPath();
    }

    final segments = uri.pathSegments;

    // ИЗМЕНЕНИЕ: Обработка нового пути /oauth/callback/:provider
    if (segments.length == 3 && segments[0] == AppRouteSegments.oauth && segments[1] == AppRouteSegments.callback) {
      final provider = segments[2];
      debugPrint("[AppRouteInformationParser] Parsed OAuthCallbackPath for provider: $provider");
      return OAuthCallbackPath(provider);
    }

    final firstSegment = segments.first;

    if (firstSegment == AppRouteSegments.landing) {
      debugPrint("[AppRouteInformationParser] Parsed LandingPath");
      return const LandingPath();
    }

    if (firstSegment == AppRouteSegments.auth) {
      debugPrint("[AppRouteInformationParser] Parsed AuthPath");
      return const AuthPath();
    }

    if (firstSegment == AppRouteSegments.home) {
      if (segments.length == 1) {
        debugPrint("[AppRouteInformationParser] Parsed HomeSubPath (default for /home): ${AppRouteSegments.allTasks}");
        return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      }
      if (segments.length == 2) {
        final subRouteSegment = segments[1];
        bool showRightSidebar = true;

        if ([AppRouteSegments.settings, AppRouteSegments.trash].contains(subRouteSegment)) {
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
      if (segments.length == 2) {
        final taskId = segments[1];
        debugPrint("[AppRouteInformationParser] Parsed TaskDetailPath with ID: $taskId");
        return TaskDetailPath(taskId);
      }
    }

    if (firstSegment == AppRouteSegments.team) {
      if (segments.length == 2) {
        final teamId = segments[1];
        debugPrint("[AppRouteInformationParser] Parsed TeamDetailPath with ID: $teamId");
        return TeamDetailPath(teamId);
      }
    }

    if (firstSegment == AppRouteSegments.joinTeam) {
      if (segments.length == 2) {
        final token = segments[1];
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

    debugPrint("[AppRouteInformationParser] URI not matched ($uri), returning UnknownPath.");
    return const UnknownPath();
  }

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) {
    if (configuration is LandingPath) {
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
    // ИЗМЕНЕНИЕ: Добавлена обработка OAuth путей
    if (configuration is OAuthCallbackPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.oAuthCallback(configuration.provider)));
    }
    if (configuration is UnknownPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.landing));
    }
    debugPrint("[AppRouteInformationParser] restoreRouteInformation: Unknown configuration type: ${configuration.runtimeType}");
    return null;
  }
}