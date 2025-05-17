// lib/widgets/sidebar/sidebar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Для доступа к RouterDelegate
import '../../core/routing/app_router_delegate.dart'; // Для RouterDelegate
import '../../core/routing/app_route_path.dart'; // Для HomeSubPath
import '../../core/routing/app_pages.dart'; // Для AppRoutes
import './menu_item.dart';
import './sidebar_constants.dart';
import 'app_logo.dart';

class Sidebar extends StatefulWidget {
  final int activeMenuIndex; // Этот параметр все еще полезен для подсветки активного элемента
  final ValueChanged<int> onMenuItemTap; // Это можно оставить, если нужна дополнительная логика при тапе,
  // но основная навигация пойдет через RouterDelegate

  const Sidebar({
    Key? key,
    required this.activeMenuIndex,
    required this.onMenuItemTap, // Технически, onMenuItemTap теперь дублирует логику навигации
    // Можно его убрать и вызывать RouterDelegate.navigateTo напрямую
  }) : super(key: key);

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  // ... (initState, _animationController, _updateAnimations, _toggleCollapse, _buildHeaderSection, dispose остаются)
  bool _isCollapsed = false;
  late AnimationController _animationController;
  late Animation<double> _sidebarWidthAnimation;
  late Animation<double> _logoSizeAnimation;
  final Duration _animationDuration = const Duration(milliseconds: 250);
  final double _minWidthForExpandedHeader = 170.0;

  late final List<_SidebarItemData> _menuItems;
  late final List<_SidebarItemData> _bottomMenuItems;


  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    _menuItems = [
      _SidebarItemData(title: "Все задачи", icon: Icons.list_alt_rounded, route: AppRoutes.allTasks.split('/').last),
      _SidebarItemData(title: "Личные задачи", icon: Icons.person_outline_rounded, route: AppRoutes.personalTasks.split('/').last),
      _SidebarItemData(title: "Команды", icon: Icons.group_outlined, route: AppRoutes.teams.split('/').last),
    ];
    _bottomMenuItems = [
      _SidebarItemData(title: "Настройки", icon: Icons.settings_outlined, route: AppRoutes.settings.split('/').last, showRightSidebar: false),
      _SidebarItemData(title: "Корзина", icon: Icons.delete_outline_rounded, route: AppRoutes.trash.split('/').last),
    ];

