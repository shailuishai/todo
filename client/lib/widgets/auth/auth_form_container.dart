// lib/widgets/auth/auth_form_container.dart
import 'package:flutter/material.dart';

class AuthFormContainer extends StatelessWidget {
  final Widget child;

  const AuthFormContainer({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // Адаптивная ширина контейнера
    // Порог 700px для переключения на более широкую версию
    final bool isWideScreen = screenWidth > 700;
    final double containerWidth = isWideScreen ? 560.0 : screenWidth * 0.92; // Уменьшил немного макс ширину и увеличил % для мобильных

    // Адаптивные внутренние отступы
    final double horizontalPadding = isWideScreen ? 64.0 : 24.0; // Увеличил для десктопа
    final double verticalPadding = isWideScreen ? 32.0 : 24.0;

    return Container(
      width: containerWidth,
      padding: EdgeInsets.symmetric(
        vertical: verticalPadding,
        horizontal: horizontalPadding,
      ),
      decoration: BoxDecoration(
        // Цвет фона контейнера. surfaceContainerHigh обычно немного светлее/темнее, чем surface
        color: colorScheme.surfaceContainerHigh,
        // Граница контейнера
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(16), // Стандартный радиус для M3
        boxShadow: [ // Тень для контейнера
          BoxShadow(
            color: theme.shadowColor.withOpacity(colorScheme.brightness == Brightness.dark ? 0.20 : 0.10),
            blurRadius: 16, // Более мягкая тень
            offset: const Offset(0, 6), // Небольшое смещение тени
          ),
        ],
      ),
      child: child,
    );
  }
}