// lib/widgets/sidebar/menu_item.dart
import 'package:flutter/material.dart';
import './sidebar_constants.dart'; // Убедитесь, что путь корректен

class MenuItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final bool isCollapsed; // Финальное состояние схлопывания
  final double currentContentWidthForMenuItem; // Текущая доступная ширина для контента этого MenuItem
  // minWidthForTextToShow больше не нужен как параметр, будем использовать currentContentWidthForMenuItem
  final VoidCallback onTap;

  const MenuItem({
    Key? key,
    required this.title,
    required this.icon,
    required this.isActive,
    required this.isCollapsed,
    required this.currentContentWidthForMenuItem,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = theme.colorScheme.onSurfaceVariant;
    final Color currentIconColor = isActive ? activeColor : inactiveColor;
    final Color currentTextColor = isActive ? activeColor : theme.colorScheme.onSurface;

    // Минимальная ширина КОНТЕНТА MenuItem (после вычета его собственных паддингов),
    // необходимая для отображения текста.
    // Иконка (24) + отступ (16) + минимальный текст (например, 30-50) = 70-90
    const double minInternalContentWidthForText = 70.0;

    Color? itemBackgroundColor;
    // Фон активного элемента показываем только если он НЕ в финальном свернутом состоянии
    // И если текущая доступная ширина контента позволяет показать текст (чтобы не было фона у просто иконки)
    if (isActive && !isCollapsed && currentContentWidthForMenuItem - (2 * 12.0) > minInternalContentWidthForText) { // 12.0 - это горизонтальный padding самого MenuItem
      itemBackgroundColor = activeColor.withOpacity(0.1);
    }

    // Решаем, показывать ли текст, на основе финального isCollapsed И текущей доступной ширины для КОНТЕНТА MenuItem
    final bool showText = !isCollapsed && (currentContentWidthForMenuItem - (2 * 12.0)) > minInternalContentWidthForText;

    // Определяем, как рендерить: полностью свернуто, или пытаться развернуть
    bool renderAsFullyCollapsed = isCollapsed || (!isCollapsed && !showText);

    return Material(
      key: ValueKey('$title-$isCollapsed-$renderAsFullyCollapsed'),
      color: itemBackgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        splashColor: activeColor.withOpacity(0.2),
        highlightColor: activeColor.withOpacity(0.1),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: renderAsFullyCollapsed ? 0 : 12.0, // Паддинг самого MenuItem
            vertical: 12.0,
          ),
          child: renderAsFullyCollapsed
              ? SizedBox(
            // Ширина для свернутого MenuItem (только иконка)
            // Должна быть равна доступной ширине контента сайдбара в свернутом состоянии
            width: kCollapsedSidebarWidth - (2 * 8.0), // 8.0 - это padding сайдбара в свернутом виде
            child: Icon(
              icon,
              color: currentIconColor,
              size: 24.0,
              semanticLabel: title,
            ),
          )
              : Row(
            children: <Widget>[
              Icon(
                icon,
                color: currentIconColor,
                size: 24.0,
                semanticLabel: title,
              ),
              // Текст и отступ показываем только если showText (определено выше)
              if (showText) ...[
                const SizedBox(width: 16.0),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: currentTextColor,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ] else ...[
                // Если текст не показываем, но мы в "развернутом" режиме Row,
                // то Row должен иметь Expanded, чтобы корректно работать.
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}