// lib/screens/task_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/routing/app_pages.dart';
import '../core/routing/app_route_path.dart';
import '../core/utils/responsive_utils.dart';
import '../models/task_model.dart';
import '../models/team_model.dart';
import '../tag_provider.dart';
import '../task_provider.dart';
import '../team_provider.dart';
import '../auth_state.dart';
import '../deleted_tasks_provider.dart';
import '../widgets/common/user_avatar.dart';
import '../widgets/tasks/task_edit_dialog.dart';
import '../widgets/tasks/team_task_edit_dialog.dart';
import '../core/routing/app_router_delegate.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;

  const TaskDetailScreen({Key? key, required this.taskId}) : super(key: key);

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);
        taskProvider.getTaskById(widget.taskId);
      }
    });
  }

  void _editTask(BuildContext context, Task task) {
    debugPrint("[TaskDetailScreen._editTask] Editing task ID: ${task.taskId}, Title: ${task.title}");
    if (task.isTeamTask && task.teamId != null) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      teamProvider.fetchTeamDetails(task.teamId!).then((_) {
        if (mounted) {
          final members = teamProvider.currentTeamDetail?.members.map((m) => m.user).toList() ?? [];
          showDialog<Task?>(
            context: context,
            builder: (BuildContext dialogContext) {
              return TeamTaskEditDialog(
                teamId: task.teamId!,
                members: members,
                taskToEdit: task,
                onTaskSaved: (Task? updatedTask) {
                  if (updatedTask != null) {
                    debugPrint("TaskDetailScreen: TeamTaskEditDialog.onTaskSaved for task ID: ${updatedTask.taskId}");
                  }
                },
              );
            },
          );
        }
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось загрузить детали команды для редактирования: $error'), backgroundColor: Colors.red),
          );
        }
      });
    } else {
      showDialog<Task?>(
        context: context,
        builder: (BuildContext dialogContext) {
          return TaskEditDialog(
            taskToEdit: task,
            onTaskSaved: (Task? updatedTaskFromCallback) {
              if (updatedTaskFromCallback != null) {
                debugPrint("[TaskDetailScreen.onTaskSaved] Received updated task from callback - ID: ${updatedTaskFromCallback.taskId}");
              }
            },
          );
        },
      );
    }
  }

  Color _getPriorityColor(TaskPriority priority, ColorScheme colorScheme) {
    switch (priority) {
      case TaskPriority.high: return colorScheme.error;
      case TaskPriority.medium: return Colors.orange.shade700;
      case TaskPriority.low: default: return Colors.green.shade700;
    }
  }

  IconData _getStatusIcon(KanbanColumnStatus status) {
    switch (status) {
      case KanbanColumnStatus.todo: return Icons.radio_button_unchecked_rounded;
      case KanbanColumnStatus.in_progress: return Icons.sync_rounded;
      case KanbanColumnStatus.deferred: return Icons.pause_circle_outline_rounded;
      case KanbanColumnStatus.done: return Icons.check_circle_outline_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href == null) return;
    final Uri uri = Uri.parse(href);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть ссылку: $href')),
        );
      }
    }
  }

  void _deleteTask(BuildContext context, Task task) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final deletedTasksProvider = Provider.of<DeletedTasksProvider>(context, listen: false);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Удалить задачу?'),
          content: Text('Вы уверены, что хотите переместить задачу "${task.title}" в корзину?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Удалить'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        taskProvider.deleteTask(task.taskId).then((success) {
          if (success && mounted) {
            deletedTasksProvider.addDeletedTask(task);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Задача "${task.title}" перемещена в корзину')),
            );
            if (routerDelegate.canPop()) {
              routerDelegate.popRoute();
            } else {
              routerDelegate.navigateTo(const HomeSubPath(AppRouteSegments.allTasks));
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка удаления задачи: ${taskProvider.error ?? "Неизвестная ошибка"}'), backgroundColor: Colors.red),
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    return Consumer2<TaskProvider, TeamProvider>(
      builder: (context, taskProvider, teamProvider, child) {
        Task? task;
        try {
          task = taskProvider.allNonDeletedFetchedTasks.firstWhere((t) => t.taskId == widget.taskId);
        } catch (e) {
          // Задача еще не загружена
        }

        if (taskProvider.isLoadingList && task == null) {
          return Scaffold(
            backgroundColor: isMobile ? colorScheme.surface : colorScheme.background,
            appBar: isMobile ? AppBar(title: const Text('Загрузка задачи...')) : null,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (taskProvider.error != null && task == null) {
          return Scaffold(
            backgroundColor: isMobile ? colorScheme.surface : colorScheme.background,
            appBar: isMobile ? AppBar(title: const Text('Ошибка')) : null,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(taskProvider.error!, style: TextStyle(color: colorScheme.error)),
              ),
            ),
          );
        }

        if (task == null) {
          return Scaffold(
            backgroundColor: isMobile ? colorScheme.surface : colorScheme.background,
            appBar: isMobile ? AppBar(leading: routerDelegate.canPop() ? BackButton(onPressed: () => routerDelegate.popRoute()) : null, title: const Text('Задача не найдена')) : null,
            body: const Center(child: Text('Не удалось загрузить детали задачи. Возможно, она была удалена.')),
          );
        }

        final nonNullTask = task;
        final String? teamId = nonNullTask.teamId;

        if (nonNullTask.isTeamTask && teamId != null) {
          final isTeamDetailAvailable = teamProvider.currentTeamDetail?.teamId == teamId;
          final isTeamDetailLoading = teamProvider.isLoadingTeamDetail;
          if (!isTeamDetailAvailable && !isTeamDetailLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                teamProvider.fetchTeamDetails(teamId);
              }
            });
          }
        }

        bool canEdit = true;
        bool canDelete = true;

        Widget pageHeader;
        if (isMobile) {
          pageHeader = AppBar(
            backgroundColor: theme.colorScheme.surface,

            // 2. Устанавливаем цвет системного статус-бара НАПРЯМУЮ
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: theme.colorScheme.surface, // <-- Самое важное
              statusBarBrightness: Brightness.dark, // Для iOS
            ),

            // 3. Отключаем другие эффекты Material 3 для чистоты эксперимента
            elevation: 1,
            scrolledUnderElevation: 1, // Чтобы цвет не менялся при скролле
            surfaceTintColor: Colors.transparent,

            leading: routerDelegate.canPop() ? BackButton(onPressed: () => routerDelegate.popRoute()) : null,
            title: Text(nonNullTask.title, overflow: TextOverflow.ellipsis),
            actions: [
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit' && canEdit) _editTask(context, nonNullTask);
                    if (value == 'delete' && canDelete) _deleteTask(context, nonNullTask);
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    if (canEdit) const PopupMenuItem<String>(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Редактировать'))),
                    if (canDelete) PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: colorScheme.error), title: Text('Удалить', style: TextStyle(color: colorScheme.error)))),
                  ],
                ),
            ],
          );
        } else {
          pageHeader = Padding(
            padding: const EdgeInsets.only(bottom: 20.0, top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (routerDelegate.canPop())
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: "Назад", onPressed: () => routerDelegate.popRoute(), color: colorScheme.onSurfaceVariant, splashRadius: 24),
                      if (routerDelegate.canPop()) const SizedBox(width: 8),
                      Flexible(child: Text(nonNullTask.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface), overflow: TextOverflow.ellipsis, maxLines: 2)),
                    ],
                  ),
                ),
                if (canEdit || canDelete)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant),
                    tooltip: "Действия",
                    onSelected: (value) {
                      if (value == 'edit' && canEdit) _editTask(context, nonNullTask);
                      if (value == 'delete' && canDelete) _deleteTask(context, nonNullTask);
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      if (canEdit) const PopupMenuItem<String>(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Редактировать'))),
                      if (canDelete) PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: colorScheme.error), title: Text('Удалить', style: TextStyle(color: colorScheme.error)))),
                    ],
                  ),
              ],
            ),
          );
        }

        Widget taskInfoSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(icon: _getStatusIcon(nonNullTask.status), label: 'Статус:', valueWidget: Text(nonNullTask.status.title, style: theme.textTheme.bodyLarge?.copyWith(color: nonNullTask.status == KanbanColumnStatus.done ? colorScheme.primary : colorScheme.onSurface, fontWeight: FontWeight.w500)), context: context, iconColor: nonNullTask.status == KanbanColumnStatus.done ? colorScheme.primary : colorScheme.onSurfaceVariant),
            _buildDetailRow(icon: nonNullTask.priority.icon, label: 'Приоритет:', valueWidget: Text(nonNullTask.priority.name.isNotEmpty ? nonNullTask.priority.name[0].toUpperCase() + nonNullTask.priority.name.substring(1) : nonNullTask.priority.name, style: theme.textTheme.bodyLarge?.copyWith(color: _getPriorityColor(nonNullTask.priority, colorScheme), fontWeight: FontWeight.w500)), context: context, iconColor: _getPriorityColor(nonNullTask.priority, colorScheme)),
            if (nonNullTask.deadline != null) _buildDetailRow(icon: Icons.alarm_outlined, label: 'Дедлайн:', value: DateFormat('dd MMMM yyyy, HH:mm', 'ru_RU').format(nonNullTask.deadline!), context: context),
            if (nonNullTask.assignedToUserId != null)
              Builder(builder: (context) {
                Widget assigneeWidget;
                final teamDetail = teamProvider.currentTeamDetail;
                final bool teamDetailIsReady = nonNullTask.isTeamTask && teamDetail?.teamId == nonNullTask.teamId;

                if (teamDetailIsReady) {
                  UserLite? assignee;
                  try {
                    assignee = teamDetail!.members.firstWhere((m) => m.user.userId.toString() == nonNullTask.assignedToUserId).user;
                  } catch (e) { /* not found */ }

                  if (assignee != null) {
                    assigneeWidget = Row(children: [
                      UserAvatar(avatarUrl: assignee.avatarUrl, login: assignee.login, radius: 12),
                      const SizedBox(width: 8),
                      Expanded(child: Text(assignee.login, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface, fontSize: 15))),
                    ]);
                  } else {
                    assigneeWidget = Text('ID: ${nonNullTask.assignedToUserId}', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface, fontSize: 15));
                  }
                } else if (nonNullTask.isTeamTask) {
                  assigneeWidget = Text('Загрузка...', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 15));
                } else {
                  assigneeWidget = Text('ID: ${nonNullTask.assignedToUserId}', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface, fontSize: 15));
                }
                return _buildDetailRow(icon: Icons.person_outline, label: 'Исполнитель:', valueWidget: assigneeWidget, context: context);
              }),
            if (nonNullTask.isTeamTask && teamId != null)
              Builder(builder: (context) {
                final teamDetail = teamProvider.currentTeamDetail;
                final bool teamDetailIsReady = teamDetail?.teamId == teamId;
                String teamName = nonNullTask.teamName ?? 'ID: ${nonNullTask.teamId}';
                String? teamImageUrl;

                if (teamDetailIsReady) {
                  teamName = teamDetail!.name;
                  teamImageUrl = teamDetail.imageUrl;
                }
                return _buildDetailRow(
                  icon: Icons.group_work_outlined,
                  label: 'Команда:',
                  valueWidget: Row(
                    children: [
                      if (teamImageUrl != null && teamImageUrl.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(right: 8.0), child: CircleAvatar(backgroundImage: NetworkImage(teamImageUrl), radius: 12)),
                      Expanded(child: Text(teamName, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w500, fontSize: 15))),
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.primary.withOpacity(0.8)),
                    ],
                  ),
                  context: context,
                  onTap: () => routerDelegate.navigateTo(TeamDetailPath(teamId)),
                );
              }),
            _buildDetailRow(icon: Icons.create_outlined, label: 'Создана:', value: DateFormat('dd.MM.yyyy HH:mm', 'ru_RU').format(nonNullTask.createdAt), context: context),
            _buildDetailRow(icon: Icons.update_outlined, label: 'Обновлена:', value: DateFormat('dd.MM.yyyy HH:mm', 'ru_RU').format(nonNullTask.updatedAt), context: context),
            if (nonNullTask.status == KanbanColumnStatus.done && nonNullTask.completedAt != null) _buildDetailRow(icon: Icons.check_circle_outline, label: 'Завершена:', value: DateFormat('dd.MM.yyyy HH:mm', 'ru_RU').format(nonNullTask.completedAt!), context: context, iconColor: colorScheme.primary),
            if (nonNullTask.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Теги'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                children: nonNullTask.tags.map((tagFromTask) {
                  final tagProvider = Provider.of<TagProvider>(context, listen: false);
                  ApiTag? actualTag;
                  if (tagFromTask.type == 'user') {
                    try { actualTag = tagProvider.userTags.firstWhere((ut) => ut.id == tagFromTask.id); } catch (e) {/* ignore */}
                  } else if (tagFromTask.type == 'team' && teamId != null) {
                    final teamIdInt = int.tryParse(teamId);
                    if (teamIdInt != null) {
                      try { actualTag = tagProvider.teamTagsByTeamId[teamIdInt]?.firstWhere((tt) => tt.id == tagFromTask.id); } catch (e) {/* ignore */}
                    }
                  }
                  final displayTag = actualTag ?? tagFromTask;
                  return Chip(label: Text(displayTag.name, style: TextStyle(fontSize: 12, color: displayTag.displayColor, fontWeight: FontWeight.w500)), backgroundColor: displayTag.displayColor.withOpacity(0.15), side: BorderSide(color: displayTag.displayColor.withOpacity(0.5)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact);
                }).toList(),
              ),
            ],
          ],
        );

        Widget descriptionSection = (nonNullTask.description != null && nonNullTask.description!.isNotEmpty)
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Описание'),
            const SizedBox(height: 12),
            Card(
              elevation: 0.5,
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3))),
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: MarkdownBody(
                  data: nonNullTask.description!,
                  selectable: true,
                  onTapLink: _onTapLink,
                  imageBuilder: (Uri uri, String? title, String? alt) {
                    final effectiveAlt = alt ?? title ?? 'изображение';
                    if (uri.scheme == 'http' || uri.scheme == 'https') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Image.network(uri.toString(), errorBuilder: (context, error, stackTrace) => Text('Не удалось загрузить: $effectiveAlt', style: TextStyle(color: colorScheme.error)), loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null));
                        }),
                      );
                    }
                    return Text('[$effectiveAlt](${uri.toString()})', style: TextStyle(color: colorScheme.primary));
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: theme.textTheme.bodyLarge?.copyWith(height: 1.5), codeblockDecoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8), border: Border.all(color: colorScheme.outlineVariant)), h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface), h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                ),
              ),
            ),
          ],
        )
            : const SizedBox.shrink();

        Widget mainContentColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [if (!isMobile) pageHeader, taskInfoSection, descriptionSection, const SizedBox(height: 24)],
        );

        Widget bodyContent;
        if (isMobile) {
          bodyContent = SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: mainContentColumn);
        } else {
          // <<< ИЗМЕНЕНИЕ: Убираем лишний SingleChildScrollView, так как он уже есть в Scaffold ниже (для десктопа) >>>
          bodyContent = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Card(
                elevation: 1.0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3))),
                clipBehavior: Clip.antiAlias,
                child: Padding(padding: const EdgeInsets.all(24.0), child: mainContentColumn),
              ),
            ),
          );
        }

        return Scaffold(
          // <<< ИЗМЕНЕНИЕ: Устанавливаем корректный фон >>>
          backgroundColor: isMobile ? colorScheme.surface : colorScheme.background,
          appBar: isMobile ? (pageHeader as AppBar) : null,
          // <<< ИЗМЕНЕНИЕ: Добавляем SafeArea и ScrollView >>>
          body: SafeArea(
            child: SingleChildScrollView(
              padding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: bodyContent,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary));
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
    required BuildContext context,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    assert(value != null || valueWidget != null, 'Either value or valueWidget must be provided');

    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: iconColor ?? colorScheme.onSurfaceVariant.withOpacity(0.8)),
        const SizedBox(width: 16),
        Text('$label ', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 15)),
        Expanded(child: valueWidget ?? Text(value!, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface, fontSize: 15))),
      ],
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: content,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: content,
    );
  }
}