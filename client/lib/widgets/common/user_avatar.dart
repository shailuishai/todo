// lib/widgets/common/user_avatar.dart
import 'package:flutter/material.dart';
import '../../models/team_model.dart'; // Для UserLite
// Если UserProfile используется для текущего пользователя, его тоже можно передавать
// import '../../services/api_service.dart'; // Для UserProfile, если потребуется

class UserAvatar extends StatelessWidget {
  final String login;
  final String? avatarUrl;
  final String? accentColorHex; // HEX строка цвета, например "#RRGGBB"
  final double radius;
  final double fontSizeMultiplier; // Для настройки размера шрифта инициалов

  const UserAvatar({
    Key? key,
    required this.login,
    this.avatarUrl,
    this.accentColorHex,
    required this.radius,
    this.fontSizeMultiplier = 0.6, // По умолчанию 0.6 от радиуса
  }) : super(key: key);

  // Статический метод для удобства, если UserLite уже есть
  factory UserAvatar.fromUserLite({
    Key? key,
    required UserLite user,
    required double radius,
    double fontSizeMultiplier = 0.6,
  }) {
    return UserAvatar(
      key: key,
      login: user.login,
      avatarUrl: user.avatarUrl,
      accentColorHex: user.accentColor, // Передаем accentColor из UserLite
      radius: radius,
      fontSizeMultiplier: fontSizeMultiplier,
    );
  }

  // Можно добавить factory UserAvatar.fromUserProfile, если нужно

  Color _parseAccentColor(BuildContext context) {
    if (accentColorHex != null && accentColorHex!.isNotEmpty) {
      try {
        final buffer = StringBuffer();
        if (accentColorHex!.length == 6 || accentColorHex!.length == 7) buffer.write('ff');
        buffer.write(accentColorHex!.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (e) {
        debugPrint("UserAvatar: Error parsing accentColorHex: $accentColorHex, error: $e");
      }
    }
    // Дефолтный цвет, если accentColorHex невалиден или отсутствует
    return Theme.of(context).colorScheme.primaryContainer;
  }

  String _getInitials() {
    String initials = "";
    if (login.isNotEmpty) {
      final names = login.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (names.isNotEmpty) {
        initials = names[0][0];
        if (names.length > 1 && names[1].isNotEmpty) {
          initials += names[1][0];
        } else if (names[0].length > 1) {
          initials = names[0].substring(0, initials.length == 1 ? 2 : 1).trim();
          if (initials.length > 2) initials = initials.substring(0, 2);
        }
      }
    }
    initials = initials.toUpperCase();
    return initials.isEmpty ? "?" : initials;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _getInitials();

    Widget avatarContent;

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: Colors.transparent, // Фон будет виден, если изображение с прозрачностью
        onBackgroundImageError: (exception, stackTrace) {
          // В случае ошибки загрузки можно показать инициалы, но это усложнит виджет,
          // т.к. потребуется StatefulWidget для управления состоянием ошибки.
          // Пока просто оставляем стандартное поведение (может показать иконку ошибки).
          debugPrint("UserAvatar: Error loading image $avatarUrl: $exception");
        },
      );
    } else {
      final avatarBackgroundColor = _parseAccentColor(context);
      final avatarTextColor = ThemeData.estimateBrightnessForColor(avatarBackgroundColor) == Brightness.dark
          ? Colors.white.withOpacity(0.95)
          : Colors.black.withOpacity(0.8);

      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: avatarBackgroundColor,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: radius * (initials.length == 1 ? fontSizeMultiplier + 0.2 : fontSizeMultiplier), // Чуть больше для одной буквы
            fontWeight: FontWeight.bold,
            color: avatarTextColor,
          ),
        ),
      );
    }
    return avatarContent;
  }
}