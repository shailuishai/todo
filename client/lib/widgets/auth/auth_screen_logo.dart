// lib/widgets/auth/auth_screen_logo.dart
import 'dart:ui'; // Для ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart'; // Путь к ассетам
import '../../core/utils/responsive_utils.dart'; // Для адаптивности

class AuthScreenLogo extends StatelessWidget {
  const AuthScreenLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Адаптивный размер логотипа
    final double logoSize = ResponsiveUtil.isMobile(context) ? 80.0 : 96.0;
    final double baseExpandedSize = 96.0; // Базовый размер, от которого считаем пропорции

    // Пропорциональный радиус и блюр
    final double borderRadius = 12.0 * (logoSize / baseExpandedSize);
    final double blurSigma = 8.0 * (logoSize / baseExpandedSize); // Блюр тоже можно сделать пропорциональным

    return Stack(
      alignment: Alignment.center,
      children: [
        // Размытый фон
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
        ),
        // Основной логотип
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: SvgPicture.asset(
            AppAssets.logo,
            fit: BoxFit.contain,
            // Если SVG монохромный и его цвет должен зависеть от темы:
            // colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
          ),
        ),
      ],
    );
  }
}