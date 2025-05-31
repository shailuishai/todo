// lib/widgets/kanban_board/kanban_board_widget.dart
import 'package:flutter/material.dart';
import '../../models/task_model.dart';
import 'kanban_column_widget.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, listEquals;

const double _baseColumnWidth = 290.0;
const double _minColumnWidth = 290.0;
const double _fixedSpaceBetweenColumns = 16.0;

class KanbanBoardWidget extends StatefulWidget {
  final List<Task> tasks; // Этот список уже должен быть отсортирован TaskProvider
  final Function(Task, KanbanColumnStatus) onTaskStatusChanged;
  final ValueChanged<Task>? onTaskDelete;
  final ValueChanged<Task>? onTaskEdit;

  const KanbanBoardWidget({
    Key? key,
    required this.tasks,
    required this.onTaskStatusChanged,
    this.onTaskDelete,
    this.onTaskEdit,
  }) : super(key: key);

  @override
  _KanbanBoardWidgetState createState() => _KanbanBoardWidgetState();
}

class _KanbanBoardWidgetState extends State<KanbanBoardWidget> {
  late Map<KanbanColumnStatus, List<Task>> _columnTasks;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    debugPrint("[KanbanBoardWidget] initState: Organizing tasks. Initial tasks count: ${widget.tasks.length}");
    _organizeTasks(widget.tasks); // Передаем актуальные задачи
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KanbanBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Проверяем, изменился ли сам объект списка tasks (ссылка) или его содержимое.
    // listEquals проверяет содержимое.
    // TaskProvider при изменении фильтров/сортировки должен возвращать НОВЫЙ экземпляр списка.
    if (!listEquals(oldWidget.tasks, widget.tasks) || oldWidget.tasks.length != widget.tasks.length) {
      debugPrint("[KanbanBoardWidget] didUpdateWidget: Tasks have changed. Reorganizing. Old count: ${oldWidget.tasks.length}, New count: ${widget.tasks.length}");
      _organizeTasks(widget.tasks); // Передаем актуальные задачи
    } else {
      debugPrint("[KanbanBoardWidget] didUpdateWidget: Tasks seem to be equal. No reorganization needed.");
    }
  }

  void _organizeTasks(List<Task> tasksToOrganize) { // Принимаем список задач
    debugPrint("[KanbanBoardWidget] _organizeTasks called. Organizing ${tasksToOrganize.length} tasks.");
    _columnTasks = {
      for (var status in KanbanColumnStatus.values) status: []
    };
    // Задачи в tasksToOrganize уже отсортированы TaskProvider.
    // Просто распределяем их по колонкам, сохраняя порядок.
    for (var task in tasksToOrganize.where((task) => !task.isDeleted)) {
      _columnTasks[task.status]?.add(task);
    }
    // УБИРАЕМ ЛОКАЛЬНУЮ СОРТИРОВКУ ВНУТРИ КОЛОНОК ЗДЕСЬ:
    // _columnTasks.forEach((status, taskList) {
    //   taskList.sort((a, b) {
    //     int priorityCompare = b.priority.index.compareTo(a.priority.index);
    //     if (priorityCompare != 0) return priorityCompare;
    //     return b.createdAt.compareTo(a.createdAt);
    //   });
    // });
    if (mounted) {
      setState(() {});
    }
  }

  void _handleLocalTaskStatusChange(Task task, KanbanColumnStatus newStatus) {
    final oldStatus = task.status;
    if (oldStatus == newStatus) return;

    // Вызываем onTaskStatusChanged, который в итоге вызовет TaskProvider.locallyUpdateTaskStatus.
    // TaskProvider обновит _allFetchedTasks, применит сортировку и вызовет notifyListeners.
    // Это приведет к перестроению KanbanBoardWidget с новым отсортированным списком widget.tasks,
    // и _organizeTasks будет вызван в didUpdateWidget.
    widget.onTaskStatusChanged(task, newStatus);

    // Старая логика локального изменения _columnTasks здесь больше не нужна,
    // так как TaskProvider становится единственным источником истины для порядка задач.
    // setState(() {
    //   _columnTasks[oldStatus]?.removeWhere((t) => t.taskId == task.taskId);
    //   final updatedTaskInstance = task.copyWith(status: newStatus, updatedAt: DateTime.now());
    //   _columnTasks[newStatus]?.add(updatedTaskInstance);
    //   // Сортировка здесь также должна использовать глобальные параметры, но лучше ее убрать,
    //   // полагаясь на порядок из widget.tasks
    // });
  }

  Widget _buildVerticalDivider(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 1.0,
      color: theme.colorScheme.outlineVariant.withOpacity(0.7),
    );
  }

  Widget _buildColumnSection(
      BuildContext context,
      KanbanColumnStatus status,
      double columnWidth,
      ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Берем задачи для колонки из уже распределенного _columnTasks
    final tasksInThisColumn = _columnTasks[status] ?? [];

    return SizedBox(
      width: columnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Text(
              "${status.title.toUpperCase()} (${tasksInThisColumn.length})",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
                letterSpacing: 0.5,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: KanbanColumnWidget(
              status: status,
              tasks: tasksInThisColumn, // Передаем уже отсортированные (относительно друг друга в этой колонке) задачи
              onTaskStatusChanged: _handleLocalTaskStatusChange, // Это для DragTarget
              onTaskDelete: widget.onTaskDelete,
              onTaskEdit: widget.onTaskEdit,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    debugPrint("[KanbanBoardWidget] build called. Total tasks from widget: ${widget.tasks.length}");

    final List<KanbanColumnStatus> statuses = KanbanColumnStatus.values;
    final int numberOfColumns = statuses.length;
    final int numberOfDividers = (numberOfColumns - 1).clamp(0, double.infinity).toInt();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
        borderRadius: BorderRadius.circular(16.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double availableWidth = constraints.maxWidth;
          double calculatedColumnWidth;
          bool enableScroll = false;

          final double totalDividersWidth = numberOfDividers * _fixedSpaceBetweenColumns;
          final double availableWidthForColumns = availableWidth - totalDividersWidth;
          double idealColumnWidth = (availableWidthForColumns / numberOfColumns).floorToDouble();

          idealColumnWidth = idealColumnWidth.clamp(_minColumnWidth, 400.0);

          if ((numberOfColumns * _minColumnWidth + totalDividersWidth) > availableWidth) {
            calculatedColumnWidth = _minColumnWidth;
            enableScroll = true;
          } else {
            calculatedColumnWidth = idealColumnWidth;
          }

          final totalContentWidth = (numberOfColumns * calculatedColumnWidth) + totalDividersWidth;

          if (!enableScroll && totalContentWidth < availableWidth) {
            double remainingSpace = availableWidth - totalContentWidth;
            double extraSpacePerColumn = (remainingSpace / numberOfColumns).floorToDouble();
            if (extraSpacePerColumn > 0) {
              calculatedColumnWidth += extraSpacePerColumn;
            }
          }

          List<Widget> rowChildren = [];
          for (int i = 0; i < numberOfColumns; i++) {
            rowChildren.add(
                _buildColumnSection(context, statuses[i], calculatedColumnWidth)
            );
            if (i < numberOfDividers) {
              rowChildren.add(
                  SizedBox(
                    width: _fixedSpaceBetweenColumns,
                    child: Center(child: _buildVerticalDivider(context)),
                  )
              );
            }
          }

          final finalTotalContentWidth = (numberOfColumns * calculatedColumnWidth) + totalDividersWidth;
          enableScroll = finalTotalContentWidth > availableWidth + 1.0;

          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: kIsWeb ? true : false,
            thickness: kIsWeb ? 8.0 : 4.0,
            radius: const Radius.circular(4.0),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: enableScroll
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowChildren,
              ),
            ),
          );
        },
      ),
    );
  }
}