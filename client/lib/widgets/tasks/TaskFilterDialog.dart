// lib/widgets/tasks/task_filter_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth_state.dart';
import '../../core/utils/responsive_utils.dart';
import '../../models/task_model.dart';
import '../../task_provider.dart';
import '../../tag_provider.dart';
import '../../models/team_model.dart';
import '../../team_provider.dart';

class TaskFilterDialog extends StatefulWidget {
  final TaskListViewType viewType;
  final String? teamIdForContext;

  const TaskFilterDialog({
    Key? key,
    required this.viewType,
    this.teamIdForContext,
  }) : super(key: key);

  @override
  State<TaskFilterDialog> createState() => _TaskFilterDialogState();
}

class _TaskFilterDialogState extends State<TaskFilterDialog> {
  KanbanColumnStatus? _selectedStatus;
  TaskPriority? _selectedPriority;
  String? _selectedAssigneeId;
  List<int> _selectedTagIds = [];
  late TextEditingController _searchController;
  DateTime? _deadlineFrom;
  DateTime? _deadlineTo;

  List<UserLite> _availableAssignees = [];
  List<ApiTag> _availableTags = [];

  @override
  void initState() {
    super.initState();
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    final currentFilters = taskProvider.activeLocalFilters;
    _selectedStatus = currentFilters['status'] != null
        ? KanbanColumnStatusExtension.fromJson(currentFilters['status'])
        : null;
    _selectedPriority = currentFilters['priority'] != null
        ? TaskPriorityExtension.fromJson(currentFilters['priority'])
        : null;
    _selectedAssigneeId = currentFilters['assigned_to_user_id']?.toString();

    if (currentFilters['tag_ids'] is List<int>) {
      _selectedTagIds = List<int>.from(currentFilters['tag_ids']);
    } else if (currentFilters['tag_ids'] is List) {
      _selectedTagIds = List<int>.from(currentFilters['tag_ids'].whereType<int>());
    } else {
      _selectedTagIds = [];
    }

    _searchController = TextEditingController(text: currentFilters['search'] ?? '');
    _deadlineFrom = currentFilters['deadline_from'] as DateTime?;
    _deadlineTo = currentFilters['deadline_to'] as DateTime?;

    _loadAvailableOptions(context, taskProvider, tagProvider, teamProvider); // Передаем context
    debugPrint("[TaskFilterDialog.initState] Initialized with filters: Status=$_selectedStatus, Prio=$_selectedPriority, AssigneeId=$_selectedAssigneeId, Tags=$_selectedTagIds, Search='${_searchController.text}', DeadlineFrom=$_deadlineFrom, DeadlineTo=$_deadlineTo");
  }

