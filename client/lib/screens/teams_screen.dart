import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/utils/responsive_utils.dart';
import '../models/team_model.dart';
import '../team_provider.dart';
import '../widgets/team/team_card_widget.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({Key? key}) : super(key: key);

  @override
  _TeamsScreenState createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      if (teamProvider.myTeams.isEmpty && !teamProvider.isLoadingMyTeams && teamProvider.error == null) {
        teamProvider.fetchMyTeams();
      }
    });
  }

  void _navigateToTeamDetail(BuildContext context, String teamId) {
    Provider.of<AppRouterDelegate>(context, listen: false)
        .navigateTo(TeamDetailPath(teamId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<TeamProvider>(
      builder: (context, teamProvider, child) {
        if (teamProvider.isLoadingMyTeams && teamProvider.myTeams.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (teamProvider.error != null && teamProvider.myTeams.isEmpty) {
          return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Ошибка: ${teamProvider.error}',
                        style: TextStyle(color: colorScheme.error), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                        onPressed: () => teamProvider.fetchMyTeams(),
                        child: const Text('Попробовать снова')
                    )
                  ],
                ),
              ));
        }

        if (teamProvider.myTeams.isEmpty) {
          return _buildEmptyState(context, colorScheme, theme, isMobile);
        }

        Widget gridContent = LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount;
              double childAspectRatio;

              // <<< ИЗМЕНЕНИЕ: Адаптивная сетка >>>
              if (isMobile) {
                crossAxisCount = 2; // Всегда 2 колонки на мобильных
                childAspectRatio = 0.9; // Сделаем карточки чуть более вытянутыми
              } else {
                if (constraints.maxWidth > 1200) {
                  crossAxisCount = 5;
                  childAspectRatio = 0.9;
                } else if (constraints.maxWidth > 900) {
                  crossAxisCount = 4;
                  childAspectRatio = 0.95;
                } else {
                  crossAxisCount = 3;
                  childAspectRatio = 0.9;
                }
              }

              final double mainAxisSpacing = isMobile ? 12 : 16;
              final double crossAxisSpacing = isMobile ? 12 : 16;
              final EdgeInsets padding = isMobile
                  ? const EdgeInsets.all(12.0)
                  : const EdgeInsets.all(16.0);

              return RefreshIndicator(
                onRefresh: () => teamProvider.fetchMyTeams(),
                child: GridView.builder(
                  padding: padding,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisSpacing: mainAxisSpacing,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: teamProvider.myTeams.length,
                  itemBuilder: (context, index) {
                    final team = teamProvider.myTeams[index];
                    return TeamCardWidget(
                      team: team,
                      onTap: () => _navigateToTeamDetail(context, team.teamId),
                    );
                  },
                ),
              );
            }
        );

        // Для мобильных не нужна обертка с тенью, так как фон будет из Scaffold
        if(isMobile) {
          return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor, // Фон из общей темы
              body: gridContent,
              floatingActionButton: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'joinTeamFab',
                    onPressed: () => teamProvider.displayJoinTeamDialog(context),
                    tooltip: 'Войти по коду',
                    child: const Icon(Icons.sensor_door_outlined),
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton(
                    heroTag: 'createTeamFab',
                    onPressed: () => teamProvider.displayCreateTeamDialog(context),
                    tooltip: 'Создать команду',
                    child: const Icon(Icons.group_add_outlined),
                  ),
                ],
              )
          );
        }

        return Container(
          margin: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 16.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.07),
                blurRadius: 8.0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: gridContent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme, ThemeData theme, bool isMobile) {
    return Center(
      child: Opacity(
        opacity: 0.7,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: isMobile ? 56 : 72, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(
              "У вас пока нет команд",
              style: theme.textTheme.headlineSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Создайте новую команду или присоединитесь к существующей.",
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text("Создать команду"),
                  onPressed: () => Provider.of<TeamProvider>(context, listen: false).displayCreateTeamDialog(context),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.sensor_door_outlined),
                  label: const Text("Войти по коду"),
                  onPressed: () => Provider.of<TeamProvider>(context, listen: false).displayJoinTeamDialog(context),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}