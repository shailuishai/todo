// lib/widgets/trash/deleted_task_card_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../deleted_tasks_provider.dart';
// import '../../tag_provider.dart'; // Раскомментируй, если будешь использовать tagProvider

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

    return Card(
      elevation: 1.0,
      // Убрал vertical: 6.0 из margin, так как GridView уже дает mainAxisSpacing
      margin: const EdgeInsets.symmetric(horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4), width: 0.8),
      ),
      // Оборачиваем Padding в IntrinsicHeight, чтобы Column мог корректно использовать Spacer
      // и при этом карточка не пыталась занять бесконечную высоту, если GridView этого не ограничивает.
      // Однако, GridView с childAspectRatio уже должен давать ограничения по высоте.
      // Попробуем сначала без IntrinsicHeight, так как GridView обычно сам управляет размерами дочерних элементов.
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // mainAxisSize: MainAxisSize.min, // Убираем, чтобы Spacer работал
          children: [
            // --- Начало основного контента ---
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
              // Оборачиваем описание в Flexible, если оно может быть длинным,
              // чтобы оно не выталкивало кнопки за пределы карточки.
              // Но это имеет смысл, если высота карточки фиксирована или ограничена.
              // В GridView с childAspectRatio высота элемента уже определяется.
              // Если описание будет слишком длинным для maxLines: 3, оно все равно обрежется.
              Text(
                task.description!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                maxLines: 3, // Ограничиваем количество строк для описания
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
                    Flexible( // Добавляем Flexible на случай длинного имени команды
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
                'Кем: ${task.deletedByUserId}',
                style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
              ),
            // --- Конец основного контента ---

            const Spacer(), // <<< ЭТОТ ВИДЖЕТ ПРИЖМЕТ ВСЕ, ЧТО НИЖЕ, К НИЗУ КАРТОЧКИ

            // const SizedBox(height: 10.0), // Можно убрать или уменьшить, Spacer даст отступ
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.restore_from_trash_outlined, size: 18, color: colorScheme.primary),
                  label: Text('Восстановить', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                  onPressed: () {
                    deletedTasksProvider.restoreFromTrash(task.taskId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Задача "${task.title}" восстановлена (из корзины)')),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Уменьшает область тапа до размеров кнопки
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: Icon(Icons.delete_forever_outlined, size: 18, color: colorScheme.error),
                  label: Text('Удалить навсегда', style: TextStyle(color: colorScheme.error, fontSize: 13)),
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
                              onPressed: () {
                                deletedTasksProvider.deletePermanently(task.taskId);
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Задача "${task.title}" удалена навсегда.')),
                                );
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