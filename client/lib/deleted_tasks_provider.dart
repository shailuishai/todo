// lib/deleted_tasks_provider.dart
import 'package:flutter/foundation.dart';
import 'models/task_model.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // Для сохранения в будущем
// import 'dart:convert'; // Для сохранения в будущем

class DeletedTasksProvider extends ChangeNotifier {
  List<Task> _deletedTasks = [];

  // TODO: В будущем загружать из SharedPreferences
  // DeletedTasksProvider() {
  //   _loadDeletedTasks();
  // }

  List<Task> get deletedTasks {
    // Сортировка по дате удаления (новые вверху)
    _deletedTasks.sort((a, b) => (b.deletedAt ?? DateTime(0)).compareTo(a.deletedAt ?? DateTime(0)));
    return List.unmodifiable(_deletedTasks);
  }

  void moveToTrash(Task task, {String? deletedByUserId}) {
    // Убедимся, что задача еще не в корзине
    if (_deletedTasks.any((t) => t.taskId == task.taskId)) return;

    final taskForTrash = task.copyWith(
      deletedAt: DateTime.now(),
      deletedByUserId: deletedByUserId,
    );
    _deletedTasks.add(taskForTrash);
    // _saveDeletedTasks(); // TODO: Сохранять в SharedPreferences
    notifyListeners();
  }

  void restoreFromTrash(String taskId) {
    final taskToRestore = _deletedTasks.firstWhere((t) => t.taskId == taskId, orElse: () => throw Exception("Task not found in trash"));
    _deletedTasks.removeWhere((t) => t.taskId == taskId);

    // Здесь в реальном приложении нужно будет уведомить другой провайдер (например, TaskProvider)
    // чтобы он добавил задачу обратно в активные списки.
    // Пока что задача просто удаляется из корзины.
    // Для восстановления в UI, экран, который отображает активные задачи,
    // должен будет ее снова добавить (например, если TaskProvider будет управлять всеми задачами).

    // _saveDeletedTasks(); // TODO: Сохранять в SharedPreferences
    notifyListeners();

    // Возвращаем восстановленную задачу, чтобы ее можно было обработать дальше
    // (например, добавить обратно в список активных задач в UI, если нет центрального TaskProvider)
    // return taskToRestore.copyWith(deletedAtIsNull: true, deletedByUserIdIsNull: true);
  }

  Task getTaskById(String taskId) {
    return _deletedTasks.firstWhere((t) => t.taskId == taskId, orElse: () => throw Exception("Task not found in trash with ID: $taskId"));
  }

  void deletePermanently(String taskId) {
    _deletedTasks.removeWhere((t) => t.taskId == taskId);
    // _saveDeletedTasks(); // TODO: Сохранять в SharedPreferences
    notifyListeners();
  }

// Примерные методы для сохранения/загрузки (нужно доработать Task.toJson/fromJson)
/*
  Future<void> _saveDeletedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> tasksJson = _deletedTasks.map((task) => jsonEncode(task.toJson())).toList(); // Предполагая, что есть toJson()
    await prefs.setStringList('deleted_tasks', tasksJson);
  }

  Future<void> _loadDeletedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? tasksJson = prefs.getStringList('deleted_tasks');
    if (tasksJson != null) {
      _deletedTasks = tasksJson.map((json) => Task.fromJson(jsonDecode(json))).toList(); // Предполагая, что есть fromJson()
      notifyListeners();
    }
  }
  */
}