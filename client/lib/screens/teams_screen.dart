// lib/screens/teams_screen.dart
import 'package:ToDo/core/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/team_model.dart';
import '../team_provider.dart';
import '../widgets/team/team_card_widget.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
import '../widgets/team/team_search_dialog.dart';

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

  void _showTeamActionsBottomSheet(BuildContext context) {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (builderContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(builderContext).viewInsets.bottom),
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('Создать команду'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  teamProvider.displayCreateTeamDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sensor_door_outlined),
                title: const Text('Присоединиться по коду'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  teamProvider.displayJoinTeamDialog(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showTeamSearchDialog(BuildContext context) {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: teamProvider,
          child: const TeamSearchDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<TeamProvider>(
      builder: (context, teamProvider, child) {
        Widget bodyContent;
        bool showFab = true;

        if (teamProvider.isLoadingMyTeams && teamProvider.myTeams.isEmpty) {
          bodyContent = const Center(child: CircularProgressIndicator());
          showFab = false;
        } else if (teamProvider.error != null && teamProvider.myTeams.isEmpty) {
          bodyContent = _buildErrorState(context, colorScheme, teamProvider);
          showFab = true;
        } else if (teamProvider.myTeams.isEmpty) {
          bodyContent = _buildEmptyState(context, colorScheme, theme);
          showFab = false;
        } else {
          if (isMobile) {
            bodyContent = RefreshIndicator(
              onRefresh: () => teamProvider.fetchMyTeams(),
              child: ListView.separated(
                padding: const EdgeInsets.all(12.0),
                itemCount: teamProvider.myTeams.length,
                itemBuilder: (context, index) {
                  final team = teamProvider.myTeams[index];
                  return TeamCardWidget(
                    team: team,
                    onTap: () => _navigateToTeamDetail(context, team.teamId),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(height: 10),
              ),
            );
          } else {
            bodyContent = LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount;
                double childAspectRatio;
                if (constraints.maxWidth > 1200) {
                  crossAxisCount = 5; childAspectRatio = 0.9;
                } else if (constraints.maxWidth > 900) {
                  crossAxisCount = 4; childAspectRatio = 0.95;
                } else {
                  crossAxisCount = 3; childAspectRatio = 0.9;
                }

                return RefreshIndicator(
                  onRefresh: () => teamProvider.fetchMyTeams(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16.0),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
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
              },
            );
          }
        }

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: theme.appBarTheme.backgroundColor,
              centerTitle: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: "Поиск команд",
                  onPressed: () => _showTeamSearchDialog(context),
                )
              ],
            ),
            body: SafeArea(child: bodyContent),
            floatingActionButton: showFab ? FloatingActionButton(
              onPressed: () => _showTeamActionsBottomSheet(context),
              tooltip: 'Действия',
              child: const Icon(Icons.add_rounded),
            ) : null,
          );
        }

        return Container(
          margin: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 16.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
            boxShadow: [ BoxShadow(color: theme.shadowColor.withOpacity(0.07), blurRadius: 8.0, offset: const Offset(0, 2)) ],
          ),
          clipBehavior: Clip.antiAlias,
          child: bodyContent,
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, ColorScheme colorScheme, TeamProvider teamProvider) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Ошибка: ${teamProvider.error}', style: TextStyle(color: colorScheme.error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => teamProvider.fetchMyTeams(), child: const Text('Попробовать снова'))
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme, ThemeData theme) {
    Widget actions = FloatingActionButton.extended(
      onPressed: () => _showTeamActionsBottomSheet(context),
      label: const Text("Начать"),
      icon: const Icon(Icons.add_rounded),
    );

    if (!ResponsiveUtil.isMobile(context)) {
      actions = Row(
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
      );
    }

    return Center(
      child: Opacity(
        opacity: 0.7,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: 72, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text("У вас пока нет команд", style: theme.textTheme.headlineSmall?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text("Создайте новую команду или присоединитесь к существующей.", style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            actions,
          ],
        ),
      ),
    );
  }
}