// lib/widgets/kanban_board/task_card_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../models/team_model.dart';
import '../../tag_provider.dart';
import '../../team_provider.dart';
import '../../theme_provider.dart';
import '../../core/routing/app_router_delegate.dart';
import '../../core/routing/app_route_path.dart';

abstract class BaseTaskCard extends StatelessWidget
{
  final Task task;
  final ValueChanged<KanbanColumnStatus> onStatusChanged;
  final VoidCallback? onTaskDelete;
  final VoidCallback? onTaskEdit; // <<< НОВЫЙ КОЛЛБЭК

  const BaseTaskCard({
    Key? key,
    required this.task,
    required this.onStatusChanged,
    this.onTaskDelete,
    this.onTaskEdit, // <<< НОВЫЙ ПАРАМЕТР
  }) : super(key: key);

  Widget _buildTitle(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Text(
      task.title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        height: 1.2,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildPriorityIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    Color priorityColor;
    IconData priorityIcon;
    String priorityName = task.priority.name;

    switch (task.priority) {
      case TaskPriority.high:
        priorityColor = colorScheme.error;
        priorityIcon = task.priority.icon;
        break;
      case TaskPriority.medium:
        priorityColor = themeProvider.isEffectivelyDark ? Colors.orange.shade300 : Colors.orange.shade700;
        priorityIcon = task.priority.icon;
        break;
      case TaskPriority.low:
      default:
        priorityColor = themeProvider.isEffectivelyDark ? Colors.green.shade300 : Colors.green.shade700;
        priorityIcon = task.priority.icon;
        break;
    }

    return Tooltip(
      message: priorityName.isNotEmpty ? priorityName[0].toUpperCase() + priorityName.substring(1) : '',
      child: Icon(priorityIcon, size: 18, color: priorityColor),
    );
  }

  Widget _buildTags(BuildContext context) {
    if (task.tags.isEmpty) {
      return const SizedBox.shrink();
    }
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
            fontSize: 12,
          ),
          side: BorderSide(color: displayTag.displayColor.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    if (tagWidgets.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4.0,
      runSpacing: 2.0,
      children: tagWidgets,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget deadlineWidget = const SizedBox.shrink();
    if (task.deadline != null) {
      final DateFormat formatter = DateFormat('d MMMM yyyy', 'ru_RU');
      final String deadlineText = formatter.format(task.deadline!);
      bool isOverdue = task.deadline!.isBefore(DateTime.now().subtract(const Duration(days: 1))) && task.status != KanbanColumnStatus.done;

      deadlineWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOverdue
              ? colorScheme.errorContainer.withOpacity(0.7)
              : colorScheme.tertiaryContainer.withOpacity(0.7),
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isOverdue ? Icons.warning_amber_rounded : Icons.alarm_outlined,
                size: 14,
                color: isOverdue ? colorScheme.onErrorContainer : colorScheme.onTertiaryContainer
            ),
            const SizedBox(width: 4),
            Text(
              deadlineText,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: isOverdue ? colorScheme.onErrorContainer : colorScheme.onTertiaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    List<PopupMenuEntry<dynamic>> popupMenuItems = [];

    if (onTaskEdit != null) {
      popupMenuItems.add(
        const PopupMenuItem<String>( // Используем String как value для этого пункта
          value: 'edit_task',
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('Редактировать'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    if (KanbanColumnStatus.values.any((s) => s != task.status)) {
      if (popupMenuItems.isNotEmpty) popupMenuItems.add(const PopupMenuDivider(height: 1));
      popupMenuItems.add(
        PopupMenuItem(
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Изменить статус:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          ),
        ),
      );
      for (var status in KanbanColumnStatus.values) {
        popupMenuItems.add(
          PopupMenuItem<KanbanColumnStatus>(
            value: status,
            enabled: task.status != status,
            child: ListTile(
              leading: Icon(
                task.status == status ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.status == status ? colorScheme.primary : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              title: Text(status.title, style: TextStyle(color: task.status == status ? colorScheme.primary : null)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        );
      }
    }

    bool hasDeletableAction = onTaskDelete != null;
    if (hasDeletableAction) {
      if (popupMenuItems.isNotEmpty) popupMenuItems.add(const PopupMenuDivider(height: 1));
      popupMenuItems.add(
        PopupMenuItem<String>(
          value: 'delete_task',
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
            title: Text('В корзину', style: TextStyle(color: colorScheme.error)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    bool hasEnabledItems = popupMenuItems.any((item) {
      if (item is PopupMenuItem) {
        return item.enabled;
      }
      return false;
    });
    bool shouldShowButton = hasEnabledItems || popupMenuItems.whereType<PopupMenuItem>().any((p) => !p.enabled && p.child is Padding);


    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (task.deadline != null) deadlineWidget,
        const Spacer(),
        if (shouldShowButton)
          PopupMenuButton<dynamic>( // Тип dynamic, так как value может быть String или KanbanColumnStatus
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
            tooltip: 'Действия с задачей',
            onSelected: (value) {
              if (value is KanbanColumnStatus) {
                onStatusChanged(value);
              } else if (value == 'delete_task') {
                onTaskDelete?.call();
              } else if (value == 'edit_task') { // <<< ОБРАБОТКА НОВОГО ДЕЙСТВИЯ >>>
                onTaskEdit?.call();
              }
            },
            itemBuilder: (BuildContext context) => popupMenuItems,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildSpecificInfo(BuildContext context);

  @override
  Widget build(BuildContext context) {
    context.watch<TagProvider>();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTitle(context)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: _buildPriorityIndicator(context),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        _buildSpecificInfo(context),
        SizedBox(height: (task.tags.isNotEmpty || _buildSpecificInfo(context) is! SizedBox) ? 8.0 : 0),
        _buildTags(context),
        if (task.tags.isNotEmpty) const SizedBox(height: 8.0),

        const Divider(height: 12, thickness: 0.5, indent: 4, endIndent: 4),
        Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
          child: _buildFooter(context),
        ),
      ],
    );

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5), width: 0.8),
      ),
      child: InkWell(
        onTap: () {
          // При нажатии на саму карточку, переходим на детальный экран
          routerDelegate.navigateTo(TaskDetailPath(task.taskId));
        },
        borderRadius: BorderRadius.circular(11.5),
        child: Container(
          width: 288,
          padding: const EdgeInsets.all(10.0),
          child: cardContent,
        ),
      ),
    );
  }
}


class PersonalTaskCard extends BaseTaskCard {
  PersonalTaskCard({
    Key? key,
    required Task task,
    required ValueChanged<KanbanColumnStatus> onStatusChanged,
    VoidCallback? onTaskDelete,
    VoidCallback? onTaskEdit, // <<< НОВЫЙ ПАРАМЕТР
  }) : assert(!task.isTeamTask),
        super(
        key: key,
        task: task,
        onStatusChanged: onStatusChanged,
        onTaskDelete: onTaskDelete,
        onTaskEdit: onTaskEdit, // <<< ПЕРЕДАЕМ ДАЛЬШЕ
      );

  @override
  Widget _buildSpecificInfo(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class TeamTaskCard extends BaseTaskCard {
  TeamTaskCard({
    Key? key,
    required Task task,
    required ValueChanged<KanbanColumnStatus> onStatusChanged,
    VoidCallback? onTaskDelete,
    VoidCallback? onTaskEdit, // <<< НОВЫЙ ПАРАМЕТР
  }) : assert(task.isTeamTask),
        super(
        key: key,
        task: task,
        onStatusChanged: onStatusChanged,
        onTaskDelete: onTaskDelete,
        onTaskEdit: onTaskEdit, // <<< ПЕРЕДАЕМ ДАЛЬШЕ
      );

  @override
  Widget _buildSpecificInfo(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final teamProvider = context.watch<TeamProvider>();

    if (task.teamId == null || task.teamId!.isEmpty) {
      return const SizedBox.shrink();
    }

    Team? team;
    try {
      team = teamProvider.myTeams.firstWhere((t) => t.teamId == task.teamId);
    } catch (e) {
      // Команда не найдена в списке, используем данные из задачи
    }

    final String teamName = team?.name ?? task.teamName ?? 'Команда ID: ${task.teamId}';
    final String? teamImageUrl = team?.imageUrl;

    return _buildTeamInfoDisplay(context, teamName, teamImageUrl, colorScheme, theme);
  }

  Widget _buildTeamInfoDisplay(BuildContext context, String displayText, String? imageUrl, ColorScheme colorScheme, ThemeData theme){
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    return GestureDetector(
      onTap: task.teamId != null ? () {
        routerDelegate.navigateTo(TeamDetailPath(task.teamId!));
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        margin: const EdgeInsets.only(bottom: 4.0),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withOpacity(0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              CircleAvatar(
                backgroundImage: NetworkImage(imageUrl),
                radius: 8,
                backgroundColor: colorScheme.secondaryContainer,
              )
            else
              Icon(Icons.group_work_outlined, size: 13, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                displayText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (task.teamId != null)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Icon(Icons.arrow_forward_ios_rounded, size: 11, color: colorScheme.onSecondaryContainer.withOpacity(0.7)),
              ),
          ],
        ),
      ),
    );
  }
}