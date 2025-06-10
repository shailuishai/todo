// lib/core/routing/app_route_path.dart
abstract class AppRoutePath {
  const AppRoutePath();
}

class LandingPath extends AppRoutePath {
  const LandingPath();
}

class AuthPath extends AppRoutePath {
  const AuthPath();
}

class HomePath extends AppRoutePath {
  const HomePath();
}

class HomeSubPath extends AppRoutePath {
  final String subRoute;
  final bool showRightSidebar;

  const HomeSubPath(this.subRoute, {this.showRightSidebar = true});
}

class TaskDetailPath extends AppRoutePath {
  final String taskId;
  const TaskDetailPath(this.taskId);
}

class TeamDetailPath extends AppRoutePath {
  final String teamId;
  const TeamDetailPath(this.teamId);
}

class JoinTeamByTokenPath extends AppRoutePath {
  final String token;
  const JoinTeamByTokenPath(this.token);
}

class JoinTeamProcessingPath extends AppRoutePath {
  const JoinTeamProcessingPath();
}

class UnknownPath extends AppRoutePath {
  const UnknownPath();
}

class LoadingPath extends AppRoutePath {
  const LoadingPath();
}

// ИЗМЕНЕНИЕ: ДОБАВЛЕНЫ КЛАССЫ ДЛЯ ПУТЕЙ OAUTH
class OAuthSuccessPath extends AppRoutePath {
  const OAuthSuccessPath();
}

class OAuthErrorPath extends AppRoutePath {
  final String? error;
  const OAuthErrorPath({this.error});
}