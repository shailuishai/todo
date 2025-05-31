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

// <<< НОВЫЙ КЛАСС ДЛЯ ПУТИ ПРИСОЕДИНЕНИЯ К КОМАНДЕ ПО ТОКЕНУ >>>
class JoinTeamByTokenPath extends AppRoutePath {
  final String token;
  const JoinTeamByTokenPath(this.token);
}
// <<< КОНЕЦ НОВОГО КЛАССА >>>

// <<< НОВЫЙ КЛАСС ДЛЯ ПУТИ ОБРАБОТКИ ПРИГЛАШЕНИЯ (ЭКРАН-ЗАГЛУШКА) >>>
class JoinTeamProcessingPath extends AppRoutePath {
  const JoinTeamProcessingPath();
}
// <<< КОНЕЦ НОВОГО КЛАССА >>>

class UnknownPath extends AppRoutePath {
  const UnknownPath();
}

// Этот класс используется внутри AppRouterDelegate, оставляем его там или выносим, если нужно для типизации извне
class LoadingPath extends AppRoutePath {
  const LoadingPath();
}