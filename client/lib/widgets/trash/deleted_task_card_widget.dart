// lib/widgets/trash/deleted_task_card_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../deleted_tasks_provider.dart';
import '../../task_provider.dart';

class DeletedTaskCardWidget extends StatelessWidget {
  final Task task;

  const DeletedTaskCardWidget({
    Key? key,
    required this.task,
  }) : super(key: key);

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Не указано';
    return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final deletedTasksProvider = Provider.of<DeletedTasksProvider>(context, listen: false);
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Card(
      elevation: 1.0,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                decoration: TextDecoration.lineThrough,
                decorationColor: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 6.0),
              Text(
                task.description!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8.0),
            if (task.isTeamTask && task.teamName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.group_work_outlined, size: 15, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "Команда: ${task.teamName}",
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Удалено: ${_formatDateTime(task.deletedAt)}',
              style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
            ),
            if (task.deletedByUserId != null)
              Text(
                // TODO: Заменить ID на имя пользователя, когда будет доступен соответствующий сервис
                'Кем: ID ${task.deletedByUserId}',
                style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.restore_from_trash_outlined, size: 18, color: colorScheme.primary),
                  label: Text('Восстановить', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                  onPressed: () async {
                    final restoredTask = await deletedTasksProvider.restoreFromTrash(task.taskId);
                    if (restoredTask != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Задача "${task.title}" восстановлена')),
                      );
                      // Принудительно обновляем список активных задач, чтобы восстановленная задача появилась
                      taskProvider.fetchTasks(forceBackendCall: true);
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: Icon(Icons.delete_forever_outlined, size: 18, color: colorScheme.error),
                  label: Text('Удалить', style: TextStyle(color: colorScheme.error, fontSize: 13)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: const Text('Удалить задачу навсегда?'),
                          content: Text('Задача "${task.title}" будет удалена без возможности восстановления.'),
                          actions: <Widget>[
                            TextButton(
                              child: const Text('Отмена'),
                              onPressed: () => Navigator.of(dialogContext).pop(),
                            ),
                            TextButton(
                              child: Text('Удалить', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final success = await deletedTasksProvider.deletePermanently(task.taskId);
                                if (context.mounted) {
                                  Navigator.of(dialogContext).pop();
                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Задача "${task.title}" удалена навсегда.')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}