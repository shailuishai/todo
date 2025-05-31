// lib/widgets/sidebar/sidebar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_router_delegate.dart';
import '../../core/routing/app_route_path.dart';
import '../../core/routing/app_pages.dart';
import '../../sidebar_state_provider.dart'; // <<< ИМПОРТ
import './menu_item.dart';
import './sidebar_constants.dart';
import 'app_logo.dart';

class Sidebar extends StatefulWidget {
  final int activeMenuIndex;

  const Sidebar({
    Key? key,
    required this.activeMenuIndex,
  }) : super(key: key);

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
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
      _SidebarItemData(title: "Все задачи", icon: Icons.list_alt_rounded, routeSegment: AppRouteSegments.allTasks),
      _SidebarItemData(title: "Личные задачи", icon: Icons.person_outline_rounded, routeSegment: AppRouteSegments.personalTasks),
      _SidebarItemData(title: "Календарь", icon: Icons.calendar_today_outlined, routeSegment: AppRouteSegments.calendar, showRightSidebar: false), // <<< НОВЫЙ ПУНКТ
      _SidebarItemData(title: "Команды", icon: Icons.group_outlined, routeSegment: AppRouteSegments.teams),
    ];
    _bottomMenuItems = [
      _SidebarItemData(title: "Настройки", icon: Icons.settings_outlined, routeSegment: AppRouteSegments.settings, showRightSidebar: false),
      _SidebarItemData(title: "Корзина", icon: Icons.delete_outline_rounded, routeSegment: AppRouteSegments.trash, showRightSidebar: false), // Тоже без правого сайдбара
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final sidebarProvider = Provider.of<SidebarStateProvider>(context, listen: false);
        if (!sidebarProvider.isCollapsed) {
          _animationController.value = 1.0;
        } else {
          _animationController.value = 0.0;
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimations();

    final sidebarProvider = Provider.of<SidebarStateProvider>(context);
    if (sidebarProvider.isCollapsed) {
      if (_animationController.status != AnimationStatus.dismissed && _animationController.value != 0.0) {
        _animationController.reverse();
      }
    } else {
      if (_animationController.status != AnimationStatus.completed && _animationController.value != 1.0) {
        _animationController.forward();
      }
    }
  }


  void _updateAnimations() {
    double targetExpandedSidebarWidth;
    final mediaQueryData = MediaQuery.maybeOf(context);
    if (mediaQueryData != null) {
      final screenWidth = mediaQueryData.size.width;
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

  Widget _buildHeaderSection(
      ThemeData theme,
      double currentAnimatingSidebarWidth,
      double currentAnimatingLogoSize,
      bool isActuallyCollapsed,
      VoidCallback onToggleCollapse
      ) {
    final colorScheme = theme.colorScheme;
    Widget toggleButton = IconButton(
      icon: Icon(
        isActuallyCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
        semanticLabel: isActuallyCollapsed ? "Развернуть меню" : "Свернуть меню",
      ),
      tooltip: isActuallyCollapsed ? "Развернуть" : "Свернуть",
      onPressed: onToggleCollapse,
      color: colorScheme.onSurfaceVariant,
      splashRadius: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );

    final bool logoShouldUseCollapsedStyle = isActuallyCollapsed || currentAnimatingSidebarWidth < _minWidthForExpandedHeader;

    Widget logoWidget = AppLogo(
      key: ValueKey('app_logo_style_$logoShouldUseCollapsedStyle'),
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
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    final sidebarProvider = Provider.of<SidebarStateProvider>(context);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        final currentAnimatingSidebarWidth = _sidebarWidthAnimation.value;
        final currentAnimatingLogoSize = _logoSizeAnimation.value;

        final bool useExpandedHorizontalPadding = currentAnimatingSidebarWidth >
            (kCollapsedSidebarWidth + (kSidebarHorizontalPaddingExpanded - kSidebarHorizontalPaddingCollapsed) / 2);
        final double currentHorizontalPadding = useExpandedHorizontalPadding
            ? kSidebarHorizontalPaddingExpanded
            : kSidebarHorizontalPaddingCollapsed;

        return Container(
          width: currentAnimatingSidebarWidth,
          height: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: 16.0,
            horizontal: currentHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.background,
          ),
          child: Column(
            key: ValueKey<bool>(sidebarProvider.isCollapsed),
            crossAxisAlignment: (sidebarProvider.isCollapsed || !useExpandedHorizontalPadding)
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(
                  theme,
                  currentAnimatingSidebarWidth,
                  currentAnimatingLogoSize,
                  sidebarProvider.isCollapsed,
                  sidebarProvider.toggleCollapse
              ),
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
                        isCollapsed: sidebarProvider.isCollapsed,
                        currentContentWidthForMenuItem: currentAnimatingSidebarWidth - (2 * currentHorizontalPadding),
                        onTap: () {
                          routerDelegate.navigateTo(HomeSubPath(item.routeSegment, showRightSidebar: item.showRightSidebar));
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
                  final overallIndex = _menuItems.length + index; // <<< ИЗМЕНЕН РАСЧЕТ ИНДЕКСА
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: MenuItem(
                      title: item.title,
                      icon: item.icon,
                      isActive: widget.activeMenuIndex == overallIndex,
                      isCollapsed: sidebarProvider.isCollapsed,
                      currentContentWidthForMenuItem: currentAnimatingSidebarWidth - (2 * currentHorizontalPadding),
                      onTap: () {
                        routerDelegate.navigateTo(HomeSubPath(item.routeSegment, showRightSidebar: item.showRightSidebar));
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

class _SidebarItemData {
  final String title;
  final IconData icon;
  final String routeSegment;
  final bool showRightSidebar;

  _SidebarItemData({
    required this.title,
    required this.icon,
    required this.routeSegment,
    this.showRightSidebar = true,
  });
}