  // Изменил, чтобы принимать context для Provider.of<AuthState>
  void _loadAvailableOptions(BuildContext context, TaskProvider taskProvider, TagProvider tagProvider, TeamProvider teamProvider) {
    Set<UserLite> assigneesSet = {};

    if (widget.viewType == TaskListViewType.teamSpecific && widget.teamIdForContext != null) {
      final teamDetail = teamProvider.currentTeamDetail;
      if (teamDetail != null && teamDetail.teamId == widget.teamIdForContext) {
        assigneesSet.addAll(teamDetail.members.map((m) => m.user));
        debugPrint("[TaskFilterDialog._loadAvailableOptions] Loaded ${assigneesSet.length} assignees from current team detail for team ${widget.teamIdForContext}.");
      } else {
        debugPrint("[TaskFilterDialog._loadAvailableOptions] Team detail not available or mismatch for teamSpecific assignee loading for team ${widget.teamIdForContext}. Fetching team details.");
        // Если детали команды еще не загружены (например, при первом открытии фильтра до полной загрузки экрана),
        // можно попытаться их загрузить. Но это может вызвать перестроение.
        // Лучше убедиться, что teamProvider.currentTeamDetail уже содержит нужные данные перед вызовом диалога.
        // Для простоты, если currentTeamDetail не тот, оставляем список пустым, но логгируем.
        // teamProvider.fetchTeamDetails(widget.teamIdForContext!); // Это может вызвать setState во время build, если диалог уже строится
      }
    } else if (widget.viewType == TaskListViewType.allAssignedOrCreated) {
      final authState = Provider.of<AuthState>(context, listen: false); // Получаем AuthState здесь
      final currentUser = authState.currentUser;
      if (currentUser != null) {
        // Для "Всех задач" можно добавить текущего пользователя как возможного исполнителя для фильтрации
        // assigneesSet.add(UserLite(userId: currentUser.userId, login: currentUser.login, avatarUrl: currentUser.avatarUrl));
      }
      // TODO: Рассмотреть сбор уникальных User ID из tasksForGlobalView и их отображение
      debugPrint("[TaskFilterDialog._loadAvailableOptions] Assignee loading for 'allAssignedOrCreated' view is currently limited.");
    }
    _availableAssignees = assigneesSet.toList()..sort((a,b) => a.login.toLowerCase().compareTo(b.login.toLowerCase()));

    Set<ApiTag> tagsSet = {};
    if (widget.viewType == TaskListViewType.teamSpecific && widget.teamIdForContext != null) {
      final teamIdInt = int.tryParse(widget.teamIdForContext!);
      if (teamIdInt != null) {
        // Убедимся, что теги для этой команды загружены
        if (!tagProvider.teamTagsByTeamId.containsKey(teamIdInt) && !tagProvider.isLoadingTeamTags) {
          debugPrint("[TaskFilterDialog._loadAvailableOptions] Team tags for team $teamIdInt not in cache, fetching...");
          tagProvider.fetchTeamTags(teamIdInt); // Асинхронный вызов, UI может обновиться позже
        }
        tagsSet.addAll(tagProvider.teamTagsByTeamId[teamIdInt] ?? []);
        debugPrint("[TaskFilterDialog._loadAvailableOptions] Loaded ${tagsSet.length} tags for team ID: $teamIdInt.");
      } else {
        debugPrint("[TaskFilterDialog._loadAvailableOptions] Invalid teamIdForContext for team tags: ${widget.teamIdForContext}");
      }
    } else {
      tagsSet.addAll(tagProvider.userTags);
      debugPrint("[TaskFilterDialog._loadAvailableOptions] Loaded ${tagsSet.length} user tags for global/personal view.");
    }
    _availableTags = tagsSet.toList()..sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final initialDateRange = (_deadlineFrom != null && _deadlineTo != null)
        ? DateTimeRange(start: _deadlineFrom!, end: _deadlineTo!)
        : (_deadlineFrom != null ? DateTimeRange(start: _deadlineFrom!, end: _deadlineFrom!.add(const Duration(days: 1))): null );

    final pickedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
      locale: const Locale('ru', 'RU'),
      helpText: 'Выберите диапазон дат дедлайна',
      cancelText: 'ОТМЕНА',
      confirmText: 'ВЫБРАТЬ',
      saveText: 'ПРИМЕНИТЬ',
    );