    if (!_isCollapsed) {
      _animationController.value = 1.0;
    }
  }

  void _updateAnimations() {
    double targetExpandedSidebarWidth;
    if (mounted && context.findRenderObject() != null && MediaQuery.maybeOf(context) != null) {
      final screenWidth = MediaQuery.of(context).size.width;
      if (screenWidth < 600) targetExpandedSidebarWidth = kExpandedSidebarWidthMobile;
      else if (screenWidth < 1000) targetExpandedSidebarWidth = kExpandedSidebarWidthTablet;
      else targetExpandedSidebarWidth = kExpandedSidebarWidthDesktop;
    } else {
      targetExpandedSidebarWidth = kExpandedSidebarWidthDesktop;
    }

    _sidebarWidthAnimation = Tween<double>(
      begin: kCollapsedSidebarWidth,
      end: targetExpandedSidebarWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));

    _logoSizeAnimation = Tween<double>(
      begin: AppLogo.collapsedLogoSize,
      end: AppLogo.expandedLogoSize,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimations();
    if (_isCollapsed) {
      if (_animationController.status != AnimationStatus.dismissed && _animationController.value != 0.0) {
        _animationController.value = 0.0;
      }
    } else {
      if (_animationController.status != AnimationStatus.completed && _animationController.value != 1.0) {
        _animationController.value = 1.0;
      }
    }
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
      if (_isCollapsed) {
        _animationController.reverse();
      } else {
        if (mounted) _updateAnimations();
        _animationController.forward();
      }
    });
  }

  Widget _buildHeaderSection(
      ThemeData theme,
      double currentAnimatingSidebarWidth,
      double currentAnimatingLogoSize
      ) {
    Widget toggleButton = IconButton(
      icon: Icon(
        _isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
        semanticLabel: _isCollapsed ? "Развернуть меню" : "Свернуть меню",
      ),
      tooltip: _isCollapsed ? "Развернуть" : "Свернуть",
      onPressed: _toggleCollapse,
      color: theme.colorScheme.onSurfaceVariant,
      splashRadius: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );

    final bool logoShouldUseCollapsedStyle = _isCollapsed || currentAnimatingSidebarWidth < _minWidthForExpandedHeader;

    Widget logoWidget = AppLogo(
      key: ValueKey('app_logo_$logoShouldUseCollapsedStyle'),
      currentSize: currentAnimatingLogoSize,
      isActuallyCollapsedState: logoShouldUseCollapsedStyle,
    );

    if (logoShouldUseCollapsedStyle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logoWidget,
          const SizedBox(height: 12),
          toggleButton,
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logoWidget,
          toggleButton,
        ],
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Получаем RouterDelegate из Provider
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        final currentAnimatingSidebarWidth = _sidebarWidthAnimation.value;
        final currentAnimatingLogoSize = _logoSizeAnimation.value;

        final bool useExpandedHorizontalPadding = currentAnimatingSidebarWidth > (kCollapsedSidebarWidth + (kExpandedHorizontalPadding - kCollapsedHorizontalPadding) / 2 );
        final double currentHorizontalPadding = useExpandedHorizontalPadding ? kExpandedHorizontalPadding : kCollapsedHorizontalPadding;

        return Container(
          width: currentAnimatingSidebarWidth,
          height: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: 16.0,
            horizontal: currentHorizontalPadding,
          ),
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Column(
            key: ValueKey<bool>(_isCollapsed),
            crossAxisAlignment: (_isCollapsed || !useExpandedHorizontalPadding)
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(theme, currentAnimatingSidebarWidth, currentAnimatingLogoSize),
              const SizedBox(height: 24.0),
              Expanded(
                child: ListView.builder(
                  itemCount: _menuItems.length,
                  itemBuilder: (context, index) {
                    final item = _menuItems[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: MenuItem(
                        title: item.title,
                        icon: item.icon,
                        isActive: widget.activeMenuIndex == index,
                        isCollapsed: _isCollapsed,
                        currentContentWidthForMenuItem: currentAnimatingSidebarWidth - (2 * currentHorizontalPadding),
                        onTap: () {
                          // widget.onMenuItemTap(index); // Вызываем старый обработчик, если он нужен для чего-то еще
                          // ИЗМЕНЕНИЕ: Навигация через RouterDelegate
                          routerDelegate.navigateTo(HomeSubPath(item.route, showRightSidebar: item.showRightSidebar));
                        },
                      ),
                    );
                  },
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _bottomMenuItems.length,
                itemBuilder: (context, index) {
                  final item = _bottomMenuItems[index];
                  final overallIndex = _menuItems.length + index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: MenuItem(
                      title: item.title,
                      icon: item.icon,
                      isActive: widget.activeMenuIndex == overallIndex,
                      isCollapsed: _isCollapsed,
                      currentContentWidthForMenuItem: currentAnimatingSidebarWidth - (2 * currentHorizontalPadding),
                      onTap: () {
                        // widget.onMenuItemTap(overallIndex);
                        // ИЗМЕНЕНИЕ: Навигация через RouterDelegate
                        routerDelegate.navigateTo(HomeSubPath(item.route, showRightSidebar: item.showRightSidebar));
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

const double kExpandedHorizontalPadding = 16.0;
const double kCollapsedHorizontalPadding = 8.0;

class _SidebarItemData {
  final String title;
  final IconData icon;
  final String route; // Имя подмаршрута (например, 'settings', 'all-tasks')
  final bool showRightSidebar;

  _SidebarItemData({
    required this.title,
    required this.icon,
    required this.route,
    this.showRightSidebar = true, // По умолчанию правый сайдбар показывается
  });
}