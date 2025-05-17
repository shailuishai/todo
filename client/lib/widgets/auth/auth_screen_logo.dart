// lib/widgets/auth/auth_screen_logo.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart'; // Путь к ассетам

class AuthScreenLogo extends StatelessWidget {
  const AuthScreenLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double logoSize = 96.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: SvgPicture.asset(
                AppAssets.logo,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  theme.colorScheme.onSurface.withOpacity(0.05), // Мягкий цвет для размытия
                  BlendMode.srcATop,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: SvgPicture.asset(
            AppAssets.logo,
            fit: BoxFit.contain,
            // Опционально: менять цвет основного лого в зависимости от темы
            // colorFilter: ColorFilter.mode(
            //   theme.brightness == Brightness.dark ? Colors.white : Colors.black,
            //   BlendMode.srcATop,
            // ),
          ),
        ),
      ],
    );
  }
}