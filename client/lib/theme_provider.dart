// lib/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_state.dart';
import 'themes.dart';

class ThemeProvider with ChangeNotifier {
  final AuthState _authState;

  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF5457FF);

  static const String _themeModeKey = 'app_theme_mode_v2';
  static const String _accentColorKey = 'app_accent_color_v2';

  ThemeProvider(this._authState) {
    _loadPreferences();
    _authState.addListener(_onAuthStateChanged);
  }

  void _onAuthStateChanged() {
    _loadPreferences();
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

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
    bool needsNotify = false;

    // Сначала загружаем из AuthState, если пользователь залогинен
    if (_authState.isLoggedIn && _authState.currentUser != null) {
      final userProfile = _authState.currentUser!;
      final themeFromServer = _stringToThemeMode(userProfile.theme);
      final accentFromServer = _stringToColor(userProfile.accentColor);

      if (_themeMode != themeFromServer) {
        _themeMode = themeFromServer;
        needsNotify = true;
      }
      if (_accentColor != accentFromServer) {
        _accentColor = accentFromServer;
        needsNotify = true;
      }
    } else { // Если не залогинен, грузим из SharedPreferences
      final themeModeIndex = prefs.getInt(_themeModeKey);
      if (themeModeIndex != null && themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length) {
        final localTheme = ThemeMode.values[themeModeIndex];
        if (_themeMode != localTheme) {
          _themeMode = localTheme;
          needsNotify = true;
        }
      }

      final accentColorValue = prefs.getInt(_accentColorKey);
      if (accentColorValue != null) {
        final localColor = Color(accentColorValue);
        if (_accentColor != localColor) {
          _accentColor = localColor;
          needsNotify = true;
        }
      }
    }

    if (needsNotify) {
      notifyListeners();
    }
  }

  Future<void> _saveLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeMode.index);
    await prefs.setInt(_accentColorKey, _accentColor.value);
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _saveLocalPreferences(); // Сохраняем локально для UI до ответа сервера
      notifyListeners();

      if (_authState.isLoggedIn) {
        _authState.patchUserProfile(theme: _themeModeToString(mode));
      }
    }
  }

  void setAccentColor(Color color) {
    if (_accentColor != color) {
      _accentColor = color;
      _saveLocalPreferences(); // Сохраняем локально для UI до ответа сервера
      notifyListeners();

      if (_authState.isLoggedIn) {
        _authState.patchUserProfile(accentColor: '#${color.value.toRadixString(16).substring(2).toUpperCase()}');
      }
    }
  }

  // --- Helper methods ---
  String _themeModeToString(ThemeMode mode) {
    switch(mode) {
      case ThemeMode.light: return 'light';
      case ThemeMode.dark: return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String? themeStr) {
    switch(themeStr) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Color _stringToColor(String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      try {
        final buffer = StringBuffer();
        if (colorStr.length == 6 || colorStr.length == 7) buffer.write('ff');
        buffer.write(colorStr.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (e) {
        // fallback to default
      }
    }
    return const Color(0xFF5457FF); // Default color
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }
}