// lib/screens/team_detail_screen.dart
import 'package:ToDo/core/utils/responsive_utils.dart';
import 'package:ToDo/models/task_model.dart';
import 'package:ToDo/task_provider.dart';
import 'package:ToDo/widgets/kanban_board/kanban_board_widget.dart';
import 'package:ToDo/widgets/tasks/TaskFilterDialog.dart';
import 'package:ToDo/widgets/tasks/TaskSortDialog.dart';
import 'package:ToDo/widgets/tasks/mobile_task_list_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/routing/app_pages.dart';
import '../models/team_model.dart';
import '../team_provider.dart';
import '../auth_state.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
import '../sidebar_state_provider.dart';
import '../widgets/tasks/team_task_edit_dialog.dart';
import '../tag_provider.dart';
import '../widgets/tags/tag_edit_dialog.dart';
import '../widgets/tags/tag_list_item_widget.dart';
import '../widgets/team/generate_invite_link_dialog.dart';
import 'package:intl/intl.dart';
import '../widgets/common/user_avatar.dart';
import '../widgets/team/change_member_role_dialog.dart';
import '../widgets/team/edit_team_info_dialog.dart';
import '../widgets/team/team_chat_widget.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;

  const TeamDetailScreen({Key? key, required this.teamId}) : super(key: key);

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Tab> _tabs = [];
  final List<Widget> _tabViews = [];

  late SidebarStateProvider _sidebarStateProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sidebarStateProvider = Provider.of<SidebarStateProvider>(context, listen: false);
        _sidebarStateProvider.addListener(_onSidebarSectionChanged);

        final teamProvider = Provider.of<TeamProvider>(context, listen: false);
        teamProvider.fetchTeamDetails(widget.teamId, forceRefresh: true).then((_) {
          if (mounted) {
            setState(() {
              _setupTabsAndController();
            });
          }
        });

        _handleSectionChange(_sidebarStateProvider.currentTeamDetailSection, isInitialCall: true);
      }
    });
  }

  void _setupTabsAndController() {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final teamDetail = teamProvider.currentTeamDetail;
    if (teamDetail == null) return;

    final oldIndex = _tabController.index;
    if(mounted) {
      _tabController.removeListener(_onTabSelected);
      _tabController.dispose();
    }

    _tabs.clear();
    _tabViews.clear();

    final userRole = teamDetail.currentUserRole;
    final canManageTeamTags = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin || userRole == TeamMemberRole.editor;

    _addTab(TeamDetailSection.tasks, "Задачи", Icons.list_alt_rounded);
    _addTab(TeamDetailSection.chat, "Чат", Icons.chat_bubble_outline_rounded);
    _addTab(TeamDetailSection.members, "Участники", Icons.group_outlined);

    if (canManageTeamTags) {
      _addTab(TeamDetailSection.teamTags, "Теги", Icons.label_outline_rounded);
    }
    _addTab(TeamDetailSection.management, "Управление", Icons.tune_rounded);

    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: (oldIndex >= 0 && oldIndex < _tabs.length) ? oldIndex : 0,
    );
    _tabController.addListener(_onTabSelected);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        _onSidebarSectionChanged();
        setState(() {});
      }
    });
  }

  void _onTabSelected() {
    if (!_tabController.indexIsChanging && mounted) {
      if (_tabController.index < _tabs.length) {
        final tag = _tabs[_tabController.index].key as ValueKey<TeamDetailSection>?;
        if (tag != null) {
          _sidebarStateProvider.setCurrentTeamDetailSection(tag.value);
        }
      }
      setState(() {});
    }
  }

  void _onSidebarSectionChanged() {
    if (ResponsiveUtil.isMobile(context) && _tabController.length > 0) {
      final section = _sidebarStateProvider.currentTeamDetailSection;
      final tabIndex = _tabs.indexWhere((tab) => (tab.key as ValueKey<TeamDetailSection>?)?.value == section);
      if (tabIndex != -1 && _tabController.index != tabIndex) {
        _tabController.animateTo(tabIndex);
      }
    }
  }


  void _addTab(TeamDetailSection section, String title, IconData icon) {
    _tabs.add(Tab(
      key: ValueKey(section),
      height: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ));
    _tabViews.add(Builder(builder: (context) {
      final teamDetail = Provider.of<TeamProvider>(context).currentTeamDetail;
      if (teamDetail == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildSectionContent(context, section, teamDetail);
    }));
  }

  @override
  void dispose() {
    _sidebarStateProvider.removeListener(_onSidebarSectionChanged);
    _tabController.removeListener(_onTabSelected);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    if (teamProvider.currentTeamDetail?.teamId != widget.teamId && !teamProvider.isLoadingTeamDetail) {
      teamProvider.fetchTeamDetails(widget.teamId, forceRefresh: true).then((_){
        if (mounted) {
          setState(() {
            _setupTabsAndController();
          });
        }
      });
    }
  }

  void _handleSectionChange(TeamDetailSection section, {bool isInitialCall = false}) {
    if (!mounted) return;
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final teamIdInt = int.tryParse(widget.teamId);

    if (section == TeamDetailSection.tasks) {
      _triggerFetchTeamTasksIfNeeded(forceCall: isInitialCall);
    } else if (section == TeamDetailSection.teamTags && teamIdInt != null) {
      if (isInitialCall || !tagProvider.teamTagsByTeamId.containsKey(teamIdInt) || (tagProvider.teamTagsByTeamId[teamIdInt]?.isEmpty ?? true) ) {
        if (!tagProvider.isLoadingTeamTags) {
          tagProvider.fetchTeamTags(teamIdInt);
        }
      }
    }
  }

  Future<void> _triggerFetchTeamTasksIfNeeded({bool forceCall = false}) async {
    if (!mounted) return;
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    await taskProvider.fetchTasks(teamId: widget.teamId, forceBackendCall: forceCall);
  }

  void _navigateToTaskDetails(BuildContext context, Task task) {
    Provider.of<AppRouterDelegate>(context, listen: false)
        .navigateTo(TaskDetailPath(task.taskId));
  }

  void _handleTaskStatusChanged(Task task, KanbanColumnStatus newStatus) {
    Provider.of<TaskProvider>(context, listen: false).locallyUpdateTaskStatus(task.taskId, newStatus);
  }

  // ... (Остальные методы-обработчики действий остаются без изменений)
  void _checkedHandleTaskDelete(Task taskToDelete, bool canGenericEdit, String currentUserId) {
    if (canGenericEdit || taskToDelete.createdByUserId == currentUserId) {
      showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Удалить задачу?'),
            content: Text('Вы уверены, что хотите переместить задачу "${taskToDelete.title}" в корзину?'),
            actions: <Widget>[
              TextButton(child: const Text('Отмена'),onPressed: () => Navigator.of(dialogContext).pop(false)),
              TextButton(style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), child: const Text('Удалить'), onPressed: () => Navigator.of(dialogContext).pop(true)),
            ],
          );
        },
      ).then((confirmed) {
        if (confirmed == true && mounted) {
          Provider.of<TaskProvider>(context, listen: false).deleteTask(taskToDelete.taskId).then((success) {
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Задача '${taskToDelete.title}' удалена.")));
            } else if (mounted && Provider.of<TaskProvider>(context, listen: false).error != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка удаления задачи: ${Provider.of<TaskProvider>(context, listen: false).error}"), backgroundColor: Colors.red));
            }
          });
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("У вас нет прав для удаления этой задачи.")));
    }
  }

  void _checkedHandleTaskEdit(Task taskToEdit, bool canGenericEdit, String currentUserId) {
    if (canGenericEdit || taskToEdit.createdByUserId == currentUserId) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      final members = teamProvider.currentTeamDetail?.members.map((m) => m.user).toList() ?? [];

      showDialog<Task?>(context: context, builder: (BuildContext dialogContext) {
        return TeamTaskEditDialog(
          teamId: taskToEdit.teamId!,
          members: members,
          taskToEdit: taskToEdit,
          onTaskSaved: (Task? updatedTask) {
            if(updatedTask != null) {
              debugPrint("TeamDetailScreen: Team task edited via dialog: ${updatedTask.title}");
            }
          },
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("У вас нет прав для редактирования этой задачи.")));
    }
  }

  void _showCreateTeamTaskDialogForMobile(BuildContext context, String teamId) {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final members = teamProvider.currentTeamDetail?.members.map((m) => m.user).toList() ?? [];

    debugPrint("[TeamDetailScreen] Showing create team task dialog (for mobile) for team ID: $teamId");
    showDialog<Task?>(context: context, builder: (BuildContext dialogContext) {
      return TeamTaskEditDialog(
        teamId: teamId,
        members: members,
        onTaskSaved: (Task? newTask) {
          if (newTask != null) {
            debugPrint("TeamDetailScreen (mobile FAB): New team task saved (ID: ${newTask.taskId}), Team ID: ${newTask.teamId}");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Задача "${newTask.title}" добавлена в команду!')));
            }
          }
        },
      );
    });
  }

  void _showTaskManagementBottomSheet(BuildContext context, TeamDetail team) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final bool canEditTasks = team.currentUserRole == TeamMemberRole.owner ||
        team.currentUserRole == TeamMemberRole.admin ||
        team.currentUserRole == TeamMemberRole.editor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (builderContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(builderContext).viewInsets.bottom),
          child: Wrap(
            children: <Widget>[
              if (canEditTasks)
                ListTile(
                  leading: const Icon(Icons.add_task_outlined),
                  title: const Text('Добавить задачу'),
                  onTap: () {
                    Navigator.of(builderContext).pop();
                    _showCreateTeamTaskDialogForMobile(context, team.teamId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.filter_list_rounded),
                title: const Text('Фильтры'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  showDialog(
                    context: context,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: taskProvider,
                      child: TaskFilterDialog(viewType: TaskListViewType.teamSpecific, teamIdForContext: team.teamId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert_rounded),
                title: const Text('Сортировка'),
                onTap: () {
                  Navigator.of(builderContext).pop();
                  showDialog(
                    context: context,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: taskProvider,
                      child: const TaskSortDialog(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _displayTeamTagEditDialog(BuildContext context, TeamDetail team, {ApiTag? tagToEdit}) {
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final teamIdInt = int.tryParse(team.teamId);
    if (teamIdInt == null) return;
    showDialog(context: context, builder: (BuildContext dialogContext) {
      return TagEditDialog(
        isTeamTag: true, teamId: team.teamId, tagToEdit: tagToEdit,
        onSave: (String name, String colorHex, {int? tagId}) async {
          bool success;
          String actionMessage;
          if (tagToEdit == null) {
            actionMessage = "Тег '$name' создан для команды";
            success = await tagProvider.createTeamTag(teamIdInt, name: name, colorHex: colorHex);
          } else {
            actionMessage = "Тег '${tagToEdit.name}' обновлен";
            success = await tagProvider.updateTeamTag(tagId ?? tagToEdit.id, teamIdInt, name: name, colorHex: colorHex);
          }
          if (mounted) {
            final scaffoldContext = dialogContext.mounted ? dialogContext : context;
            if (success) {
              ScaffoldMessenger.of(scaffoldContext).showSnackBar(SnackBar(content: Text(actionMessage)));
              tagProvider.fetchTeamTags(teamIdInt, forceRefresh: true);
            } else {
              ScaffoldMessenger.of(scaffoldContext).showSnackBar(SnackBar(content: Text(tagProvider.error ?? 'Не удалось сохранить тег команды'), backgroundColor: Colors.red));
              if(tagProvider.error != null) tagProvider.clearError();
            }
          }
        },
      );
    });
  }
  void _confirmDeleteTeamTag(BuildContext context, TeamDetail team, ApiTag tag) {
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final teamIdInt = int.tryParse(team.teamId);
    if (teamIdInt == null) return;
    showDialog<bool>(context: context, builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Удалить тег команды?'),
        content: Text('Вы уверены, что хотите удалить тег "${tag.name}" из команды "${team.name}"? Это действие нельзя будет отменить.'),
        actions: <Widget>[
          TextButton(child: const Text('Отмена'), onPressed: () => Navigator.of(dialogContext).pop(false)),
          TextButton(style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), child: const Text('Удалить'), onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      );
    },
    ).then((confirmed) async {
      if (confirmed == true && mounted) {
        bool success = await tagProvider.deleteTeamTag(tag.id, teamIdInt);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Тег "${tag.name}" удален из команды.')));
            tagProvider.fetchTeamTags(teamIdInt, forceRefresh: true);
          } else if (tagProvider.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tagProvider.error ?? "Не удалось удалить тег"), backgroundColor: Colors.red));
            tagProvider.clearError();
          }
        }
      }
    });
  }
  void _showGenerateInviteDialog(BuildContext contextFromButton, TeamDetail team) {
    debugPrint("[TeamDetailScreen._showGenerateInviteDialog] Showing GenerateInviteLinkDialog. Context from button: $contextFromButton, Mounted: $mounted");
    showDialog(context: contextFromButton, builder: (BuildContext dialogBuildContextForGenerate) {
      debugPrint("[TeamDetailScreen._showGenerateInviteDialog builder] GenerateInviteLinkDialog context: $dialogBuildContextForGenerate, Mounted: ${dialogBuildContextForGenerate.mounted}");
      return ChangeNotifierProvider.value(
        value: Provider.of<TeamProvider>(contextFromButton, listen: false),
        child: GenerateInviteLinkDialog(
          teamId: team.teamId,
          onInviteGenerated: (TeamInviteTokenResponse inviteResponse) {
            debugPrint("[TeamDetailScreen onInviteGenerated callback] Received inviteResponse: ${inviteResponse.inviteToken}. TeamDetailScreen mounted: $mounted. Context from button ($contextFromButton) is active: ${contextFromButton.findRenderObject()?.attached ?? false}");
            Future.delayed(Duration.zero, () {
              if (mounted && (contextFromButton.findRenderObject()?.attached ?? false)) {
                _showInviteTokenInfoDialog(contextFromButton, inviteResponse);
              } else {
                debugPrint("[TeamDetailScreen onInviteGenerated callback with delay] TeamDetailScreen is NOT mounted OR original context is not active. Cannot show info dialog.");
              }
            });
          },
        ),
      );
    });
  }
  void _showInviteTokenInfoDialog(BuildContext contextForInfoDialog, TeamInviteTokenResponse inviteResponse) {
    final theme = Theme.of(contextForInfoDialog);
    debugPrint("[TeamDetailScreen._showInviteTokenInfoDialog] Preparing to show info dialog. Context: $contextForInfoDialog (Mounted: ${contextForInfoDialog.findRenderObject()?.attached ?? false}), Token: ${inviteResponse.inviteToken}, Link from backend: ${inviteResponse.inviteLink}");
    String? displayInviteLink = inviteResponse.inviteLink;
    if (displayInviteLink != null && displayInviteLink.isEmpty) {
      displayInviteLink = null;
    }
    debugPrint("[TeamDetailScreen._showInviteTokenInfoDialog] Using invite_link from backend (if available): $displayInviteLink");
    String expiresAtFormatted = "Не указан";
    if (inviteResponse.expiresAt != null) {
      try {
        expiresAtFormatted = DateFormat('dd.MM.yyyy HH:mm', 'ru_RU').format(inviteResponse.expiresAt!.toLocal());
      } catch (e) {
        debugPrint("Error formatting expiresAt date: ${inviteResponse.expiresAt}. Error: $e");
        expiresAtFormatted = inviteResponse.expiresAt.toString();
      }
    }
    String roleFormatted = inviteResponse.roleOnJoin?.localizedName ?? "Участник";
    debugPrint("[TeamDetailScreen._showInviteTokenInfoDialog] Displaying info dialog. Token: ${inviteResponse.inviteToken}, Effective Link: $displayInviteLink. Context: $contextForInfoDialog, Mounted: ${contextForInfoDialog.findRenderObject()?.attached ?? false}");
    showDialog(context: contextForInfoDialog, builder: (BuildContext dialogBuildContextForInfo) {
      debugPrint("[TeamDetailScreen._showInviteTokenInfoDialog builder] AlertDialog context: $dialogBuildContextForInfo, Mounted: ${dialogBuildContextForInfo.findRenderObject()?.attached ?? false}");
      return AlertDialog(
        title: const Text('Ссылка-приглашение создана'),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text('Код-приглашение:', style: theme.textTheme.titleSmall),
              SelectableText(inviteResponse.inviteToken, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (displayInviteLink != null) ...[
                Text('Ссылка для вступления:', style: theme.textTheme.titleSmall),
                SelectableText(displayInviteLink, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 12),
              ] else ...[
                Text('Ссылка для вступления:', style: theme.textTheme.titleSmall),
                Text('Не предоставлена сервером.', style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
              ],
              Text('Роль при вступлении:', style: theme.textTheme.titleSmall),
              Text(roleFormatted, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('Действителен до:', style: theme.textTheme.titleSmall),
              Text(expiresAtFormatted, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Копировать код'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: inviteResponse.inviteToken));
              if (dialogBuildContextForInfo.mounted) {
                ScaffoldMessenger.of(dialogBuildContextForInfo).showSnackBar(const SnackBar(content: Text('Код приглашения скопирован!')));
              }
            },
          ),
          if (displayInviteLink != null)
            TextButton.icon(
              icon: const Icon(Icons.link_rounded),
              label: const Text('Копировать ссылку'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: displayInviteLink!));
                if (dialogBuildContextForInfo.mounted) {
                  ScaffoldMessenger.of(dialogBuildContextForInfo).showSnackBar(const SnackBar(content: Text('Ссылка приглашения скопирована!')));
                }
              },
            ),
          ElevatedButton(child: const Text('OK'), onPressed: () => Navigator.of(dialogBuildContextForInfo).pop()),
        ],
      );
    });
    debugPrint("[TeamDetailScreen._showInviteTokenInfoDialog] After showDialog call for info dialog.");
  }
  void _showChangeMemberRoleDialog(BuildContext parentContext, TeamDetail team, TeamMember memberToUpdate) {
    final teamProvider = Provider.of<TeamProvider>(parentContext, listen: false);
    showDialog(context: parentContext, builder: (BuildContext dialogContext) {
      return ChangeNotifierProvider.value(
        value: teamProvider,
        child: ChangeMemberRoleDialog(
          teamId: team.teamId,
          memberToUpdate: memberToUpdate,
          onRoleChanged: (TeamMemberRole newRole) async {
            debugPrint("[TeamDetailScreen] Changing role for ${memberToUpdate.user.login} (ID: ${memberToUpdate.user.userId}) to ${newRole.name}");
            bool success = await teamProvider.updateTeamMemberRole(team.teamId, memberToUpdate.user.userId, newRole);
            if (parentContext.mounted) {
              if (success) {
                ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text('Роль для ${memberToUpdate.user.login} обновлена на ${newRole.localizedName}.')));
              } else {
                ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text(teamProvider.error ?? 'Не удалось обновить роль.'), backgroundColor: Theme.of(parentContext).colorScheme.error));
                teamProvider.clearError();
              }
            }
          },
        ),
      );
    });
  }
  void _confirmRemoveMember(BuildContext parentContext, TeamDetail team, TeamMember memberToRemove) {
    final teamProvider = Provider.of<TeamProvider>(parentContext, listen: false);
    showDialog<bool>(context: parentContext, builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text('Удалить ${memberToRemove.user.login}?'),
        content: Text('Вы уверены, что хотите удалить участника ${memberToRemove.user.login} из команды "${team.name}"?'),
        actions: <Widget>[
          TextButton(child: const Text('Отмена'), onPressed: () => Navigator.of(dialogContext).pop(false)),
          TextButton(style: TextButton.styleFrom(foregroundColor: Theme.of(parentContext).colorScheme.error), child: const Text('Удалить'), onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      );
    }).then((confirmed) async {
      if (confirmed == true) {
        debugPrint("[TeamDetailScreen] Removing member ${memberToRemove.user.login} (ID: ${memberToRemove.user.userId}) from team ${team.teamId}");
        bool success = await teamProvider.removeTeamMember(team.teamId, memberToRemove.user.userId);
        if (parentContext.mounted) {
          if (success) {
            ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text('Участник ${memberToRemove.user.login} удален из команды.')));
          } else {
            ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text(teamProvider.error ?? 'Не удалось удалить участника.'), backgroundColor: Theme.of(parentContext).colorScheme.error));
            teamProvider.clearError();
          }
        }
      }
    });
  }
  void _showEditTeamInfoDialog(BuildContext context, TeamDetail team) {
    if (team.currentUserRole == TeamMemberRole.owner) {
      showDialog(context: context, builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: Provider.of<TeamProvider>(context, listen: false),
          child: EditTeamInfoDialog(teamToEdit: team),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Только владелец может редактировать информацию о команде.')));
    }
  }

  Widget _buildSectionContent(BuildContext context, TeamDetailSection section, TeamDetail team) {
    final authState = Provider.of<AuthState>(context, listen: false);
    final userRole = team.currentUserRole;
    bool canEditTasks = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin || userRole == TeamMemberRole.editor;
    bool canManageMembers = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin;
    bool canManageTeamTags = userRole == TeamMemberRole.owner || userRole == TeamMemberRole.admin || userRole == TeamMemberRole.editor;

    return SafeArea(
      top: ResponsiveUtil.isMobile(context),
      bottom: ResponsiveUtil.isMobile(context),
      child: switch (section) {
        TeamDetailSection.tasks => _buildTasksTab(context, authState.currentUser?.userId.toString() ?? '', team.teamId, canEditTasks),
        TeamDetailSection.chat => _buildChatTab(context, team),
        TeamDetailSection.members => _buildMembersTab(context, team, canManageMembers, authState.currentUser?.userId ?? 0),
        TeamDetailSection.teamTags => _buildTeamTagsTab(context, team, canManageTeamTags),
        TeamDetailSection.management => _buildManagementTab(context, team),
      },
    );
  }

  Widget _buildMobileLayout(TeamDetail team) {
    if (_tabs.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text("Загрузка...")), body: const Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
        leading: routerDelegate.canPop() ? BackButton(color: theme.colorScheme.onSurface) : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 2.5,
          labelPadding: EdgeInsets.zero,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabViews,
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
        onPressed: () => _showTaskManagementBottomSheet(context, team),
        tooltip: 'Действия с задачами',
        child: const Icon(Icons.more_horiz_rounded),
      )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<TeamProvider>(
      builder: (context, teamProvider, child) {
        final team = teamProvider.currentTeamDetail;

        if (teamProvider.isLoadingTeamDetail && team == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (teamProvider.error != null && team == null) {
          return Scaffold(body: Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Ошибка загрузки команды: ${teamProvider.error}", textAlign: TextAlign.center),
          )));
        }
        if (team == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (isMobile) {
          return _buildMobileLayout(team);
        }

        final sidebarState = Provider.of<SidebarStateProvider>(context);
        return _buildSectionContent(context, sidebarState.currentTeamDetailSection, team);
      },
    );
  }

  Widget _buildTasksTab(BuildContext context, String currentUserId, String teamIdForDialog, bool canEditTasksOverall) {
    final isMobile = ResponsiveUtil.isMobile(context);
    final taskProvider = Provider.of<TaskProvider>(context);

    return RefreshIndicator(
      onRefresh: () => taskProvider.fetchTasks(teamId: widget.teamId, forceBackendCall: true),
      child: Column(
        children: [
          Expanded(
            child: Builder(
                builder: (context) {
                  final List<Task> teamTasks = taskProvider.tasksForTeamView(widget.teamId);

                  if (taskProvider.isLoadingList && teamTasks.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (taskProvider.error != null && teamTasks.isEmpty) {
                    return ListView(children: [Center(child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text("Ошибка загрузки задач: ${taskProvider.error}", textAlign: TextAlign.center),
                    ))]);
                  }
                  if (teamTasks.isEmpty && !taskProvider.isLoadingList) {
                    return ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("В этой команде пока нет задач.")))]);
                  }

                  if (isMobile) {
                    return MobileTaskListWidget(
                      tasks: teamTasks,
                      onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
                      onTaskTap: (task) => _navigateToTaskDetails(context, task),
                      onTaskDelete: (Task taskForDelete) => _checkedHandleTaskDelete(taskForDelete, canEditTasksOverall, currentUserId),
                      onTaskEdit: (Task taskForEdit) => _checkedHandleTaskEdit(taskForEdit, canEditTasksOverall, currentUserId),
                      currentUserId: currentUserId,
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
                    child: KanbanBoardWidget(
                      tasks: teamTasks,
                      onTaskStatusChanged: (task, newStatus) => _handleTaskStatusChanged(task, newStatus),
                      onTaskDelete: (Task taskForDelete) => _checkedHandleTaskDelete(taskForDelete, canEditTasksOverall, currentUserId),
                      onTaskEdit: (Task taskForEdit) => _checkedHandleTaskEdit(taskForEdit, canEditTasksOverall, currentUserId),
                    ),
                  );
                }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab(BuildContext context, TeamDetail team) {
    final authState = Provider.of<AuthState>(context, listen: false);
    if (authState.currentUser == null) {
      return const Center(child: Text("Пожалуйста, войдите, чтобы использовать чат."));
    }
    return TeamChatWidget(
      teamId: team.teamId,
    );
  }


  Widget _buildMembersTab(BuildContext context, TeamDetail team, bool canManageTeam, int currentUserId) {
    final theme = Theme.of(context);
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    if (team.members.isEmpty) {
      return const Center(child: Text("В команде пока нет участников."));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: team.members.length,
      itemBuilder: (context, index) {
        final member = team.members[index];
        final bool isCurrentUser = member.user.userId == currentUserId;
        final bool isOwner = member.role == TeamMemberRole.owner;

        bool canKickThisMember = canManageTeam && !isOwner && !isCurrentUser;
        if (team.currentUserRole == TeamMemberRole.admin && (member.role == TeamMemberRole.admin || member.role == TeamMemberRole.owner)) {
          canKickThisMember = false;
        }

        bool canChangeRoleForThisMember = canManageTeam && !isOwner && !isCurrentUser;
        if (team.currentUserRole == TeamMemberRole.admin && (member.role == TeamMemberRole.admin || member.role == TeamMemberRole.owner)) {
          canChangeRoleForThisMember = false;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: UserAvatar.fromUserLite(
              user: member.user,
              radius: 22,
            ),
            title: Text(member.user.login, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
            subtitle: Text(member.role.localizedName, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            trailing: (canKickThisMember || canChangeRoleForThisMember) && !teamProvider.isProcessingTeamAction
                ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (String value) {
                if (value == 'change_role') {
                  _showChangeMemberRoleDialog(context, team, member);
                } else if (value == 'remove_member') {
                  _confirmRemoveMember(context, team, member);
                }
              },
              itemBuilder: (BuildContext popupContext) => <PopupMenuEntry<String>>[
                if (canChangeRoleForThisMember)
                  const PopupMenuItem<String>(
                    value: 'change_role',
                    child: ListTile(leading: Icon(Icons.edit_attributes_outlined), title: Text('Изменить роль')),
                  ),
                if (canKickThisMember)
                  const PopupMenuItem<String>(
                    value: 'remove_member',
                    child: ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red), title: Text('Удалить из команды', style: TextStyle(color: Colors.red))),
                  ),
              ],
            )
                : (teamProvider.isProcessingTeamAction ? const SizedBox(width:24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5,)) : null),
          ),
        );
      },
    );
  }

  Widget _buildTeamTagsTab(BuildContext context, TeamDetail team, bool canManageTags) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);
    final tagProvider = Provider.of<TagProvider>(context);
    final teamIdInt = int.tryParse(team.teamId);

    if (teamIdInt == null) {
      return const Center(child: Text("Неверный ID команды."));
    }

    final List<ApiTag> currentTeamTags = tagProvider.teamTagsByTeamId[teamIdInt] ?? [];

    if (!canManageTags) {
      return currentTeamTags.isEmpty
          ? const Center(child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("В этой команде пока нет тегов.", textAlign: TextAlign.center)))
          : ListView.separated(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0).copyWith(top: isMobile ? 20 : 28, left: isMobile ? 16: 32, right: isMobile? 16 : 32),
        itemCount: currentTeamTags.length,
        itemBuilder: (context, index) {
          final tag = currentTeamTags[index];
          return TagListItemWidget(tag: tag, showActions: false);
        },
        separatorBuilder: (context, index) => Divider(
          color: colorScheme.outlineVariant.withOpacity(isMobile ? 0.3 : 0.4),
          height: isMobile ? 16 : 20,
          thickness: 0.8,
        ),
      );
    }

    Widget content;
    if (tagProvider.isLoadingTeamTags && currentTeamTags.isEmpty && tagProvider.error == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (tagProvider.error != null && currentTeamTags.isEmpty && !tagProvider.isLoadingTeamTags) {
      content = Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text("Ошибка загрузки тегов", style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(tagProvider.error!, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Попробовать снова"),
                  onPressed: () => tagProvider.fetchTeamTags(teamIdInt, forceRefresh: true),
                )
              ],
            ),
          )
      );
    } else if (currentTeamTags.isEmpty && !tagProvider.isLoadingTeamTags) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.label_off_outlined, size: isMobile ? 48 : 64, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
              const SizedBox(height: 20),
              Text(
                "В команде '${team.name}' пока нет тегов.",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    } else {
      content = ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: currentTeamTags.length,
        itemBuilder: (context, index) {
          final tag = currentTeamTags[index];
          return TagListItemWidget(
            tag: tag,
            onEdit: () => _displayTeamTagEditDialog(context, team, tagToEdit: tag),
            onDelete: () => _confirmDeleteTeamTag(context, team, tag),
          );
        },
        separatorBuilder: (context, index) => Divider(
          color: colorScheme.outlineVariant.withOpacity(isMobile ? 0.3 : 0.4),
          height: isMobile ? 16 : 20,
          thickness: 0.8,
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0).copyWith(
        top: isMobile ? 20 : 28,
        left: isMobile ? 16 : 32,
        right: isMobile ? 16 : 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Теги команды",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: isMobile ? 20 : 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(isMobile ? "Добавить" : "Добавить тег"),
                onPressed: () => _displayTeamTagEditDialog(context, team),
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12: 16, vertical: isMobile? 10: 12)
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          content,
        ],
      ),
    );
  }

  Widget _buildManagementTab(BuildContext context, TeamDetail team) {
    final theme = Theme.of(context);
    final bool isMobile = ResponsiveUtil.isMobile(context);
    final teamProvider = Provider.of<TeamProvider>(context, listen:false);
    final currentUserRole = team.currentUserRole;

    final bool canEditTeamInfo = currentUserRole == TeamMemberRole.owner;
    final bool canManageInvites = currentUserRole == TeamMemberRole.owner || currentUserRole == TeamMemberRole.admin;
    final bool canLeaveTeam = currentUserRole != TeamMemberRole.owner;
    final bool canDeleteTeam = currentUserRole == TeamMemberRole.owner;

    Widget teamAvatarWidget;
    if (team.imageUrl != null && team.imageUrl!.isNotEmpty) {
      teamAvatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(isMobile ? 24 : 30),
        child: Image.network(
          team.imageUrl!,
          width: isMobile ? 48 : 60,
          height: isMobile ? 48 : 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return UserAvatar(
              login: team.name,
              accentColorHex: team.colorHex,
              radius: isMobile ? 24 : 30,
            );
          },
        ),
      );
    } else {
      teamAvatarWidget = UserAvatar(
        login: team.name,
        accentColorHex: team.colorHex,
        radius: isMobile ? 24 : 30,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              teamAvatarWidget,
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  team.name,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 24 : 28,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (team.description != null && team.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(team.description!, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 24),

          if (canEditTeamInfo) ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text("Редактировать информацию"),
              onPressed: () => _showEditTeamInfoDialog(context, team),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 15)
              ),
            ),
            const Divider(height: 50, thickness: 0.8),
          ],

          if (canManageInvites) ...[
            Text("Приглашения", style: theme.textTheme.headlineSmall?.copyWith(fontSize: isMobile ? 20 : 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_link_rounded),
              label: const Text("Создать ссылку-приглашение"),
              onPressed: () => _showGenerateInviteDialog(context, team),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), textStyle: const TextStyle(fontSize: 15)),
            ),
            const Divider(height: 50, thickness: 0.8),
          ],

          Text("Действия с командой", style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.error, fontSize: isMobile ? 20 : 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          if (canLeaveTeam)
            OutlinedButton.icon(
              icon: const Icon(Icons.exit_to_app_rounded),
              label: const Text("Покинуть команду"),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  side: BorderSide(color: Colors.orange.shade800, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 15)
              ),
              onPressed: teamProvider.isProcessingTeamAction ? null : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text('Покинуть команду "${team.name}"?'),
                    content: const Text('Вы уверены, что хотите выйти из этой команды?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Отмена')),
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        child: Text('Покинуть', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  bool success = await teamProvider.leaveTeam(team.teamId);
                  if (mounted) {
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Вы покинули команду "${team.name}".')));
                      Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const HomeSubPath(AppRouteSegments.teams));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teamProvider.error ?? 'Не удалось покинуть команду.'), backgroundColor: Colors.red));
                    }
                  }
                }
              },
            ),

          if (canDeleteTeam) ...[
            if (canLeaveTeam) const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text("Удалить команду"),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 15)
              ),
              onPressed: teamProvider.isProcessingTeamAction ? null : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text('Удалить команду "${team.name}"?'),
                    content: const Text('ВНИМАНИЕ! Это действие необратимо и приведет к удалению всех задач и данных команды.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Отмена')),
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        child: Text('УДАЛИТЬ', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  bool success = await teamProvider.deleteTeam(team.teamId);
                  if (mounted) {
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Команда "${team.name}" удалена.')));
                      Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const HomeSubPath(AppRouteSegments.teams));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teamProvider.error ?? 'Не удалось удалить команду.'), backgroundColor: Colors.red));
                    }
                  }
                }
              },
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}