    if (pickedDateRange != null && mounted) {
      setState(() {
        _deadlineFrom = pickedDateRange.start;
        _deadlineTo = DateTime(pickedDateRange.end.year, pickedDateRange.end.month, pickedDateRange.end.day, 23, 59, 59);
      });
    }
  }

  void _applyFilters() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    Map<String, dynamic> newFilters = {};
    if (_selectedStatus != null) newFilters['status'] = _selectedStatus!.toJson();
    if (_selectedPriority != null) newFilters['priority'] = _selectedPriority!.toJson();
    if (_selectedAssigneeId != null) newFilters['assigned_to_user_id'] = _selectedAssigneeId;
    if (_searchController.text.trim().isNotEmpty) newFilters['search'] = _searchController.text.trim();
    if (_selectedTagIds.isNotEmpty) newFilters['tag_ids'] = _selectedTagIds;
    if (_deadlineFrom != null) newFilters['deadline_from'] = _deadlineFrom;
    if (_deadlineTo != null) newFilters['deadline_to'] = _deadlineTo;

    debugPrint("[TaskFilterDialog._applyFilters] Applying filters: $newFilters");
    taskProvider.applyFilters(newFilters);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _clearFilters() {
    debugPrint("[TaskFilterDialog._clearFilters] Clearing filters.");
    Provider.of<TaskProvider>(context, listen: false).clearFilters();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);
    final statusOptions = [null, ...KanbanColumnStatus.values];
    final priorityOptions = [null, ...TaskPriority.values];

    String deadlineText = "Не выбран";
    if (_deadlineFrom != null && _deadlineTo != null) {
      deadlineText = "${DateFormat('dd.MM.yy', 'ru_RU').format(_deadlineFrom!)} - ${DateFormat('dd.MM.yy', 'ru_RU').format(_deadlineTo!)}";
    } else if (_deadlineFrom != null) {
      deadlineText = "С ${DateFormat('dd.MM.yy', 'ru_RU').format(_deadlineFrom!)}";
    } else if (_deadlineTo != null) {
      deadlineText = "До ${DateFormat('dd.MM.yy', 'ru_RU').format(_deadlineTo!)}";
    }

    return AlertDialog(
      title: const Text('Фильтры задач'),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 24),
      content: SingleChildScrollView(
        child: SizedBox(
          width: isMobile ? MediaQuery.of(context).size.width * 0.8 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<KanbanColumnStatus?>(
                value: _selectedStatus,
                decoration: InputDecoration(
                  labelText: 'Статус',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 10 : 14),
                ),
                hint: const Text('Любой статус'),
                isExpanded: true,
                items: statusOptions.map((status) {
                  return DropdownMenuItem<KanbanColumnStatus?>(
                    value: status,
                    child: Text(status?.title ?? 'Любой статус'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedStatus = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskPriority?>(
                value: _selectedPriority,
                decoration: InputDecoration(
                  labelText: 'Приоритет',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 10 : 14),
                ),
                hint: const Text('Любой приоритет'),
                isExpanded: true,
                items: priorityOptions.map((priority) {
                  return DropdownMenuItem<TaskPriority?>(
                    value: priority,
                    child: Text(priority?.name ?? 'Любой приоритет'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedPriority = value),
              ),
              const SizedBox(height: 16),

              if (widget.viewType == TaskListViewType.allAssignedOrCreated ||
                  (widget.viewType == TaskListViewType.teamSpecific && _availableAssignees.isNotEmpty))
                DropdownButtonFormField<String?>(
                  value: _selectedAssigneeId,
                  decoration: InputDecoration(
                    labelText: 'Исполнитель',
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 10 : 14),
                  ),
                  hint: const Text('Любой исполнитель'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Любой исполнитель')),
                    const DropdownMenuItem<String?>(value: "0", child: Text('Не назначен')),
                    ..._availableAssignees.map((user) {
                      return DropdownMenuItem<String?>(
                        value: user.userId.toString(),
                        child: Text(user.login),
                      );
                    }),
                  ],
                  onChanged: (value) => setState(() => _selectedAssigneeId = value),
                ),
              if (widget.viewType == TaskListViewType.allAssignedOrCreated ||
                  (widget.viewType == TaskListViewType.teamSpecific && _availableAssignees.isNotEmpty))
                const SizedBox(height: 16),

              Text('Дедлайн:', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              InkWell( // Обернул ListTile в InkWell для лучшего отклика
                onTap: () => _pickDateRange(context),
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), // Увеличил vertical padding
                    // Убрал иконку календаря отсюда, т.к. она теперь в ListTile
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(child: Text(deadlineText, style: theme.textTheme.bodyLarge)),
                      IconButton( // Кнопка для сброса дат
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: "Сбросить дедлайн",
                        onPressed: (_deadlineFrom != null || _deadlineTo != null) ? () {
                          setState(() {
                            _deadlineFrom = null;
                            _deadlineTo = null;
                          });
                        } : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Поиск',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 10 : 14),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      }
                  )
                      : null,
                ),
                onChanged: (value) => setState((){}),
              ),
              const SizedBox(height: 16),

              if (_availableTags.isNotEmpty) ...[
                Text('Теги:', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Container(
                  constraints: BoxConstraints(maxHeight: isMobile ? 80 : 100),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 6.0,
                        runSpacing: 0.0,
                        children: _availableTags.map((tag) {
                          final isSelected = _selectedTagIds.contains(tag.id);
                          return FilterChip(
                            label: Text(tag.name, style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? (tag.displayColor.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.9) : Colors.white)
                                    : tag.textColorPreview)),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTagIds.add(tag.id);
                                } else {
                                  _selectedTagIds.remove(tag.id);
                                }
                              });
                            },
                            backgroundColor: tag.backgroundColorPreview.withOpacity(isSelected ? 0.25 : 0.15),
                            selectedColor: tag.displayColor,
                            checkmarkColor: tag.displayColor.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.9) : Colors.white,
                            shape: StadiumBorder(side: BorderSide(color: tag.borderColorPreview.withOpacity(isSelected ? 0.8 : 0.4), width: 1.2)),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        TextButton(
          child: const Text('Сбросить все'),
          onPressed: _clearFilters,
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: const Text('Применить'),
          onPressed: _applyFilters,
        ),
      ],
    );
  }
}