// lib/screens/personal_tasks_kanban_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_model.dart';
import '../task_provider.dart';
import '../auth_state.dart';
import '../widgets/kanban_board/kanban_board_widget.dart';
import '../core/utils/responsive_utils.dart';
import '../widgets/tasks/mobile_task_list_widget.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
import '../widgets/tasks/task_edit_dialog.dart';

class PersonalTasksKanbanScreen extends StatefulWidget {
  const PersonalTasksKanbanScreen({Key? key}) : super(key: key);

  @override
  State<PersonalTasksKanbanScreen> createState() => _PersonalTasksKanbanScreenState();
}

class _PersonalTasksKanbanScreenState extends State<PersonalTasksKanbanScreen> {

  Future<void> _refreshData() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    return taskProvider.fetchTasks(viewType: TaskListViewType.personal, forceBackendCall: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);
        debugPrint("[PersonalTasksKanbanScreen] initState: Fetching tasks for personal view.");
        taskProvider.fetchTasks(viewType: TaskListViewType.personal);
      }
    });
  }

  void _handleTaskStatusChanged(Task task, KanbanColumnStatus newStatus) {
    Provider.of<TaskProvider>(context, listen: false).locallyUpdateTaskStatus(task.taskId, newStatus);
  }

  void _navigateToTaskDetails(BuildContext context, Task task) {
    Provider.of<AppRouterDelegate>(context, listen: false)
        .navigateTo(TaskDetailPath(task.taskId));
  }

  void _handleTaskDelete(BuildContext context, Task task) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Удалить задачу?'),
          content: Text('Вы уверены, что хотите переместить задачу "${task.title}" в корзину?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Удалить'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        taskProvider.deleteTask(task.taskId).then((success) {
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Задача "${task.title}" перемещена в корзину')),
            );
          } else if (mounted && taskProvider.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка удаления задачи: ${taskProvider.error}'), backgroundColor: Colors.red),
            );
          }
        });
      }
    });
  }

  void _handleTaskEdit(BuildContext context, Task task) {
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TaskEditDialog(
          taskToEdit: task,
          onTaskSaved: (Task? updatedTask) {
            if (updatedTask != null) {
              debugPrint("PersonalTasksKanbanScreen: TaskEditDialog.onTaskSaved for task ID: ${updatedTask.taskId}");
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final authState = Provider.of<AuthState>(context, listen: false);
    final String? currentUserId = authState.currentUser?.userId.toString();

    final List<Task> displayedPersonalTasks = taskProvider.tasksForPersonalView;

    debugPrint("[PersonalTasksKanbanScreen] Building. isLoadingList: ${taskProvider.isLoadingList}, Error: ${taskProvider.error}, Displayed personal tasks: ${displayedPersonalTasks.length}");

    Widget content;

    if (taskProvider.isLoadingList && displayedPersonalTasks.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (taskProvider.error != null && displayedPersonalTasks.isEmpty) {
      content = Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text("Ошибка загрузки задач", style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center,),
                const SizedBox(height: 8),
                Text(taskProvider.error!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center,),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Попробовать снова"),
                  onPressed: _refreshData,
                )
              ],
            ),
          )
      );
    } else if (displayedPersonalTasks.isEmpty && !taskProvider.isLoadingList) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
              const SizedBox(height: 24),
              Text(
                "У вас нет личных задач",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Все ваши личные задачи выполнены или их еще нет.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      bool isMobile = ResponsiveUtil.isMobile(context);
      content = isMobile
          ? MobileTaskListWidget(
        tasks: displayedPersonalTasks,
        onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
        onTaskTap: (task) => _navigateToTaskDetails(context, task),
        onTaskDelete: (task) => _handleTaskDelete(context, task),
        onTaskEdit: (task) => _handleTaskEdit(context, task),
        currentUserId: currentUserId ?? '',
      )
          : Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: KanbanBoardWidget(
          tasks: displayedPersonalTasks,
          onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
          onTaskDelete: (task) => _handleTaskDelete(context, task),
          onTaskEdit: (task) => _handleTaskEdit(context, task),
        ),
      );
    }

    final isMobile = ResponsiveUtil.isMobile(context);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Личные задачи"),
          leading: Provider.of<AppRouterDelegate>(context).canPop()
              ? BackButton(onPressed: () => Provider.of<AppRouterDelegate>(context, listen: false).popRoute())
              : null,
        ),
        // <<< ИЗМЕНЕНИЕ: Оборачиваем body в SafeArea >>>
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: content,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // Для десктопа фон от HomePage
      body: content,
    );
  }
}