// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/sidebar/right_sidebar.dart';
import 'settings_screen.dart';
import '../core/routing/app_pages.dart'; // Для AppRoutes
import '../core/routing/app_router_delegate.dart'; // Для AppRouterDelegate и AppRoutePath
import '../core/routing/app_route_path.dart'; // Для HomeSubPath

class HomePage extends StatefulWidget {
  final String initialSubRoute; // Например, AppRoutes.settings или AppRoutes.allTasks
  final bool showRightSidebar;

  const HomePage({
    super.key,
    required this.initialSubRoute,
    this.showRightSidebar = true, // По умолчанию правый сайдбар показывается
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // _activeMenuIndex больше не нужен здесь, он будет управляться через URL
  // или RouterDelegate. Sidebar будет вызывать навигацию.

  Widget _getCurrentPageContent(String subRoute) {
    // Удаляем /home/ из subRoute, если он там есть, для сравнения с константами AppRoutes
    final cleanSubRoute = subRoute.startsWith('/home/') ? subRoute.substring(6) : subRoute;

    // Сравниваем чистый subRoute с константами
    if (cleanSubRoute == AppRoutes.settings.split('/').last) { // 'settings'
      return const SettingsScreen(); // SettingsScreen сам по себе Scaffold
    } else if (cleanSubRoute == AppRoutes.allTasks.split('/').last) { // 'all-tasks'
      return _buildPlaceholderPage("Все задачи");
    } else if (cleanSubRoute == AppRoutes.personalTasks.split('/').last) { // 'personal-tasks'
      return _buildPlaceholderPage("Личные задачи");
    } else if (cleanSubRoute == AppRoutes.teams.split('/').last) { // 'teams'
      return _buildPlaceholderPage("Команды");
    } else if (cleanSubRoute == AppRoutes.trash.split('/').last) { // 'trash'
      return _buildPlaceholderPage("Корзина");
    }
    return _buildPlaceholderPage("Неизвестный раздел: $cleanSubRoute");
  }

  Widget _buildPlaceholderPage(String title) {
    // Placeholder теперь не должен быть Scaffold, так как HomePage - это Scaffold
    return Center(
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  // Определяем активный индекс для Sidebar на основе текущего subRoute
  int _getActiveMenuIndexFromSubRoute(String subRoute) {
    final cleanSubRoute = subRoute.startsWith('/home/') ? subRoute.substring(6) : subRoute;
    if (cleanSubRoute == AppRoutes.allTasks.split('/').last) return 0;
    if (cleanSubRoute == AppRoutes.personalTasks.split('/').last) return 1;
    if (cleanSubRoute == AppRoutes.teams.split('/').last) return 2;
    if (cleanSubRoute == AppRoutes.settings.split('/').last) return 3;
    if (cleanSubRoute == AppRoutes.trash.split('/').last) return 4;
    return 0; // По умолчанию
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    // Получаем текущий активный индекс для сайдбара
    // widget.initialSubRoute должен содержать только сам подмаршрут (например, 'settings')
    final activeMenuIndex = _getActiveMenuIndexFromSubRoute(widget.initialSubRoute);

    Widget mainContentArea = _getCurrentPageContent(widget.initialSubRoute);

    // Если это SettingsScreen, он уже Scaffold, так что не оборачиваем его снова.
    // Для других страниц (плейсхолдеров) — оборачиваем в нужную структуру.
    // ИЗМЕНЕНИЕ: SettingsScreen теперь должен быть частью основного контента, а не отдельным Scaffold
    if (widget.initialSubRoute.split('/').last != AppRoutes.settings.split('/').last) {
      mainContentArea = Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1), // Уменьшил интенсивность тени
              blurRadius: 8,
              offset: const Offset(0, 2), // Сместил тень немного вниз
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: mainContentArea, // Здесь будет _buildPlaceholderPage
      );
    }
    // Если это SettingsScreen, он уже имеет свой SingleChildScrollView и паддинги.
    // Мы просто вставляем его в Expanded.

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(
            activeMenuIndex: activeMenuIndex,
            onMenuItemTap: (index) {
              String targetSubRoute;
              bool showRightSidebar = true; // По умолчанию
              switch (index) {
                case 0:
                  targetSubRoute = AppRoutes.allTasks.split('/').last;
                  break;
                case 1:
                  targetSubRoute = AppRoutes.personalTasks.split('/').last;
                  break;
                case 2:
                  targetSubRoute = AppRoutes.teams.split('/').last;
                  break;
                case 3: // Настройки
                  targetSubRoute = AppRoutes.settings.split('/').last;
                  showRightSidebar = false; // Для настроек правый сайдбар не нужен
                  break;
                case 4:
                  targetSubRoute = AppRoutes.trash.split('/').last;
                  break;
                default:
                  targetSubRoute = AppRoutes.allTasks.split('/').last; // Фоллбэк
              }
              // Используем routerDelegate для навигации
              routerDelegate.navigateTo(HomeSubPath(targetSubRoute, showRightSidebar: showRightSidebar));
            },
          ),
          Expanded(
            // ИЗМЕНЕНИЕ: Контент настроек (SettingsScreen) должен быть здесь
            // и SettingsScreen не должен быть Scaffold, а должен возвращать Column/SingleChildScrollView
            child: mainContentArea,
          ),
          if (widget.showRightSidebar) // Показываем правый сайдбар только если нужно
            const RightSidebar(),
        ],
      ),
    );
  }
}