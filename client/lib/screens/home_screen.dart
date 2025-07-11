// lib/screens/home_screen.dart
import 'package:ToDo/core/utils/responsive_utils.dart';
import 'package:ToDo/screens/tasks_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late int _mobilePageIndex;
  // <<< ИЗМЕНЕНИЕ: Убираем инициализацию списка виджетов отсюда >>>

  @override
  void initState() {
    super.initState();
    _mobilePageIndex = _getInitialMobilePageIndex();
  }

  int _getInitialMobilePageIndex() {
    final subRoute = widget.initialSubRoute;
    if (subRoute == AppRouteSegments.teams || widget.teamIdToShow != null) {
      return 1;
    }
    if (subRoute == AppRouteSegments.settings) {
      return 2;
    }
    // <<< ИЗМЕНЕНИЕ: Любой другой subRoute (all-tasks, personal-tasks, calendar) теперь относится к вкладке 0 >>>
    return 0;
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSubRoute != oldWidget.initialSubRoute) {
      final newIndex = _getInitialMobilePageIndex();
      if (_mobilePageIndex != newIndex) {
        setState(() {
          _mobilePageIndex = newIndex;
        });
      }
    }
  }

  Widget _getCurrentPageContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (widget.teamIdToShow != null) {
      Widget teamDetailContent = TeamDetailScreen(teamId: widget.teamIdToShow!);
      if (!ResponsiveUtil.isMobile(context)) {
        return Container(
          margin: const EdgeInsets.only(top: 16.0, right: 0, bottom: 16.0, left: 16.0),
          decoration: BoxDecoration(
            color: colorScheme.surface,
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
          child: teamDetailContent,
        );
      }
      return teamDetailContent;
    }
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
      // <<< ИЗМЕНЕНИЕ: Если subRoute неизвестен, для десктопа показываем канбан, для мобильного - хаб (логика ниже) >>>
        pageContent = const AllTasksKanbanScreen();
    }
    return pageContent;
  }

  // <<< ИЗМЕНЕНИЕ: Новый метод для определения, какой экран показывать на первой вкладке мобильной навигации >>>
  Widget _getTasksPageForMobile() {
    switch (widget.initialSubRoute) {
      case AppRouteSegments.allTasks:
        return const AllTasksKanbanScreen();
      case AppRouteSegments.personalTasks:
        return const PersonalTasksKanbanScreen();
      case AppRouteSegments.calendar:
        return const CalendarScreen();
      case AppRouteSegments.trash:
        return const TrashScreen();
      default:
      // Показываем хаб, если мы не на конкретном экране задач
        return const TasksHubScreen();
    }
  }


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

  List<BottomNavigationBarItem> _buildBottomNavigationBarItems(BuildContext context) {
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.task_alt_rounded), label: "Задачи"),
      BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: "Команды"),
      BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: "Настройки"),
    ];
  }

  void _onBottomNavItemTapped(int index, AppRouterDelegate routerDelegate) {
    if (_mobilePageIndex == index) {
      // <<< ИЗМЕНЕНИЕ: Если мы уже на вкладке "Задачи", возвращаемся на хаб >>>
      if (index == 0) {
        routerDelegate.navigateTo(const HomeSubPath(AppRouteSegments.home));
      }
      return;
    }

    setState(() {
      _mobilePageIndex = index;
    });

    String targetRouteSegment;
    switch (index) {
      case 0:
      // <<< ИЗМЕНЕНИЕ: По умолчанию первая вкладка ведет на хаб >>>
        targetRouteSegment = AppRouteSegments.home; // Используем 'home' как сигнал для показа хаба
        break;
      case 1: targetRouteSegment = AppRouteSegments.teams; break;
      case 2: targetRouteSegment = AppRouteSegments.settings; break;
      default: targetRouteSegment = AppRouteSegments.home;
    }
    routerDelegate.navigateTo(HomeSubPath(targetRouteSegment, showRightSidebar: false));
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    final bool isMobile = ResponsiveUtil.isMobile(context);

    if (isMobile) {
      // Экраны с деталями (команды/задачи) обрабатываются отдельно и имеют свой собственный Scaffold
      if (widget.teamIdToShow != null || widget.taskIdToShow != null) {
        return _getCurrentPageContent(context);
      }

      // <<< ИЗМЕНЕНИЕ: Динамически создаем список страниц для IndexedStack >>>
      final List<Widget> mobilePages = [
        _getTasksPageForMobile(),
        const TeamsScreen(),
        const SettingsScreen(),
      ];

      return Scaffold(
        body: IndexedStack(
          index: _mobilePageIndex,
          children: mobilePages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: _buildBottomNavigationBarItems(context),
          currentIndex: _mobilePageIndex,
          onTap: (index) => _onBottomNavItemTapped(index, routerDelegate),
        ),
      );

    } else {
      // Десктопная логика остается без изменений
      final Widget currentPageContent = _getCurrentPageContent(context);
      final int activeSidebarMenuIndex = _getActiveMenuIndex();

      bool shouldShowRightSidebar = false;
      if (widget.teamIdToShow != null) {
        shouldShowRightSidebar = true;
      } else {
        final currentActualPath = routerDelegate.currentConfiguration;
        if (currentActualPath is HomeSubPath) {
          shouldShowRightSidebar = currentActualPath.showRightSidebar;
        }
      }

      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
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