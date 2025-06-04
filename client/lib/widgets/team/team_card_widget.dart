// lib/widgets/team/team_card_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Для DateFormat
import '../../models/team_model.dart';

class TeamCardWidget extends StatelessWidget {
  final Team team;
  final VoidCallback? onTap;

  const TeamCardWidget({
    Key? key,
    required this.team,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final bool hasDescription = team.description != null && team.description!.isNotEmpty;
    final Color cardColor = team.displayColor;

    Widget avatarWidget;
    if (team.imageUrl != null && team.imageUrl!.isNotEmpty) {
      avatarWidget = CircleAvatar(
        radius: 16, // Уменьшаем радиус аватара для компактности
        backgroundColor: cardColor.withOpacity(0.2),
        backgroundImage: NetworkImage(team.imageUrl!),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint("Error loading team image: ${team.imageUrl}, Error: $exception");
        },
        child: Text(
          team.name.isNotEmpty ? team.name[0].toUpperCase() : "?",
          style: TextStyle(
            color: cardColor,
            fontWeight: FontWeight.bold,
            fontSize: 14, // Уменьшаем шрифт инициалов
          ),
        ),
      );
    } else {
      avatarWidget = CircleAvatar(
        radius: 16, // Уменьшаем радиус аватара
        backgroundColor: cardColor.withOpacity(0.3),
        child: Text(
          team.name.isNotEmpty ? team.name[0].toUpperCase() : "?",
          style: TextStyle(
            color: cardColor.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.bold,
            fontSize: 14, // Уменьшаем шрифт инициалов
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.0),
      hoverColor: cardColor.withOpacity(0.08),
      splashColor: cardColor.withOpacity(0.12),
      highlightColor: cardColor.withOpacity(0.1),
      child: Container(
        padding: const EdgeInsets.all(10.0), // Уменьшаем внутренние отступы
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: cardColor.withOpacity(0.6), width: 1.0), // Тоньше граница
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.05), // Меньше тень
              blurRadius: 4.0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Оставляем для вертикального распределения
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center, // Выравниваем по центру для компактности
              children: [
                avatarWidget, // Аватар теперь слева и меньше
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    team.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      fontSize: 15, // Немного уменьшаем шрифт названия
                      height: 1.2,
                    ),
                    maxLines: 1, // Ограничиваем одной строкой для компактности
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Можно добавить иконку "меню" или "инфо" если нужно будет
              ],
            ),
            if (hasDescription)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0), // Уменьшаем отступы
                child: Text(
                  team.description!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                    height: 1.2,
                    fontSize: 11, // Уменьшаем шрифт описания
                  ),
                  maxLines: 2, // Оставляем две строки для описания
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Если нет описания, добавим небольшой отступ, чтобы футер не прилипал к шапке
            if (!hasDescription) const SizedBox(height: 6),

            Padding(
              padding: const EdgeInsets.only(top: 4.0), // Уменьшаем отступ сверху
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center, // Выравниваем по центру
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_outlined, size: 14, color: colorScheme.onSurfaceVariant), // Уменьшаем иконку
                      const SizedBox(width: 3),
                      Text(
                        '${team.memberCount} уч.',
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 10), // Уменьшаем шрифт
                      ),
                    ],
                  ),
                  Text(
                    '${DateFormat('dd.MM.yy', 'ru_RU').format(team.createdAt)}', // Более короткий формат даты
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 10), // Уменьшаем шрифт
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}