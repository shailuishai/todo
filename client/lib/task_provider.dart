// lib/task_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:collection';
import 'deleted_tasks_provider.dart';
import 'models/task_model.dart';
import 'services/api_service.dart';
import 'auth_state.dart';

enum TaskListViewType {
  allAssignedOrCreated,
  personal,
  teamSpecific,
}

class TaskProvider with ChangeNotifier {
  final ApiService _apiService;
  final AuthState _authState;
  final DeletedTasksProvider _deletedTasksProvider;

  List<Task> _allFetchedTasks = [];
  bool _isLoadingList = false;
  bool _isProcessingTask = false;
  String? _error;

  Map<String, dynamic> _activeLocalFilters = {};
  String? _localSortByField;
  String? _localSortOrder;

  TaskListViewType? _currentFetchedViewType;
  String? _currentFetchedTeamId;

  TaskProvider(this._apiService, this._authState, this._deletedTasksProvider) {
    _authState.addListener(_onAuthStateChanged);
    if (_authState.isLoggedIn) {
      fetchTasks(viewType: TaskListViewType.allAssignedOrCreated);
    }
  }

  void _onAuthStateChanged() {
    if (_authState.isLoggedIn) {
      fetchTasks(viewType: TaskListViewType.allAssignedOrCreated);
    } else {
      _allFetchedTasks = [];
      _error = null;
      _isLoadingList = false;
      _isProcessingTask = false;
      _activeLocalFilters = {};
      _localSortByField = null;
      _localSortOrder = null;
      _currentFetchedViewType = null;
      _currentFetchedTeamId = null;
      notifyListeners();
    }
  }

  bool get isLoadingList => _isLoadingList;
  bool get isProcessingTask => _isProcessingTask;
  String? get error => _error;
  Map<String, dynamic> get activeLocalFilters => UnmodifiableMapView(_activeLocalFilters);
  String? get localSortByField => _localSortByField;
  String? get localSortOrder => _localSortOrder;

  Future<void> fetchTasks({
    TaskListViewType? viewType,
    String? teamId,
    bool forceBackendCall = false,
  }) async {
    if (!_authState.isLoggedIn || _authState.currentUser == null) {
      _allFetchedTasks = [];
      _isLoadingList = false;
      _currentFetchedViewType = null;
      _currentFetchedTeamId = null;
      notifyListeners();
      return;
    }

    bool contextChanged = true;
    if (teamId != null) {
      contextChanged = (_currentFetchedTeamId != teamId || _currentFetchedViewType != TaskListViewType.teamSpecific);
    } else if (viewType != null) {
      contextChanged = (_currentFetchedViewType != viewType || _currentFetchedTeamId != null);
    } else {
      contextChanged = (_currentFetchedViewType != TaskListViewType.allAssignedOrCreated || _currentFetchedTeamId != null);
    }

    if (!forceBackendCall && !contextChanged && !_isLoadingList && _error == null && _allFetchedTasks.isNotEmpty) {
      debugPrint("[TaskProvider.fetchTasks] Context for viewType: ${_currentFetchedViewType} / teamId: ${_currentFetchedTeamId} seems up-to-date. Skipping API call.");
      return;
    }

    _isLoadingList = true;
    _error = null;
    if (contextChanged) {
      _activeLocalFilters = {};
      _localSortByField = null;
      _localSortOrder = null;
      debugPrint("[TaskProvider.fetchTasks] Context changed. Local filters and sort cleared.");
    }
    notifyListeners();

    Map<String, String> queryParamsForApi = {};
    String fetchContextDescription = "default";

    if (teamId != null) {
      queryParamsForApi['team_id'] = teamId;
      _currentFetchedViewType = TaskListViewType.teamSpecific;
      _currentFetchedTeamId = teamId;
      fetchContextDescription = "team: $teamId";
    } else if (viewType != null) {
      _currentFetchedViewType = viewType;
      _currentFetchedTeamId = null;
      switch (viewType) {
        case TaskListViewType.allAssignedOrCreated:
          queryParamsForApi['view_type'] = 'global';
          fetchContextDescription = "global view (API)";
          break;
        case TaskListViewType.personal:
          queryParamsForApi['view_type'] = 'personal';
          fetchContextDescription = "personal view (API)";
          break;
        case TaskListViewType.teamSpecific:
          _error = "Для TaskListViewType.teamSpecific должен быть указан teamId.";
          _isLoadingList = false;
          notifyListeners();
          debugPrint("[TaskProvider.fetchTasks] ERROR: teamSpecific view type without teamId.");
          return;
      }
    } else {
      queryParamsForApi['view_type'] = 'global';
      _currentFetchedViewType = TaskListViewType.allAssignedOrCreated;
      _currentFetchedTeamId = null;
      fetchContextDescription = "default global view (API)";
    }

    debugPrint("[TaskProvider.fetchTasks] Fetching for context: $fetchContextDescription with API queryParams: $queryParamsForApi");

    try {
      _allFetchedTasks = await _apiService.getTasks(queryParams: queryParamsForApi.isNotEmpty ? queryParamsForApi : null);
      debugPrint("[TaskProvider.fetchTasks] Loaded ${_allFetchedTasks.length} tasks from server for context: $fetchContextDescription");
    } on ApiException catch (e) {
      _error = "Ошибка загрузки задач (${e.statusCode}): ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка: $e";
    }
    _isLoadingList = false;
    notifyListeners();
  }

