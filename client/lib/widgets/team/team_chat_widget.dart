// lib/widgets/team/team_chat_widget.dart
import 'dart:async'; // Для Timer (для сброса подсветки)
import 'package:client/auth_state.dart';
import 'package:client/models/chat_model.dart';
import 'package:client/models/team_model.dart';
import 'package:client/widgets/common/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Для Clipboard
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:context_menus/context_menus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../services/api_service.dart';


class TeamChatWidget extends StatefulWidget {
  final String teamId;
  final String currentUserId;

  const TeamChatWidget({
    Key? key,
    required this.teamId,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<TeamChatWidget> createState() => _TeamChatWidgetState();
}

class _TeamChatWidgetState extends State<TeamChatWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  List<ChatMessage> _messages = [];
  UserProfile? _currentUserProfile;

  bool _isEditing = false;
  String? _editingMessageId;
  ChatMessage? _replyingToMessage;

  Timer? _highlightTimer;
  String? _highlightedMessageId;

  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _currentUserProfile = Provider.of<AuthState>(context, listen: false).currentUser;
    _loadDummyMessages();
    _inputFocusNode.addListener(() {
      if (!_inputFocusNode.hasFocus && _showEmojiPicker) {
        // setState(() {
        //   _showEmojiPicker = false;
        // });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom(animated: false);
    });
  }

  void _scrollToBottom({bool animated = true, double? specificPosition}) {
    if (!_scrollController.hasClients) return;
    final position = specificPosition ?? _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      position,
      duration: Duration(milliseconds: animated ? 300 : 0),
      curve: Curves.easeOut,
    );
  }

