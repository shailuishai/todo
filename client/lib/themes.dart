// lib/themes.dart
import 'package:flutter/material.dart';

// Базовая цветовая схема для светлой темы (акцентный цвет будет добавлен позже)
const ColorScheme _lightColorSchemeBase = ColorScheme.light(
  // primary: будет заменен акцентным цветом,
  // onPrimary: будет рассчитан на основе яркости primary,
  background: Color(0xFFF5F5F5),
  onBackground: Color(0xFF333333),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF444444), // Основной цвет текста
  secondary: Color(0xFF505050), // Можно также сделать зависимым от акцента
  onSecondary: Colors.white,
  error: Color(0xFFFF5454),
  onError: Colors.white,
  brightness: Brightness.light,
  surfaceContainerHighest: Color(0xFFE0E0E0), // Для фона инпутов в светлой теме
);

// Базовая цветовая схема для темной темы (акцентный цвет будет добавлен позже)
const ColorScheme _darkColorSchemeBase = ColorScheme.dark(
  // primary: будет заменен акцентным цветом,
  // onPrimary: будет рассчитан на основе яркости primary,
  surface: Color(0xFF161616),       // Задний фон контейнеров
  background: Color(0xFF252525),    // Основной фон
  onSurface: Color(0xFFE0E0E0),     // Основной цвет текста (сделал светлее чем white70)
  secondary: Color(0xFF5457FF),    // Может быть акцентным, или отдельным
  error: Color(0xFFFF5454),
  onError: Colors.black,            // Для контраста с красной ошибкой
  brightness: Brightness.dark,
  surfaceContainerHighest: Color(0xFF393939), // Для фона инпутов в темной теме
);

ThemeData getLightTheme(Color accentColor) {
  final onPrimaryColor = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
      ? Colors.white
      : Colors.black;

  final colorScheme = _lightColorSchemeBase.copyWith(
    primary: accentColor,
    secondary: accentColor, // Используем акцентный цвет и для secondary
    onPrimary: onPrimaryColor,
  );

  return ThemeData(
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.background,
    canvasColor: const Color(0xFFF0F0F0), // Фон для DropdownButton в светлой теме
    dividerColor: const Color(0xFFCCCCCC),
    textTheme: _buildTextTheme(colorScheme.onSurface, accentColor, Brightness.light),
    elevatedButtonTheme: _buildElevatedButtonTheme(accentColor, onPrimaryColor),
    inputDecorationTheme: _buildInputDecorationTheme(colorScheme, false),
    brightness: Brightness.light,
    appBarTheme: AppBarTheme( // Добавим базовую настройку AppBar
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
  );
}

ThemeData getDarkTheme(Color accentColor) {
  final onPrimaryColor = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
      ? Colors.white
      : Colors.black;

  final colorScheme = _darkColorSchemeBase.copyWith(
    primary: accentColor,
    secondary: accentColor, // Используем акцентный цвет и для secondary
    onPrimary: onPrimaryColor,
  );

  return ThemeData(
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.background,
    canvasColor: const Color(0xFF2C2C2C), // Фон для DropdownButton в темной теме
    dividerColor: colorScheme.surfaceContainerHighest,
    textTheme: _buildTextTheme(colorScheme.onSurface, accentColor, Brightness.dark),
    elevatedButtonTheme: _buildElevatedButtonTheme(accentColor, onPrimaryColor),
    inputDecorationTheme: _buildInputDecorationTheme(colorScheme, true),
    brightness: Brightness.dark,
    appBarTheme: AppBarTheme( // Добавим базовую настройку AppBar
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
  );
}

// Общий метод для создания TextTheme
TextTheme _buildTextTheme(Color onSurfaceColor, Color accentColor, Brightness brightness) {
  // Получаем базовую типографику в зависимости от яркости.
  // Typography.material2021() предоставляет современные стили Material Design 3.
  // Если вы хотите стили Material Design 2, используйте Typography.material2018().
  final typography = Typography.material2021(
    platform: TargetPlatform.android, // или TargetPlatform.iOS, или null для адаптивной
    colorScheme: brightness == Brightness.light
        ? _lightColorSchemeBase.copyWith(onSurface: onSurfaceColor) // Передаем обновленный onSurface
        : _darkColorSchemeBase.copyWith(onSurface: onSurfaceColor),  // Передаем обновленный onSurface
  );

  // Теперь используем текстовые стили из этой типографики.
  // В Material 3, 'bodyLarge' и 'bodyMedium' часто являются основными.
  // 'titleLarge' для заголовков, 'labelLarge' для кнопок/меток.

  TextTheme baseTextTheme;
  if (brightness == Brightness.light) {
    baseTextTheme = typography.black; // Стили для светлой темы
  } else {
    baseTextTheme = typography.white; // Стили для темной темы
  }

  return baseTextTheme.copyWith(
    // Переопределяем или дополняем стили при необходимости
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: onSurfaceColor, // Уже должно быть установлено через typography, но для явности
      fontFamily: 'Inter',   // Явно указываем шрифт, если он отличается от дефолтного в Typography
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      color: onSurfaceColor.withOpacity(0.85),
      fontFamily: 'Inter',
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      fontSize: 16,
      color: onSurfaceColor.withOpacity(0.75),
      fontFamily: 'Inter',
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      color: onSurfaceColor,
      fontWeight: FontWeight.bold,
      fontFamily: 'Inter',
    ),
    // Стиль для описаний настроек (можем использовать titleMedium или bodyMedium с другими параметрами)
    titleMedium: baseTextTheme.titleMedium?.copyWith( // Или baseTextTheme.bodyMedium
      color: onSurfaceColor.withOpacity(0.8),
      fontWeight: FontWeight.w400,
      fontSize: 14,
      fontFamily: 'Inter',
    ),
    // Стиль для текста на кнопках Dropdown и других метках
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      fontSize: 16,
      color: onSurfaceColor,
    ),
  ).apply(fontFamily: 'Inter'); // Глобально применяем 'Inter', если он основной
}


ElevatedButtonThemeData _buildElevatedButtonTheme(Color backgroundColor, Color foregroundColor) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

InputDecorationTheme _buildInputDecorationTheme(ColorScheme colorScheme, bool isDark) {
  return InputDecorationTheme(
    filled: true,
    fillColor: isDark ? colorScheme.surfaceContainerHighest : const Color(0xFFEAEAEA), // Чуть светлее E0E0E0
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontFamily: 'Inter'),
    labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7), fontFamily: 'Inter'),
    // Можно добавить contentPadding, если нужно
    // contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
  );
}