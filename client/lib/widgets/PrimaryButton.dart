// lib/widgets/PrimaryButton.dart  (Убедись, что имя файла именно такое)
import 'package:flutter/material.dart';
import '../core/utils/responsive_utils.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed; // Может быть null, если isLoading = true
  final double desktopHeight;
  final bool isLoading;
  final ButtonStyle? style; // Возможность передать кастомный стиль поверх темы

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed, // Изменено: onPressed теперь может быть null напрямую
    this.desktopHeight = 43,
    this.isLoading = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final elevButtonStyle = theme.elevatedButtonTheme.style;

    final double currentHeight = ResponsiveUtil.isMobile(context) ? 48 : desktopHeight;

    final Color effectiveForegroundColor = isLoading
        ? elevButtonStyle?.foregroundColor?.resolve({MaterialState.disabled}) ?? colorScheme.onSurface.withOpacity(0.38)
        : elevButtonStyle?.foregroundColor?.resolve({}) ?? colorScheme.onPrimary;

    final ButtonStyle finalButtonStyle = (elevButtonStyle ?? const ButtonStyle())
        .merge(style)
        .copyWith(
      minimumSize: MaterialStateProperty.all(Size.fromHeight(currentHeight)),
    );

    return SizedBox(
      height: currentHeight,
      width: double.infinity,
      child: ElevatedButton(
        style: finalButtonStyle,
        onPressed: onPressed, // Передаем onPressed напрямую
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(effectiveForegroundColor),
          ),
        )
            : Text(text),
      ),
    );
  }
}