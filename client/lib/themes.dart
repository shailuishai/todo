// lib/themes.dart
import 'package:flutter/material.dart';

// Базовая цветовая схема для светлой темы
const ColorScheme _lightColorSchemeBase = ColorScheme.light(
  background: Color(0xFFF5F5F5), // Основной фон приложения
  onBackground: Color(0xFF1C1B1F), // Цвет текста и иконок на фоне background
  surface: Color(0xFFFFFFFF), // Цвет поверхностей компонентов (карточки, меню)
  onSurface: Color(0xFF1C1B1F), // Цвет текста и иконок на фоне surface
  surfaceVariant: Color(0xFFE7E0EC), // Альтернативный цвет поверхности, чуть темнее/светлее
  onSurfaceVariant: Color(0xFF49454F), // Цвет текста и иконок на surfaceVariant
  outline: Color(0xFF79747E), // Цвет границ, разделителей
  outlineVariant: Color(0xFFCAC4D0), // Более светлый/темный вариант outline
  shadow: Color(0xFF000000),
  inverseSurface: Color(0xFF313033), // Для элементов, которые должны контрастировать с surface
  onInverseSurface: Color(0xFFF4EFF4),
  inversePrimary: Color(0xFFD0BCFF), // Контрастный к primary (для текста на primary, если onPrimary не подходит)
  primaryContainer: Color(0xFFEADDFF), // Контейнер для primary-акцентных элементов
  onPrimaryContainer: Color(0xFF21005D),
  secondaryContainer: Color(0xFFE8DEF8), // Контейнер для secondary-акцентных элементов
  onSecondaryContainer: Color(0xFF1D192B),
  tertiary: Color(0xFF7D5260),
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFFFFD8E4),
  onTertiaryContainer: Color(0xFF31111D),
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surfaceTint: Colors.transparent, // Отключаем тонирование поверхности по умолчанию
  // primary, onPrimary, secondary, onSecondary будут добавлены
  brightness: Brightness.light,
  surfaceContainerHighest: Color(0xFFEAEAEA), // Для фона инпутов в светлой теме (специально)
  surfaceContainerLow: Color(0xFFF0F0F0), // Для фона DropdownButton в светлой теме (специально)
);

// Базовая цветовая схема для темной темы
const ColorScheme _darkColorSchemeBase = ColorScheme.dark(
  background: Color(0xFF252525),    // Основной фон приложения
  onBackground: Color(0xFFE6E1E5), // Цвет текста и иконок на фоне background
  surface: Color(0xFF161616),       // Цвет поверхностей компонентов (карточки, меню)
  onSurface: Color(0xFFE0E0E0),     // Цвет текста и иконок на фоне surface
  surfaceVariant: Color(0xFF49454F), // Альтернативный цвет поверхности
  onSurfaceVariant: Color(0xFFCAC4D0), // Цвет текста и иконок на surfaceVariant
  outline: Color(0xFF938F99),       // Цвет границ, разделителей
  outlineVariant: Color(0xFF49454F), // Более светлый/темный вариант outline
  shadow: Color(0xFF000000),
  inverseSurface: Color(0xFFE6E1E5),
  onInverseSurface: Color(0xFF313033),
  inversePrimary: Color(0xFF6750A4),
  primaryContainer: Color(0xFF4A4458),
  onPrimaryContainer: Color(0xFFEADDFF),
  secondaryContainer: Color(0xFF4A4458),
  onSecondaryContainer: Color(0xFFE8DEF8),
  tertiary: Color(0xFFEFB8C8),
  onTertiary: Color(0xFF492532),
  tertiaryContainer: Color(0xFF633B48),
  onTertiaryContainer: Color(0xFFFFD8E4),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surfaceTint: Colors.transparent, // Отключаем тонирование поверхности по умолчанию
  // primary, onPrimary, secondary, onSecondary будут добавлены
  brightness: Brightness.dark,
  surfaceContainerHighest: Color(0xFF393939), // Для фона инпутов в темной теме (специально)
  surfaceContainerLow: Color(0xFF2C2C2C), // Для фона DropdownButton в темной теме (специально)
);

ThemeData getLightTheme(Color accentColor) {
  final baseScheme = _lightColorSchemeBase;
  final onPrimaryColor = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
      ? Colors.white
      : Colors.black;

  final colorScheme = baseScheme.copyWith(
    primary: accentColor,
    onPrimary: onPrimaryColor,
    secondary: accentColor, // Используем акцентный цвет и для secondary (можно изменить)
    onSecondary: onPrimaryColor, // Соответственно
    surfaceTint: accentColor, // Для Material 3 эффектов, если используются
  );
  return _buildThemeData(colorScheme, Brightness.light, accentColor);
}

