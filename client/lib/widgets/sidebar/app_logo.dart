// lib/widgets/sidebar/app_logo.dart
import 'dart:ui'; // Для ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart'; // Путь к ассетам

class AppLogo extends StatelessWidget {
  final double currentSize;
  final bool isActuallyCollapsedState;

  static const double expandedLogoSize = 96.0;
  static const double collapsedLogoSize = 50.0;

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

    final double currentBorderRadius = isActuallyCollapsedState
        ? _borderRadiusBase * (collapsedLogoSize / expandedLogoSize)
        : _borderRadiusBase;

    final double currentBlurSigma = isActuallyCollapsedState ? _blurSigmaBase / 2.0 : _blurSigmaBase;

    // Стек для наложения эффектов
    Widget logoContent = Stack(
      alignment: Alignment.center,
      children: [
        // 1. Фон с блюром. Он имеет тот же размер, что и основной виджет.
        SizedBox(
          width: currentSize,
          height: currentSize,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: currentBlurSigma, sigmaY: currentBlurSigma),
            child: SvgPicture.asset(
              AppAssets.logo,
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(
                colorScheme.onSurface.withOpacity(0.05),
                BlendMode.srcATop,
              ),
            ),
          ),
        ),
        // 2. Четкий логотип поверх блюра.
        SizedBox(
          width: currentSize,
          height: currentSize,
          child: SvgPicture.asset(
            AppAssets.logo,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );

    // Оборачиваем все в SizedBox для корректного размера и ClipRRect для скругления углов.
    // Теперь обрезаться будет уже готовый виджет с блюром, что даст правильный эффект.
    return SizedBox(
      width: currentSize,
      height: currentSize,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(currentBorderRadius),
        child: logoContent,
      ),
    );
  }
}