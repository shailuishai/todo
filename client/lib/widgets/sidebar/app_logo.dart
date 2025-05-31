// lib/widgets/app_logo.dart
import 'dart:ui'; // Для ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart'; // Путь к ассетам

class AppLogo extends StatelessWidget {
  final double currentSize; // Анимированный текущий размер логотипа
  final bool isActuallyCollapsedState; // Флаг для определения стиля блюра и радиуса

  // Статические константы для размеров логотипа
  static const double expandedLogoSize = 96.0;
  static const double collapsedLogoSize = 50.0; // Минимальный размер для свернутого состояния

  // Константы для визуальных эффектов
  static const double _blurSigmaBase = 8.0;
  static const double _borderRadiusBase = 12.0;

  const AppLogo({
    Key? key,
    required this.currentSize,
    required this.isActuallyCollapsedState,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Радиус и сила блюра зависят от ФИНАЛЬНОГО состояния коллапса (isActuallyCollapsedState),
    // а не от промежуточного анимированного размера (currentSize).
    // Это позволяет блюру и радиусу изменяться скачком при достижении порогового значения,
    // в то время как сам размер (currentSize) анимируется плавно.

    // Пропорциональный радиус для свернутого состояния
    final double currentBorderRadius = isActuallyCollapsedState
        ? _borderRadiusBase * (collapsedLogoSize / expandedLogoSize)
        : _borderRadiusBase;

    // Уменьшаем блюр в свернутом состоянии для лучшей читаемости маленького лого
    final double currentBlurSigma = isActuallyCollapsedState ? _blurSigmaBase / 2.0 : _blurSigmaBase;

    // Основной SVG логотип
    Widget mainLogoSvg = SizedBox(
      width: currentSize,
      height: currentSize,
      child: SvgPicture.asset(
        AppAssets.logo,
        fit: BoxFit.contain,
        // Если SVG поддерживает изменение цвета через colorFilter, можно его использовать
        // colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
      ),
    );

    // Размытый фон для логотипа
    Widget blurredBackground = ClipRRect(
      borderRadius: BorderRadius.circular(currentBorderRadius),
      child: SizedBox(
        width: currentSize,
        height: currentSize,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: currentBlurSigma, sigmaY: currentBlurSigma),
          child: SvgPicture.asset(
            AppAssets.logo,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(
              colorScheme.onSurface.withOpacity(0.05), // Цвет для блюра из темы
              BlendMode.srcATop,
            ),
          ),
        ),
      ),
    );

    // Собираем логотип: размытый фон и основной SVG поверх
    Widget logoContent = Stack(
      alignment: Alignment.center,
      children: [
        blurredBackground,
        mainLogoSvg,
      ],
    );

    // Оборачиваем в SizedBox с анимированным currentSize, чтобы сам виджет логотипа
    // корректно занимал анимированное пространство.
    return SizedBox(
      width: currentSize,
      height: currentSize,
      child: logoContent,
    );
  }
}