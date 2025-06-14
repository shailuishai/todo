import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Для DateFormat
import '../../models/team_model.dart';
import '../common/user_avatar.dart'; // <<< ИМПОРТИРУЕМ НАШ УНИВЕРСАЛЬНЫЙ АВАТАР

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

    // <<< ИЗМЕНЕНИЕ: Используем наш новый универсальный UserAvatar >>>
    Widget avatarWidget = UserAvatar(
        login: team.name,
        avatarUrl: team.imageUrl,
        accentColorHex: team.colorHex,
        radius: 20 // Уменьшаем радиус аватара для компактности
    );

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardColor.withOpacity(0.15),
                colorScheme.surfaceContainerHigh,
              ],
              stops: const [0.0, 0.8],
            ),
            border: Border(top: BorderSide(color: cardColor, width: 2.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatarWidget,
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            team.name,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (hasDescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          team.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.3,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${team.memberCount}',
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      Text(
                        '${DateFormat('dd.MM.yy', 'ru_RU').format(team.createdAt)}',
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}