  void _scrollToMessageAndHighlight(GlobalKey messageKey, String messageId) {
    final context = messageKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        alignment: 0.3,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ).then((_) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() {
              for (var msg in _messages) {
                msg.isHighlighted = false;
              }
              final targetMsgIndex = _messages.indexWhere((m) => m.id == messageId);
              if (targetMsgIndex != -1) {
                _messages[targetMsgIndex].isHighlighted = true;
                _highlightedMessageId = messageId;
              }
            });
            _highlightTimer?.cancel();
            _highlightTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _highlightedMessageId == messageId) {
                setState(() {
                  final targetMsgIndex = _messages.indexWhere((m) => m.id == messageId);
                  if (targetMsgIndex != -1) {
                    _messages[targetMsgIndex].isHighlighted = false;
                  }
                  _highlightedMessageId = null;
                });
              }
            });
          }
        });
      });
    }
  }

  void _loadDummyMessages() {
    final userAlice = UserLite(userId: 1, login: "Alice Wonderland", accentColor: "#E91E63", avatarUrl: null);
    final userYou = UserLite(
        userId: int.tryParse(widget.currentUserId) ?? 0,
        login: _currentUserProfile?.login ?? "You",
        accentColor: _currentUserProfile?.accentColor ?? "#4CAF50",
        avatarUrl: _currentUserProfile?.avatarUrl);
    final userBob = UserLite(userId: 3, login: "Bob The Builder", accentColor: "#2196F3", avatarUrl: null);
    final userCharlie = UserLite(userId: 4, login: "Charlie Brown", accentColor: "#FF9800", avatarUrl: null);

    List<ChatMessage> dummyMessagesSource = [
      ChatMessage(id: '1', text: 'Всем привет! 👋', sender: userAlice, timestamp: DateTime.now().subtract(const Duration(minutes: 20)), status: MessageStatus.read),
      ChatMessage(id: '2', text: 'Я начала работу над новой задачей по UI. Уже есть первые наброски. Это очень длинное сообщение, чтобы проверить как оно будет переноситься и выглядеть в несколько строк, а также как будет работать группировка.', sender: userAlice, timestamp: DateTime.now().subtract(const Duration(minutes: 19, seconds: 30)), status: MessageStatus.read),
      ChatMessage(id: '2a', text: 'Второе сообщение от Alice подряд.', sender: userAlice, timestamp: DateTime.now().subtract(const Duration(minutes: 19)), status: MessageStatus.read),

      ChatMessage(id: 'msg_you_1', text: 'Привет, Alice! Отлично! Это мой ответ, он может быть достаточно длинным, чтобы проверить, как он будет отображаться в цитате.', sender: userYou, timestamp: DateTime.now().subtract(const Duration(minutes: 18)), status: MessageStatus.read),
      ChatMessage(id: 'msg_you_2', text: 'Последний коммит посмотрел, все ок.', sender: userYou, timestamp: DateTime.now().subtract(const Duration(minutes: 17)), status: MessageStatus.read),
      ChatMessage(id: 'msg_you_3', text: '```dart\nvoid main() {\n  print("Hello, team!");\n}\n```', sender: userYou, timestamp: DateTime.now().subtract(const Duration(minutes: 16, seconds: 30)), status: MessageStatus.read),

      ChatMessage(id: '6', text: 'Здорово! Бэкенд готовлю.', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 15)), status: MessageStatus.read),
      ChatMessage(id: '6a', text: 'Первое сообщение Боба в группе', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 14, seconds: 50)), status: MessageStatus.read),
      ChatMessage(id: '7', text: 'Добавил эндпоинт `/api/v1/stats`. Отвечаю на твое длинное сообщение.', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 14)), status: MessageStatus.read, replyToMessageId: 'msg_you_1', replyToText: 'Привет, Alice! Отлично! Это мой ответ, он может быть достаточно длинным, чтобы проверить, как он будет отображаться в цитате. И еще немного текста, чтобы цитата стала многострочной и мы могли это протестировать.', replyToSenderLogin: userYou.login),

      ChatMessage(id: '8', text: 'Всем хай! Я Чарли.', sender: userCharlie, timestamp: DateTime.now().subtract(const Duration(minutes: 10)), status: MessageStatus.read),
      ChatMessage(id: '9', text: '`docker-compose up` падает иногда.', sender: userCharlie, timestamp: DateTime.now().subtract(const Duration(minutes: 9)), status: MessageStatus.read),

      ChatMessage(id: '10', text: 'Charlie, попробуй `docker-compose down && docker-compose up --build`.', sender: userAlice, timestamp: DateTime.now().subtract(const Duration(minutes: 8)), status: MessageStatus.read, editedAt: DateTime.now().subtract(const Duration(minutes: 7, seconds: 50))),

      ChatMessage(id: '11', text: 'Bob, спасибо за инфу по бэку!', sender: userYou, timestamp: DateTime.now().subtract(const Duration(minutes: 7)), status: MessageStatus.sent),

      ChatMessage(id: '12', text: 'Всегда пожалуйста!', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 5)), status: MessageStatus.read),
      ChatMessage(id: '13', text: 'Готовьтесь к тестированию бэка завтра!', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 4, seconds: 30)), status: MessageStatus.read),
      ChatMessage(id: '14', text: 'Основные изменения:\n- Улучшена производительность\n- Добавлены новые метрики\n- Исправлены мелкие баги', sender: userBob, timestamp: DateTime.now().subtract(const Duration(minutes: 4)), status: MessageStatus.read),

      ChatMessage(id: '15', text: 'Ок, будем готовы!', sender: userCharlie, timestamp: DateTime.now().subtract(const Duration(minutes: 2)), status: MessageStatus.read, replyToMessageId: '13', replyToText: 'Готовьтесь к тестированию бэка завтра!', replyToSenderLogin: userBob.login),
      ChatMessage(id: '16', text: 'Это сообщение для проверки группировки аватара Чарли.', sender: userCharlie, timestamp: DateTime.now().subtract(const Duration(minutes: 1, seconds: 50)), status: MessageStatus.sent),
      ChatMessage(id: '17', text: 'И еще одно от Чарли, чтобы он был последним в группе. Проверяем хвостик и аватар.    \n   ', sender: userCharlie, timestamp: DateTime.now().subtract(const Duration(minutes: 1, seconds: 40)), status: MessageStatus.sent),
    ];

    setState(() {
      _messages = dummyMessagesSource.map((msg) {
        MessageStatus finalStatus = msg.status;
        if (!msg.isCurrentUser && DateTime.now().difference(msg.timestamp).inMinutes > 2 && finalStatus == MessageStatus.sent) {
          finalStatus = MessageStatus.read;
        }
        return ChatMessage(
          id: msg.id,
          text: msg.text,
          sender: msg.sender,
          timestamp: msg.timestamp,
          isCurrentUser: msg.sender.userId.toString() == widget.currentUserId,
          status: finalStatus,
          replyToMessageId: msg.replyToMessageId,
          replyToText: msg.replyToText,
          replyToSenderLogin: msg.replyToSenderLogin,
          editedAt: msg.editedAt,
        );
      }).toList();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _markAsReadByOthers();
        }
      });
    });
  }

  void _markAsReadByOthers() {
    setState(() {
      for (var msg in _messages) {
        if (!msg.isCurrentUser && msg.status == MessageStatus.sent) {
          msg.status = MessageStatus.read;
        }
      }
    });
  }

  void _sendMessage() {
    final String newText = _textController.text.trimRight();

    if (newText.isEmpty) {
      _cancelReplyAndEdit();
      return;
    }

    if (_isEditing && _editingMessageId != null) {
      int msgIndex = _messages.indexWhere((m) => m.id == _editingMessageId);
      if (msgIndex != -1) {
        setState(() {
          _messages[msgIndex].text = newText;
          _messages[msgIndex].editedAt = DateTime.now();
        });
      }
    } else {
      final senderUser = UserLite(
          userId: _currentUserProfile?.userId ?? 0,
          login: _currentUserProfile?.login ?? "You",
          accentColor: _currentUserProfile?.accentColor,
          avatarUrl: _currentUserProfile?.avatarUrl);
      final newMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: newText,
        sender: senderUser,
        timestamp: DateTime.now(),
        isCurrentUser: true,
        status: MessageStatus.sent,
        replyToMessageId: _replyingToMessage?.id,
        replyToText: _replyingToMessage?.text,
        replyToSenderLogin: _replyingToMessage?.sender.login,
      );
      setState(() {
        _messages.add(newMessage);
      });
    }
    _textController.clear();
    _cancelReplyAndEdit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    if (!_showEmojiPicker) {
      _inputFocusNode.requestFocus();
    }
  }

  void _startReply(ChatMessage message) {
    _resetHighlight();
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _replyingToMessage = message;
      _showEmojiPicker = false;
      _inputFocusNode.requestFocus();
    });
  }

  void _startEdit(ChatMessage message) {
    if (!message.isCurrentUser) return;
    _resetHighlight();
    setState(() {
      _isEditing = true;
      _editingMessageId = message.id;
      _replyingToMessage = null;
      _textController.text = message.text;
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
      _showEmojiPicker = false;
      _inputFocusNode.requestFocus();
    });
  }

  void _resetHighlight() {
    if (_highlightedMessageId != null) {
      final currentlyHighlightedIndex = _messages.indexWhere((m) => m.id == _highlightedMessageId);
      if (currentlyHighlightedIndex != -1 && _messages[currentlyHighlightedIndex].isHighlighted) {
        setState(() {
          _messages[currentlyHighlightedIndex].isHighlighted = false;
        });
      }
      _highlightedMessageId = null;
      _highlightTimer?.cancel();
    } else {
      bool changed = false;
      for(var msg in _messages) {
        if (msg.isHighlighted) {
          msg.isHighlighted = false;
          changed = true;
        }
      }
      if (changed && mounted) {
        setState(() {});
      }
    }
  }


  void _deleteMessage(ChatMessage message) {
    _resetHighlight();
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
      if (_replyingToMessage?.id == message.id) _cancelReplyAndEdit();
      if (_editingMessageId == message.id) _cancelReplyAndEdit();
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Сообщение \"${message.text.substring(0, (message.text.length > 20) ? 20 : message.text.length)}...\" удалено.")));
  }

  void _copyMessageText(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Текст сообщения скопирован.")));
  }

  void _cancelReplyAndEdit() {
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _replyingToMessage = null;
      if (_textController.text.isNotEmpty && !_inputFocusNode.hasFocus && !_showEmojiPicker) {
        // не очищаем
      } else {
        _textController.clear();
      }
    });
  }

  void _onEmojiSelected(Emoji emoji) {
    _textController
      ..text += emoji.emoji
      ..selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length));
  }

  void _onBackspacePressed() {
    _textController
      ..text = _textController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length));
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_inputFocusNode);
      }
    } else {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    }
    if (mounted) {
      setState(() {
        _showEmojiPicker = !_showEmojiPicker;
      });
    }
  }


  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  GlobalKey? _findMessageKeyById(String? messageId) {
    if (messageId == null) return null;
    try {
      return _messages.firstWhere((msg) => msg.id == messageId).messageKey;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double avatarSize = 16.0 * 2;
    final double avatarPadding = 8.0;
    final double avatarSpaceWidth = avatarSize + avatarPadding;

    return ContextMenuOverlay(
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (){
                if (_showEmojiPicker && mounted) {
                  setState(() { _showEmojiPicker = false; });
                }
                _resetHighlight();
              },
              child: _messages.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_rounded, size: 64, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      "В этом чате пока нет сообщений.",
                      style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    top: 12.0,
                    bottom: 12.0 + (_replyingToMessage != null || _isEditing || _showEmojiPicker ? 0 : MediaQuery.of(context).padding.bottom)),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final bool isFirstInGroup = index == 0 ||
                      _messages[index - 1].sender.userId != message.sender.userId ||
                      message.timestamp.difference(_messages[index - 1].timestamp).inMinutes >= 5 ||
                      _messages[index - 1].isCurrentUser != message.isCurrentUser;
                  final bool isLastInGroup = index == _messages.length - 1 ||
                      _messages[index + 1].sender.userId != message.sender.userId ||
                      _messages[index + 1].timestamp.difference(message.timestamp).inMinutes >= 5 ||
                      _messages[index + 1].isCurrentUser != message.isCurrentUser;

                  return ChatMessageBubble(
                    key: message.messageKey,
                    message: message,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                    avatarSpace: avatarSpaceWidth,
                    onReply: () => _startReply(message),
                    onEdit: message.isCurrentUser ? () => _startEdit(message) : null,
                    onDelete: () => _deleteMessage(message),
                    onCopy: () => _copyMessageText(message),
                    onQuotedMessageTap: (replyToId) {
                      final key = _findMessageKeyById(replyToId);
                      if (key != null) {
                        _scrollToMessageAndHighlight(key, replyToId);
                      }
                    },
                  );
                },
              ),
            ),
          ),
          if (_replyingToMessage != null || _isEditing) _buildReplyOrEditHeader(context),
          _buildMessageInputField(context),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
  }

  Widget _buildReplyOrEditHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String title;
    String content;
    ChatMessage? targetMessage = _isEditing
        ? _messages.firstWhere((m) => m.id == _editingMessageId, orElse: () => _replyingToMessage!)
        : _replyingToMessage;

    if (targetMessage == null) return const SizedBox.shrink();


    if (_isEditing && _editingMessageId != null) {
      final editingMsg = _messages.firstWhere((m) => m.id == _editingMessageId, orElse: () => targetMessage);
      title = "Редактирование сообщения";
      content = editingMsg.text;
    } else if (_replyingToMessage != null) {
      title = "Ответ на ${ _replyingToMessage!.isCurrentUser ? 'ваше сообщение' : _replyingToMessage!.sender.login}";
      content = _replyingToMessage!.text;
    } else {
      return const SizedBox.shrink();
    }

    Widget headerRow = Row(
      children: [
        Icon(
          _isEditing ? Icons.edit_outlined : Icons.reply_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
              Text(
                content,
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: _cancelReplyAndEdit,
          tooltip: "Отменить",
          color: colorScheme.onSurfaceVariant,
        )
      ],
    );

    Widget tappableHeader = headerRow;
    if (_replyingToMessage != null && _replyingToMessage!.messageKey != null) {
      tappableHeader = InkWell(
        onTap: () {
          _scrollToMessageAndHighlight(_replyingToMessage!.messageKey, _replyingToMessage!.id);
        },
        child: headerRow,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.7)))
      ),
      child: tappableHeader,
    );
  }

  Widget _buildMessageInputField(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 8.0,
      color: colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(
          left: 8.0,
          right: 8.0,
          top: 8.0,
          bottom: 8.0 + (_showEmojiPicker ? 0 : (MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: _toggleEmojiPicker,
              tooltip: "Смайлики",
            ),
            Expanded(
              child: TextField(
                focusNode: _inputFocusNode,
                controller: _textController,
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _isEditing ? "Редактировать..." : _replyingToMessage != null ? "Ответить..." : "Сообщение...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                ),
                onTap: () {
                  if (_showEmojiPicker && mounted) {
                    setState(() { _showEmojiPicker = false; });
                  }
                },
              ),
            ),
            const SizedBox(width: 8.0),
            IconButton(
              icon: Icon(_isEditing ? Icons.check_rounded : Icons.send_rounded, color: colorScheme.primary),
              onPressed: _sendMessage,
              tooltip: _isEditing ? "Сохранить" : "Отправить",
              style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  padding: const EdgeInsets.all(14),
                  shape: const CircleBorder()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final theme = Theme.of(context);
    return SizedBox(
      height: 250,
      child: EmojiPicker(
        onEmojiSelected: (Category? category, Emoji emoji) {
          _onEmojiSelected(emoji);
        },
        onBackspacePressed: _onBackspacePressed,
        config: Config(
          height: 250,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            emojiSizeMax: 28 * (kIsWeb ? 1.0 : 1.1),
            columns: kIsWeb ? 10 : 8,
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            buttonMode: ButtonMode.MATERIAL,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: theme.colorScheme.surface,
            indicatorColor: theme.colorScheme.primary,
            iconColorSelected: theme.colorScheme.primary,
            iconColor: theme.colorScheme.onSurfaceVariant,
            dividerColor: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            enabled: false,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            buttonIconColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}


// --- ChatMessageBubble ---
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final double avatarSpace;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final Function(String replyToMessageId)? onQuotedMessageTap;

  const ChatMessageBubble({
    Key? key,
    required this.message,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.avatarSpace,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onQuotedMessageTap,
  }) : super(key: key);


  List<ContextMenuButtonConfig> _getContextMenuButtonConfigs(BuildContext context) {
    final List<ContextMenuButtonConfig> configs = [];
    final theme = Theme.of(context);

    if (onReply != null) {
      configs.add(ContextMenuButtonConfig("Ответить", icon: Icon(Icons.reply_rounded, size: 20), onPressed: () => onReply!()));
    }
    if (onEdit != null && message.isCurrentUser) {
      configs.add(ContextMenuButtonConfig("Редактировать", icon: Icon(Icons.edit_outlined, size: 20), onPressed: () => onEdit!()));
    }
    if (onCopy != null) {
      configs.add(ContextMenuButtonConfig("Копировать текст", icon: Icon(Icons.copy_all_rounded, size: 20), onPressed: () => onCopy!()));
    }
    if (onDelete != null) {
      configs.add(ContextMenuButtonConfig(
        "Удалить",
        icon: Icon(Icons.delete_outline_rounded, size: 20, color: theme.colorScheme.error),
        onPressed: () => onDelete!(),
      ));
    }
    return configs;
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool byMe = message.isCurrentUser;

    final defaultPStyle = theme.textTheme.bodyMedium?.copyWith(
      color: byMe ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
      fontSize: 15.5, height: 1.4,
    );
    final replyMarkdownStyleSheet = MarkdownStyleSheet( // Отдельный стиль для цитаты
      p: theme.textTheme.bodySmall?.copyWith( // Используем bodySmall для цитаты
        color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.9) : colorScheme.onSurfaceVariant.withOpacity(0.9), // Чуть приглушеннее
        fontSize: 13.5, // Меньше основного текста
        height: 1.3,
      ),
      // Можно определить и другие стили для цитаты если нужно (ссылки, код и т.д.)
      // Например, если в цитате есть код, он будет отрендерен с этим p-стилем,
      // либо нужно будет определить для него code: стиль здесь.
    );

    final mainMarkdownStyleSheet = MarkdownStyleSheet(
      p: defaultPStyle,
      code: defaultPStyle?.copyWith(
        fontFamily: 'JetBrains Mono',
        backgroundColor: (byMe ? colorScheme.primary.withOpacity(0.15) : colorScheme.onSurface.withOpacity(0.1)),
        color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.95) : colorScheme.onSurface.withOpacity(0.95),
        fontSize: 13.5,
      ),
      strong: defaultPStyle?.copyWith(fontWeight: FontWeight.w600),
      em: defaultPStyle?.copyWith(fontStyle: FontStyle.italic),
      a: defaultPStyle?.copyWith(color: byMe ? colorScheme.secondary : colorScheme.primary, decoration: TextDecoration.underline, decorationColor: byMe ? colorScheme.secondary.withOpacity(0.7) : colorScheme.primary.withOpacity(0.7)),
      blockquoteDecoration: BoxDecoration(color: (byMe ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest).withOpacity(0.4), border: Border(left: BorderSide(color: byMe ? colorScheme.primary.withOpacity(0.7) : colorScheme.outline.withOpacity(0.7), width: 4)),),
      blockquote: defaultPStyle?.copyWith(color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.85) : colorScheme.onSurface.withOpacity(0.85), fontSize: 15),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(color: (byMe ? colorScheme.primary.withOpacity(0.08) : colorScheme.surface.withOpacity(0.7)), borderRadius: BorderRadius.circular(8), border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),),
      listBullet: defaultPStyle,
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(width: 1.5, color: colorScheme.outlineVariant.withOpacity(0.6))),),
    );

    const Radius bubbleRadiusVal = Radius.circular(18.0);
    const Radius tailRadiusVal = Radius.circular(5.0);

    final BorderRadius messageBorderRadius = BorderRadius.only(
      topLeft: bubbleRadiusVal,
      topRight: bubbleRadiusVal,
      bottomLeft: byMe ? bubbleRadiusVal : (isLastInGroup ? tailRadiusVal : bubbleRadiusVal),
      bottomRight: byMe ? (isLastInGroup ? tailRadiusVal : bubbleRadiusVal) : bubbleRadiusVal,
    );

    Widget replyContentWidget = const SizedBox.shrink();
    if (message.isReply && message.replyToMessageId != null) {
      replyContentWidget = InkWell(
        onTap: () {
          if (onQuotedMessageTap != null) {
            onQuotedMessageTap!(message.replyToMessageId!);
          }
        },
        child: Container(
          width: MediaQuery.of(context).size.width * 0.3,
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          decoration: BoxDecoration(
              color: (byMe ? colorScheme.primary : colorScheme.secondary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.0),
              border: Border(left: BorderSide(color: byMe ? colorScheme.primary : colorScheme.secondary, width: 3))
          ),
          child: Column( // Используем Column для вертикального расположения
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start, // Имя и иконка выровнены по верху
                children: [
                  Expanded( // Даем Expanded тексту имени, чтобы он мог переноситься, если очень длинный
                    child: Text(
                      message.replyToSenderLogin!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: byMe ? colorScheme.primary : colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5, // Чуть меньше
                      ),
                      // overflow: TextOverflow.ellipsis, // Убираем, чтобы видеть полный текст если он переносится
                    ),
                  ),
                  const SizedBox(width: 4), // Небольшой отступ
                  Icon(Icons.reply_rounded, size: 14, color: (byMe ? colorScheme.primary : colorScheme.secondary).withOpacity(0.7))
                ],
              ),
              const SizedBox(height: 2), // Маленький отступ между именем и текстом цитаты
              // MarkdownBody для текста цитаты, чтобы он корректно переносился
              MarkdownBody(
                data: message.replyToText!,
                styleSheet: replyMarkdownStyleSheet,
                // selectable: false, // Обычно текст цитаты не делают выделяемым
              ),
            ],
          ),
        ),
      );
    }

    final bool showEditedMark = message.isEdited;
    final bool showStatusAndTime = byMe || (!byMe && !showEditedMark) || (!byMe && showEditedMark); // Показываем время всегда, если не свои - то и "изм."

    // Уменьшаем зарезервированную ширину для времени/статуса
    // "HH:mm" ~30px, "✓✓" ~16px, "изм." ~20px. Отступы ~2+3=5px
    // Максимум: изм. + HH:mm + ✓✓ = 20 + 30 + 16 + 5 = 71
    // Только HH:mm = 30 + 2 = 32
    double timeStatusReservedWidth = 0;
    double timeStampHorizontalPadding = 0; // Отступ для блока времени/статуса

    if (byMe) { // Свои сообщения
      timeStatusReservedWidth += 30; // Время
      timeStatusReservedWidth += 16; // Статус
      if (showEditedMark) timeStatusReservedWidth += 20; // изм.
      timeStatusReservedWidth += 5; // Общие отступы (2+3)
      timeStampHorizontalPadding = 3.0;
    } else { // Чужие сообщения
      timeStatusReservedWidth += 30; // Время
      if (showEditedMark) timeStatusReservedWidth += 20; // изм.
      timeStatusReservedWidth += 2; // Общий отступ
      timeStampHorizontalPadding = 0; // Для чужих нет дополнительного отступа
    }
    timeStatusReservedWidth = timeStatusReservedWidth.clamp(32.0, 70.0);


    Widget mainContentColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!byMe && isFirstInGroup)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              message.sender.login,
              style: theme.textTheme.titleSmall?.copyWith(
                color: message.sender.displayAccentColor ?? colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        if (message.isReply) replyContentWidget,
        Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                // Отступ справа, чтобы текст не залезал под время/статус
                right: showStatusAndTime ? timeStatusReservedWidth : 0.0,
                // Добавляем небольшой отступ снизу, если время/статус будут на новой строке
                // Это нужно, чтобы текст и время/статус не были слишком близко по вертикали
                bottom: showStatusAndTime ? 4.0 : 0.0,
              ),
              child: MarkdownBody(
                data: message.text,
                selectable: true,
                styleSheet: mainMarkdownStyleSheet,
              ),
            ),
            if (showStatusAndTime) // Показываем блок времени/статуса только если нужно
              Positioned(
                bottom: 0,
                right: 0,
                child: Padding( // Добавляем небольшой отступ для всего блока времени/статуса
                  padding: EdgeInsets.only(left: timeStampHorizontalPadding),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (message.isEdited)
                        Padding(
                          padding: const EdgeInsets.only(right: 2.0),
                          child: Text(
                            "изм.",
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9.5,
                              fontStyle: FontStyle.italic,
                              color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.6) : colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ),
                      Text(
                        DateFormat('HH:mm').format(message.timestamp.toLocal()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.7) : colorScheme.onSurfaceVariant.withOpacity(0.8),
                        ),
                      ),
                      if (byMe) ...[
                        const SizedBox(width: 3),
                        Icon(
                          message.status == MessageStatus.read ? Icons.done_all_rounded : Icons.check_rounded,
                          size: 14,
                          color: message.status == MessageStatus.read
                              ? colorScheme.secondary
                              : colorScheme.onPrimaryContainer.withOpacity(0.6),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );


    Widget bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0, bottom: 6.0),
      decoration: BoxDecoration(
        color: message.isHighlighted
            ? (byMe ? colorScheme.primaryContainer.withOpacity(0.7) : colorScheme.secondaryContainer.withOpacity(0.5) )
            : (byMe ? colorScheme.primaryContainer : (theme.brightness == Brightness.light ? Colors.white : colorScheme.surfaceVariant)),
        borderRadius: messageBorderRadius,
        boxShadow: !byMe || theme.brightness == Brightness.light ? [
          BoxShadow(
            color: theme.shadowColor.withOpacity(theme.brightness == Brightness.light ? 0.08 : 0.15),
            blurRadius: 5,
            offset: const Offset(1, 2),
          )
        ] : null,
        border: message.isHighlighted
            ? Border.all(color: colorScheme.secondary, width: 1.5)
            : null,
      ),
      child: mainContentColumn,
    );

    return ContextMenuRegion(
      contextMenu: GenericContextMenu(
        buttonConfigs: _getContextMenuButtonConfigs(context),
      ),
      child: Row(
        mainAxisAlignment: byMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!byMe && isLastInGroup)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: UserAvatar.fromUserLite(user: message.sender, radius: 16),
            ),
          if (!byMe && !isLastInGroup)
            SizedBox(width: avatarSpace),

          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              margin: EdgeInsets.only(
                top: isFirstInGroup ? 8.0 : 2.0,
                bottom: 2.0,
                left: byMe ? MediaQuery.of(context).size.width * 0.1 - avatarSpace : 0,
              ),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}