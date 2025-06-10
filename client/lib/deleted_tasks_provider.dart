// lib/deleted_tasks_provider.dart
import 'package:flutter/foundation.dart';
import 'models/task_model.dart';
import 'services/api_service.dart';
import 'auth_state.dart';

class DeletedTasksProvider extends ChangeNotifier {
  final ApiService _apiService;
  final AuthState _authState;
  List<Task> _deletedTasks = [];
  bool _isLoading = false;
  String? _error;

  DeletedTasksProvider(this._apiService, this._authState) {
    _authState.addListener(_onAuthStateChanged);
    if (_authState.isLoggedIn) {
      fetchDeletedTasks();
    }
  }

  // --- Getters ---
  List<Task> get deletedTasks => List.unmodifiable(_deletedTasks);
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _onAuthStateChanged() {
    if (_authState.isLoggedIn) {
      fetchDeletedTasks();
    } else {
      _deletedTasks = [];
      _error = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDeletedTasks() async {
    if (!_authState.isLoggedIn) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Используем существующий метод getTasks с новым query-параметром
      final tasks = await _apiService.getTasks(queryParams: {'is_deleted': 'true'});
      _deletedTasks = tasks;
    } on ApiException catch (e) {
      _error = "Ошибка API: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Вызывается из TaskProvider после успешного логического удаления
  void addDeletedTask(Task task) {
    // Добавляем задачу в начало списка, чтобы она сразу появилась в UI
    if (!_deletedTasks.any((t) => t.taskId == task.taskId)) {
      _deletedTasks.insert(0, task);
      notifyListeners();
    }
  }

  Future<Task?> restoreFromTrash(String taskId) async {
    if (!_authState.isLoggedIn) return null;

    final originalIndex = _deletedTasks.indexWhere((t) => t.taskId == taskId);
    if (originalIndex == -1) return null;

    final taskToRestore = _deletedTasks[originalIndex];
    _deletedTasks.removeAt(originalIndex);
    notifyListeners();

    try {
      final restoredTask = await _apiService.restoreTask(taskId);
      return restoredTask;
    } catch (e) {
      // Возвращаем задачу обратно в список, если произошла ошибка
      _deletedTasks.insert(originalIndex, taskToRestore);
      _error = "Не удалось восстановить задачу: $e";
      notifyListeners();
      return null;
    }
  }

  Future<bool> deletePermanently(String taskId) async {
    if (!_authState.isLoggedIn) return false;

    final originalIndex = _deletedTasks.indexWhere((t) => t.taskId == taskId);
    if (originalIndex == -1) return false;

    final taskToDelete = _deletedTasks[originalIndex];
    _deletedTasks.removeAt(originalIndex);
    notifyListeners();

    try {
      await _apiService.deleteTaskPermanently(taskId);
      return true;
    } catch (e) {
      // Возвращаем задачу обратно, если ошибка
      _deletedTasks.insert(originalIndex, taskToDelete);
      _error = "Не удалось окончательно удалить задачу: $e";
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }
}