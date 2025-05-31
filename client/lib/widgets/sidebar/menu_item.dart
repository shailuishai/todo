// lib/widgets/sidebar/menu_item.dart
import 'package:flutter/material.dart';
import './sidebar_constants.dart'; // Путь к константам

class MenuItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final bool isCollapsed; // Финальное состояние схлопывания сайдбара
  final double currentContentWidthForMenuItem; // Текущая доступная ширина для контента MenuItem
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
    final colorScheme = theme.colorScheme;

    // Цвета для активного и неактивного состояния
    final Color activeIconColor = colorScheme.primary;
    final Color activeTextColor = colorScheme.primary;
    final Color inactiveIconColor = colorScheme.onSurfaceVariant;
    final Color inactiveTextColor = colorScheme.onSurface; // Или onSurfaceVariant для меньшего контраста

    final Color currentIconColor = isActive ? activeIconColor : inactiveIconColor;
    final Color currentTextColor = isActive ? activeTextColor : inactiveTextColor;

    // Фон для активного элемента
    final Color? itemBackgroundColor = isActive
        ? activeIconColor.withOpacity(0.08) // Легкий фон для активного элемента
        : null;

    // Минимальная ширина КОНТЕНТА MenuItem (после вычета его собственных паддингов),
    // необходимая для отображения текста.
    // Иконка (kSidebarItemIconSize) + отступ (kSidebarItemGap) + минимальный текст (например, 30-50)
    // Паддинги самого MenuItem: kSidebarItemHorizontalPadding * 2
    final double minInternalContentWidthForTextToShowText = kSidebarItemIconSize + kSidebarItemGap + 30.0;

    // Решаем, показывать ли текст, на основе isCollapsed И текущей доступной ширины для КОНТЕНТА MenuItem
    // Контент MenuItem = currentContentWidthForMenuItem - (2 * kSidebarItemHorizontalPadding)
    final bool showText = !isCollapsed &&
        (currentContentWidthForMenuItem - (2 * kSidebarItemHorizontalPadding)) > minInternalContentWidthForTextToShowText;

    // Определяем, как рендерить: полностью свернуто (только иконка), или пытаться развернуть (иконка + текст, если помещается)
    // Если isCollapsed = true, всегда рендерим как свернутый.
    // Если isCollapsed = false, но текст не помещается (showText = false), также рендерим как свернутый (только иконка, но центрированная в доступном пространстве).
    bool renderAsIconOnly = isCollapsed || (!isCollapsed && !showText);

    return Material(
      key: ValueKey('$title-$isActive-$renderAsIconOnly'), // Ключ для корректной анимации
      color: itemBackgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(10.0), // Стандартный радиус для M3
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.0),
        splashColor: activeIconColor.withOpacity(0.12),
        highlightColor: activeIconColor.withOpacity(0.1),
        child: Padding(
          // Внутренние отступы самого MenuItem
          padding: EdgeInsets.symmetric(
            horizontal: kSidebarItemHorizontalPadding,
            vertical: kSidebarItemVerticalPadding,
          ),
          child: renderAsIconOnly
              ? SizedBox( // Если только иконка, центрируем ее в доступном пространстве
            width: currentContentWidthForMenuItem - (2 * kSidebarItemHorizontalPadding), // Ширина для центрирования иконки
            child: Icon(
              icon,
              color: currentIconColor,
              size: kSidebarItemIconSize,
              semanticLabel: title, // Для доступности
            ),
          )
              : Row( // Иконка и текст
            children: <Widget>[
              Icon(
                icon,
                color: currentIconColor,
                size: kSidebarItemIconSize,
                semanticLabel: title, // Для доступности, даже если текст виден
              ),
              // Текст и отступ показываем только если showText (определено выше)
              // Это условие уже учтено в renderAsIconOnly, но для ясности можно оставить
              // if (showText) ...[ // showText уже true, если мы здесь
              const SizedBox(width: kSidebarItemGap), // Отступ между иконкой и текстом
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith( // Используем подходящий стиль из темы
                    color: currentTextColor,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, // Активный текст жирнее
                    fontSize: 14, // Явный размер, если нужно
                  ),
                  overflow: TextOverflow.ellipsis, // Обрезка длинного текста
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              // ]
              // else if (!isCollapsed) ...[ // Это случай, когда !isCollapsed, но !showText. Этот случай обрабатывается в renderAsIconOnly.
              //   // Если текст не показываем, но мы в "развернутом" режиме Row (т.е. isCollapsed=false),
              //   // то Row должен иметь Expanded, чтобы корректно работать.
              //   const Expanded(child: SizedBox.shrink()),
              // ],
            ],
          ),
        ),
      ),
    );
  }
}