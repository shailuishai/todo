// lib/models/team_model.dart
import 'package:flutter/material.dart'; // Для Color

// Используется для идентификации роли пользователя в команде.
enum TeamMemberRole {
  owner,
  admin,
  editor,
  member; // Просто участник

  String toJson() => name;

  static TeamMemberRole fromJson(String? jsonValue) {
    if (jsonValue == null) return TeamMemberRole.member; // Фоллбэк
    return TeamMemberRole.values.firstWhere(
          (e) => e.name == jsonValue,
      orElse: () => TeamMemberRole.member,
    );
  }

  String get localizedName {
    switch (this) {
      case TeamMemberRole.owner:
        return 'Владелец';
      case TeamMemberRole.admin:
        return 'Администратор';
      case TeamMemberRole.editor:
        return 'Редактор';
      case TeamMemberRole.member:
        return 'Участник';
    }
  }
}

// Упрощенная информация о пользователе для списка участников команды
class UserLite {
  final int userId;
  final String login;
  final String? avatarUrl;
  final String? accentColor; // <<< НОВОЕ ПОЛЕ >>>

  UserLite({
    required this.userId,
    required this.login,
    this.avatarUrl,
    this.accentColor, // <<< НОВЫЙ ПАРАМЕТР КОНСТРУКТОРА >>>
  });