  List<Task> _applyLocalFiltersAndSort(List<Task> tasks) {
    List<Task> filteredTasks = List.from(tasks);

    _activeLocalFilters.forEach((key, value) {
      if (value == null || value.toString().isEmpty && key != 'assigned_to_user_id') return;
      switch (key) {
        case 'status':
          filteredTasks = filteredTasks.where((task) => task.status.toJson() == value).toList();
          break;
        case 'priority':
          final priorityValue = value is int ? value : int.tryParse(value.toString());
          if (priorityValue != null) {
            filteredTasks = filteredTasks.where((task) => task.priority.toJson() == priorityValue).toList();
          }
          break;
        case 'assigned_to_user_id':
          if (value.toString() == "0") {
            filteredTasks = filteredTasks.where((task) => task.assignedToUserId == null || task.assignedToUserId!.isEmpty).toList();
          } else if (value.toString().isNotEmpty) {
            filteredTasks = filteredTasks.where((task) => task.assignedToUserId == value.toString()).toList();
          }
          break;
        case 'search':
          String searchTerm = value.toString().toLowerCase().trim();
          if (searchTerm.isNotEmpty) {
            filteredTasks = filteredTasks.where((task) =>
            task.title.toLowerCase().contains(searchTerm) ||
                (task.description?.toLowerCase().contains(searchTerm) ?? false)
            ).toList();
          }
          break;
        case 'tag_ids':
          if (value is List<int> && value.isNotEmpty) {
            filteredTasks = filteredTasks.where((task) {
              if (task.tags.isEmpty) return false;
              return task.tags.any((tag) => value.contains(tag.id));
            }).toList();
          }
          break;
        case 'deadline_from':
          if (value is DateTime) {
            filteredTasks = filteredTasks.where((task) =>
            task.deadline != null && !task.deadline!.isBefore(value)
            ).toList();
          }
          break;
        case 'deadline_to':
          if (value is DateTime) {
            final endOfDay = DateTime(value.year, value.month, value.day, 23, 59, 59);
            filteredTasks = filteredTasks.where((task) =>
            task.deadline != null && !task.deadline!.isAfter(endOfDay)
            ).toList();
          }
          break;
      }
    });

    if (_localSortByField != null && _localSortOrder != null) {
      filteredTasks.sort((a, b) {
        int comparisonResult = 0;
        switch (_localSortByField) {
          case 'title':
            comparisonResult = a.title.toLowerCase().compareTo(b.title.toLowerCase());
            break;
          case 'status':
            comparisonResult = a.status.index.compareTo(b.status.index);
            break;
          case 'priority':
          // Для сортировки по убыванию (High -> Low), b должен идти перед a, если b.priority > a.priority
            comparisonResult = b.priority.index.compareTo(a.priority.index);
            // Если нужно ASC (Low -> High), то a.priority.index.compareTo(b.priority.index)
            // Стандартная инверсия ниже обработает это.
            // Оставим a.compareTo(b) для консистентности, инверсия ниже сделает свое дело.
            // comparisonResult = a.priority.index.compareTo(b.priority.index); // Low (0) < Medium (1) < High (2)
            break;
          case 'deadline':
            final dateA = a.deadline;
            final dateB = b.deadline;
            if (dateA == null && dateB == null) comparisonResult = 0;
            else if (dateA == null) comparisonResult = 1; // nulls last
            else if (dateB == null) comparisonResult = -1; // nulls last
            else comparisonResult = dateA.compareTo(dateB);
            break;
          case 'created_at':
            comparisonResult = a.createdAt.compareTo(b.createdAt);
            break;
          case 'updated_at':
            comparisonResult = a.updatedAt.compareTo(b.updatedAt);
            break;
          default:
            comparisonResult = 0;
        }

        // Отдельная обработка для приоритета, если хотим интуитивное DESC/ASC
        if (_localSortByField == 'priority') {
          // Индекс: Low=0, Med=1, High=2
          // ASC (по значению) -> Low, Med, High -> a.index.compareTo(b.index)
          // DESC (по значению) -> High, Med, Low -> b.index.compareTo(a.index)
          int prioA = a.priority.index;
          int prioB = b.priority.index;
          comparisonResult = (_localSortOrder == 'ASC') ? prioA.compareTo(prioB) : prioB.compareTo(prioA);
          return comparisonResult; // Направление уже учтено
        }

        return _localSortOrder == 'ASC' ? comparisonResult : -comparisonResult;
      });
    } else {
      // Дефолтная сортировка
      filteredTasks.sort((a, b) {
        int priorityCompare = b.priority.index.compareTo(a.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        DateTime deadlineA = a.deadline ?? DateTime(9999,12,31);
        DateTime deadlineB = b.deadline ?? DateTime(9999,12,31);
        int deadlineCompare = deadlineA.compareTo(deadlineB);
        if (deadlineCompare != 0) return deadlineCompare;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    }
    return filteredTasks;
  }

  List<Task> get tasksForGlobalView {
    if (!_authState.isLoggedIn || _authState.currentUser == null) return [];
    return _applyLocalFiltersAndSort(_allFetchedTasks.where((task) => !task.isDeleted).toList());
  }

  List<Task> get tasksForPersonalView {
    if (!_authState.isLoggedIn || _authState.currentUser == null) return [];
    return _applyLocalFiltersAndSort(_allFetchedTasks.where((task) => !task.isDeleted && task.teamId == null).toList());
  }

  List<Task> tasksForTeamView(String teamId) {
    if (!_authState.isLoggedIn) return [];
    return _applyLocalFiltersAndSort(_allFetchedTasks.where((task) => !task.isDeleted && task.teamId == teamId).toList());
  }

  List<Task> get allNonDeletedFetchedTasks => UnmodifiableListView(_allFetchedTasks.where((task) => !task.isDeleted).toList());

  void applyFilters(Map<String, dynamic> newFilters) {
    _activeLocalFilters = Map.from(newFilters);
    debugPrint("[TaskProvider] Local filters applied: $_activeLocalFilters");
    notifyListeners();
  }

  void clearFilters() {
    _activeLocalFilters = {};
    debugPrint("[TaskProvider] Local filters cleared.");
    notifyListeners();
  }

  void applySorting(String field, String order) {
    _localSortByField = field;
    _localSortOrder = order;
    debugPrint("[TaskProvider.applySorting] Local sorting: Field=$_localSortByField, Order=$_localSortOrder. Notifying.");
    notifyListeners();
  }

  void clearSorting() {
    _localSortByField = null;
    _localSortOrder = null;
    debugPrint("[TaskProvider] Local sorting cleared.");
    notifyListeners();
  }

  Future<Task?> getTaskById(String taskId) async {
    if (!_authState.isLoggedIn) return null;
    try {
      final existingTask = _allFetchedTasks.firstWhere((t) => t.taskId == taskId && !t.isDeleted);
      return existingTask;
    } catch (e) { /* ... */ }
    Task? fetchedTask;
    try {
      fetchedTask = await _apiService.getTaskById(taskId);
      if (fetchedTask != null) {
        final index = _allFetchedTasks.indexWhere((t) => t.taskId == taskId);
        if (index != -1) _allFetchedTasks[index] = fetchedTask;
        else _allFetchedTasks.add(fetchedTask);
        notifyListeners();
      }
    } catch (e) { _error = "Ошибка: $e"; notifyListeners(); }
    return fetchedTask;
  }

  Future<Task?> createTaskAndReturn(Task taskData) async {
    if (!_authState.isLoggedIn || _authState.currentUser == null) { _error = "Не авторизован"; notifyListeners(); return null; }
    _isProcessingTask = true; _error = null; notifyListeners();
    Task? createdTaskResult;
    try {
      final currentUserId = _authState.currentUser!.userId.toString();
      Task dataToSend = taskData.copyWith(
        createdByUserId: taskData.createdByUserId ?? currentUserId,
        assignedToUserId: (taskData.isTeamTask || taskData.assignedToUserId != null) ? taskData.assignedToUserId : currentUserId,
      );
      createdTaskResult = await _apiService.createTask(dataToSend);
      // Принудительно перезагружаем текущий вид задач, чтобы новая задача появилась с учетом всех фильтров API
      await fetchTasks(
          viewType: _currentFetchedViewType,
          teamId: _currentFetchedTeamId,
          forceBackendCall: true
      );
      // Ищем созданную задачу в обновленном списке
      createdTaskResult = _allFetchedTasks.firstWhere((t) => t.taskId == createdTaskResult?.taskId, orElse: () => null as Task);
    } catch (e) { _error = "Ошибка создания: $e"; }
    _isProcessingTask = false;
    notifyListeners();
    return createdTaskResult;
  }

  Future<Task?> updateTaskAndReturn(Task task) async {
    if (!_authState.isLoggedIn) { _error = "Не авторизован"; notifyListeners(); return null; }
    _isProcessingTask = true; _error = null; notifyListeners();
    Task? updatedTaskResult;
    try {
      updatedTaskResult = await _apiService.updateTask(task.taskId, task);
      final index = _allFetchedTasks.indexWhere((t) => t.taskId == updatedTaskResult!.taskId);
      if (index != -1) _allFetchedTasks[index] = updatedTaskResult;
      else _allFetchedTasks.add(updatedTaskResult);
    } catch (e) { _error = "Ошибка обновления: $e"; }
    _isProcessingTask = false;
    notifyListeners();
    return updatedTaskResult;
  }

  Future<bool> patchTask(String taskId, Map<String, dynamic> patchData) async {
    if (!_authState.isLoggedIn) return false;
    _error = null;
    try {
      final patchedTask = await _apiService.patchTask(taskId, patchData);
      final index = _allFetchedTasks.indexWhere((t) => t.taskId == patchedTask.taskId);
      if (index != -1) _allFetchedTasks[index] = patchedTask;
      else _allFetchedTasks.add(patchedTask);
      notifyListeners();
      return true;
    } catch (e) { _error = "Ошибка патча: $e"; }
    notifyListeners();
    return false;
  }

  Future<bool> deleteTask(String taskId) async {
    if (!_authState.isLoggedIn) return false;
    _isProcessingTask = true; _error = null; notifyListeners();

    final taskIndex = _allFetchedTasks.indexWhere((t) => t.taskId == taskId);
    if (taskIndex == -1) {
      _error = "Задача для удаления не найдена в текущем списке.";
      _isProcessingTask = false; notifyListeners();
      return false;
    }
    final taskToDelete = _allFetchedTasks[taskIndex];

    try {
      await _apiService.deleteTask(taskId);
      _allFetchedTasks.removeAt(taskIndex);
      _deletedTasksProvider.addDeletedTask(taskToDelete.copyWith(
        deletedAt: DateTime.now(),
        deletedByUserId: _authState.currentUser?.userId.toString(),
      ));
    } catch (e) {
      _error = "Ошибка удаления: $e";
      _isProcessingTask = false; notifyListeners(); return false;
    }
    _isProcessingTask = false; notifyListeners(); return true;
  }

  void locallyUpdateTaskStatus(String taskId, KanbanColumnStatus newStatus) {
    final index = _allFetchedTasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1) {
      Task oldTask = _allFetchedTasks[index];
      DateTime now = DateTime.now();
      _allFetchedTasks[index] = _allFetchedTasks[index].copyWith(
        status: newStatus, updatedAt: now,
        completedAt: newStatus == KanbanColumnStatus.done ? (oldTask.completedAt ?? now) : null,
        completedAtIsNull: newStatus != KanbanColumnStatus.done,
      );
      notifyListeners();

      Map<String, dynamic> patchData = {'status': newStatus.toJson()};
      if (newStatus == KanbanColumnStatus.done) patchData['completed_at'] = now.toUtc().toIso8601String();
      else if (oldTask.status == KanbanColumnStatus.done) patchData['completed_at'] = null;

      patchTask(taskId, patchData).then((success) {
        if (!success) {
          final currentIndexAfterFail = _allFetchedTasks.indexWhere((t) => t.taskId == taskId);
          if (currentIndexAfterFail != -1) _allFetchedTasks[currentIndexAfterFail] = oldTask;
          notifyListeners();
        } else {
          getTaskById(taskId); // Обновляем с сервера для консистентности updatedAt
        }
      });
    }
  }

  void clearError() { if (_error != null) { _error = null; notifyListeners(); } }
  @override
  void dispose() { _authState.removeListener(_onAuthStateChanged); super.dispose(); }
}