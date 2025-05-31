// lib/widgets/tags/tag_list_item_widget.dart
import 'package:flutter/material.dart';
import '../../models/task_model.dart'; // Для ApiTag

class TagListItemWidget extends StatelessWidget {
  final ApiTag tag;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;

  const TagListItemWidget({
    Key? key,
    required this.tag,
    this.onEdit,
    this.onDelete,
    this.showActions = true, // По умолчанию показываем действия
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      leading: Container(
        width: 36, // Немного увеличил
        height: 36,
        decoration: BoxDecoration(
            color: tag.displayColor,
            shape: BoxShape.circle,
            border: Border.all(
                color: tag.displayColor.computeLuminance() > 0.6
                    ? Colors.black.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
                width: 1.5)),
      ),
      title: Text(
        tag.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: showActions && (onEdit != null || onDelete != null)
          ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
              tooltip: "Редактировать тег",
              splashRadius: 22,
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: colorScheme.error),
              tooltip: "Удалить тег",
              splashRadius: 22,
              onPressed: onDelete,
            ),
        ],
      )
          : null,
    );
  }
}