// lib/screens/all_tasks_kanban_screen.dart
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
import '../widgets/tasks/team_task_edit_dialog.dart';
import '../widgets/tasks/task_edit_dialog.dart';
import '../team_provider.dart';

class AllTasksKanbanScreen extends StatefulWidget {
  const AllTasksKanbanScreen({Key? key}) : super(key: key);

  @override
  State<AllTasksKanbanScreen> createState() => _AllTasksKanbanScreenState();
}

class _AllTasksKanbanScreenState extends State<AllTasksKanbanScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);
        debugPrint("[AllTasksKanbanScreen] initState: Fetching tasks for global view.");
        // Запрашиваем задачи для "Всех задач"
        taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated);
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
    if (task.isTeamTask && task.teamId != null) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      teamProvider.fetchTeamDetails(task.teamId!).then((_) {
        if (mounted) {
          final members = teamProvider.currentTeamDetail?.members.map((m) => m.user).toList() ?? [];
          showDialog<Task?>(
            context: context,
            builder: (BuildContext dialogContext) {
              return TeamTaskEditDialog(
                teamId: task.teamId!,
                members: members,
                taskToEdit: task,
                onTaskSaved: (updatedTask) { /* ... */ },
              );
            },
          );
        }
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось загрузить детали команды: $error'), backgroundColor: Colors.red),
          );
          showDialog<Task?>(
            context: context,
            builder: (BuildContext dialogContext) {
              return TeamTaskEditDialog(
                teamId: task.teamId!,
                members: [],
                taskToEdit: task,
                onTaskSaved: (updatedTask) { /* ... */ },
              );
            },
          );
        }
      });
    } else {
      showDialog<Task?>(
        context: context,
        builder: (BuildContext dialogContext) {
          return TaskEditDialog(
            taskToEdit: task,
            onTaskSaved: (updatedTask) { /* ... */ },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final authState = Provider.of<AuthState>(context, listen: false);
    final String? currentUserId = authState.currentUser?.userId.toString();

    final List<Task> displayedTasks = taskProvider.tasksForGlobalView;

    debugPrint("[AllTasksKanbanScreen] Building. isLoadingList: ${taskProvider.isLoadingList}, Error: ${taskProvider.error}, Displayed Global tasks: ${displayedTasks.length}");

    Widget content;
    // Показываем индикатор, если идет загрузка И (список пуст ИЛИ произошла ошибка И список пуст)
    // Это предотвращает мигание, если данные уже есть, но идет фоновое обновление.
    if (taskProvider.isLoadingList && (displayedTasks.isEmpty || taskProvider.error != null)) {
      content = const Center(child: CircularProgressIndicator());
    } else if (taskProvider.error != null && displayedTasks.isEmpty) { // Ошибка и нет данных для отображения
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
                  onPressed: () => taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated),
                )
              ],
            ),
          )
      );
    } else if (displayedTasks.isEmpty && !taskProvider.isLoadingList) { // Загрузка завершена, ошибок нет, но список пуст
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
              const SizedBox(height: 24),
              Text(
                "Для вас пока нет задач",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Создайте новую задачу или проверьте назначенные вам.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else { // Есть задачи для отображения
      bool isMobile = ResponsiveUtil.isMobile(context);
      content = isMobile
          ? MobileTaskListWidget(
        tasks: displayedTasks,
        onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
        onTaskTap: (task) => _navigateToTaskDetails(context, task),
        onTaskDelete: (task) => _handleTaskDelete(context, task),
        onTaskEdit: (task) => _handleTaskEdit(context, task),
        currentUserId: currentUserId ?? '',
      )
          : Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: KanbanBoardWidget(
          tasks: displayedTasks,
          onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
          onTaskDelete: (task) => _handleTaskDelete(context, task),
          onTaskEdit: (task) => _handleTaskEdit(context, task),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
    );
  }
}