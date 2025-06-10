// lib/chat_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models/chat_model.dart';
import 'services/api_service.dart';
import 'auth_state.dart';
import 'models/team_model.dart';

class ChatProvider with ChangeNotifier {
  final ApiService _apiService;
  final AuthState _authState;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;

  String? _currentTeamId;
  final Map<String, List<ChatMessage>> _messagesByTeam = {};
  final Map<String, bool> _isLoadingHistory = {};
  final Map<String, bool> _hasMoreHistory = {};
  String? _error;

  ChatProvider(this._apiService, this._authState);

  List<ChatMessage> messagesForTeam(String teamId) => _messagesByTeam[teamId] ?? [];
  bool isLoadingHistory(String teamId) => _isLoadingHistory[teamId] ?? false;
  bool hasMoreHistory(String teamId) => _hasMoreHistory[teamId] ?? true;
  String? get error => _error;

  Future<void> connect(String teamId) async {
    if (_currentTeamId == teamId && (_channel != null || (_isLoadingHistory[teamId] ?? false))) {
      return;
    }
    await disconnect();

    _currentTeamId = teamId;
    _error = null;
    notifyListeners();

    try {
      final dynamic wsConnection = await _apiService.getWebSocketChannel(teamId);

      if (wsConnection is Uri) {
        _channel = WebSocketChannel.connect(wsConnection);
      } else if (wsConnection is WebSocketChannel) {
        _channel = wsConnection;
      } else {
        throw Exception("Unknown WebSocket connection type");
      }

      _channelSubscription = _channel!.stream.listen(
        _onDataReceived,
        onError: _onError,
        onDone: _onDone,
      );
      debugPrint("[ChatProvider] Connected to WebSocket for team $teamId");

      if ((_messagesByTeam[teamId] ?? []).isEmpty) {
        await fetchHistory(teamId);
      }

    } catch (e) {
      _error = "Ошибка подключения к чату: $e";
      debugPrint("[ChatProvider] WebSocket connection error: $e");
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      await _channelSubscription?.cancel();
      await _channel?.sink.close();
      _channel = null;
      _channelSubscription = null;
      debugPrint("[ChatProvider] Disconnected from WebSocket.");
    }
  }

  Future<void> fetchHistory(String teamId, {bool loadMore = false}) async {
    if (isLoadingHistory(teamId)) return;
    if (loadMore && !(hasMoreHistory(teamId))) {
      debugPrint("[ChatProvider] No more history to load for team $teamId.");
      return;
    }

    _isLoadingHistory[teamId] = true;
    _error = null;
    notifyListeners();

    try {
      String? beforeMessageId;
      final currentMessages = _messagesByTeam[teamId] ?? [];
      if (loadMore && currentMessages.isNotEmpty) {
        beforeMessageId = currentMessages.first.id;
      }

      debugPrint("[ChatProvider] Fetching history for team $teamId. Before ID: $beforeMessageId");

      final Map<String, dynamic> historyResponse = await _apiService.getChatHistory(teamId, beforeMessageId: beforeMessageId);

      final List<dynamic> messagesData = historyResponse['items'] ?? [];
      final bool hasMore = historyResponse['has_more'] ?? false;

      final newMessages = messagesData.map((item) => ChatMessage.fromJson(item)).toList();
      debugPrint("[ChatProvider] Fetched ${newMessages.length} messages from history. HasMore: $hasMore");

      _hasMoreHistory[teamId] = hasMore;

      final existingIds = currentMessages.map((m) => m.id).toSet();
      newMessages.removeWhere((m) => existingIds.contains(m.id));

      _messagesByTeam[teamId] = [...newMessages, ...currentMessages];
      _messagesByTeam[teamId]?.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    } on ApiException catch (e) {
      _error = "Ошибка загрузки истории: ${e.message}";
      debugPrint("[ChatProvider] API Error fetching history: $_error");
    } catch (e, s) {
      _error = "Неизвестная ошибка загрузки истории: $e";
      debugPrint("[ChatProvider] Unknown Error fetching history: $e, Stack: $s");
    } finally {
      _isLoadingHistory[teamId] = false;
      notifyListeners();
    }
  }

