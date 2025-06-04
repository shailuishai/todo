// lib/widgets/tasks/mobile_task_list_item_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../tag_provider.dart';
import '../../theme_provider.dart';
// import '../../core/routing/app_router_delegate.dart'; // Не нужен напрямую здесь
// import '../../core/routing/app_route_path.dart';    // Не нужен напрямую здесь

class MobileTaskListItemWidget extends StatelessWidget {
  final Task task;
  final Function(KanbanColumnStatus newStatus)? onStatusChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onEdit; // <<< НОВЫЙ КОЛЛБЭК ДЛЯ РЕДАКТИРОВАНИЯ

  const MobileTaskListItemWidget({
    Key? key,
    required this.task,
    this.onStatusChanged,
    this.onDelete,
    this.onTap,
    this.onEdit, // <<< НОВЫЙ ПАРАМЕТР
  }) : super(key: key);

  Widget _buildLeadingIndicator(BuildContext context, Color priorityColor, IconData priorityIcon) {
    final theme = Theme.of(context);
    bool isDone = task.status == KanbanColumnStatus.done;
    final Color effectivePriorityColor = isDone ? priorityColor.withOpacity(0.5) : priorityColor;

    return Container(
      padding: const EdgeInsets.only(right: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(priorityIcon, color: effectivePriorityColor, size: 20),
          const SizedBox(height: 2),
          Text(
            task.priority.name.isNotEmpty ? task.priority.name.substring(0,1).toUpperCase() : '',
            style: theme.textTheme.labelSmall?.copyWith(
                color: effectivePriorityColor,
                fontWeight: FontWeight.bold,
                fontSize: 10
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTags(BuildContext context) {
    if (task.tags.isEmpty) {
      return const SizedBox.shrink();
    }
    // Используем context.watch для автоматического обновления при изменении тегов
    final tagProvider = context.watch<TagProvider>();

    List<Widget> tagWidgets = [];

    for (var taskTagInfo in task.tags) {
      ApiTag? actualTag;
      if (taskTagInfo.type == 'user') {
        try {
          actualTag = tagProvider.userTags.firstWhere((ut) => ut.id == taskTagInfo.id && ut.type == 'user');
        } catch (e) { /* Тег не найден */ }
      } else if (taskTagInfo.type == 'team' && task.teamId != null) {
        final teamIdInt = int.tryParse(task.teamId!);
        if (teamIdInt != null && tagProvider.teamTagsByTeamId.containsKey(teamIdInt)) {
          try {
            actualTag = tagProvider.teamTagsByTeamId[teamIdInt]!
                .firstWhere((tt) => tt.id == taskTagInfo.id && tt.type == 'team');
          } catch (e) { /* Тег не найден */ }
        }
      }

      final displayTag = actualTag ?? taskTagInfo;
      if (actualTag == null && taskTagInfo.id != 0 && displayTag.id == taskTagInfo.id) {
        continue;
      }
      if (displayTag.id == 0 && displayTag.name.trim().isEmpty) {
        continue;
      }

      tagWidgets.add(
        Chip(
          label: Text(displayTag.name),
          backgroundColor: displayTag.displayColor.withOpacity(0.15),
          labelStyle: TextStyle(
            color: displayTag.displayColor,
            fontWeight: FontWeight.w500,
            fontSize: 10,
          ),
          side: BorderSide(color: displayTag.displayColor.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        ),
      );
    }

    if (tagWidgets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Wrap(
        spacing: 4.0,
        runSpacing: 2.0,
        children: tagWidgets,
      ),
    );
  }

  Widget _buildFooterInfo(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    final List<Widget> footerItems = [];

    if (task.deadline != null) {
      final now = DateTime.now();
      final bool isOverdue = task.deadline!.isBefore(DateTime(now.year, now.month, now.day)) && task.status != KanbanColumnStatus.done;
      final deadlineColor = isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant;
      footerItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isOverdue ? Icons.warning_amber_rounded : Icons.alarm_outlined,
                size: 13,
                color: (isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant).withOpacity(0.9)
            ),
            const SizedBox(width: 3),
            Text(
              DateFormat('dd MMM yy', 'ru_RU').format(task.deadline!),
              style: textTheme.labelSmall?.copyWith(
                  color: deadlineColor,
                  fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                  fontSize: 10.5
              ),
            ),
          ],
        ),
      );
    }

    if (task.isTeamTask && task.teamName != null) {
      if (footerItems.isNotEmpty) footerItems.add(const SizedBox(width: 6));
      footerItems.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(task.status == KanbanColumnStatus.done ? 0.25 : 0.45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_work_outlined, size: 11, color: colorScheme.onSecondaryContainer.withOpacity(task.status == KanbanColumnStatus.done ? 0.65 : 0.85)),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    task.teamName!,
                    style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer.withOpacity(task.status == KanbanColumnStatus.done ? 0.65 : 0.85),
                        fontWeight: FontWeight.w500,
                        fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
      );
    }

    if (footerItems.isEmpty && task.status == KanbanColumnStatus.done && task.completedAt != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: Text(
          'Завершено: ${DateFormat('dd MMM HH:mm', 'ru_RU').format(task.completedAt!)}',
          style: textTheme.labelSmall?.copyWith(color: colorScheme.primary.withOpacity(0.8), fontSize: 10.5),
        ),
      );
    }
    if (footerItems.isEmpty) return const SizedBox(height: 4);

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Wrap(
        spacing: 6.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: footerItems,
      ),
    );
  }

  Widget _buildActionsMenuButton(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    List<PopupMenuEntry<String>> items = [];

    // <<< ПУНКТ РЕДАКТИРОВАТЬ >>>
    if (onEdit != null) {
      items.add(
        const PopupMenuItem<String>(
          value: 'edit_task',
          height: 38,
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('Редактировать'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    bool canChangeStatus = onStatusChanged != null && KanbanColumnStatus.values.any((s) => s != task.status);
    if (canChangeStatus) {
      if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 1));
      items.add(
        PopupMenuItem<String>(
          enabled: false, height: 30,
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
          child: Text("Изменить статус:", style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8), fontWeight: FontWeight.w600)),
        ),
      );
      for (var status in KanbanColumnStatus.values) {
        items.add(
          PopupMenuItem<String>(
            value: 'status_${status.name}', height: 38,
            enabled: task.status != status,
            child: ListTile(
              leading: Icon(
                task.status == status ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20, color: task.status == status ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              title: Text(status.title, style: theme.textTheme.bodyMedium?.copyWith(color: task.status == status ? colorScheme.primary : colorScheme.onSurface, fontWeight: task.status == status ? FontWeight.bold : FontWeight.normal)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        );
      }
    }

    if (onDelete != null) {
      if (items.isNotEmpty) { items.add(const PopupMenuDivider(height: 1)); }
      items.add(
        PopupMenuItem<String>(
          value: 'delete_task', height: 38,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
            title: Text('В корзину', style: TextStyle(color: colorScheme.error)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
      tooltip: "Действия",
      offset: const Offset(0, 30),
      itemBuilder: (BuildContext context) => items,
      onSelected: (String value) {
        if (value.startsWith('status_')) {
          final statusName = value.substring('status_'.length);
          final newStatus = KanbanColumnStatus.values.firstWhere((s) => s.name == statusName);
          onStatusChanged?.call(newStatus);
        } else if (value == 'delete_task') {
          onDelete?.call();
        } else if (value == 'edit_task') { // <<< ОБРАБОТКА РЕДАКТИРОВАНИЯ >>>
          onEdit?.call();
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.canvasColor,
      elevation: 3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    Color priorityColor;
    IconData priorityIcon;

    switch (task.priority) {
      case TaskPriority.high:
        priorityColor = colorScheme.error;
        priorityIcon = task.priority.icon;
        break;
      case TaskPriority.medium:
        priorityColor = themeProvider.isEffectivelyDark ? Colors.orange.shade300 : Colors.orange.shade800;
        priorityIcon = task.priority.icon;
        break;
      case TaskPriority.low:
      default:
        priorityColor = themeProvider.isEffectivelyDark ? Colors.green.shade300 : Colors.green.shade700;
        priorityIcon = task.priority.icon;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      splashColor: colorScheme.primaryContainer.withOpacity(0.1),
      highlightColor: colorScheme.primaryContainer.withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: task.status == KanbanColumnStatus.done
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(task.status == KanbanColumnStatus.done ? 0.25 : 0.4),
              width: 0.8
          ),
          boxShadow: task.status == KanbanColumnStatus.done ? [] : [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.03),
              blurRadius: 3.0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeadingIndicator(context, priorityColor, priorityIcon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: task.status == KanbanColumnStatus.done ? colorScheme.onSurfaceVariant.withOpacity(0.65) : colorScheme.onSurface,
                      decoration: task.status == KanbanColumnStatus.done ? TextDecoration.lineThrough : null,
                      decorationColor: colorScheme.onSurfaceVariant.withOpacity(0.65),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _buildTags(context),
                  _buildFooterInfo(context, colorScheme, textTheme),
                ],
              ),
            ),
            _buildActionsMenuButton(context, colorScheme),
          ],
        ),
      ),
    );
  }
}