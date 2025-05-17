// lib/core/routing/app_route_path.dart
abstract class AppRoutePath {
  const AppRoutePath();
}

class AuthPath extends AppRoutePath {
  const AuthPath();
}

class HomePath extends AppRoutePath {
  const HomePath();
}

// Для вложенных путей внутри HomePage (например, /home/settings)
class HomeSubPath extends AppRoutePath {
  final String subRoute; // например, 'settings', 'all-tasks'
  final bool showRightSidebar;

  const HomeSubPath(this.subRoute, {this.showRightSidebar = true});
}

class UnknownPath extends AppRoutePath {
  const UnknownPath();
}