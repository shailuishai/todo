// lib/widgets/kanban_board/kanban_column_widget.dart
import 'package:flutter/material.dart';
import '../../models/task_model.dart';
import '../tasks/task_card_widget.dart';

class KanbanColumnWidget extends StatelessWidget {
  final KanbanColumnStatus status;
  final List<Task> tasks;
  final Function(Task, KanbanColumnStatus) onTaskStatusChanged;
  final ValueChanged<Task>? onTaskDelete;
  final ValueChanged<Task>? onTaskEdit; // <<< НОВЫЙ ПАРАМЕТР

  const KanbanColumnWidget({
    Key? key,
    required this.status,
    required this.tasks,
    required this.onTaskStatusChanged,
    this.onTaskDelete,
    this.onTaskEdit, // <<< НОВЫЙ ПАРАМЕТР
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DragTarget<Task>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: tasks.isEmpty
              ? LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: Opacity(
                  opacity: 0.6,
                  child: Text(
                    'Нет задач',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          )
              : ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final BaseTaskCard taskCardWidget = task.isTeamTask
                  ? TeamTaskCard(
                key: ValueKey(task.taskId), // Используем ValueKey для корректного обновления
                task: task,
                onStatusChanged: (newStatus) => onTaskStatusChanged(task, newStatus),
                onTaskDelete: onTaskDelete != null ? () => onTaskDelete!(task) : null,
                onTaskEdit: onTaskEdit != null ? () => onTaskEdit!(task) : null, // <<< ПЕРЕДАЕМ КОЛЛБЭК
              )
                  : PersonalTaskCard(
                key: ValueKey(task.taskId), // Используем ValueKey для корректного обновления
                task: task,
                onStatusChanged: (newStatus) => onTaskStatusChanged(task, newStatus),
                onTaskDelete: onTaskDelete != null ? () => onTaskDelete!(task) : null,
                onTaskEdit: onTaskEdit != null ? () => onTaskEdit!(task) : null, // <<< ПЕРЕДАЕМ КОЛЛБЭК
              );

              return Draggable<Task>(
                data: task,
                feedback: Material(
                  elevation: 4.0,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 288.0),
                    child: taskCardWidget,
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.5,
                  child: taskCardWidget,
                ),
                child: taskCardWidget,
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 8.0),
          ),
        );
      },
      onWillAccept: (Task? incomingTask) {
        return incomingTask != null && incomingTask.status != status;
      },
      onAccept: (Task incomingTask) {
        onTaskStatusChanged(incomingTask, status);
      },
    );
  }
}