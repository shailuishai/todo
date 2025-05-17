// lib/widgets/app_logo.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart'; // Убедитесь, что этот путь правильный

class AppLogo extends StatelessWidget {
  // final bool isCollapsed; // Больше не нужен, будем получать анимированный размер
  final double currentSize; // Анимированный текущий размер логотипа
  final bool isActuallyCollapsedState; // Флаг для определения блюра и радиуса, а не размера

  // Константы размеров теперь могут быть здесь или передаваться
  static const double expandedLogoSize = 96.0;
  static const double collapsedLogoSize = 50.0;


  const AppLogo({
    Key? key,
    // required this.isCollapsed,
    required this.currentSize,
    required this.isActuallyCollapsedState, // Чтобы знать, какой блюр и радиус использовать
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // const double expandedLogoSize = 96.0; // Перемещены в статические константы или можно передавать
    // const double collapsedLogoSize = 50.0;
    const double blurSigma = 8.0;
    const double baseBorderRadius = 12.0;

    // currentSize теперь приходит как параметр

    // Радиус и блюр зависят от финального состояния коллапса, а не от промежуточного размера анимации
    final double currentBorderRadius = isActuallyCollapsedState
        ? baseBorderRadius * (collapsedLogoSize / expandedLogoSize) // Пропорциональный радиус
        : baseBorderRadius;

    final double currentBlurSigma = isActuallyCollapsedState ? blurSigma / 2.5 : blurSigma;

    Widget logoContent = Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(currentBorderRadius),
          child: SizedBox( // SizedBox для ImageFiltered нужен, чтобы он не влиял на размер Stack
            width: currentSize,
            height: currentSize,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: currentBlurSigma, sigmaY: currentBlurSigma),
              child: SvgPicture.asset(
                AppAssets.logo,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  theme.colorScheme.onSurface.withOpacity(0.05),
                  BlendMode.srcATop,
                ),
              ),
            ),
          ),
        ),
        SizedBox( // SizedBox для основного SVG
          width: currentSize,
          height: currentSize,
          child: SvgPicture.asset(
            AppAssets.logo,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );

    // Оборачиваем в SizedBox с анимированным currentSize, чтобы сам логотип менял размер
    return SizedBox(
      width: currentSize,
      height: currentSize,
      child: logoContent,
    );
  }
}