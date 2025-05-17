import 'package:flutter/material.dart';
import 'app_route_path.dart';
import 'app_pages.dart'; // Для AppRoutes и AppRouteSegments

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(RouteInformation routeInformation) async {
    final uri = Uri.parse(routeInformation.uri.toString());

    // Аутентификация
    // Если путь пустой (только #) или /auth
    if (uri.pathSegments.isEmpty || (uri.pathSegments.isNotEmpty && uri.pathSegments.first == AppRouteSegments.auth)) {
      return const AuthPath();
    }

    // Главная страница и ее подразделы
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == AppRouteSegments.home) {
      if (uri.pathSegments.length == 1) {
        // Просто /home, перенаправляем на дефолтный подраздел (например, all-tasks)
        return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      }
      if (uri.pathSegments.length == 2) {
        final subRouteSegment = uri.pathSegments[1];
        // Проверяем, является ли это известным подмаршрутом
        switch (subRouteSegment) {
          case AppRouteSegments.settings:
            return const HomeSubPath(AppRouteSegments.settings, showRightSidebar: false);
          case AppRouteSegments.allTasks:
            return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
          case AppRouteSegments.personalTasks:
            return const HomeSubPath(AppRouteSegments.personalTasks, showRightSidebar: true);
          case AppRouteSegments.teams:
            return const HomeSubPath(AppRouteSegments.teams, showRightSidebar: true);
          case AppRouteSegments.trash:
            return const HomeSubPath(AppRouteSegments.trash, showRightSidebar: true);
          default:
          // Если подраздел неизвестен, можно либо на 404, либо на дефолтный /home
            return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true); // Или UnknownPath
        }
      }
      // Если больше 2 сегментов после /home, например /home/settings/details - это не обрабатывается
      // Вернем дефолтный или UnknownPath
      return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true); // Или UnknownPath()
    }
    // По умолчанию, если ничего не подошло
    return const UnknownPath();
  }

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) {
    if (configuration is AuthPath) {
      return RouteInformation(uri: Uri.parse(AppRoutes.auth));
    }
    // HomePath не должен напрямую восстанавливаться, всегда идем на конкретный HomeSubPath
    if (configuration is HomePath) {
      // Перенаправляем на дефолтный sub-route
      return RouteInformation(uri: Uri.parse('/${AppRouteSegments.home}/${AppRouteSegments.allTasks}'));
    }
    if (configuration is HomeSubPath) {
      // configuration.subRoute теперь это 'settings', 'all-tasks'
      return RouteInformation(uri: Uri.parse('/${AppRouteSegments.home}/${configuration.subRoute}'));
    }
    if (configuration is UnknownPath) {
      return RouteInformation(uri: Uri.parse('/404')); // или просто /unknown
    }
    return null;
  }
}