  void _onDataReceived(dynamic data) {
    try {
      final messageJson = json.decode(data as String);
      final type = messageJson['type'] as String;
      final payload = messageJson['payload'] as Map<String, dynamic>;

      debugPrint("[ChatProvider] WS Received: type=$type, payload: $payload");

      switch (type) {
        case 'MESSAGE_RECEIVED':
          final newMessage = ChatMessage.fromJson(payload);
          _addOrUpdateMessage(newMessage);
          break;
        case 'MESSAGE_EDITED':
          final teamId = payload['teamId'].toString();
          final messageId = payload['id'] as String;
          final newText = payload['text'] as String;
          final editedAt = DateTime.parse(payload['editedAt'] as String);
          _updateMessageContent(teamId, messageId, newText, editedAt);
          break;
        case 'MESSAGE_DELETED':
          final teamId = payload['teamId'].toString();
          final messageId = payload['id'] as String;
          _removeMessage(teamId, messageId);
          break;
        case 'ERROR':
          _error = payload['message'] as String?;
          debugPrint("[ChatProvider] WS Error from server: $_error");
          notifyListeners();
          break;
      }
    } catch (e, s) {
      debugPrint("[ChatProvider] Error parsing WS message: $e, Stack: $s, Data: $data");
    }
  }

  void _onError(error) {
    _error = "Ошибка соединения с чатом: $error";
    debugPrint("[ChatProvider] WebSocket error: $error");
    disconnect();
    notifyListeners();
  }

  void _onDone() {
    debugPrint("[ChatProvider] WebSocket connection closed by server.");
    if (_error == null) {
      _error = "Соединение с чатом закрыто.";
    }
    disconnect();
    notifyListeners();
  }

  void _addOrUpdateMessage(ChatMessage message) {
    final teamIdStr = message.teamId.toString();
    if (_messagesByTeam[teamIdStr] == null) _messagesByTeam[teamIdStr] = [];

    final messageList = _messagesByTeam[teamIdStr]!;

    if (message.clientMessageId != null) {
      final index = messageList.indexWhere((m) => m.clientMessageId == message.clientMessageId);
      if (index != -1) {
        messageList[index] = message;
        notifyListeners();
        return;
      }
    }

    final existingIndex = messageList.indexWhere((m) => m.id == message.id);
    if (existingIndex == -1) {
      messageList.add(message);
    } else {
      messageList[existingIndex] = message;
    }
    messageList.sort((a,b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  void _updateMessageContent(String teamId, String messageId, String newText, DateTime editedAt) {
    final messageList = _messagesByTeam[teamId];
    if (messageList == null) return;
    final index = messageList.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      messageList[index].text = newText;
      messageList[index].editedAt = editedAt;
      notifyListeners();
    }
  }

  void _removeMessage(String teamId, String messageId) {
    final messageList = _messagesByTeam[teamId];
    if (messageList == null) return;
    messageList.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  void _updateMessageStatus(String teamId, String messageId, String newStatusStr) {
    final messageList = _messagesByTeam[teamId];
    if (messageList == null) return;
    final index = messageList.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final newStatus = ChatMessage.fromJson({'status': newStatusStr}).status;
      if (newStatus.index > messageList[index].status.index) {
        messageList[index].status = newStatus;
        notifyListeners();
      }
    }
  }

  void _send(Map<String, dynamic> message) {
    if (_channel != null) {
      try {
        _channel!.sink.add(json.encode(message));
      } catch (e) {
        debugPrint("[ChatProvider] Error sending message to WS sink: $e");
        _onError(e);
      }
    }
  }

  void sendMessage(String text, {String? replyToId}) {
    if (text.trim().isEmpty || _currentTeamId == null) return;

    final currentUser = _authState.currentUser;
    if (currentUser == null) return;

    final clientMessageId = "client_${DateTime.now().millisecondsSinceEpoch}";

    ChatMessage? repliedMessage;
    if (replyToId != null) {
      try {
        repliedMessage = _messagesByTeam[_currentTeamId]?.firstWhere((m) => m.id == replyToId);
      } catch (e) {
        repliedMessage = null;
      }
    }

    final tempMessage = ChatMessage(
      id: clientMessageId,
      teamId: int.parse(_currentTeamId!),
      clientMessageId: clientMessageId,
      text: text,
      sender: UserLite.fromUserProfile(currentUser),
      timestamp: DateTime.now(),
      isCurrentUser: true,
      status: MessageStatus.sent,
      replyToMessageId: repliedMessage?.id,
      replyToText: repliedMessage?.text,
      replyToSenderLogin: repliedMessage?.sender.login,
    );
    _addOrUpdateMessage(tempMessage);

    final payload = {
      "text": text.trim(),
      "client_message_id": clientMessageId,
      if (replyToId != null) "reply_to_message_id": int.tryParse(replyToId),
    };
    _send({"type": "NEW_MESSAGE", "payload": payload});
  }

  void editMessage(String messageId, String newText) {
    _send({"type": "EDIT_MESSAGE", "payload": {"message_id": int.parse(messageId), "new_text": newText.trim()}});
  }

  void deleteMessage(String messageId) {
    _send({"type": "DELETE_MESSAGE", "payload": {"message_id": int.parse(messageId)}});
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}