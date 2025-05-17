// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart'; // Убедитесь, что путь корректен

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedTabIndex = 0;
  int _previousTabIndex = 0;

  final Map<Color, String> _availableAccentColors = {
    const Color(0xFF5457FF): "Ультрамарин",
    const Color(0xFFFF5454): "Коралл",
    const Color(0xFFE2FF54): "Лайм",
    Colors.green: "Зеленый", // Example: Added more colors
    Colors.orange: "Оранжевый",
    Colors.purple: "Фиолетовый",
    Colors.teal: "Бирюзовый",
  };

  final Map<ThemeMode, String> _themeOptions = {
    ThemeMode.light: "Светлая",
    ThemeMode.dark: "Тёмная",
    ThemeMode.system: "Системная",
  };

  void _onTabTapped(int index) {
    if (_selectedTabIndex != index) {
      setState(() {
        _previousTabIndex = _selectedTabIndex;
        _selectedTabIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 60.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopTabBar(context, colorScheme),
            const SizedBox(height: 48.0),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutQuint,
              switchOutCurve: Curves.easeInQuint,
              transitionBuilder: (Widget child, Animation<double> animation) {
                final bool goingRight = _selectedTabIndex > _previousTabIndex;
                final Offset beginOffset = Offset(goingRight ? 1.0 : -1.0, 0.0);
                final Offset endOffset = Offset.zero;

                final Animation<Offset> slideAnimation = Tween<Offset>(
                  begin: beginOffset,
                  end: endOffset,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuint));

                return SlideTransition(
                  position: slideAnimation,
                  child: FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                    child: child,
                  ),
                );
              },
              child: _buildSelectedTabContent(context, theme, colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    switch (_selectedTabIndex) {
      case 0:
        return KeyedSubtree(
            key: const ValueKey<int>(0),
            child: _buildAppearanceSettings(context, theme, colorScheme));
      case 1:
        return KeyedSubtree(
            key: const ValueKey<int>(1),
            child: _buildNotificationsSettings(context, theme, colorScheme));
      case 2:
        return KeyedSubtree(
            key: const ValueKey<int>(2),
            child: _buildProfileSettings(context, theme, colorScheme));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTopTabBar(BuildContext context, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTabItem(
          context,
          iconData: Icons.palette_outlined,
          label: "Внешний вид",
          index: 0,
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.onSurface.withOpacity(0.5),
          isProfile: false,
        ),
        const SizedBox(width: 60),
        _buildTabItem(
          context,
          iconData: Icons.notifications_none_outlined,
          label: "Уведомления",
          index: 1,
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.onSurface.withOpacity(0.5),
          isProfile: false,
        ),
        const SizedBox(width: 60),
        _buildTabItem(
          context,
          iconWidget: CircleAvatar(
            radius: 12.5,
            backgroundColor: _selectedTabIndex == 2 ? colorScheme.primary.withOpacity(0.2) : colorScheme.onSurface.withOpacity(0.3),
            child: CircleAvatar(
              radius: 11.5,
              backgroundColor: colorScheme.surfaceVariant ?? colorScheme.surface,
              child: Icon(Icons.person, size: 15, color: colorScheme.onSurfaceVariant ?? colorScheme.onSurface),
            ),
          ),
          label: "shailuishai",
          index: 2,
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.onSurface.withOpacity(0.5),
          isProfile: true,
        ),
      ],
    );
  }

  Widget _buildTabItem(
      BuildContext context, {
        IconData? iconData,
        Widget? iconWidget,
        required String label,
        required int index,
        required Color activeColor,
        required Color inactiveColor,
        required bool isProfile,
      }) {
    final bool isActive = _selectedTabIndex == index;
    final color = isActive ? activeColor : inactiveColor;

    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(8),
      hoverColor: color.withOpacity(0.1),
      splashColor: color.withOpacity(0.15),
      highlightColor: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget ?? Icon(iconData, size: 25, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 3,
              width: isActive && !isProfile ? 90.0 : 0,
              color: Colors.transparent, // This was likely for an underline, can be colorScheme.primary if needed
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSettings(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildSettingRow(
          context,
          theme: theme,
          title: "Тема",
          description: "Выберите светлую, темную или системную тему оформления.",
          control: _buildThemeControl(context, theme),
        ),
        const SizedBox(height: 32),
        _buildSettingRow(
          context,
          theme: theme,
          title: "Акцентный цвет",
          description: "Персонализируйте приложение, выбрав основной цвет элементов.",
          control: _buildAccentColorControl(context, theme), // MODIFIED
        ),
        const SizedBox(height: 32),
        _buildSettingRow(
          context,
          theme: theme,
          title: "Способ раскладки задач",
          description: "Выберите, как будут отображаться ваши задачи (в разработке).",
          control: _buildTaskLayoutControl(context, theme),
        ),
      ],
    );
  }

  Widget _buildNotificationsSettings(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: Text(
          "Настройки уведомлений (в разработке)",
          style: theme.textTheme.titleLarge,
        ),
      ),
    );
  }

  Widget _buildProfileSettings(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: Text(
          "Настройки профиля (в разработке)",
          style: theme.textTheme.titleLarge,
        ),
      ),
    );
  }

  Widget _buildSettingRow(
      BuildContext context, {
        required ThemeData theme,
        required String title,
        required String description,
        required Widget control,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 361,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
        control,
      ],
    );
  }

  Widget _buildThemeControl(BuildContext context, ThemeData theme) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return DropdownButtonHideUnderline(
      child: DropdownButton<ThemeMode>(
        value: themeProvider.themeMode,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 20,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
        dropdownColor: theme.canvasColor, // Use theme.canvasColor for dropdown background
        borderRadius: BorderRadius.circular(8),
        items: _themeOptions.entries.map((entry) {
          return DropdownMenuItem<ThemeMode>(
            value: entry.key,
            child: Text(
              entry.value,
              style: theme.textTheme.labelLarge,
            ),
          );
        }).toList(),
        onChanged: (ThemeMode? newMode) {
          if (newMode != null) {
            Provider.of<ThemeProvider>(context, listen: false).setThemeMode(newMode);
          }
        },
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  // MODIFIED: This now builds a clickable swatch that opens a dialog
  Widget _buildAccentColorControl(BuildContext context, ThemeData theme) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentColor = themeProvider.accentColor;

    return InkWell(
      onTap: () {
        _showAccentColorDialog(context, themeProvider, theme);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Add some padding for better tap area
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (theme.brightness == Brightness.light && currentColor.computeLuminance() > 0.85) ||
                      (theme.brightness == Brightness.dark && currentColor.computeLuminance() < 0.15)
                      ? theme.colorScheme.outlineVariant ?? theme.colorScheme.onSurface.withOpacity(0.2)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 16), // Space before the dropdown icon
            Icon(
              Icons.keyboard_arrow_down_rounded, // Still looks like a selector
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Method to show the accent color selection dialog
  void _showAccentColorDialog(BuildContext context, ThemeProvider themeProvider, ThemeData currentTheme) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use a separate context for the dialog
        return SimpleDialog(
          title: Text(
            'Выберите акцентный цвет',
            style: currentTheme.textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          backgroundColor: currentTheme.canvasColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          children: _availableAccentColors.entries.map((entry) {
            final color = entry.key;
            final name = entry.value;
            final bool isSelected = themeProvider.accentColor == color;

            return SimpleDialogOption(
              onPressed: () {
                themeProvider.setAccentColor(color);
                Navigator.of(dialogContext).pop(); // Close the dialog
              },
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (currentTheme.brightness == Brightness.light && color.computeLuminance() > 0.85) ||
                            (currentTheme.brightness == Brightness.dark && color.computeLuminance() < 0.15)
                            ? currentTheme.colorScheme.outlineVariant ?? currentTheme.colorScheme.onSurface.withOpacity(0.2)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                      Icons.check,
                      size: 16,
                      color: color.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.9),
                    )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    name,
                    style: currentTheme.textTheme.labelLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) const Spacer(), // Pushes check to the right if needed, but icon in container is better
                  if (isSelected)
                    Icon(
                      Icons.arrow_right_alt, // Optional: indicate selection
                      color: currentTheme.colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTaskLayoutControl(BuildContext context, ThemeData theme) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Выбор раскладки задач (в разработке)")),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Канбан-доска",
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(width: 16),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }
}