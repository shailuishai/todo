// lib/screens/calendar_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/task_model.dart';
import '../task_provider.dart';
import '../auth_state.dart';
import '../theme_provider.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final ValueNotifier<List<Task>> _selectedEvents;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  // RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOff; // Пока не используем выбор диапазона
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // DateTime? _rangeStart; // Пока не используем
  // DateTime? _rangeEnd; // Пока не используем

  // _cachedTasksForEvents больше не нужен, будем брать из taskProvider.tasksForGlobalView
  // List<Task> _cachedTasksForEvents = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier([]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);
        // Загружаем задачи для "глобального вида" (все назначенные или созданные пользователем)
        // Это обеспечит, что tasksForGlobalView будет содержать актуальные данные.
        debugPrint("[CalendarScreen] initState: Fetching tasks for global view.");
        taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated).then((_) {
          // После загрузки обновляем события для выбранного дня
          if (mounted && _selectedDay != null) {
            _selectedEvents.value = _getEventsForDay(_selectedDay!, taskProvider.tasksForGlobalView);
          }
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Этот метод может быть вызван, если TaskProvider изменился из-за внешних факторов.
    // Обновляем события, если _selectedDay установлен.
    if (mounted && _selectedDay != null) {
      final taskProvider = Provider.of<TaskProvider>(context); // listen: true
      _selectedEvents.value = _getEventsForDay(_selectedDay!, taskProvider.tasksForGlobalView);
      debugPrint("[CalendarScreen] didChangeDependencies: Refreshed events for day $_selectedDay. Count: ${_selectedEvents.value.length}");
    }
  }


  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  List<Task> _getEventsForDay(DateTime day, List<Task> tasksToFilter) {
    return tasksToFilter.where((task) {
      return task.deadline != null && isSameDay(task.deadline!, day);
    }).toList();
  }

  // _getEventsForRange пока не используется активно
  // List<Task> _getEventsForRange(DateTime start, DateTime end, List<Task> tasksToFilter) {
  //   final days = daysInRange(start, end);
  //   return [
  //     for (final d in days) ..._getEventsForDay(d, tasksToFilter),
  //   ];
  // }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        // _rangeStart = null; // Пока не используем
        // _rangeEnd = null;
        // _rangeSelectionMode = RangeSelectionMode.toggledOff;
      });
      _selectedEvents.value = _getEventsForDay(selectedDay, taskProvider.tasksForGlobalView);
    }
  }

  // _onRangeSelected пока не используется
  // void _onRangeSelected(DateTime? start, DateTime? end, DateTime focusedDay) { /* ... */ }

  void _navigateToTaskDetails(BuildContext context, Task task) {
    Provider.of<AppRouterDelegate>(context, listen: false)
        .navigateTo(TaskDetailPath(task.taskId));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final taskProvider = Provider.of<TaskProvider>(context); // listen: true
    final theme = themeProvider.currentTheme;
    final colorScheme = theme.colorScheme;

    final List<Task> tasksForCalendarEvents = taskProvider.tasksForGlobalView;

    if (taskProvider.isLoadingList && tasksForCalendarEvents.isEmpty && taskProvider.error == null) {
      // Показываем индикатор, только если идет загрузка И список для календаря еще пуст И нет ошибки
      // (чтобы избежать мигания индикатора, если данные уже есть, но идет фоновое обновление)
      return const Center(child: CircularProgressIndicator());
    }

    if (taskProvider.error != null && tasksForCalendarEvents.isEmpty) {
      return Center(
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
                  onPressed: () => taskProvider.fetchTasks(viewType: TaskListViewType.allAssignedOrCreated),
                )
              ],
            ),
          )
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        margin: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 16.0, left: 16.0), // Добавил left отступ
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
        child: Column(
          children: [
            TableCalendar<Task>(
              locale: 'ru_RU',
              firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
              lastDay: DateTime.utc(DateTime.now().year + 2, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              // rangeStartDay: _rangeStart, // Пока не используем
              // rangeEndDay: _rangeEnd,
              calendarFormat: _calendarFormat,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Месяц',
                CalendarFormat.twoWeeks: '2 недели',
                CalendarFormat.week: 'Неделя',
              },
              // rangeSelectionMode: _rangeSelectionMode, // Пока не используем
              eventLoader: (day) => _getEventsForDay(day, tasksForCalendarEvents), // Используем отфильтрованный список
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
              // onRangeSelected: _onRangeSelected, // Пока не используем
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                if(!isSameDay(_focusedDay, focusedDay)){
                  setState(() {
                    _focusedDay = focusedDay;
                    // При смене месяца, если день не выбран, можно сбросить/обновить _selectedEvents
                    if(_selectedDay == null /*|| !isSameMonth(_selectedDay, _focusedDay)*/ ){ // Убрал isSameMonth, чтобы не сбрасывать при переключении месяца
                      _selectedEvents.value = []; // или загружать для _focusedDay
                    } else if (_selectedDay != null) {
                      // Если день был выбран, обновляем события для него на новой странице (если он видим)
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
                  value.sort((a,b) => (a.deadline ?? DateTime(0)).compareTo(b.deadline ?? DateTime(0))); // Сортируем по времени дедлайна
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
        ),
      ),
    );
  }
}

// daysInRange и isSameDay (если еще не определены глобально)
// bool isSameDay(DateTime? a, DateTime? b) {
//   if (a == null || b == null) {
//     return false;
//   }
//   return a.year == b.year && a.month == b.month && a.day == b.day;
// }

// List<DateTime> daysInRange(DateTime first, DateTime last) {
//   final dayCount = last.difference(first).inDays + 1;
//   return List.generate(
//     dayCount,
//         (index) => DateTime.utc(first.year, first.month, first.day + index),
//   );
// }