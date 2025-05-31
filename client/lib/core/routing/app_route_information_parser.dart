// lib/core/routing/app_route_information_parser.dart
import 'package:flutter/material.dart';
import 'app_route_path.dart';
import 'app_pages.dart';
// import 'app_router_delegate.dart'; // Не используется здесь напрямую

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(RouteInformation routeInformation) async {
    final uri = Uri.parse(routeInformation.uri.toString());
    debugPrint("[AppRouteInformationParser] Parsing URI: $uri");

    if (uri.pathSegments.isEmpty) {
      debugPrint("[AppRouteInformationParser] URI is empty, returning HomePath");
      return const HomePath(); // Или HomeSubPath(AppRouteSegments.allTasks)
    }

    final firstSegment = uri.pathSegments.first;

    if (firstSegment == AppRouteSegments.auth) {
      debugPrint("[AppRouteInformationParser] Parsed AuthPath");
      return const AuthPath();
    }

    if (firstSegment == AppRouteSegments.home) {
      if (uri.pathSegments.length == 1) {
        // Для /home по умолчанию показываем allTasks с правым сайдбаром
        debugPrint("[AppRouteInformationParser] Parsed HomeSubPath (default for /home): ${AppRouteSegments.allTasks}");
        return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      }
      if (uri.pathSegments.length == 2) {
        final subRouteSegment = uri.pathSegments[1];
        bool showRightSidebar = true; // По умолчанию правый сайдбар показываем

        // Определяем, нужно ли скрывать правый сайдбар для определенных подмаршрутов
        if ([
          AppRouteSegments.settings,
          AppRouteSegments.trash,
          // AppRouteSegments.calendar, // Calendar теперь с правым сайдбаром
        ].contains(subRouteSegment)) {
          showRightSidebar = false;
        }

        final validHomeSubRoutes = [
          AppRouteSegments.settings, AppRouteSegments.allTasks, AppRouteSegments.personalTasks,
          AppRouteSegments.teams, AppRouteSegments.trash, AppRouteSegments.calendar,
        ];

        // Особое правило для /home/teams и /home/calendar - всегда показывать правый сайдбар
        if (subRouteSegment == AppRouteSegments.teams || subRouteSegment == AppRouteSegments.calendar) {
          showRightSidebar = true;
        }


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

    if (firstSegment == AppRouteSegments.team) { // Это для /team/:id
      if (uri.pathSegments.length == 2) {
        final teamId = uri.pathSegments[1];
        debugPrint("[AppRouteInformationParser] Parsed TeamDetailPath with ID: $teamId");
        return TeamDetailPath(teamId);
      }
    }

    // <<< ОБРАБОТКА ССЫЛКИ-ПРИГЛАШЕНИЯ >>>
    if (firstSegment == AppRouteSegments.joinTeam) {
      if (uri.pathSegments.length == 2) {
        final token = uri.pathSegments[1];
        if (token.isNotEmpty) {
          debugPrint("[AppRouteInformationParser] Parsed JoinTeamByTokenPath with token: $token");
          return JoinTeamByTokenPath(token);
        }
      }
      // Если URL не соответствует /join-team/TOKEN, считаем это невалидным и отправляем на главную
      debugPrint("[AppRouteInformationParser] Invalid JoinTeamByTokenPath, token missing or malformed URI: $uri. Returning HomePath.");
      return const HomePath(); // Или UnknownPath, если это предпочтительнее
    }

    // <<< ОБРАБОТКА ПУТИ К ЭКРАНУ ЗАГЛУШКЕ >>>
    if (firstSegment == AppRouteSegments.processingInvite) {
      debugPrint("[AppRouteInformationParser] Parsed JoinTeamProcessingPath");
      return const JoinTeamProcessingPath();
    }

    debugPrint("[AppRouteInformationParser] URI not matched, returning UnknownPath for $uri");
    return const UnknownPath();
  }

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) {
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
    if (configuration is JoinTeamByTokenPath) { // <<< ВОССТАНОВЛЕНИЕ URL ДЛЯ ССЫЛКИ-ПРИГЛАШЕНИЯ >>>
      return RouteInformation(uri: Uri.parse(AppRoutes.joinTeamByToken(configuration.token)));
    }
    if (configuration is JoinTeamProcessingPath) { // <<< ВОССТАНОВЛЕНИЕ URL ДЛЯ ЭКРАНА-ЗАГЛУШКИ >>>
      return RouteInformation(uri: Uri.parse(AppRoutes.processingInvite));
    }
    if (configuration is UnknownPath) {
      // Можно редиректить на дефолтный HomeSubPath, если пользователь залогинен, или на AuthPath.
      // Пока оставим AuthPath, т.к. UnknownPath обычно означает ошибку в URL.
      return RouteInformation(uri: Uri.parse(AppRoutes.auth));
    }
    // if (configuration is LoadingPath) { // LoadingPath не должен восстанавливаться как URL
    //   return null;
    // }
    debugPrint("[AppRouteInformationParser] restoreRouteInformation: Unknown configuration type: ${configuration.runtimeType}");
    return null; // Для LoadingPath и других неизвестных
  }
}