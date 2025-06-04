// lib/core/utils/responsive_utils.dart
import 'package:flutter/material.dart';
// import 'dart:io' show Platform; // Если нужна проверка на конкретную платформу (Android/iOS)

class ResponsiveUtil {
  // Пороги для определения типа устройства (можно настроить)
  static const double _mobileBreakpoint = 650;  // Все что меньше - мобильное
  static const double _tabletBreakpoint = 1024; // От mobileBreakpoint до этого - планшет

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < _mobileBreakpoint;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= _mobileBreakpoint && width < _tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) {
    // Все что больше или равно _tabletBreakpoint - считаем десктопом
    // (или можно ввести отдельный _desktopBreakpoint, если нужна трехступенчатая градация)
    return MediaQuery.of(context).size.width >= _tabletBreakpoint;
  }

  // Пример адаптивного значения на основе типа устройства
  static ResponsiveValue<T extends Object>({
    required BuildContext context,
    required T mobile,
    T? tablet, // Планшетное значение может быть опциональным
    required T desktop,
  }) {
    if (isMobile(context)) {
      return mobile;
    } else if (isTablet(context)) {
      return tablet ?? desktop; // Если для планшета не задано, используем десктопное
    } else {
      return desktop;
    }
  }
}