// lib/widgets/primary_button.dart
import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double height;
  final bool isLoading; // Для отображения индикатора загрузки

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.height = 43,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Определяем цвета, которые будут использоваться
    // Эти цвета специфичны для этой кнопки, как было в CustomFlatButton
    const Color buttonBackgroundColor = Color(0xFF333333);
    const Color buttonForegroundColor = Color(0xFF5457FF); // Для текста и индикатора

    final ButtonStyle effectiveButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: buttonBackgroundColor,
      foregroundColor: buttonForegroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      textStyle: const TextStyle( // Стиль текста для кнопки
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 14,
        height: 17 / 14,
      ),
      alignment: Alignment.center,
      elevation: 0,
      minimumSize: Size.fromHeight(height), // Для установки высоты
    );

    // Получаем цвет для индикатора из ButtonStyle.
    // effectiveButtonStyle.foregroundColor здесь MaterialStateProperty<Color?> (не null, т.к. мы его задали)
    // .resolve({}) вернет Color? (значение этого свойства для дефолтного состояния)
    // В качестве запасного значения используем тот же buttonForegroundColor, если resolve вдруг вернет null.
    final Color indicatorColor = effectiveButtonStyle.foregroundColor?.resolve({}) ?? buttonForegroundColor;

    return SizedBox(
      height: height,
      width: double.infinity, // Чтобы кнопка занимала всю доступную ширину
      child: ElevatedButton(
        style: effectiveButtonStyle,
        onPressed: isLoading ? null : onPressed, // Блокируем при загрузке
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
          ),
        )
            : Text(text),
      ),
    );
  }
}