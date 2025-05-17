// right_sidebar.dart
import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';

// Figma Style Constants
const Color _figmaBorderColor = Color(0xFF393939); // Также используется для разделителя
const Color _figmaIconColor = Color(0xFFFCFCFC); // Цвет иконок
const double _figmaBorderWidth = 2.0;
const double _standardButtonSize = 64.0;
const double _largeButtonSize = 80.0;
const double _spaceBetweenItems = 16.0;
const double _dividerThickness = 2.0; // Толщина разделителя
const double _dividerWidth = 48.0;    // Ширина разделителя

class RightSidebar extends StatelessWidget {
  const RightSidebar({Key? key}) : super(key: key);

  Widget _buildDivider() {
    return Container(
      width: _dividerWidth,
      height: _dividerThickness,
      decoration: BoxDecoration(
        color: _figmaBorderColor, // surfaceContainerHighest
        borderRadius: BorderRadius.circular(_dividerThickness / 2), // Закругленные концы
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color indicatorBorderColor = Theme.of(context).colorScheme.background;

    return Container(
      width: 96,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: _spaceBetweenItems),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Профиль
          ProfileCircle(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundImage: AssetImage(AppAssets.avatar), // Убедитесь, что файл есть
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: indicatorBorderColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _spaceBetweenItems),

          // Разделитель
          _buildDivider(),
          const SizedBox(height: _spaceBetweenItems),

          // Иконки действий (64x64)
          ActionButton(icon: Icons.tune_outlined, tooltip: "Фильтрация"), // Фильтрация
          const SizedBox(height: _spaceBetweenItems),
          ActionButton(icon: Icons.swap_vert, tooltip: "Сортировка"),    // Сортировка
          const SizedBox(height: _spaceBetweenItems),
          ActionButton(icon: Icons.group_outlined, tooltip: "Члены команды"), // Члены команды
          const SizedBox(height: _spaceBetweenItems),
          ActionButton(icon: Icons.chat_bubble_outline, tooltip: "Чат команды"), // Чат команды

          const Spacer(), // Прижимает следующую кнопку к низу

          // Большая кнопка "Добавить задачу" внизу (80x80)
          ActionButton(
            icon: Icons.add_task_outlined, // Иконка "Добавить задачу"
            size: _largeButtonSize,
            tooltip: "Добавить задачу",
          ),
        ],
      ),
    );
  }
}

// Вспомогательные виджеты

class ProfileCircle extends StatelessWidget {
  final List<Widget> children;
  final Color borderColor;
  final double borderWidth;

  const ProfileCircle({
    Key? key,
    required this.children,
    this.borderColor = _figmaBorderColor,
    this.borderWidth = _figmaBorderWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _standardButtonSize,
      height: _standardButtonSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: _standardButtonSize,
            height: _standardButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color iconColor;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback? onPressed;
  final String? tooltip; // Добавлено для подсказок

  const ActionButton({
    Key? key,
    required this.icon,
    this.size = _standardButtonSize,
    this.iconColor = _figmaIconColor,
    this.borderColor = _figmaBorderColor,
    this.borderWidth = _figmaBorderWidth,
    this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double iconWidgetSize = size * 0.45;

    Widget buttonContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: Icon(icon, color: iconColor, size: iconWidgetSize),
    );

    // Оборачиваем в Tooltip, если он предоставлен
    if (tooltip != null && tooltip!.isNotEmpty) {
      buttonContent = Tooltip(
        message: tooltip!,
        child: buttonContent,
      );
    }

    return GestureDetector(
      onTap: onPressed ?? () {
        // print('ActionButton ${tooltip ?? icon.codePoint} pressed');
      },
      child: buttonContent,
    );
  }
}