// lib/widgets/auth/social_auth_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SocialAuthButton extends StatelessWidget {
  final String assetPath;
  final String providerName;
  final VoidCallback onPressed;

  const SocialAuthButton({
    super.key,
    required this.assetPath,
    required this.providerName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          // color: const Color(0xFF333333), // Заменяем на цвет из темы
            color: theme.colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor.withOpacity(0.5))
        ),
        child: Center(
          child: SvgPicture.asset(
            assetPath,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              // const Color(0xFF505050), // Заменяем
              theme.colorScheme.onSurfaceVariant,
              BlendMode.srcATop,
            ),
            semanticsLabel: 'Войти через $providerName',
          ),
        ),
      ),
    );
  }
}