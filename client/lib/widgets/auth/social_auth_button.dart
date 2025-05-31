// lib/widgets/auth/social_auth_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SocialAuthButton extends StatelessWidget {
  final String assetPath;
  final String providerName;
  final VoidCallback? onPressed; // <<< ИЗМЕНЕНО НА NULLABLE

  const SocialAuthButton({
    super.key,
    required this.assetPath,
    required this.providerName,
    required this.onPressed, // <<< onPressed теперь может быть null
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDisabled = onPressed == null; // Проверяем, отключена ли кнопка

    return InkWell(
      onTap: onPressed, // Передаем как есть
      borderRadius: BorderRadius.circular(12),
      splashColor: isDisabled ? Colors.transparent : colorScheme.primary.withOpacity(0.1),
      highlightColor: isDisabled ? Colors.transparent : colorScheme.primary.withOpacity(0.05),
      child: Opacity( // Делаем кнопку полупрозрачной, если она отключена
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withOpacity(isDisabled ? 0.3 : 0.7)),
          ),
          child: Center(
            child: SvgPicture.asset(
              assetPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                isDisabled ? colorScheme.onSurfaceVariant.withOpacity(0.5) : colorScheme.onSurfaceVariant,
                BlendMode.srcIn,
              ),
              semanticsLabel: 'Войти через $providerName',
            ),
          ),
        ),
      ),
    );
  }
}