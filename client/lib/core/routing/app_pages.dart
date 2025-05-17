import 'package:flutter/material.dart';
import '../../screens/auth_screen.dart';
import '../../screens/home_screen.dart';
// import '../../screens/settings_screen.dart'; // Не используется напрямую здесь
import 'app_route_path.dart';

// Определяем константы для имен СЕГМЕНТОВ маршрутов
class AppRouteSegments {
  static const String auth = 'auth';
  static const String home = 'home';
  static const String settings = 'settings';
  static const String allTasks = 'all-tasks';
  static const String personalTasks = 'personal-tasks';
  static const String teams = 'teams';
  static const String trash = 'trash';
}

// Определяем константы для ПОЛНЫХ имен маршрутов
class AppRoutes {
  static const String auth = '/${AppRouteSegments.auth}';
  static const String home = '/${AppRouteSegments.home}';
  static const String settings = '/${AppRouteSegments.home}/${AppRouteSegments.settings}';
  static const String allTasks = '/${AppRouteSegments.home}/${AppRouteSegments.allTasks}';
  static const String personalTasks = '/${AppRouteSegments.home}/${AppRouteSegments.personalTasks}';
  static const String teams = '/${AppRouteSegments.home}/${AppRouteSegments.teams}';
  static const String trash = '/${AppRouteSegments.home}/${AppRouteSegments.trash}';
}


// Функция для создания MaterialPage на основе пути
MaterialPage buildPage(AppRoutePath path, {Object? arguments}) {
  String name = '/unknown'; // По умолчанию
  Widget child;

  if (path is AuthPath) {
    name = AppRoutes.auth;
    child = const AuthScreen();
  } else if (path is HomePath) { // Основной путь /home
    name = AppRoutes.home;
    // По умолчанию открываем "Все задачи" или другую дефолтную страницу
    // Передаем только сегмент
    child = const HomePage(initialSubRoute: AppRouteSegments.allTasks);
  } else if (path is HomeSubPath) {
    // path.subRoute теперь это просто 'settings', 'all-tasks' и т.д.
    name = '/${AppRouteSegments.home}/${path.subRoute}';
    // HomePage будет отвечать за отображение нужного контента на основе subRoute
    child = HomePage(initialSubRoute: path.subRoute, showRightSidebar: path.showRightSidebar);
  } else { // UnknownPath
    name = '/unknown';
    child = const Scaffold(
      body: Center(child: Text('404 - Страница не найдена')),
    );
  }

  return MaterialPage(
    key: ValueKey(name), // Ключ важен для корректной работы Navigator 2.0
    name: name, // Имя маршрута для отладки и аналитики
    child: child,
    arguments: arguments,
  );
}