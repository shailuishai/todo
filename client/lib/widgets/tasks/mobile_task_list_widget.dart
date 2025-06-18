// lib/widgets/tasks/mobile_task_list_widget.dart
import 'package:flutter/material.dart';
import '../../models/task_model.dart';
import './mobile_task_list_item_widget.dart';

class MobileTaskListWidget extends StatelessWidget {
  final List<Task> tasks;
  final Function(Task, KanbanColumnStatus) onTaskStatusChanged;
  final Function(Task) onTaskTap;
  final Function(Task) onTaskDelete;
  final Function(Task) onTaskEdit;
  final ScrollController? scrollController;

  const MobileTaskListWidget({
    Key? key,
    required this.tasks,
    required this.onTaskStatusChanged,
    required this.onTaskTap,
    required this.onTaskDelete,
    required this.onTaskEdit,
    this.scrollController,
    // Неиспользуемый параметр currentUserId удален
  }) : super(key: key);

  String _getTaskSuffix(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'задача';
    } else if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'задачи';
    } else {
      return 'задач';
    }
  }

  List<Widget> _buildTaskGroupSlivers({
    required BuildContext context,
    required String sectionTitle,
    required List<Task> tasks,
    required Function(Task, KanbanColumnStatus) onTaskStatusChanged,
    required Function(Task) onTaskTap,
    required Function(Task) onTaskDelete,
    required Function(Task) onTaskEdit,
  }) {
    if (tasks.isEmpty) {
      return [];
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final orderedStatuses = [
      KanbanColumnStatus.in_progress,
      KanbanColumnStatus.todo,
      KanbanColumnStatus.deferred,
      KanbanColumnStatus.done,
    ];

    final Map<KanbanColumnStatus, List<Task>> groupedTasks = {};
    for (var status in orderedStatuses) {
      groupedTasks[status] = tasks.where((task) => task.status == status).toList();
    }

    List<Widget> slivers = [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            sectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    ];

    for (var status in orderedStatuses) {
      final tasksInGroup = groupedTasks[status] ?? [];
      if (tasksInGroup.isEmpty) {
        // Не показываем пустые группы, кроме "Выполнено" для ясности
        if (status != KanbanColumnStatus.done) continue;
      }

      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
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
                "${tasksInGroup.length} ${_getTaskSuffix(tasksInGroup.length)}",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ));

      if (tasksInGroup.isEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Center(
              child: Text(
                "Нет выполненных задач",
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
              ),
            ),
          ),
        ));
      } else {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            sliver: SliverList.separated(
              itemCount: tasksInGroup.length,
              itemBuilder: (context, taskIndex) {
                final task = tasksInGroup[taskIndex];
                return MobileTaskListItemWidget(
                  key: ValueKey(task.taskId + task.updatedAt.toIso8601String()),
                  task: task,
                  onTap: () => onTaskTap(task),
                  onStatusChanged: (newStatus) => onTaskStatusChanged(task, newStatus),
                  onDelete: () => onTaskDelete(task),
                  onEdit: () => onTaskEdit(task),
                );
              },
              separatorBuilder: (context, _) => const SizedBox(height: 8),
            ),
          ),
        );
      }
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final personalTasks = tasks.where((t) => !t.isTeamTask && !t.isDeleted).toList();
    final teamTasks = tasks.where((t) => t.isTeamTask && !t.isDeleted).toList();

    if (personalTasks.isEmpty && teamTasks.isEmpty) {
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

    List<Widget> slivers = [];

    if (personalTasks.isNotEmpty) {
      slivers.addAll(_buildTaskGroupSlivers(
        context: context,
        sectionTitle: "Личные задачи",
        tasks: personalTasks,
        onTaskStatusChanged: onTaskStatusChanged,
        onTaskTap: onTaskTap,
        onTaskDelete: onTaskDelete,
        onTaskEdit: onTaskEdit,
      ));
    }

    if (personalTasks.isNotEmpty && teamTasks.isNotEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Divider(height: 32, thickness: 1.5, indent: 20, endIndent: 20),
        ),
      ));
    }

    if (teamTasks.isNotEmpty) {
      slivers.addAll(_buildTaskGroupSlivers(
        context: context,
        sectionTitle: "Командные задачи",
        tasks: teamTasks,
        onTaskStatusChanged: onTaskStatusChanged,
        onTaskTap: onTaskTap,
        onTaskDelete: onTaskDelete,
        onTaskEdit: onTaskEdit,
      ));
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));

    return CustomScrollView(
      controller: scrollController,
      slivers: slivers,
    );
  }
}