import 'package:ToDo/screens/tasks_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/utils/responsive_utils.dart';
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

// <<< ИЗМЕНЕНИЕ: Добавлен `with SingleTickerProviderStateMixin` для TabController >>>
class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // <<< НОВЫЙ КОД ДЛЯ МОБИЛЬНОЙ НАВИГАЦИИ >>>
  late int _mobilePageIndex;
  late final List<Widget> _mobilePages;

  @override
  void initState() {
    super.initState();
    _mobilePageIndex = _getInitialMobilePageIndex();
    // Определяем список страниц, которые будут в мобильной навигации
    _mobilePages = [
      const TasksHubScreen(),
      const TeamsScreen(),
      const SettingsScreen(),
    ];
  }

  // Определяем начальный индекс для BottomNavigationBar на основе роута
  int _getInitialMobilePageIndex() {
    final subRoute = widget.initialSubRoute;
    if (subRoute == AppRouteSegments.teams || widget.teamIdToShow != null) {
      return 1;
    }
    if (subRoute == AppRouteSegments.settings) {
      return 2;
    }
    // Все остальные связанные с задачами роуты ведут на хаб задач
    return 0;
  }

  // Обновляем индекс при изменении виджета (например, при навигации через URL)
  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = _getInitialMobilePageIndex();
    if (_mobilePageIndex != newIndex) {
      setState(() {
        _mobilePageIndex = newIndex;
      });
    }
  }
  // <<< КОНЕЦ НОВОГО КОДА >>>


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

  // <<< ИЗМЕНЕНИЕ: Метод больше не нужен, т.к. AppBar на мобильных не имеет заголовка >>>
  // String _getPageTitleForAppBar() { ... }

  // <<< ИЗМЕНЕНИЕ: Этот метод больше не нужен, логика перенесена в initState и didUpdateWidget >>>
  // int _getActiveBottomNavIndex() { ... }

  List<BottomNavigationBarItem> _buildBottomNavigationBarItems(BuildContext context) {
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.task_alt_rounded), label: "Задачи"),
      BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: "Команды"),
      BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: "Настройки"),
    ];
  }

  void _onBottomNavItemTapped(int index, AppRouterDelegate routerDelegate) {
    if (_mobilePageIndex == index) return;

    // <<< ИЗМЕНЕНИЕ: Навигация теперь ведёт на главные экраны-хабы, а не на под-страницы >>>
    setState(() {
      _mobilePageIndex = index;
    });

    // Навигацию через роутер можно оставить для синхронизации URL, если это нужно
    String targetRouteSegment;
    switch (index) {
      case 0: targetRouteSegment = AppRouteSegments.allTasks; break; // По умолчанию для "Задач"
      case 1: targetRouteSegment = AppRouteSegments.teams; break;
      case 2: targetRouteSegment = AppRouteSegments.settings; break;
      default: targetRouteSegment = AppRouteSegments.allTasks;
    }
    routerDelegate.navigateTo(HomeSubPath(targetRouteSegment, showRightSidebar: false));
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    final bool isMobile = ResponsiveUtil.isMobile(context);

    // <<< ИЗМЕНЕНИЕ: Основная логика билда теперь разделена на mobile и desktop >>>

    if (isMobile) {
      // Если на мобильном открыта детальная страница (команды или задачи),
      // она сама строит свой Scaffold с кнопкой "назад" и не нуждается в BottomNavigationBar.
      if (widget.teamIdToShow != null || widget.taskIdToShow != null) {
        return _getCurrentPageContent(context);
      }

      return Scaffold(
        appBar: AppBar(
          title: null, // Убираем заголовок
          automaticallyImplyLeading: false, // Убираем кнопку "назад" по умолчанию
          elevation: 1,
        ),
        body: IndexedStack(
          index: _mobilePageIndex,
          children: _mobilePages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: _buildBottomNavigationBarItems(context),
          currentIndex: _mobilePageIndex,
          onTap: (index) => _onBottomNavItemTapped(index, routerDelegate),
        ),
      );

    } else { // Десктоп/планшет
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