// lib/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert'; // Больше не нужен здесь
import 'themes.dart';
// import 'models/task_model.dart'; // Больше не нужен здесь

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF5457FF);
  // List<TaskTag> _userTags = []; // УДАЛЕНО

  static const String _themeModeKey = 'app_theme_mode_v2';
  static const String _accentColorKey = 'app_accent_color_v2';
  // static const String _userTagsKey = 'app_user_tags_v1'; // УДАЛЕНО

  ThemeProvider() {
    _loadPreferences();
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  // List<TaskTag> get userTags => List.unmodifiable(_userTags); // УДАЛЕНО

  bool get isEffectivelyDark {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeData get currentTheme {
    return isEffectivelyDark ? getDarkTheme(_accentColor) : getLightTheme(_accentColor);
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final themeModeIndex = prefs.getInt(_themeModeKey);
    if (themeModeIndex != null && themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeModeIndex];
    }

    final accentColorValue = prefs.getInt(_accentColorKey);
    if (accentColorValue != null) {
      _accentColor = Color(accentColorValue);
    }

    // Загрузка тегов УДАЛЕНА отсюда

    notifyListeners();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeMode.index);
    await prefs.setInt(_accentColorKey, _accentColor.value);
    // Сохранение тегов УДАЛЕНО отсюда
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _savePreferences();
      notifyListeners();
    }
  }

  void setAccentColor(Color color) {
    if (_accentColor != color) {
      _accentColor = color;
      _savePreferences();
      notifyListeners();
    }
  }

// Методы для управления тегами УДАЛЕНЫ отсюда
}