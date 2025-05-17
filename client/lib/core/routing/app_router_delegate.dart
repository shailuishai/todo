import 'package:flutter/material.dart';
import 'app_route_path.dart';
import 'app_pages.dart'; // Для buildPage, AppRoutes и AppRouteSegments

// Для управления состоянием аутентификации
class AuthState extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  void login() {
    _isLoggedIn = true;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    notifyListeners();
  }
}


class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {

  final AuthState authState;
  AppRoutePath _currentPath = const AuthPath(); // Начальный путь

  AppRouterDelegate({required this.authState}) {
    authState.addListener(() {
      if (authState.isLoggedIn && _currentPath is AuthPath) {
        // Передаем только сегмент
        _currentPath = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
      } else if (!authState.isLoggedIn && (_currentPath is HomePath || _currentPath is HomeSubPath)) {
        _currentPath = const AuthPath();
      }
      notifyListeners();
    });
  }

  @override
  GlobalKey<NavigatorState> get navigatorKey => GlobalKey<NavigatorState>();

  @override
  AppRoutePath get currentConfiguration {
    if (!authState.isLoggedIn) return const AuthPath();
    if (authState.isLoggedIn && _currentPath is AuthPath) {
      // Передаем только сегмент
      return const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
    }
    return _currentPath;
  }

  @override
  Widget build(BuildContext context) {
    List<Page> stack = [];

    if (!authState.isLoggedIn) {
      stack.add(buildPage(const AuthPath()));
    } else {
      if (_currentPath is HomeSubPath) {
        final homeSubPath = _currentPath as HomeSubPath;
        stack.add(buildPage(homeSubPath));
      } else if (_currentPath is HomePath) {
        // Передаем только сегмент
        stack.add(buildPage(const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true)));
      }
      else {
        // Передаем только сегмент
        stack.add(buildPage(const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true)));
      }
    }
    if (stack.isEmpty) {
      stack.add(buildPage(const UnknownPath()));
    }

    return Navigator(
      key: navigatorKey,
      pages: stack,
      onPopPage: (route, result) {
        if (!route.didPop(result)) {
          return false;
        }
        if (stack.length > 1) {
          final previousPage = stack[stack.length - 2];
          final previousPageName = previousPage.name;

          if (previousPageName == AppRoutes.auth) {
            _currentPath = const AuthPath();
          } else if (previousPageName != null && previousPageName.startsWith('/${AppRouteSegments.home}/')) {
            // Извлекаем сегмент из полного имени пути
            String segment = previousPageName.replaceFirst('/${AppRouteSegments.home}/', '');
            // Определяем showRightSidebar на основе сегмента.
            // Эту логику можно сделать более гибкой, если у вас много разных правил.
            bool showSidebar = true;
            if (segment == AppRouteSegments.settings) {
              showSidebar = false;
            }
            _currentPath = HomeSubPath(segment, showRightSidebar: showSidebar);

          } else {
            // Fallback, если предыдущий путь не распознан как home subpath
            _currentPath = const HomeSubPath(AppRouteSegments.allTasks, showRightSidebar: true);
          }
          notifyListeners();
          return true;
        }
        return false;
      },
    );
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath path) async {
    _currentPath = path;
    // notifyListeners() не нужен здесь явно, если currentConfiguration правильно обновляется
    // и build вызывается после этого. Однако, если есть сомнения, можно раскомментировать,
    // но это может привести к двойному вызову notifyListeners.
    // В большинстве случаев RouterDelegate сам заботится о перестроении,
    // когда currentConfiguration изменяется в результате setNewRoutePath.
  }

  void navigateTo(AppRoutePath path) {
    _currentPath = path;
    notifyListeners();
  }
}