// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_state.dart';
import '../services/api_service.dart';
import '../theme_provider.dart';
import '../tag_provider.dart';
import '../core/utils/responsive_utils.dart';
import '../models/task_model.dart';
import '../widgets/settings/profile_settings_tab.dart';
import '../widgets/tags/tag_list_item_widget.dart';
import '../widgets/tags/tag_edit_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final Map<Color, String> _availableAccentColors = {
    const Color(0xFF5457FF): "Ультрамарин",
    const Color(0xFFFF5454): "Коралл",
    const Color(0xFFE2FF54): "Лайм",
    Colors.green.shade600: "Зеленый",
    Colors.orange.shade700: "Оранжевый",
    Colors.purple.shade400: "Фиолетовый",
    Colors.teal.shade500: "Бирюзовый",
    Colors.pink.shade400: "Розовый",
    Colors.amber.shade700: "Янтарный",
  };

  final Map<ThemeMode, String> _themeOptions = {
    ThemeMode.system: "Системная",
    ThemeMode.light: "Светлая",
    ThemeMode.dark: "Тёмная",
  };

  final List<String> _tabLabels = ["Внешний вид", "Теги", "Уведомления", "Профиль"];
  final List<IconData> _tabIcons = [
    Icons.palette_outlined,
    Icons.label_outline_rounded,
    Icons.notifications_none_outlined,
    Icons.person_outline_rounded
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(_handleTabSelection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tagProvider = Provider.of<TagProvider>(context, listen: false);
        if (tagProvider.userTags.isEmpty && !tagProvider.isLoadingUserTags && tagProvider.error == null) {
          tagProvider.fetchUserTags();
        }
      }
    });
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildInitialsAvatarForTab(BuildContext context, UserProfile user, double radius) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String initials = "";
    String nameSource = user.login;

    if (nameSource.isNotEmpty) {
      final names = nameSource.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (names.isNotEmpty && names[0].isNotEmpty) {
        initials = names[0][0];
        if (names.length > 1 && names[1].isNotEmpty) {
          initials += names[1][0];
        } else if (names[0].length > 1) {
          initials = names[0].substring(0, initials.length == 1 ? 2 : 1).trim();
          if (initials.length > 2) initials = initials.substring(0,2);
        }
      }
    }

    initials = initials.toUpperCase();
    if (initials.isEmpty && user.email.isNotEmpty) {
      initials = user.email[0].toUpperCase();
    }
    if (initials.isEmpty) {
      initials = "?";
    }

    Color avatarBackgroundColor = colorScheme.primaryContainer;
    Color avatarTextColor = colorScheme.onPrimaryContainer;

    if (user.accentColor != null && user.accentColor!.isNotEmpty) {
      try {
        final userAccent = Color(int.parse(user.accentColor!.replaceFirst('#', '0xff')));
        avatarTextColor = ThemeData.estimateBrightnessForColor(userAccent) == Brightness.dark
            ? Colors.white.withOpacity(0.95)
            : Colors.black.withOpacity(0.8);
        avatarBackgroundColor = userAccent;
      } catch (_) { /* Используем дефолтные цвета */ }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: avatarBackgroundColor,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * (initials.length == 1 ? 0.8 : 0.6),
          fontWeight: FontWeight.bold,
          color: avatarTextColor,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<AuthState>(
        builder: (context, authState, _) {
          final UserProfile? currentUser = authState.currentUser;

          Widget settingsContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopTabBar(context, colorScheme, isMobile, currentUser),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    KeyedSubtree(key: const ValueKey<String>('appearance_tab'), child: _buildAppearanceSettings(context, theme, colorScheme, isMobile)),
                    KeyedSubtree(key: const ValueKey<String>('tags_tab'), child: _buildUserTagsSettings(context, theme, colorScheme, isMobile)),
                    KeyedSubtree(key: const ValueKey<String>('notifications_tab'), child: _buildNotificationsSettingsTab(context, authState)),
                    const KeyedSubtree(key: ValueKey<String>('profile_tab'), child: ProfileSettingsTab()),
                  ],
                ),
              ),
            ],
          );

          if (isMobile) {
            return settingsContent;
          }

          return Container(
            margin: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 16.0),
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 16.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.07),
                  blurRadius: 10.0,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: settingsContent,
          );
        }
    );
  }

  Widget _buildTopTabBar(BuildContext context, ColorScheme colorScheme, bool isMobile, UserProfile? currentUser) {
    const double iconTabContainerSizeMobile = 24.0;
    const double iconItselfSizeMobile = 22.0;
    const double avatarRadiusMobile = iconTabContainerSizeMobile / 2;

    if (isMobile) {
      return Material(
        color: colorScheme.surface,
        elevation: 1,
        child: TabBar(
          controller: _tabController,
          tabs: List.generate(_tabLabels.length, (index) {
            bool isProfileTab = index == _tabLabels.length - 1;
            Widget iconWidget;

            if (isProfileTab) {
              if (currentUser?.avatarUrl != null && currentUser!.avatarUrl!.isNotEmpty) {
                iconWidget = SizedBox(
                  width: iconTabContainerSizeMobile,
                  height: iconTabContainerSizeMobile,
                  child: CircleAvatar(
                    radius: avatarRadiusMobile,
                    backgroundImage: NetworkImage(currentUser.avatarUrl!),
                    backgroundColor: colorScheme.surfaceVariant,
                    onBackgroundImageError: (_, __) {},
                  ),
                );
              } else if (currentUser != null) {
                iconWidget = SizedBox(
                  width: iconTabContainerSizeMobile,
                  height: iconTabContainerSizeMobile,
                  child: _buildInitialsAvatarForTab(context, currentUser, avatarRadiusMobile),
                );
              } else {
                iconWidget = SizedBox(
                  width: iconTabContainerSizeMobile,
                  height: iconTabContainerSizeMobile,
                  child: CircleAvatar(
                    radius: avatarRadiusMobile,
                    backgroundColor: colorScheme.surfaceVariant,
                    child: Icon(_tabIcons[index], size: iconItselfSizeMobile * 0.75, color: colorScheme.onSurfaceVariant),
                  ),
                );
              }
            } else {
              iconWidget = SizedBox(
                width: iconTabContainerSizeMobile,
                height: iconTabContainerSizeMobile,
                child: Icon(_tabIcons[index], size: iconItselfSizeMobile),
              );
            }
            return Tab(
              height: 56,
              iconMargin: const EdgeInsets.only(bottom: 4),
              icon: iconWidget,
              child: Text(
                _tabLabels[index],
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.tab,
          splashBorderRadius: BorderRadius.circular(8),
        ),
      );
    }

    const double desktopIconContainerSize = 28.0;
    const double desktopIconItselfSize = 22.0;
    const double desktopAvatarRadius = desktopIconContainerSize / 2.2;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_tabLabels.length, (index) {
          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 32),
            child: _buildDesktopTabItem(
              context: context,
              defaultIconData: _tabIcons[index],
              label: _tabLabels[index],
              index: index,
              isActive: _tabController.index == index,
              isProfile: index == _tabLabels.length - 1,
              currentUserForAvatar: index == _tabLabels.length - 1 ? currentUser : null,
              onTap: () {
                if (_tabController.index != index) {
                  _tabController.animateTo(index);
                }
              },
              iconContainerSize: desktopIconContainerSize,
              iconItselfSize: desktopIconItselfSize,
              avatarRadius: desktopAvatarRadius,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDesktopTabItem({
    required BuildContext context,
    required IconData defaultIconData,
    required String label,
    required int index,
    required bool isActive,
    required double iconContainerSize,
    required double iconItselfSize,
    required double avatarRadius,
    bool isProfile = false,
    UserProfile? currentUserForAvatar,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color activeColor = colorScheme.primary;
    final Color inactiveColor = colorScheme.onSurfaceVariant;
    final Color currentColor = isActive ? activeColor : inactiveColor;
    final double fontSize = 14;

    Widget iconDisplay;
    if (isProfile) {
      if (currentUserForAvatar?.avatarUrl != null && currentUserForAvatar!.avatarUrl!.isNotEmpty) {
        iconDisplay = CircleAvatar(
          radius: avatarRadius,
          backgroundImage: NetworkImage(currentUserForAvatar.avatarUrl!),
          backgroundColor: colorScheme.surfaceVariant,
          onBackgroundImageError: (_, __) {},
        );
      } else if (currentUserForAvatar != null) {
        iconDisplay = _buildInitialsAvatarForTab(context, currentUserForAvatar, avatarRadius);
      } else {
        iconDisplay = CircleAvatar(
          radius: avatarRadius,
          backgroundColor: colorScheme.surfaceVariant,
          child: Icon(defaultIconData, size: iconItselfSize * 0.75, color: currentColor),
        );
      }
    } else {
      iconDisplay = Icon(defaultIconData, size: iconItselfSize, color: currentColor);
    }

    Widget iconContentHolder = SizedBox(
      width: iconContainerSize,
      height: iconContainerSize,
      child: isProfile
          ? CircleAvatar(
        radius: iconContainerSize / 2,
        backgroundColor: isActive && isProfile ? activeColor.withOpacity(0.12) : Colors.transparent,
        child: iconDisplay,
      )
          : Center(child: iconDisplay),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: activeColor.withOpacity(0.08),
      splashColor: activeColor.withOpacity(0.12),
      highlightColor: activeColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconContentHolder,
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: fontSize,
                color: currentColor,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: 2.5,
              width: isActive ? (fontSize * label.length * 0.6).clamp(30.0, 60.0) : 0,
              decoration: BoxDecoration(
                  color: isActive ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(1.5)
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSettings(BuildContext context, ThemeData theme, ColorScheme colorScheme, bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: isMobile ? 20 : 28,
        bottom: 16,
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
      ),
      child: Column(
        children: [
          _buildSettingRow(
            context: context, theme: theme, isMobile: isMobile,
            title: "Тема оформления",
            description: "Выберите светлую, темную или системную тему.",
            control: _buildThemeControl(context, theme, isMobile),
          ),
          _buildSettingRow(
            context: context, theme: theme, isMobile: isMobile,
            title: "Акцентный цвет",
            description: "Персонализируйте приложение, выбрав основной цвет.",
            control: _buildAccentColorControl(context, theme, isMobile),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeControl(BuildContext context, ThemeData theme, bool isMobile) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = theme.colorScheme;

    if (isMobile) {
      return SegmentedButton<ThemeMode>(
        segments: _themeOptions.entries.map((entry) {
          return ButtonSegment<ThemeMode>(
            value: entry.key,
            label: Text(entry.value),
          );
        }).toList(),
        selected: {themeProvider.themeMode},
        onSelectionChanged: (Set<ThemeMode> newSelection) {
          if (newSelection.isNotEmpty) {
            themeProvider.setThemeMode(newSelection.first);
          }
        },
      );
    }

    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: colorScheme.outline.withOpacity(0.7), width: 1),
        ),
        child: DropdownButton<ThemeMode>(
          value: themeProvider.themeMode,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
          dropdownColor: theme.canvasColor,
          borderRadius: BorderRadius.circular(10),
          items: _themeOptions.entries.map((entry) {
            return DropdownMenuItem<ThemeMode>(
              value: entry.key,
              child: Text(entry.value, style: theme.textTheme.bodyMedium),
            );
          }).toList(),
          onChanged: (ThemeMode? newMode) {
            if (newMode != null) {
              themeProvider.setThemeMode(newMode);
            }
          },
          style: theme.textTheme.bodyMedium,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildAccentColorControl(BuildContext context, ThemeData theme, bool isMobile) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentColor = themeProvider.accentColor;
    final colorScheme = theme.colorScheme;

    Widget displayContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isMobile ? 28 : 22,
          height: isMobile ? 28 : 22,
          decoration: BoxDecoration(
            color: currentColor,
            borderRadius: BorderRadius.circular(isMobile ? 8 : 6),
            border: Border.all(
              color: (currentColor.computeLuminance() > 0.85 && colorScheme.brightness == Brightness.light) ||
                  (currentColor.computeLuminance() < 0.15 && colorScheme.brightness == Brightness.dark)
                  ? colorScheme.outline.withOpacity(0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _availableAccentColors[currentColor] ?? "Выбранный цвет",
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
        ]
      ],
    );

    if (isMobile) {
      return ElevatedButton(
        onPressed: () => _showAccentColorDialog(context, themeProvider, theme, isMobile),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colorScheme.outline.withOpacity(0.7))
          ),
          elevation: 0,
        ),
        child: displayContent,
      );
    }

    return InkWell(
      onTap: () => _showAccentColorDialog(context, themeProvider, theme, isMobile),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: colorScheme.outline.withOpacity(0.7), width: 1),
        ),
        child: displayContent,
      ),
    );
  }

  void _showAccentColorDialog(BuildContext context, ThemeProvider themeProvider, ThemeData currentTheme, bool isMobile) {
    final colorScheme = currentTheme.colorScheme;

    Widget dialogContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
              top: isMobile ? 20 : 20,
              left: 24, right: 24,
              bottom: isMobile ? 16 : 16),
          child: Text(
            'Выберите акцентный цвет',
            style: currentTheme.textTheme.titleLarge?.copyWith(fontSize: isMobile ? 18 : 20),
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            shrinkWrap: true,
            children: _availableAccentColors.entries.map((entry) {
              final color = entry.key;
              final name = entry.value;
              final bool isSelected = themeProvider.accentColor.value == color.value;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    themeProvider.setAccentColor(color);
                    Navigator.of(context).pop();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (color.computeLuminance() > 0.85 && colorScheme.brightness == Brightness.light) ||
                                  (color.computeLuminance() < 0.15 && colorScheme.brightness == Brightness.dark)
                                  ? colorScheme.outline.withOpacity(0.7)
                                  : colorScheme.outline.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: isSelected
                              ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.8))
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Text(name, style: currentTheme.textTheme.bodyLarge?.copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? colorScheme.primary : colorScheme.onSurface))),
                        if (isSelected && !isMobile) Icon(Icons.arrow_forward_ios_rounded, color: colorScheme.primary.withOpacity(0.7), size: 16),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (isMobile)
          Padding(
            padding: const EdgeInsets.all(16.0).copyWith(top: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("ЗАКРЫТЬ"),
            ),
          )
      ],
    );

    if (isMobile) {
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (BuildContext dialogContext) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(dialogContext).viewInsets.bottom + 8,
                top: 8,
              ),
              child: dialogContent,
            );
          });
    } else {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
                child: dialogContent,
              )
          );
        },
      );
    }
  }

  // --- Методы для Тегов (остаются без изменений) ---
  Widget _buildUserTagsSettings(BuildContext context, ThemeData theme, ColorScheme colorScheme, bool isMobile) {
    // ... этот метод не меняется, оставляем как был
    final tagProvider = Provider.of<TagProvider>(context);
    final List<ApiTag> currentTags = tagProvider.userTags;

    if (tagProvider.isLoadingUserTags && currentTags.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tagProvider.error != null && currentTags.isEmpty && !tagProvider.isLoadingUserTags) {
      return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text("Ошибка загрузки тегов", style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(tagProvider.error!, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Попробовать снова"),
                  onPressed: () => tagProvider.fetchUserTags(),
                )
              ],
            ),
          )
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0).copyWith(
        top: isMobile ? 20 : 28, // Разные верхние отступы для мобильных и десктопа
        left: isMobile ? 16 : 32,
        right: isMobile ? 16 : 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Личные теги",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: isMobile ? 20 : 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(isMobile ? "Добавить" : "Добавить тег"),
                onPressed: () => _displayTagEditDialog(context, isTeamTag: false, tagProvider: tagProvider),
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12: 16, vertical: isMobile? 10: 12)
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (currentTags.isEmpty && !tagProvider.isLoadingUserTags)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.label_off_outlined, size: isMobile ? 48 : 64, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                    const SizedBox(height: 20),
                    Text(
                      "У вас пока нет личных тегов.\nНажмите 'Добавить тег', чтобы создать первый.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else if (currentTags.isNotEmpty)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currentTags.length,
              itemBuilder: (context, index) {
                final tag = currentTags[index];
                return TagListItemWidget(
                  tag: tag,
                  onEdit: () => _displayTagEditDialog(context, isTeamTag: false, tagToEdit: tag, tagProvider: tagProvider),
                  onDelete: () => _confirmDeleteUserTag(context, tag, tagProvider),
                );
              },
              separatorBuilder: (context, index) => Divider(
                color: colorScheme.outlineVariant.withOpacity(isMobile ? 0.3 : 0.4),
                height: isMobile ? 16 : 20,
                thickness: 0.8,
              ),
            ),
        ],
      ),
    );
  }
  void _displayTagEditDialog(BuildContext context, {
    required bool isTeamTag,
    String? teamId,
    ApiTag? tagToEdit,
    required TagProvider tagProvider,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return TagEditDialog(
          isTeamTag: isTeamTag,
          teamId: teamId,
          tagToEdit: tagToEdit,
          onSave: (String name, String colorHex, {int? tagId}) async {
            bool success;
            String actionMessage;

            if (tagToEdit == null) {
              actionMessage = "Личный тег '$name' создан";
              success = await tagProvider.createUserTag(name: name, colorHex: colorHex);
            } else {
              actionMessage = "Личный тег '${tagToEdit.name}' обновлен";
              success = await tagProvider.updateUserTag(tagId ?? tagToEdit.id, name: name, colorHex: colorHex);
            }

            if (mounted) {
              final scaffoldContext = dialogContext.mounted ? dialogContext : context;
              if (success) {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(SnackBar(content: Text(actionMessage)));
              } else {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(content: Text(tagProvider.error ?? 'Не удалось сохранить тег'), backgroundColor: Colors.red),
                );
                if(tagProvider.error != null) tagProvider.clearError();
              }
            }
          },
        );
      },
    );
  }
  void _confirmDeleteUserTag(BuildContext context, ApiTag tag, TagProvider tagProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Удалить личный тег?'),
          content: RichText(
            text: TextSpan(
                style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: "Вы уверены, что хотите удалить тег \""),
                  TextSpan(
                      text: tag.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: tag.displayColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                          backgroundColor: tag.displayColor.withOpacity(0.3)
                      )
                  ),
                  const TextSpan(text: "\"?\nЭто действие нельзя будет отменить."),
                ]
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text('Удалить', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    ).then((confirmed) async {
      if (confirmed == true && mounted) {
        bool success = await tagProvider.deleteUserTag(tag.id);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Тег "${tag.name}" удален.')),
            );
          } else if (tagProvider.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tagProvider.error!), backgroundColor: Colors.red),
            );
            tagProvider.clearError();
          }
        }
      }
    });
  }

  // --- Новая реализация вкладки уведомлений ---
  Widget _buildNotificationsSettingsTab(BuildContext context, AuthState authState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);
    final currentUser = authState.currentUser;

    if (currentUser == null) {
      return const Center(child: Text("Загрузка настроек..."));
    }

    // Helper для ToggleButtons
    List<bool> getSelection(String currentValue, List<String> options) {
      return options.map((option) => option == currentValue).toList();
    }

    Widget buildSectionTitle(String title) {
      return Padding(
        padding: EdgeInsets.only(
          top: isMobile ? 20 : 28, bottom: isMobile ? 10 : 12,
          left: isMobile ? 16 : 0, right: isMobile ? 16 : 0,
        ),
        child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: isMobile ? 18 : 20, color: colorScheme.primary)),
      );
    }

    Widget buildToggleSetting(String title, String subtitle, String currentValue, List<String> options, List<String> labels, Function(String) onSelect) {
      double minWidthButton = (MediaQuery.of(context).size.width - (isMobile ? 32 : 48) - 32 - (labels.length - 1) * 1 - 40) / labels.length;
      if (!isMobile) minWidthButton = ((MediaQuery.of(context).size.width * 0.4).clamp(280, 420) - 32 - (labels.length - 1) * 1) / labels.length;

      return Card(
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 0, vertical: 6.0),
        elevation: isMobile ? 1.5 : 1.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Center(
                child: ToggleButtons(
                  isSelected: getSelection(currentValue, options),
                  onPressed: (int index) => onSelect(options[index]),
                  borderRadius: BorderRadius.circular(8),
                  constraints: BoxConstraints(minHeight: 38.0, minWidth: minWidthButton.clamp(60, 200)),
                  children: labels.map((label) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Text(label, style: TextStyle(fontSize: isMobile ? 11.5 : 12.5), textAlign: TextAlign.center),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSwitchSetting(String title, String subtitle, bool value, Function(bool) onChanged) {
      return Card(
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 0, vertical: 6.0),
        elevation: isMobile ? 1.5 : 1.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.only(left: 16.0, right: 10.0, top: 8.0, bottom: 8.0),
          title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          value: value,
          onChanged: onChanged,
          activeColor: colorScheme.primary,
          dense: isMobile,
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: isMobile ? null : const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: EdgeInsets.only(
            bottom: 24.0,
            left: isMobile ? 0 : 24.0,
            right: isMobile ? 0 : 24.0,
          ),
          children: <Widget>[
            buildSectionTitle("Каналы уведомлений"),
            buildToggleSetting(
                "Email-уведомления",
                "Получать сводку и важные оповещения на почту.",
                currentUser.emailNotificationsLevel,
                ['all', 'important', 'none'],
                ["Всегда", "Только важные", "Никогда"],
                    (newValue) => authState.patchUserProfile(emailNotificationsLevel: newValue)
            ),
            buildToggleSetting(
                "Push-уведомления о задачах",
                "Мгновенные оповещения на ваши устройства.",
                currentUser.pushNotificationsTasksLevel,
                ['all', 'my_tasks', 'none'],
                ["Все", "Мои задачи", "Выключены"],
                    (newValue) => authState.patchUserProfile(pushNotificationsTasksLevel: newValue)
            ),

            buildSectionTitle("Уведомления о событиях"),
            buildSwitchSetting(
                "Упоминания в чатах команд",
                "Когда вас цитируют в командном чате.",
                currentUser.pushNotificationsChatMentions,
                    (newValue) => authState.patchUserProfile(pushNotificationsChatMentions: newValue)
            ),

            buildSectionTitle("Напоминания"),
            buildSwitchSetting(
                "Напоминания о дедлайнах задач",
                "Получать напоминания о задачах с приближающимся сроком.",
                currentUser.taskDeadlineRemindersEnabled,
                    (newValue) => authState.patchUserProfile(taskDeadlineRemindersEnabled: newValue)
            ),
            if (currentUser.taskDeadlineRemindersEnabled)
              buildToggleSetting(
                  "Время напоминания о дедлайне",
                  "За сколько времени до срока присылать напоминание.",
                  currentUser.taskDeadlineReminderTimePreference,
                  ['one_hour', 'one_day', 'two_days'],
                  ["За час", "За день", "За 2 дня"],
                      (newValue) => authState.patchUserProfile(taskDeadlineReminderTimePreference: newValue)
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String description,
    required Widget control,
    required bool isMobile,
    bool isLast = false,
  }) {
    final colorScheme = theme.colorScheme;
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 14)),
            ),
            SizedBox(
              width: double.infinity,
              child: control,
            ),
            if (!isLast) ...[
              const SizedBox(height: 20),
              Divider(thickness: 1, color: theme.dividerColor.withOpacity(0.5)),
            ] else ... [
              const SizedBox(height: 8),
            ]
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: control)
          ),
        ],
      ),
    );
  }
}