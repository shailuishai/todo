// lib/models/chat_model.dart
import 'package:flutter/material.dart'; // Для GlobalKey
import 'package:client/models/team_model.dart'; // Для UserLite

// Обновленный enum MessageStatus
enum MessageStatus { sent, read }

class ChatMessage {
  final String id;
  String text;
  final UserLite sender;
  final DateTime timestamp;
  final bool isCurrentUser;
  MessageStatus status;
  String? replyToMessageId;
  String? replyToText;
  String? replyToSenderLogin;
  DateTime? editedAt;
  GlobalKey messageKey; // Убрал nullable, т.к. всегда инициализируется

  // Флаг для подсветки
  bool isHighlighted;

  ChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.isCurrentUser = false,
    this.status = MessageStatus.sent, // По умолчанию 'sent'
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderLogin,
    this.editedAt,
    GlobalKey? messageKey, // Оставляем возможность передать ключ
    this.isHighlighted = false, // По умолчанию не подсвечено
  }) : messageKey = messageKey ?? GlobalKey();


  bool get isReply => replyToMessageId != null && replyToText != null && replyToSenderLogin != null;
  bool get isEdited => editedAt != null;
}