// lib/widgets/tasks/mobile_task_list_widget.dart
import 'package:client/widgets/tasks/task_edit_dialog.dart'; // << ИМПОРТ ДИАЛОГА
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../theme_provider.dart';
import './mobile_task_list_item_widget.dart';
// import '../../task_provider.dart'; // Не нужен здесь напрямую, если передаем коллбэки

class MobileTaskListWidget extends StatelessWidget {
  final List<Task> tasks;
  final Function(Task, KanbanColumnStatus) onTaskStatusChanged;
  final Function(Task) onTaskTap;
  final Function(Task) onTaskDelete;
  final Function(Task) onTaskEdit; // <<< НОВЫЙ ПАРАМЕТР
  final String currentUserId;
  final ScrollController? scrollController;

  const MobileTaskListWidget({
    Key? key,
    required this.tasks,
    required this.onTaskStatusChanged,
    required this.onTaskTap,
    required this.onTaskDelete,
    required this.onTaskEdit, // <<< НОВЫЙ ПАРАМЕТР
    required this.currentUserId,
    this.scrollController,
  }) : super(key: key);

  // <<< НОВЫЙ МЕТОД ДЛЯ ОТКРЫТИЯ ДИАЛОГА РЕДАКТИРОВАНИЯ >>>
  void _showEditDialog(BuildContext context, Task task) {
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TaskEditDialog(
          taskToEdit: task,
          onTaskSaved: (updatedTask) {
            // TaskProvider обновит состояние, MobileTaskListWidget перерисуется через родителя
            debugPrint("MobileTaskListWidget: TaskEditDialog.onTaskSaved for task ID: ${updatedTask.taskId}");
          },
        );
      },
    );
    // .then((returnedTask) { // Не обязательно обрабатывать then, если onTaskSaved достаточно
    //   if (returnedTask != null) {
    //     // UI должен обновиться через TaskProvider -> родительский виджет -> MobileTaskListWidget
    //   }
    // });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Map<KanbanColumnStatus, List<Task>> groupedTasks = {};
    for (var status in KanbanColumnStatus.values) {
      groupedTasks[status] = tasks.where((task) => task.status == status && !task.isDeleted).toList();
      groupedTasks[status]?.sort((a, b) {
        int priorityCompare = a.priority.index.compareTo(b.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        if (a.deadline == null && b.deadline == null) return 0;
        if (a.deadline == null) return 1;
        if (b.deadline == null) return -1;
        return a.deadline!.compareTo(b.deadline!);
      });
    }

    final orderedStatuses = [
      KanbanColumnStatus.in_progress,
      KanbanColumnStatus.todo,
      KanbanColumnStatus.deferred,
      KanbanColumnStatus.done,
    ];

    if (tasks.where((t) => !t.isDeleted).isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.7,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 56, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  "Задач пока нет",
                  style: theme.textTheme.headlineSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Самое время добавить новые или отдохнуть!",
                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final status = orderedStatuses[index];
                final tasksInGroup = groupedTasks[status] ?? [];

                if (tasksInGroup.isEmpty && status != KanbanColumnStatus.done) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 4.0, right: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            status.title.toUpperCase(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary.withOpacity(0.9),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            "${tasksInGroup.length} задач${_getTaskSuffix(tasksInGroup.length)}",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tasksInGroup.isEmpty && status == KanbanColumnStatus.done)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: Text(
                            "Нет выполненных задач",
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tasksInGroup.length,
                        itemBuilder: (context, taskIndex) {
                          final task = tasksInGroup[taskIndex];
                          return MobileTaskListItemWidget(
                            key: ValueKey(task.taskId + task.updatedAt.toIso8601String()), // Обновляем ключ при изменении updatedAt
                            task: task,
                            onTap: () => onTaskTap(task),
                            onStatusChanged: (newStatus) => onTaskStatusChanged(task, newStatus),
                            onDelete: () => onTaskDelete(task),
                            onEdit: () => _showEditDialog(context, task), // <<< ВЫЗЫВАЕМ ДИАЛОГ РЕДАКТИРОВАНИЯ >>>
                          );
                        },
                        separatorBuilder: (context, _) => const SizedBox(height: 8),
                      ),
                    if (index < orderedStatuses.length - 1)
                      Divider(
                        height: 24,
                        thickness: 0.8,
                        color: colorScheme.outlineVariant.withOpacity(0.3),
                      )
                    else
                      const SizedBox(height: 16),
                  ],
                );
              },
              childCount: orderedStatuses.length,
            ),
          ),
        ),
      ],
    );
  }

  String _getTaskSuffix(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return '';
    } else if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'и';
    } else {
      return '';
    }
  }
}