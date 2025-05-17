// lib/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'themes.dart'; // Импортируем наш обновленный themes.dart

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // По умолчанию системная
  Color _accentColor = const Color(0xFF5457FF); // По умолчанию синий (Ультрамарин)

  // Ключи для SharedPreferences
  static const String _themeModeKey = 'app_theme_mode_v1'; // Изменил ключ на случай старых данных
  static const String _accentColorKey = 'app_accent_color_v1';

  ThemeProvider() {
    _loadPreferences();
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

  // Определяет, является ли текущая тема темной (с учетом системных настроек)
  bool get isEffectivelyDark {
    if (_themeMode == ThemeMode.system) {
      // WidgetsBinding.instance.window deprecated, use platformDispatcher
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  // Возвращает текущую тему на основе _themeMode и _accentColor
  ThemeData get currentTheme {
    if (isEffectivelyDark) {
      return getDarkTheme(_accentColor);
    } else {
      return getLightTheme(_accentColor);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Загрузка ThemeMode
    final themeModeIndex = prefs.getInt(_themeModeKey);
    if (themeModeIndex != null && themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeModeIndex];
    } else {
      _themeMode = ThemeMode.system; // Значение по умолчанию
    }

    // Загрузка AccentColor
    final accentColorValue = prefs.getInt(_accentColorKey);
    if (accentColorValue != null) {
      _accentColor = Color(accentColorValue);
    } else {
      _accentColor = const Color(0xFF5457FF); // Значение по умолчанию
    }
    notifyListeners(); // Уведомить подписчиков после загрузки
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeMode.index);
    await prefs.setInt(_accentColorKey, _accentColor.value);
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _savePreferences();
      notifyListeners();
    }
  }

  void setAccentColor(Color color) {
    // Проверяем, есть ли такой цвет в нашем списке доступных,
    // чтобы избежать сохранения произвольных цветов, если палитра не реализована.
    // Это необязательно, если вы доверяете источнику цвета.
    // final List<Color> availableColors = [const Color(0xFF5457FF), const Color(0xFFFF5454), const Color(0xFFE2FF54)];
    // if (_accentColor != color && availableColors.contains(color)) {
    if (_accentColor != color) { // Пока разрешаем любой цвет, если в будущем будет палитра
      _accentColor = color;
      _savePreferences();
      notifyListeners();
    }
  }
}