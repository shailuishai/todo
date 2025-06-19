// lib/screens/all_tasks_kanban_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/routing/app_pages.dart';
import '../models/task_model.dart';
import '../task_provider.dart';
import '../auth_state.dart';
import '../widgets/kanban_board/kanban_board_widget.dart';
import '../core/utils/responsive_utils.dart';
import '../widgets/sidebar/right_sidebar.dart';
import '../widgets/tasks/TaskFilterDialog.dart';
import '../widgets/tasks/TaskSortDialog.dart';
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

  Future<void> _refreshData() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    return taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated, forceBackendCall: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);
        debugPrint("[AllTasksKanbanScreen] initState: Fetching tasks for global view.");
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

  // ИЗМЕНЕНИЕ: Метод для вызова диалога создания личной задачи
  void _showCreatePersonalTaskDialog(BuildContext context) {
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TaskEditDialog(
          onTaskSaved: (newTask) {
            if (mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('Задача "${newTask.title}" добавлена!')),
              );
            }
          },
        );
      },
    );
  }

  // ИЗМЕНЕНИЕ: Метод для показа меню действий
  void _showTaskActionsBottomSheet(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (builderContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(builderContext).viewInsets.bottom),
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.add_task_outlined),
                title: const Text('Добавить личную задачу'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  _showCreatePersonalTaskDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.filter_list_rounded),
                title: const Text('Фильтры'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  showDialog(
                    context: context,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: taskProvider,
                      child: const TaskFilterDialog(viewType: TaskListViewType.allAssignedOrCreated),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert_rounded),
                title: const Text('Сортировка'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  showDialog(
                    context: context,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: taskProvider,
                      child: const TaskSortDialog(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final authState = Provider.of<AuthState>(context, listen: false);
    final bool isMobile = ResponsiveUtil.isMobile(context);

    final List<Task> displayedTasks = taskProvider.tasksForGlobalView;

    Widget content;
    if (taskProvider.isLoadingList && displayedTasks.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (taskProvider.error != null && displayedTasks.isEmpty) {
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
                  onPressed: () => _refreshData(),
                )
              ],
            ),
          )
      );
    } else if (displayedTasks.isEmpty && !taskProvider.isLoadingList) {
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
    } else {
      content = isMobile
          ? MobileTaskListWidget(
        tasks: displayedTasks,
        onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
        onTaskTap: (task) => _navigateToTaskDetails(context, task),
        onTaskDelete: (task) => _handleTaskDelete(context, task),
        onTaskEdit: (task) => _handleTaskEdit(context, task),
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

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Все задачи"),
          centerTitle: true,
          // ИЗМЕНЕНИЕ: Обновлена логика кнопки "назад"
          leading: BackButton(onPressed: () => Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const HomeSubPath(AppRouteSegments.home, showRightSidebar: false))),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: content,
          ),
        ),
        // ИЗМЕНЕНИЕ: Добавлена FAB
        floatingActionButton: ActionButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Действия с задачами',
          onPressed: () => _showTaskActionsBottomSheet(context),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
    }

    // Для десктопа оставляем как есть, так как он встраивается в HomePage
    return Scaffold(
      backgroundColor: Colors.transparent, // Для десктопа фон задает HomePage
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: content,
      ),
    );
  }
}