  factory UserLite.fromJson(Map<String, dynamic> json) {
    return UserLite(
      userId: json['user_id'] as int? ?? 0,
      login: json['login'] as String? ?? 'Unknown User',
      avatarUrl: json['avatar_url'] as String?,
      accentColor: json['accent_color'] as String?, // <<< ПАРСИНГ НОВОГО ПОЛЯ >>>
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'login': login,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (accentColor != null) 'accent_color': accentColor, // <<< ДОБАВЛЕНИЕ В JSON (если нужно) >>>
  };

  // Вспомогательный геттер для получения цвета из HEX строки
  // Можно вынести в утилиты, если используется в нескольких местах
  Color? get displayAccentColor {
    if (accentColor != null && accentColor!.isNotEmpty) {
      try {
        final buffer = StringBuffer();
        if (accentColor!.length == 6 || accentColor!.length == 7) buffer.write('ff');
        buffer.write(accentColor!.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (e) {
        debugPrint("Error parsing UserLite accentColor: $accentColor, error: $e");
        return null;
      }
    }
    return null;
  }
}

// Информация об участнике команды
class TeamMember {
  final UserLite user;
  final TeamMemberRole role;
  final DateTime joinedAt;

  TeamMember({
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      user: UserLite.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      role: TeamMemberRoleExtension.fromJson(json['role'] as String?),
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'role': role.toJson(),
    'joined_at': joinedAt.toIso8601String(),
  };
}

// Базовая информация о команде (для списка команд)
class Team {
  final String teamId;
  final String name;
  final String? description;
  final String? colorHex;
  final String? imageUrl;
  final int createdByUserId;
  final TeamMemberRole currentUserRole;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final int memberCount;

  Team({
    required this.teamId,
    required this.name,
    this.description,
    this.colorHex,
    this.imageUrl,
    required this.createdByUserId,
    required this.currentUserRole,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.memberCount = 0,
  });

  Color get displayColor {
    if (colorHex != null && colorHex!.isNotEmpty) {
      try {
        final buffer = StringBuffer();
        if (colorHex!.length == 6 || colorHex!.length == 7) buffer.write('ff');
        buffer.write(colorHex!.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (e) {
        return Colors.primaries[teamId.hashCode % Colors.primaries.length].shade400;
      }
    }
    return Colors.primaries[teamId.hashCode % Colors.primaries.length].shade400;
  }


  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      teamId: (json['team_id'] as int? ?? 0).toString(),
      name: json['name'] as String? ?? 'Без названия',
      description: json['description'] as String?,
      colorHex: json['color'] as String?,
      imageUrl: json['image_url'] as String?,
      createdByUserId: json['created_by_user_id'] as int? ?? 0,
      currentUserRole: TeamMemberRoleExtension.fromJson(json['current_user_role'] as String?),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      isDeleted: json['is_deleted'] as bool? ?? false,
      memberCount: json['member_count'] as int? ?? (json['members'] as List?)?.length ?? 0,
    );
  }
  Map<String, dynamic> toJson() => {
    'team_id': int.tryParse(teamId) ?? 0,
    'name': name,
    if (description != null) 'description': description,
    if (colorHex != null) 'color': colorHex,
    if (imageUrl != null) 'image_url': imageUrl,
    'created_by_user_id': createdByUserId,
    'current_user_role': currentUserRole.toJson(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
    'member_count': memberCount,
  };
}

// Детальная информация о команде (включает список участников)
class TeamDetail extends Team {
  final List<TeamMember> members;

  TeamDetail({
    required super.teamId,
    required super.name,
    super.description,
    super.colorHex,
    super.imageUrl,
    required super.createdByUserId,
    required super.currentUserRole,
    required super.createdAt,
    required super.updatedAt,
    super.isDeleted,
    super.memberCount,
    this.members = const [],
  });

  factory TeamDetail.fromJson(Map<String, dynamic> json) {
    return TeamDetail(
      teamId: (json['team_id'] as int? ?? 0).toString(),
      name: json['name'] as String? ?? 'Без названия',
      description: json['description'] as String?,
      colorHex: json['color'] as String?,
      imageUrl: json['image_url'] as String?,
      createdByUserId: json['created_by_user_id'] as int? ?? 0,
      currentUserRole: TeamMemberRoleExtension.fromJson(json['current_user_role'] as String?),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      isDeleted: json['is_deleted'] as bool? ?? false,
      members: (json['members'] as List<dynamic>?)
          ?.map((memberJson) => TeamMember.fromJson(memberJson as Map<String, dynamic>))
          .toList() ??
          [],
      memberCount: (json['members'] as List<dynamic>?)?.length ?? json['member_count'] as int? ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['members'] = members.map((m) => m.toJson()).toList();
    return json;
  }
}


// Для запроса на создание команды
class CreateTeamRequest {
  final String name;
  final String? description;
  final String? colorHex;

  CreateTeamRequest({
    required this.name,
    this.description,
    this.colorHex,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null && description!.isNotEmpty) 'description': description,
      if (colorHex != null && colorHex!.isNotEmpty) 'color': colorHex,
    };
  }
}

// Для запроса на обновление команды (отправляем только json_data)
class UpdateTeamDetailsRequest {
  final String? name;
  final String? description;
  final String? colorHex;
  final bool? resetImage;

  UpdateTeamDetailsRequest({
    this.name,
    this.description,
    this.colorHex,
    this.resetImage,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (colorHex != null) map['color'] = colorHex;
    if (resetImage != null) map['reset_image'] = resetImage;
    return map;
  }
}


// Для генерации токена-приглашения
class GenerateInviteTokenRequest {
  final int? expiresInHours;
  final TeamMemberRole? roleToAssign;

  GenerateInviteTokenRequest({this.expiresInHours, this.roleToAssign});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (expiresInHours != null) map['expires_in_hours'] = expiresInHours;
    if (roleToAssign != null) map['role_to_assign'] = roleToAssign!.toJson();
    return map;
  }
}

// Для ответа с токеном-приглашением
class TeamInviteTokenResponse {
  final String inviteToken;
  final DateTime? expiresAt; // Сделал nullable, если бэк может не прислать
  final TeamMemberRole? roleOnJoin; // Сделал nullable
  final String? inviteLink;

  TeamInviteTokenResponse({
    required this.inviteToken,
    this.expiresAt,
    this.roleOnJoin,
    this.inviteLink,
  });

  factory TeamInviteTokenResponse.fromJson(Map<String, dynamic> json) {
    return TeamInviteTokenResponse(
      inviteToken: json['invite_token'] as String,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      roleOnJoin: TeamMemberRoleExtension.fromJson(json['role_on_join'] as String?),
      inviteLink: json['invite_link'] as String?,
    );
  }
}

// Для запроса на присоединение к команде
class JoinTeamByTokenRequest {
  final String inviteToken;
  JoinTeamByTokenRequest({required this.inviteToken});
  Map<String, dynamic> toJson() => {'invite_token': inviteToken};
}

// Для добавления участника
class AddTeamMemberRequest {
  final int userId;
  final TeamMemberRole? role;

  AddTeamMemberRequest({required this.userId, this.role});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'user_id': userId};
    if (role != null) map['role'] = role!.toJson();
    return map;
  }
}

// Для обновления роли участника
class UpdateTeamMemberRoleRequest {
  final TeamMemberRole role;
  UpdateTeamMemberRoleRequest({required this.role});
  Map<String, dynamic> toJson() => {'role': role.toJson()};
}


// Вспомогательное расширение для TeamMemberRole (для fromJson, toJson уже есть в enum)
extension TeamMemberRoleExtension on TeamMemberRole {
  static TeamMemberRole fromJson(String? value) {
    if (value == null) return TeamMemberRole.member;
    try {
      return TeamMemberRole.values.firstWhere((e) => e.name == value);
    } catch (e) {
      return TeamMemberRole.member;
    }
  }
}