ThemeData getDarkTheme(Color accentColor) {
  final baseScheme = _darkColorSchemeBase;
  final onPrimaryColor = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final colorScheme = baseScheme.copyWith(
    primary: accentColor,
    onPrimary: onPrimaryColor,
    secondary: accentColor, // Используем акцентный цвет и для secondary (можно изменить)
    onSecondary: onPrimaryColor, // Соответственно
    surfaceTint: accentColor, // Для Material 3 эффектов, если используются
  );
  return _buildThemeData(colorScheme, Brightness.dark, accentColor);
}

ThemeData _buildThemeData(ColorScheme colorScheme, Brightness brightness, Color accentColor) {
  return ThemeData(
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.background,
    canvasColor: colorScheme.surfaceContainerLow, // Фон для DropdownButton и подобных
    dividerColor: colorScheme.outlineVariant,
    textTheme: _buildTextTheme(colorScheme, accentColor),
    elevatedButtonTheme: _buildElevatedButtonTheme(accentColor, colorScheme.onPrimary, colorScheme),
    inputDecorationTheme: _buildInputDecorationTheme(colorScheme),
    brightness: brightness,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface, // Или surfaceContainer для другого эффекта
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      surfaceTintColor: colorScheme.surfaceTint, // Для M3 эффекта при прокрутке
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colorScheme.surface, // Или surfaceContainer
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: colorScheme.onSurfaceVariant,
      elevation: 0, // Можно добавить, если нужен эффект поднятия
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
      unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogBackgroundColor: colorScheme.surfaceContainerLow,
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colorScheme.surfaceContainerLow,
      titleTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
      contentTextStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15, fontFamily: 'Inter'),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface, fontFamily: 'Inter'),
      actionTextColor: colorScheme.inversePrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
          if (states.contains(MaterialState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
          if (states.contains(MaterialState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.onSurface;
        }),
        side: MaterialStateProperty.all(BorderSide(color: colorScheme.outline.withOpacity(0.5))),
        padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
        textStyle: MaterialStateProperty.all(const TextStyle(fontFamily: 'Inter', fontSize: 13)),
        shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ),
    useMaterial3: true, // Включаем Material 3
  );
}

TextTheme _buildTextTheme(ColorScheme colorScheme, Color accentColor) {
  final typography = Typography.material2021(
    platform: TargetPlatform.android,
    colorScheme: colorScheme, // Передаем текущую colorScheme
  );

  // Используем базовые стили из типографии, которые уже учитывают цвет onSurface из colorScheme
  TextTheme baseTextTheme = colorScheme.brightness == Brightness.light ? typography.black : typography.white;

  return baseTextTheme.copyWith(
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      // color: colorScheme.onSurface, // Уже должно быть установлено
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      color: colorScheme.onSurface.withOpacity(0.85),
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      fontSize: 16,
      color: colorScheme.onSurface.withOpacity(0.75),
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      // color: colorScheme.onSurface, // Уже должно быть установлено
      fontWeight: FontWeight.bold,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      color: colorScheme.onSurface.withOpacity(0.8),
      fontWeight: FontWeight.w400,
      fontSize: 14,
    ),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 16,
      // color: colorScheme.onSurface, // Уже должно быть установлено для кнопок и т.д.
    ),
  ).apply(fontFamily: 'Inter');
}

ElevatedButtonThemeData _buildElevatedButtonTheme(Color backgroundColor, Color foregroundColor, ColorScheme colorScheme) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: backgroundColor, // Это акцентный цвет
      foregroundColor: foregroundColor, // Цвет текста/иконки на акцентном цвете
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Немного увеличил радиус для M3
      ),
      elevation: 2, // Небольшая тень для M3 стиля
      // minimumSize: const Size(64, 40), // M3 рекомендует мин. высоту 40
    ),
  );
}

InputDecorationTheme _buildInputDecorationTheme(ColorScheme colorScheme) {
  return InputDecorationTheme(
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest,
    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7), fontFamily: 'Inter'),
    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontFamily: 'Inter', fontWeight: FontWeight.w500),
    floatingLabelStyle: TextStyle(color: colorScheme.primary, fontFamily: 'Inter', fontWeight: FontWeight.w500), // Цвет метки при фокусе
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10), // Немного увеличил радиус
      borderSide: BorderSide(color: colorScheme.outline, width: 1.0),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.7), width: 1.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colorScheme.error, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colorScheme.error, width: 2.0),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}