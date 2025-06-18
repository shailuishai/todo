// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/task_model.dart';
import '../task_provider.dart';
import '../theme_provider.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
import '../core/utils/responsive_utils.dart'; // <<< Добавлен импорт

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final ValueNotifier<List<Task>> _selectedEvents;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier([]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && _selectedDay != null) {
      final taskProvider = Provider.of<TaskProvider>(context);
      _selectedEvents.value = _getEventsForDay(_selectedDay!, taskProvider.tasksForGlobalView);
    }
  }

  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  Future<void> _refreshData() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    debugPrint("[CalendarScreen] Refreshing data...");
    return taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated, forceBackendCall: true).then((_) {
      if (mounted && _selectedDay != null) {
        _selectedEvents.value = _getEventsForDay(_selectedDay!, taskProvider.tasksForGlobalView);
      }
    });
  }

  List<Task> _getEventsForDay(DateTime day, List<Task> tasksToFilter) {
    return tasksToFilter.where((task) {
      return task.deadline != null && isSameDay(task.deadline!, day);
    }).toList();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      _selectedEvents.value = _getEventsForDay(selectedDay, taskProvider.tasksForGlobalView);
    }
  }

  void _navigateToTaskDetails(BuildContext context, Task task) {
    Provider.of<AppRouterDelegate>(context, listen: false)
        .navigateTo(TaskDetailPath(task.taskId));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final taskProvider = Provider.of<TaskProvider>(context);
    final theme = themeProvider.currentTheme;
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);

    final List<Task> tasksForCalendarEvents = taskProvider.tasksForGlobalView;

    Widget calendarContent;

    if (taskProvider.isLoadingList && tasksForCalendarEvents.isEmpty) {
      calendarContent = const Center(child: CircularProgressIndicator());
    } else if (taskProvider.error != null && tasksForCalendarEvents.isEmpty) {
      calendarContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  "Ошибка загрузки данных",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  taskProvider.error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Попробовать снова"),
                  onPressed: _refreshData,
                )
              ],
            ),
          )
      );
    } else {
      calendarContent = Column(
        children: [
          TableCalendar<Task>(
            locale: 'ru_RU',
            firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
            lastDay: DateTime.utc(DateTime.now().year + 2, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: _calendarFormat,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Месяц',
              CalendarFormat.twoWeeks: '2 недели',
              CalendarFormat.week: 'Неделя',
            },
            eventLoader: (day) => _getEventsForDay(day, tasksForCalendarEvents),
            startingDayOfWeek: StartingDayOfWeek.monday,
            daysOfWeekHeight: 28.0,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 1,
              markerSize: 5.0,
              defaultTextStyle: TextStyle(color: colorScheme.onSurface),
              weekendTextStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              outsideTextStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.3)),
            ),
            headerStyle: HeaderStyle(
              titleTextStyle: theme.textTheme.titleLarge!.copyWith(color: colorScheme.onSurface, fontSize: 18),
              formatButtonTextStyle: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 12.0),
              formatButtonDecoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.7),
                borderRadius: const BorderRadius.all(Radius.circular(8.0)),
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: colorScheme.onSurface),
              rightChevronIcon: Icon(Icons.chevron_right, color: colorScheme.onSurface),
              headerPadding: const EdgeInsets.symmetric(vertical: 8.0),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
              weekendStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 12),
            ),
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() { _calendarFormat = format; });
              }
            },
            onPageChanged: (focusedDay) {
              if(!isSameDay(_focusedDay, focusedDay)){
                setState(() {
                  _focusedDay = focusedDay;
                  if(_selectedDay != null) {
                    _selectedEvents.value = _getEventsForDay(_selectedDay!, tasksForCalendarEvents);
                  }
                });
              }
            },
          ),
          const SizedBox(height: 8.0),
          const Divider(height: 1),
          const SizedBox(height: 8.0),
          Expanded(
            child: ValueListenableBuilder<List<Task>>(
              valueListenable: _selectedEvents,
              builder: (context, value, _) {
                if (value.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _selectedDay != null
                            ? "Нет задач на ${DateFormat('dd MMMM yyyy', 'ru_RU').format(_selectedDay!)}"
                            : "Нет задач на выбранный период",
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                value.sort((a,b) => (a.deadline ?? DateTime(0)).compareTo(b.deadline ?? DateTime(0)));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final task = value[index];
                    return Card(
                      elevation: 1.0,
                      margin: const EdgeInsets.symmetric(vertical: 5.0),
                      color: task.isTeamTask
                          ? colorScheme.secondaryContainer.withOpacity(0.6)
                          : colorScheme.tertiaryContainer.withOpacity(0.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        leading: Icon(
                          task.isTeamTask ? Icons.group_work_outlined : Icons.person_outline,
                          color: task.isTeamTask
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onTertiaryContainer,
                          size: 26,
                        ),
                        title: Text(
                          task.title,
                          style: TextStyle(
                              color: task.isTeamTask
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onTertiaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 15
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: task.deadline != null
                            ? Text(
                          'Дедлайн: ${DateFormat('HH:mm', 'ru_RU').format(task.deadline!)}' + (task.isTeamTask && task.teamName != null ? ' (${task.teamName})' : ''),
                          style: TextStyle(
                              color: (task.isTeamTask
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onTertiaryContainer).withOpacity(0.85),
                              fontSize: 12.5
                          ),
                        )
                            : null,
                        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: (task.isTeamTask
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onTertiaryContainer).withOpacity(0.7)),
                        onTap: () {
                          _navigateToTaskDetails(context, task);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    Widget body = RefreshIndicator(
      onRefresh: _refreshData,
      child: isMobile ? calendarContent : Container(
        margin: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 8.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: calendarContent,
      ),
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Календарь"),
          leading: Provider.of<AppRouterDelegate>(context).canPop()
              ? BackButton(onPressed: () => Provider.of<AppRouterDelegate>(context, listen: false).popRoute())
              : null,
        ),
        // <<< ИЗМЕНЕНИЕ: Оборачиваем body в SafeArea >>>
        body: SafeArea(child: body),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // Для десктопа фон от HomePage
      body: body,
    );
  }
}