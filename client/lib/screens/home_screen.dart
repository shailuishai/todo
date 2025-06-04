// lib/screens/home_screen.dart
import 'package:client/core/utils/responsive_utils.dart';
import 'package:client/widgets/tasks/task_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_model.dart';
import '../team_provider.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/sidebar/right_sidebar.dart';
import 'settings_screen.dart';
import 'personal_tasks_kanban_screen.dart';
import 'teams_screen.dart';
import 'all_tasks_kanban_screen.dart';
import 'trash_screen.dart';
import 'calendar_screen.dart';
import 'team_detail_screen.dart';
import '../core/routing/app_pages.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
// import '../sidebar_state_provider.dart'; // Не нужен здесь напрямую

class HomePage extends StatefulWidget {
  final String initialSubRoute;
  final bool showRightSidebarInitially;
  final String? teamIdToShow;
  final String? taskIdToShow;

  const HomePage({
    super.key,
    required this.initialSubRoute,
    this.showRightSidebarInitially = true,
    this.teamIdToShow,
    this.taskIdToShow,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  Widget _getCurrentPageContent(BuildContext context) {
    final theme = Theme.of(context); // Получаем тему для стилизации
    final colorScheme = theme.colorScheme;

    if (widget.teamIdToShow != null) {
      // Оборачиваем TeamDetailScreen в стилизованный контейнер для десктопа
      Widget teamDetailContent = TeamDetailScreen(teamId: widget.teamIdToShow!);
      if (!ResponsiveUtil.isMobile(context)) { // Только для десктопа/планшета
        return Container(
          margin: const EdgeInsets.only(top: 16.0, right: 0, bottom: 16.0, left: 16.0), // Отступ слева, т.к. правый сайдбар будет справа
          decoration: BoxDecoration(
            color: colorScheme.surface, // Как в CalendarScreen, или surfaceContainer
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.07), // Немного другая тень
                blurRadius: 8.0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: teamDetailContent,
        );
      }
      return teamDetailContent; // Для мобильных возвращаем "чистый" экран
    }

    // if (widget.taskIdToShow != null) {
    //   return TaskDetailScreen(taskId: widget.taskIdToShow!); // TaskDetailScreen сам управляет своим Scaffold
    // }

    // Стандартные экраны
    Widget pageContent;
    switch (widget.initialSubRoute) {
      case AppRouteSegments.settings:
        pageContent = const SettingsScreen();
        break;
      case AppRouteSegments.allTasks:
        pageContent = const AllTasksKanbanScreen();
        break;
      case AppRouteSegments.personalTasks:
        pageContent = const PersonalTasksKanbanScreen();
        break;
      case AppRouteSegments.teams:
        pageContent = const TeamsScreen();
        break;
      case AppRouteSegments.trash:
        pageContent = const TrashScreen();
        break;
      case AppRouteSegments.calendar:
        pageContent = const CalendarScreen();
        break;
      default:
        pageContent = const AllTasksKanbanScreen();
    }
    // Для стандартных экранов, которые уже имеют свой Container с margin,
    // дополнительная обертка не нужна здесь (они сами себя стилизуют).
    return pageContent;
  }

  // ... (остальные методы _getActiveMenuIndex, _getPageTitleForAppBar, etc. без изменений)
  int _getActiveMenuIndex() {
    if (widget.teamIdToShow != null) {
      return 3;
    }
    if (widget.taskIdToShow != null && Provider.of<AppRouterDelegate>(context, listen:false).currentConfiguration is! TaskDetailPath) {
      return -1;
    }
    final subRouteSegment = widget.initialSubRoute;
    if (subRouteSegment.isEmpty || subRouteSegment == AppRouteSegments.allTasks) return 0;
    if (subRouteSegment == AppRouteSegments.personalTasks) return 1;
    if (subRouteSegment == AppRouteSegments.calendar) return 2;
    if (subRouteSegment == AppRouteSegments.teams) return 3;
    if (subRouteSegment == AppRouteSegments.settings) return 4;
    if (subRouteSegment == AppRouteSegments.trash) return 5;
    return 0;
  }

  String _getPageTitleForAppBar() {
    if (widget.teamIdToShow != null) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      return teamProvider.currentTeamDetail?.name ?? "Команда";
    }
    if (widget.taskIdToShow != null && Provider.of<AppRouterDelegate>(context, listen:false).currentConfiguration is! TaskDetailPath) {
      return "Детали задачи";
    }
    final subRouteSegment = widget.initialSubRoute;
    if (subRouteSegment == AppRouteSegments.settings) return "Настройки";
    if (subRouteSegment.isEmpty || subRouteSegment == AppRouteSegments.allTasks) return "Все задачи";
    if (subRouteSegment == AppRouteSegments.personalTasks) return "Личные задачи";
    if (subRouteSegment == AppRouteSegments.teams) return "Команды";
    if (subRouteSegment == AppRouteSegments.trash) return "Корзина";
    if (subRouteSegment == AppRouteSegments.calendar) return "Календарь";
    return "ChronosHub";
  }

  int _getActiveBottomNavIndex() {
    if (widget.teamIdToShow != null) {
      return 2;
    }
    final subRouteSegment = widget.initialSubRoute;
    if (subRouteSegment.isEmpty || subRouteSegment == AppRouteSegments.allTasks) return 0;
    if (subRouteSegment == AppRouteSegments.personalTasks) return 1;
    if (subRouteSegment == AppRouteSegments.teams) return 2;
    if (subRouteSegment == AppRouteSegments.settings) return 3;
    if (subRouteSegment == AppRouteSegments.trash || subRouteSegment == AppRouteSegments.calendar) return 0;
    return 0;
  }

  List<BottomNavigationBarItem> _buildBottomNavigationBarItems(BuildContext context) {
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.list_alt_rounded), label: "Все задачи"),
      BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: "Личные"),
      BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: "Команды"),
      BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: "Настройки"),
    ];
  }

  void _onBottomNavItemTapped(int index, AppRouterDelegate routerDelegate) {
    String targetSubRouteSegment;
    bool showRightSidebarForRoute = true;
    switch (index) {
      case 0: targetSubRouteSegment = AppRouteSegments.allTasks; break;
      case 1: targetSubRouteSegment = AppRouteSegments.personalTasks; break;
      case 2: targetSubRouteSegment = AppRouteSegments.teams; showRightSidebarForRoute = false; break;
      case 3: targetSubRouteSegment = AppRouteSegments.settings; showRightSidebarForRoute = false; break;
      default: targetSubRouteSegment = AppRouteSegments.allTasks;
    }
    routerDelegate.navigateTo(HomeSubPath(targetSubRouteSegment, showRightSidebar: showRightSidebarForRoute));
  }

  List<Widget> _getMobileAppBarActions(BuildContext context) {
    if (widget.teamIdToShow != null) {
      return [];
    }
    final currentSubRouteSegment = widget.initialSubRoute;
    final bool isSettingsPage = currentSubRouteSegment == AppRouteSegments.settings;
    final bool isTeamsListPage = currentSubRouteSegment == AppRouteSegments.teams;
    final bool isTrashPage = currentSubRouteSegment == AppRouteSegments.trash;
    final bool isCalendarPage = currentSubRouteSegment == AppRouteSegments.calendar;

    if (isSettingsPage || isTrashPage || isCalendarPage) return [];

    List<Widget> actions = [];
    if (!isTeamsListPage) {
      actions.addAll([
        IconButton(icon: const Icon(Icons.filter_list_rounded), tooltip: "Фильтры", onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Фильтры (в разработке)")));
        }),
        IconButton(icon: const Icon(Icons.sort_rounded), tooltip: "Сортировка", onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Сортировка (в разработке)")));
        }),
      ]);
    }
    return actions;
  }

  void _showCreateTaskDialog(BuildContext context) {
    showDialog<Task?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TaskEditDialog(
          onTaskSaved: (createdTask) {
            debugPrint("HomePage: Task created via dialog: ${createdTask.title}");
          },
        );
      },
    ).then((returnedTask) {
      if (returnedTask != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Задача "${returnedTask.title}" добавлена!')),
        );
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    final bool isMobile = ResponsiveUtil.isMobile(context);

    final Widget currentPageContent = _getCurrentPageContent(context);
    final int activeSidebarMenuIndex = _getActiveMenuIndex();

    bool shouldShowRightSidebar = false; // По умолчанию скрываем
    if (widget.teamIdToShow != null) { // Если открыты детали команды, правый сайдбар показывается (это будет контекстный)
      shouldShowRightSidebar = true;
    } else {
      // Для обычных под-экранов HomePage, используем значение из AppRouterDelegate
      final currentActualPath = routerDelegate.currentConfiguration;
      if (currentActualPath is HomeSubPath) {
        shouldShowRightSidebar = currentActualPath.showRightSidebar;
      }
    }

    if (isMobile) {
      Widget? mobileFab;
      if (widget.teamIdToShow == null && widget.taskIdToShow == null &&
          ![AppRouteSegments.settings, AppRouteSegments.teams, AppRouteSegments.trash, AppRouteSegments.calendar].contains(widget.initialSubRoute)) {
        mobileFab = FloatingActionButton(
          onPressed: () => _showCreateTaskDialog(context),
          tooltip: "Добавить задачу",
          child: const Icon(Icons.add_task_outlined),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(_getPageTitleForAppBar()),
          actions: _getMobileAppBarActions(context),
          leading: (routerDelegate.canPop() && (widget.taskIdToShow != null || widget.teamIdToShow != null))
              ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => routerDelegate.popRoute())
              : null,
        ),
        body: currentPageContent,
        bottomNavigationBar: (widget.teamIdToShow == null && widget.taskIdToShow == null)
            ? BottomNavigationBar(
          items: _buildBottomNavigationBarItems(context),
          currentIndex: _getActiveBottomNavIndex(),
          onTap: (index) => _onBottomNavItemTapped(index, routerDelegate),
        )
            : null,
        floatingActionButton: mobileFab,
      );

    } else { // Десктоп/планшет
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Sidebar(
              activeMenuIndex: activeSidebarMenuIndex,
            ),
            Expanded(
              child: Material(
                elevation: 0,
                color: theme.colorScheme.background,
                child: currentPageContent,
              ),
            ),
            if (shouldShowRightSidebar) const RightSidebar(),
          ],
        ),
      );
    }
  }
}