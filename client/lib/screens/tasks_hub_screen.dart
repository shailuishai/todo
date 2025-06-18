// lib/screens/tasks_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routing/app_pages.dart';
import '../core/routing/app_route_path.dart';
import '../core/routing/app_router_delegate.dart';

class TasksHubScreen extends StatelessWidget {
  const TasksHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // <<< ИЗМЕНЕНИЕ: Оборачиваем весь экран в Scaffold для мобильной версии >>>
    // Это добавляет AppBar и обеспечивает правильную обработку SafeArea.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Задачи'),
        // Можете добавить actions, если нужно
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNavigationCard(
                  context: context,
                  icon: Icons.list_alt_rounded,
                  title: "Все задачи",
                  subtitle: "Задачи, созданные вами или назначенные вам",
                  onTap: () {
                    Provider.of<AppRouterDelegate>(context, listen: false)
                        .navigateTo(const HomeSubPath(AppRouteSegments.allTasks));
                  },
                ),
                const SizedBox(height: 16),
                _buildNavigationCard(
                  context: context,
                  icon: Icons.person_outline_rounded,
                  title: "Личные задачи",
                  subtitle: "Задачи, не привязанные к командам",
                  onTap: () {
                    Provider.of<AppRouterDelegate>(context, listen: false)
                        .navigateTo(const HomeSubPath(AppRouteSegments.personalTasks));
                  },
                ),
                const SizedBox(height: 16),
                _buildNavigationCard(
                  context: context,
                  icon: Icons.calendar_today_outlined,
                  title: "Календарь",
                  subtitle: "Просмотр задач с дедлайнами на календаре",
                  onTap: () {
                    Provider.of<AppRouterDelegate>(context, listen: false)
                        .navigateTo(const HomeSubPath(AppRouteSegments.calendar, showRightSidebar: false));
                  },
                ),
                const SizedBox(height: 16),
                _buildNavigationCard(
                  context: context,
                  icon: Icons.delete_outline_rounded,
                  title: "Корзина",
                  subtitle: "Просмотр и восстановление удаленных задач",
                  color: Theme.of(context).colorScheme.error,
                  onTap: () {
                    Provider.of<AppRouterDelegate>(context, listen: false)
                        .navigateTo(const HomeSubPath(AppRouteSegments.trash, showRightSidebar: false));
                  },
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavigationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.primary;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: effectiveColor.withOpacity(0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: effectiveColor.withOpacity(0.1),
        highlightColor: effectiveColor.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, size: 36, color: effectiveColor),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }
}