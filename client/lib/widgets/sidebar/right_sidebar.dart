// lib/widgets/sidebar/right_sidebar.dart
import '../../core/routing/app_pages.dart';
import '../../core/routing/app_router_delegate.dart';
import '../../core/routing/app_route_path.dart';
import '../../models/team_model.dart';
import '../../sidebar_state_provider.dart';
import '../../team_provider.dart';
import '../../task_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../tasks/TaskFilterDialog.dart';
import '../tasks/TaskSortDialog.dart';
import '../tasks/team_task_edit_dialog.dart';
import '../tasks/task_edit_dialog.dart';
import '../../models/task_model.dart';
import '../team/team_search_dialog.dart';

class RightSidebar extends StatelessWidget {
  const RightSidebar({Key? key}) : super(key: key);

  static const double _sidebarWidth = 96.0;
  static const double _itemSpacing = 16.0;
  static const double _standardButtonSize = 60.0;

  void _showCreateTeamTaskDialog(BuildContext context, String teamId, List<UserLite> members) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    debugPrint("[RightSidebar] Showing create TEAM task dialog for team ID: $teamId");
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TeamTaskEditDialog(
          teamId: teamId,
          members: members,
          onTaskSaved: (newTask) {
            debugPrint("RightSidebar (via TeamTaskEditDialog): New team task saved callback. Task ID: ${newTask.taskId}");
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('Задача "${newTask.title}" для команды добавлена!')),
              );
            }
            taskProvider.fetchTasks(teamId: teamId, forceBackendCall: true);
          },
        );
      },
    );
  }

  void _showCreatePersonalTaskDialog(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    debugPrint("[RightSidebar] Showing create PERSONAL task dialog");
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TaskEditDialog(
          onTaskSaved: (newTask) {
            debugPrint("RightSidebar (via TaskEditDialog): New personal task saved callback. Task ID: ${newTask.taskId}");
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('Задача "${newTask.title}" добавлена!')),
              );
            }
            final currentPath = Provider.of<AppRouterDelegate>(context, listen: false).currentConfiguration;
            if (currentPath is HomeSubPath) {
              if (currentPath.subRoute == AppRouteSegments.allTasks) {
                taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated, forceBackendCall: true);
              } else if (currentPath.subRoute == AppRouteSegments.personalTasks) {
                taskProvider.fetchTasks(viewType: TaskListViewType.personal, forceBackendCall: true);
              } else if (currentPath.subRoute == AppRouteSegments.calendar) {
                taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated, forceBackendCall: true);
              }
            } else {
              taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated, forceBackendCall: true);
            }
          },
        );
      },
    );
  }

  void _showFilterDialog(BuildContext context, TaskListViewType viewType, String? teamIdContext) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: taskProvider,
          child: TaskFilterDialog(
            viewType: viewType,
            teamIdForContext: teamIdContext,
          ),
        );
      },
    );
  }

  void _showSortDialog(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: taskProvider,
          child: const TaskSortDialog(),
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
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    final currentPath = routerDelegate.currentConfiguration;
    final sidebarStateProvider = Provider.of<SidebarStateProvider>(context);

    List<Widget> topActionButtons = [];
    List<Widget> bottomActionButtons = [];

    if (currentPath is TeamDetailPath) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      final teamDetail = teamProvider.currentTeamDetail;
      bool canManageTeamOverall = false; // Owner, Admin
      bool canManageTeamTags = false;    // Owner, Admin, Editor
      bool canEditTasks = false;         // Owner, Admin, Editor
      // bool canOnlyViewAndLeave = false; // Member, Editor (для вкладки управления) - убрал, т.к. управление в самой вкладке

      if (teamDetail != null) {
        final userRole = teamDetail.currentUserRole;
        canManageTeamOverall = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin;
        canManageTeamTags = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin || userRole == TeamMemberRole.editor;
        canEditTasks = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin || userRole == TeamMemberRole.editor;
      }

      topActionButtons.addAll([
        ActionButton(
          icon: Icons.list_alt_rounded,
          tooltip: "Задачи команды",
          isActive: sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.tasks,
          onPressed: () => sidebarStateProvider.setCurrentTeamDetailSection(TeamDetailSection.tasks),
        ),
        const SizedBox(height: _itemSpacing),
        ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          tooltip: "Чат команды",
          isActive: sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.chat,
          onPressed: () => sidebarStateProvider.setCurrentTeamDetailSection(TeamDetailSection.chat),
        ),
        const SizedBox(height: _itemSpacing),
        ActionButton(
          icon: Icons.group_outlined,
          tooltip: "Участники",
          isActive: sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.members,
          onPressed: () => sidebarStateProvider.setCurrentTeamDetailSection(TeamDetailSection.members),
        ),
        const SizedBox(height: _itemSpacing),
      ]);

      if (canManageTeamTags) { // Доступно для Owner, Admin, Editor
        topActionButtons.add(
          ActionButton(
            icon: Icons.label_outline_rounded,
            tooltip: "Теги команды",
            isActive: sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.teamTags,
            onPressed: () => sidebarStateProvider.setCurrentTeamDetailSection(TeamDetailSection.teamTags),
          ),
        );
        topActionButtons.add(const SizedBox(height: _itemSpacing));
      }

      // Вкладка "Управление" доступна всем участникам команды
      topActionButtons.add(
        ActionButton(
          icon: Icons.tune_rounded, // Иконка как у настроек, но можно изменить
          tooltip: "Управление командой", // <<< ИЗМЕНЕН ТУЛТИП
          isActive: sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.management, // <<< ИЗМЕНЕН ENUM
          onPressed: () => sidebarStateProvider.setCurrentTeamDetailSection(TeamDetailSection.management), // <<< ИЗМЕНЕН ENUM
        ),
      );

      if (sidebarStateProvider.currentTeamDetailSection == TeamDetailSection.tasks) {
        if (topActionButtons.isNotEmpty && topActionButtons.last is ActionButton) {
          if (!(topActionButtons.length >= 2 && topActionButtons[topActionButtons.length-2] is ActionButton && (topActionButtons[topActionButtons.length-2] as ActionButton).tooltip == "Управление командой")) { // Проверяем, что предыдущая кнопка не "Управление"
            topActionButtons.add(const SizedBox(height: _itemSpacing * 1.5));
          }
        } else if (topActionButtons.isEmpty) {
          topActionButtons.add(const SizedBox(height: _itemSpacing * 0.5));
        }

        topActionButtons.add(
            ActionButton(
              icon: Icons.filter_list_rounded, // Изменил иконку
              tooltip: "Фильтры задач команды",
              onPressed: () => _showFilterDialog(context, TaskListViewType.teamSpecific, currentPath.teamId),
            )
        );
        topActionButtons.add(const SizedBox(height: _itemSpacing));
        topActionButtons.add(
            ActionButton(
              icon: Icons.swap_vert_rounded,
              tooltip: "Сортировка задач команды",
              onPressed: () => _showSortDialog(context),
            )
        );

        if (canEditTasks) {
          final teamId = currentPath.teamId;
          final members = teamDetail?.members.map((m) => m.user).toList() ?? [];
          bottomActionButtons.add(
              ActionButton(
                icon: Icons.add_task_outlined,
                tooltip: "Добавить задачу в команду",
                onPressed: () => _showCreateTeamTaskDialog(context, teamId, members),
              )
          );
        }
      }
    } else if (currentPath is HomeSubPath) {
      TaskListViewType? currentViewType;
      bool showTaskManagementActions = false;

      if (currentPath.subRoute == AppRouteSegments.allTasks) {
        currentViewType = TaskListViewType.allAssignedOrCreated;
        showTaskManagementActions = true;
      } else if (currentPath.subRoute == AppRouteSegments.personalTasks) {
        currentViewType = TaskListViewType.personal;
        showTaskManagementActions = true;
      } else if (currentPath.subRoute == AppRouteSegments.calendar) {
        currentViewType = TaskListViewType.allAssignedOrCreated;
        showTaskManagementActions = true;
      }
      else if (currentPath.subRoute == AppRouteSegments.teams) {
        topActionButtons.add(
          ActionButton(
            icon: Icons.manage_search_outlined,
            tooltip: "Поиск команд",
            onPressed: () => _showTeamSearchDialog(context),
          ),
        );
        bottomActionButtons.addAll([
          ActionButton(
            icon: Icons.group_add_outlined,
            tooltip: "Создать команду",
            onPressed: () => Provider.of<TeamProvider>(context, listen: false).displayCreateTeamDialog(context),
          ),
          const SizedBox(height: _itemSpacing),
          ActionButton(
            icon: Icons.sensor_door_outlined,
            tooltip: "Войти по коду",
            onPressed: () => Provider.of<TeamProvider>(context, listen: false).displayJoinTeamDialog(context),
          ),
        ]);
      }

      if (showTaskManagementActions && currentViewType != null) {
        topActionButtons.addAll([
          ActionButton(
            icon: Icons.tune_outlined, // Оставил tune для общих фильтров
            tooltip: "Фильтрация задач",
            onPressed: () => _showFilterDialog(context, currentViewType!, null),
          ),
          const SizedBox(height: _itemSpacing),
          ActionButton(
            icon: Icons.swap_vert_rounded,
            tooltip: "Сортировка задач",
            onPressed: () => _showSortDialog(context),
          ),
        ]);

        if (currentPath.subRoute == AppRouteSegments.allTasks ||
            currentPath.subRoute == AppRouteSegments.personalTasks ||
            currentPath.subRoute == AppRouteSegments.calendar) {
          bottomActionButtons.add(
              ActionButton(
                icon: Icons.add_circle_outline_rounded,
                tooltip: "Добавить личную задачу",
                onPressed: () => _showCreatePersonalTaskDialog(context),
              )
          );
        }
      }
    }

    List<Widget> finalWidgets = [];
    finalWidgets.addAll(topActionButtons);
    if (bottomActionButtons.isNotEmpty) {
      if (finalWidgets.isNotEmpty && (finalWidgets.last is! Spacer && finalWidgets.last is! SizedBox && !(finalWidgets.length == 1 && finalWidgets.first is Spacer))) {
        finalWidgets.add(const Spacer());
      } else if (finalWidgets.isEmpty) {
        finalWidgets.add(const Spacer());
      }
      for (int i = 0; i < bottomActionButtons.length; i++) {
        finalWidgets.add(bottomActionButtons[i]);
        if (i < bottomActionButtons.length - 1) {
          finalWidgets.add(const SizedBox(height: _itemSpacing));
        }
      }
    }

    return Container(
      width: _sidebarWidth,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: _itemSpacing, horizontal: (_sidebarWidth - _standardButtonSize) / 2),
      decoration: BoxDecoration(
        color: colorScheme.background, // Изменено на background для консистентности
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: finalWidgets,
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? iconColor;
  final Color? borderColor;
  final Color? backgroundColor;
  final double borderWidth;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  const ActionButton({
    Key? key,
    required this.icon,
    this.size = RightSidebar._standardButtonSize,
    this.iconColor,
    this.borderColor,
    this.backgroundColor,
    this.borderWidth = 1.5,
    this.onPressed,
    this.tooltip,
    this.isActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color finalIconColor;
    Color finalBorderColor;
    Color finalBackgroundColor;
    bool showActiveShadow = false;

    // Если явно задан цвет фона для кнопки (например, для FAB-подобных)
    if (backgroundColor != null) {
      finalIconColor = iconColor ?? (ThemeData.estimateBrightnessForColor(backgroundColor!) == Brightness.dark ? Colors.white70 : Colors.black87);
      finalBorderColor = borderColor ?? backgroundColor!.withAlpha(200); // Рамка чуть темнее/светлее фона
      finalBackgroundColor = backgroundColor!;
    } else { // Стандартные кнопки сайдбара
      if (isActive) {
        finalIconColor = iconColor ?? colorScheme.onPrimaryContainer;
        finalBorderColor = borderColor ?? colorScheme.primary;
        finalBackgroundColor = colorScheme.primaryContainer.withOpacity(0.7); // Полупрозрачный фон для активной
        showActiveShadow = true;
      } else {
        finalIconColor = iconColor ?? colorScheme.onSurfaceVariant;
        finalBorderColor = borderColor ?? colorScheme.outline.withOpacity(0.5);
        finalBackgroundColor = colorScheme.surfaceContainerHigh; // Фон для неактивных
      }
    }

    final double iconWidgetSize = size * 0.45; // Размер иконки относительно размера кнопки

    Widget buttonContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: finalBackgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: finalBorderColor,
            width: borderWidth,
          ),
          boxShadow: [
            if(showActiveShadow)
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.25),
                blurRadius: 5,
                spreadRadius: 1,
              )
          ]
      ),
      child: Icon(icon, color: finalIconColor, size: iconWidgetSize),
    );

    return Material( // Material для InkWell эффектов
      color: Colors.transparent,
      shape: const CircleBorder(), // Форма для InkWell
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: colorScheme.primary.withOpacity(0.12),
        highlightColor: colorScheme.primary.withOpacity(0.1),
        child: (tooltip != null && tooltip!.isNotEmpty)
            ? Tooltip(
          message: tooltip!,
          preferBelow: true, // Показываем тултип снизу
          verticalOffset: size / 2 + 8, // Смещение тултипа
          margin: const EdgeInsets.only(right: 10),
          child: buttonContent,
        )
            : buttonContent,
      ),
    );
  }
}