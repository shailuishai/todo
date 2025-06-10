// lib/models/chat_model.dart
import 'package:flutter/material.dart';
import 'team_model.dart'; // Для UserLite

enum MessageStatus { sent, read, delivered }

// <<< ВОЗВРАЩАЕМ МОДЕЛЬ К МАКСИМАЛЬНО ПОХОЖЕЙ НА ТВОЮ ЗАГЛУШКУ >>>
class ChatMessage {
  final String id;
  // <<< НО СОХРАНЯЕМ teamId, он нужен для провайдера >>>
  final int teamId;
  String text;
  final UserLite sender;
  final DateTime timestamp;
  final bool isCurrentUser;
  MessageStatus status;
  String? replyToMessageId;
  String? replyToText;
  String? replyToSenderLogin; // <<< ВОЗВРАЩАЕМ ЭТО ПОЛЕ
  DateTime? editedAt;
  GlobalKey messageKey;
  bool isHighlighted;
  final String? clientMessageId;

  ChatMessage({
    required this.id,
    required this.teamId,
    required this.text,
    required this.sender,
    required this.timestamp,
    required this.isCurrentUser,
    this.status = MessageStatus.sent,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderLogin, // <<< ВОЗВРАЩАЕМ ЭТО ПОЛЕ
    this.editedAt,
    this.clientMessageId,
    GlobalKey? messageKey,
    this.isHighlighted = false,
  }) : messageKey = messageKey ?? GlobalKey();

  bool get isReply => replyToMessageId != null && replyToText != null && replyToSenderLogin != null;
  bool get isEdited => editedAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Вспомогательная UserLite модель для получения replyToSenderLogin
    final UserLite? replyToSender = json['replyToSender'] != null
        ? UserLite.fromJson(json['replyToSender'] as Map<String, dynamic>)
        : null;

    return ChatMessage(
      id: json['id'].toString(),
      teamId: json['teamId'] as int? ?? json['team_id'] as int,
      text: json['text'] as String,
      sender: UserLite.fromJson(json['sender'] as Map<String, dynamic>),
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
      isCurrentUser: json['isCurrentUser'] as bool? ?? json['is_current_user'] as bool? ?? false,
      status: _statusFromString(json['status'] as String?),
      replyToMessageId: json['replyToMessageId']?.toString() ?? json['reply_to_message_id']?.toString(),
      replyToText: json['replyToText'] as String?,
      replyToSenderLogin: replyToSender?.login, // Заполняем поле из вложенного объекта
      editedAt: json['editedAt'] != null
          ? DateTime.parse(json['editedAt'] as String).toLocal()
          : null,
      clientMessageId: json['clientMessageId'] as String? ?? json['client_message_id'] as String?,
    );
  }

  static MessageStatus _statusFromString(String? status) {
    switch (status) {
      case 'read':
        return MessageStatus.read;
      case 'delivered':
        return MessageStatus.delivered;
      case 'sent':
      default:
        return MessageStatus.sent;
    }
  }
}