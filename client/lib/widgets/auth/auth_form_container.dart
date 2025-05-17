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

    // Адаптивная ширина и паддинги
    final containerWidth = screenWidth > 700 ? 620.0 : screenWidth * 0.9;
    final horizontalPadding = screenWidth > 700 ? 100.0 : 24.0;

    return Container(
      width: containerWidth,
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            // color: Colors.black.withOpacity(0.5), // Адаптируем
            color: theme.shadowColor.withOpacity(theme.brightness == Brightness.dark ? 0.5 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}