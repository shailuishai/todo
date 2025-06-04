// lib/models/task_model.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ... (ApiTag, Enums, etc. остаются без изменений, как в вашем последнем предоставленном файле) ...
class ApiTag {
  final int id;
  final String name;
  final String? colorHex;
  final int ownerId;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;

  ApiTag({
    required this.id,
    required this.name,
    this.colorHex,
    required this.ownerId,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get displayColor {
    if (colorHex != null && colorHex!.isNotEmpty) {
      try {
        final buffer = StringBuffer();
        if (colorHex!.length == 6 || colorHex!.length == 7) buffer.write('ff');
        buffer.write(colorHex!.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (e) {
        return Colors.grey.shade400;
      }
    }
    return Colors.grey.shade400;
  }

  Color get backgroundColorPreview => displayColor.withOpacity(0.2);
  Color get textColorPreview => displayColor.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.9);
  Color get borderColorPreview => displayColor;

  factory ApiTag.fromJson(Map<String, dynamic> json) {
    return ApiTag(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Unknown Tag',
      colorHex: json['color'] as String?,
      ownerId: json['owner_id'] as int? ?? 0,
      type: json['type'] as String? ?? 'user',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorHex,
    'owner_id': ownerId,
    'type': type,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ApiTag &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              type == other.type;

  @override
  int get hashCode => id.hashCode ^ type.hashCode;

  ApiTag copyWith({
    int? id,
    String? name,
    String? colorHex,
    int? ownerId,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ApiTag(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum KanbanColumnStatus {
  todo,
  in_progress,
  deferred,
  done,
}

extension KanbanColumnStatusExtension on KanbanColumnStatus {
  String get title {
    switch (this) {
      case KanbanColumnStatus.todo:
        return 'К выполнению';
      case KanbanColumnStatus.in_progress:
        return 'В процессе';
      case KanbanColumnStatus.deferred:
        return 'Отложено';
      case KanbanColumnStatus.done:
        return 'Выполнено';
    }
  }
  String toJson() => name;

  static KanbanColumnStatus fromJson(String? jsonValue) {
    if (jsonValue == null) return KanbanColumnStatus.todo;
    return KanbanColumnStatus.values.firstWhere(
          (e) => e.name == jsonValue,
      orElse: () => KanbanColumnStatus.todo,
    );
  }
}

enum TaskPriority {
  low,
  medium,
  high,
}

extension TaskPriorityExtension on TaskPriority {
  String get name {
    switch (this) {
      case TaskPriority.low:
        return 'Низкий';
      case TaskPriority.medium:
        return 'Средний';
      case TaskPriority.high:
        return 'Высокий';
    }
  }
  String get nameUkr {
    switch (this) {
      case TaskPriority.low:
        return 'Низький';
      case TaskPriority.medium:
        return 'Середній';
      case TaskPriority.high:
        return 'Високий';
    }
  }

  IconData get icon {
    switch (this) {
      case TaskPriority.low:
        return Icons.arrow_downward_rounded;
      case TaskPriority.medium:
        return Icons.remove_rounded;
      case TaskPriority.high:
        return Icons.arrow_upward_rounded;
    }
  }

  int toJson() {
    switch (this) {
      case TaskPriority.low: return 1;
      case TaskPriority.medium: return 2;
      case TaskPriority.high: return 3;
    }
  }

  static TaskPriority fromJson(int? jsonValue) {
    if (jsonValue == null) return TaskPriority.low;
    switch (jsonValue) {
      case 1: return TaskPriority.low;
      case 2: return TaskPriority.medium;
      case 3: return TaskPriority.high;
      default: return TaskPriority.low;
    }
  }
}

class Task {
  final String taskId;
  String title;
  String? description;
  KanbanColumnStatus status;
  TaskPriority priority;
  DateTime? deadline;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? completedAt;
  DateTime? deletedAt;
  List<ApiTag> tags;
  String? teamId;
  String? teamName;
  String? assignedToUserId;
  String? createdByUserId;
  String? deletedByUserId;

  Task({
    required this.taskId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.deadline,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.deletedAt,
    this.tags = const [],
    this.teamId,
    this.teamName,
    this.assignedToUserId,
    this.createdByUserId,
    this.deletedByUserId,
  });

  bool get isTeamTask => teamId != null && teamId!.isNotEmpty;
  bool get isDeleted => deletedAt != null;

  factory Task.fromJson(Map<String, dynamic> json) {
    // <<<< ИСПРАВЛЕНИЕ ЗДЕСЬ >>>>
    // Предполагаем, что 'task_id' от API всегда приходит как int.
    // Если 'task_id' отсутствует или null, используем "0" как фоллбэк,
    // но это должно быть исключением, а не правилом для существующих задач.
    final int taskIdInt = json['task_id'] as int? ?? (json['id'] as int? ?? 0);

    return Task(
      taskId: taskIdInt.toString(), // Преобразуем в строку
      title: json['title'] as String? ?? 'Без названия',
      description: json['description'] as String?,
      status: KanbanColumnStatusExtension.fromJson(json['status'] as String?),
      priority: TaskPriorityExtension.fromJson(json['priority'] as int?),
      deadline: json['deadline'] != null ? DateTime.tryParse(json['deadline'] as String)?.toLocal() : null,
      createdAt: (DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now()).toLocal(),
      updatedAt: (DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now()).toLocal(),
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'] as String)?.toLocal() : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String)?.toLocal() : null,
      tags: (json['tags'] as List<dynamic>?)
          ?.map((tagJson) => ApiTag.fromJson(tagJson as Map<String, dynamic>))
          .toList() ??
          [],
      teamId: (json['team_id'] as int?)?.toString(),
      teamName: json['team_name'] as String?,
      assignedToUserId: (json['assigned_to_user_id'] as int?)?.toString(),
      createdByUserId: (json['created_by_user_id'] as int?)?.toString(),
      deletedByUserId: (json['deleted_by_user_id'] as int?)?.toString(),
    );
  }

  Map<String, dynamic> toJsonForCreate() {
    return {
      'title': title,
      if (description != null) 'description': description,
      'status': status.toJson(),
      'priority': priority.toJson(),
      if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      if (teamId != null && teamId!.isNotEmpty) 'team_id': int.tryParse(teamId!),
      if (assignedToUserId != null && assignedToUserId!.isNotEmpty) 'assigned_to_user_id': int.tryParse(assignedToUserId!),
      'user_tag_ids': tags.where((t) => t.type == 'user').map((t) => t.id).toList(),
      'team_tag_ids': tags.where((t) => t.type == 'team').map((t) => t.id).toList(),
    };
  }

  Map<String, dynamic> toJsonForUpdate() {
    return {
      'title': title,
      'description': description,
      'status': status.toJson(),
      'priority': priority.toJson(),
      'deadline': deadline?.toUtc().toIso8601String(),
      'assigned_to_user_id': (assignedToUserId != null && assignedToUserId!.isNotEmpty) ? int.tryParse(assignedToUserId!) : null,
      'user_tag_ids': tags.where((t) => t.type == 'user').map((t) => t.id).toList(),
      'team_tag_ids': tags.where((t) => t.type == 'team').map((t) => t.id).toList(),
    };
  }

  Task copyWith({
    String? taskId,
    String? title,
    String? description,
    bool? descriptionIsNull,
    KanbanColumnStatus? status,
    TaskPriority? priority,
    DateTime? deadline,
    bool? deadlineIsNull,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool? completedAtIsNull,
    DateTime? deletedAt,
    bool? deletedAtIsNull,
    List<ApiTag>? tags,
    String? teamId,
    bool? teamIdIsNull,
    String? teamName,
    bool? teamNameIsNull,
    String? assignedToUserId,
    bool? assignedToUserIdIsNull,
    String? createdByUserId,
    String? deletedByUserId,
    bool? deletedByUserIdIsNull,
  }) {
    return Task(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      description: descriptionIsNull == true ? null : (description ?? this.description),
      status: status ?? this.status,
      priority: priority ?? this.priority,
      deadline: deadlineIsNull == true ? null : (deadline ?? this.deadline),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAtIsNull == true ? null : (completedAt ?? this.completedAt),
      deletedAt: deletedAtIsNull == true ? null : (deletedAt ?? this.deletedAt),
      tags: tags ?? List<ApiTag>.from(this.tags),
      teamId: teamIdIsNull == true ? null : (teamId ?? this.teamId),
      teamName: teamNameIsNull == true ? null : (teamName ?? this.teamName),
      assignedToUserId: assignedToUserIdIsNull == true ? null : (assignedToUserId ?? this.assignedToUserId),
      createdByUserId: createdByUserId ?? this.createdByUserId,
      deletedByUserId: deletedByUserIdIsNull == true ? null : (deletedByUserId ?? this.deletedByUserId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Task &&
        other.taskId == taskId &&
        other.title == title &&
        other.description == description &&
        other.status == status &&
        other.priority == priority &&
        other.deadline == deadline &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt && // updatedAt важен для сравнения
        other.completedAt == completedAt &&
        other.deletedAt == deletedAt &&
        other.teamId == teamId &&
        other.teamName == teamName &&
        other.assignedToUserId == assignedToUserId &&
        other.createdByUserId == createdByUserId &&
        other.deletedByUserId == deletedByUserId &&
        listEquals(other.tags, tags);
  }

  @override
  int get hashCode {
    return Object.hash(
      taskId, title, description, status, priority, deadline,
      createdAt, updatedAt, completedAt, deletedAt, // updatedAt важен для hashCode
      teamId, teamName,
      assignedToUserId, createdByUserId, deletedByUserId,
      Object.hashAll(tags),
    );
  }
}