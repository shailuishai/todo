// lib/widgets/team/team_chat_widget.dart
import 'dart:async';
import '../../chat_provider.dart';
import '../../models/chat_model.dart';
import '../../models/team_model.dart';
import '../common/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:context_menus/context_menus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class TeamChatWidget extends StatefulWidget {
  final String teamId;

  const TeamChatWidget({
    Key? key,
    required this.teamId,
  }) : super(key: key);

  @override
  State<TeamChatWidget> createState() => _TeamChatWidgetState();
}

class _TeamChatWidgetState extends State<TeamChatWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  String? _editingMessageId;
  String _editingMessageOriginalText = '';
  ChatMessage? _replyingToMessage;
  bool get _isEditing => _editingMessageId != null;

  Timer? _highlightTimer;
  String? _highlightedMessageId;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _connectToChat();
    _scrollController.addListener(_onScroll);
  }

  void _connectToChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ChatProvider>(context, listen: false).connect(widget.teamId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TeamChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _connectToChat();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      if (chatProvider.hasMoreHistory(widget.teamId) && !chatProvider.isLoadingHistory(widget.teamId)) {
        chatProvider.fetchHistory(widget.teamId, loadMore: true);
      }
    }
  }

  void _scrollToMessageAndHighlight(GlobalKey messageKey, String messageId) {
    final context = messageKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        alignment: 0.3,
      ).then((_) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() => _highlightedMessageId = messageId);
            _highlightTimer?.cancel();
            _highlightTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _highlightedMessageId == messageId) {
                setState(() => _highlightedMessageId = null);
              }
            });
          }
        });
      });
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _cancelReplyAndEdit();
      return;
    }

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (_isEditing) {
      chatProvider.editMessage(_editingMessageId!, text);
    } else {
      chatProvider.sendMessage(text, replyToId: _replyingToMessage?.id);
    }

    _textController.clear();
    _cancelReplyAndEdit();
    if (!_showEmojiPicker) {
      _inputFocusNode.requestFocus();
    }
  }

  void _startReply(ChatMessage message) {
    _resetHighlight();
    setState(() {
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
      _editingMessageId = message.id;
      _editingMessageOriginalText = message.text;
      _replyingToMessage = null;
      _textController.text = message.text;
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
      _showEmojiPicker = false;
      _inputFocusNode.requestFocus();
    });
  }

  void _resetHighlight() {
    if (_highlightedMessageId != null) {
      setState(() => _highlightedMessageId = null);
      _highlightTimer?.cancel();
    }
  }

  void _deleteMessage(ChatMessage message) {
    _resetHighlight();
    Provider.of<ChatProvider>(context, listen: false).deleteMessage(message.id);
  }

  void _copyMessageText(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Текст сообщения скопирован.")));
  }

  void _cancelReplyAndEdit() {
    setState(() {
      _editingMessageId = null;
      _editingMessageOriginalText = '';
      _replyingToMessage = null;
      _textController.clear();
    });
  }

  void _onEmojiSelected(Emoji emoji) {
    _textController
      ..text += emoji.emoji
      ..selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
  }

  void _onBackspacePressed() {
    _textController
      ..text = _textController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
  }

  void _toggleEmojiPicker() {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_showEmojiPicker) {
      _inputFocusNode.requestFocus();
    } else {
      if (isKeyboardVisible) _inputFocusNode.unfocus();
    }
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // <<< НАЧАЛО: ИСПРАВЛЕНИЕ - ДОБАВЛЕНА ОБЕРТКА ContextMenuOverlay >>>
    return ContextMenuOverlay(
      child: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final messages = chatProvider.messagesForTeam(widget.teamId);
                final isLoading = chatProvider.isLoadingHistory(widget.teamId);
                final hasMore = chatProvider.hasMoreHistory(widget.teamId);

                if (isLoading && messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text("В этом чате пока нет сообщений.", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  );
                }
                return _buildMessagesList(context, messages, hasMore);
              },
            ),
          ),
          if (_replyingToMessage != null || _isEditing) _buildReplyOrEditHeader(context),
          _buildMessageInputField(context),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
    // <<< КОНЕЦ: ИСПРАВЛЕНИЕ >>>
  }

  Widget _buildMessagesList(BuildContext context, List<ChatMessage> messages, bool hasMore) {
    const double avatarSize = 16.0 * 2;
    const double avatarPadding = 8.0;
    final double avatarSpace = avatarSize + avatarPadding;

    return GestureDetector(
      onTap: () {
        if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
        _resetHighlight();
        FocusScope.of(context).unfocus();
      },
      child: ListView.builder(
        reverse: true,
        controller: _scrollController,
        itemCount: messages.length + (hasMore ? 1 : 0),
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          if (hasMore && index == messages.length) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
          }

          final reversedIndex = messages.length - 1 - index;
          final message = messages[reversedIndex];

          final prevMessage = (reversedIndex > 0) ? messages[reversedIndex - 1] : null;
          final nextMessage = (reversedIndex < messages.length - 1) ? messages[reversedIndex + 1] : null;

          final bool isFirstInGroup = prevMessage == null ||
              prevMessage.sender.userId != message.sender.userId ||
              message.timestamp.difference(prevMessage.timestamp).inMinutes.abs() >= 5 ||
              prevMessage.isCurrentUser != message.isCurrentUser;

          final bool isLastInGroup = nextMessage == null ||
              nextMessage.sender.userId != message.sender.userId ||
              nextMessage.timestamp.difference(message.timestamp).inMinutes.abs() >= 5 ||
              nextMessage.isCurrentUser != message.isCurrentUser;

          return ChatMessageBubble(
            key: message.messageKey,
            message: message,
            isFirstInGroup: isFirstInGroup,
            isLastInGroup: isLastInGroup,
            isHighlighted: _highlightedMessageId == message.id,
            avatarSpace: avatarSpace,
            onReply: () => _startReply(message),
            onEdit: message.isCurrentUser ? () => _startEdit(message) : null,
            onDelete: message.isCurrentUser ? () => _deleteMessage(message) : null,
            onCopy: () => _copyMessageText(message),
            onQuotedMessageTap: (replyToId) {
              try {
                final key = messages.firstWhere((m) => m.id == replyToId).messageKey;
                _scrollToMessageAndHighlight(key, replyToId);
              } catch (_) {}
            },
          );
        },
      ),
    );
  }

  Widget _buildReplyOrEditHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final messages = context.watch<ChatProvider>().messagesForTeam(widget.teamId);

    String title;
    String content;
    ChatMessage? targetMessage;

    if (_isEditing) {
      title = "Редактирование сообщения";
      content = _editingMessageOriginalText;
      try {
        targetMessage = messages.firstWhere((m) => m.id == _editingMessageId, orElse: () => _replyingToMessage!);
      } catch (e) {
        targetMessage = null;
      }
    } else if (_replyingToMessage != null) {
      title = "Ответ на ${ _replyingToMessage!.isCurrentUser ? 'ваше сообщение' : _replyingToMessage!.sender.login}";
      content = _replyingToMessage!.text;
      targetMessage = _replyingToMessage;
    } else {
      return const SizedBox.shrink();
    }

    Widget headerRow = Row(
      children: [
        Icon( _isEditing ? Icons.edit_outlined : Icons.reply_rounded, color: colorScheme.primary, size: 20, ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
              Text(content, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    if (targetMessage != null) {
      tappableHeader = InkWell(
        onTap: () => _scrollToMessageAndHighlight(targetMessage!.messageKey, targetMessage.id),
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
          left: 8.0, right: 8.0, top: 8.0,
          bottom: 8.0 + (_showEmojiPicker ? 0 : MediaQuery.of(context).viewInsets.bottom),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(_showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, color: colorScheme.onSurfaceVariant),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.0), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                ),
                onTap: () {
                  if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
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
        onEmojiSelected: (Category? category, Emoji emoji) => _onEmojiSelected(emoji),
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
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          searchViewConfig: SearchViewConfig(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            buttonIconColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool isHighlighted;
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
    required this.isHighlighted,
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
      configs.add(ContextMenuButtonConfig("Ответить", icon: const Icon(Icons.reply_rounded, size: 20), onPressed: () => onReply!()));
    }
    if (onEdit != null) {
      configs.add(ContextMenuButtonConfig("Редактировать", icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => onEdit!()));
    }
    if (onCopy != null) {
      configs.add(ContextMenuButtonConfig("Копировать текст", icon: const Icon(Icons.copy_all_rounded, size: 20), onPressed: () => onCopy!()));
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
    final replyMarkdownStyleSheet = MarkdownStyleSheet(
      p: theme.textTheme.bodySmall?.copyWith(
        color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.9) : colorScheme.onSurfaceVariant.withOpacity(0.9),
        fontSize: 13.5,
        height: 1.3,
      ),
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
      blockquoteDecoration: BoxDecoration(color: (byMe ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest).withOpacity(0.4), border: Border(left: BorderSide(color: byMe ? colorScheme.primary.withOpacity(0.7) : colorScheme.outline.withOpacity(0.7), width: 4))),
      blockquote: defaultPStyle?.copyWith(color: byMe ? colorScheme.onPrimaryContainer.withOpacity(0.85) : colorScheme.onSurface.withOpacity(0.85), fontSize: 15),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(color: (byMe ? colorScheme.primary.withOpacity(0.08) : colorScheme.surface.withOpacity(0.7)), borderRadius: BorderRadius.circular(8), border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4))),
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
    if (message.isReply) {
      replyContentWidget = InkWell(
        onTap: () {
          if (onQuotedMessageTap != null && message.replyToMessageId != null) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      message.replyToSenderLogin ?? "Unknown User",
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: byMe ? colorScheme.primary : colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.reply_rounded, size: 14, color: (byMe ? colorScheme.primary : colorScheme.secondary).withOpacity(0.7))
                ],
              ),
              const SizedBox(height: 2),
              MarkdownBody(
                data: message.replyToText!,
                styleSheet: replyMarkdownStyleSheet,
              ),
            ],
          ),
        ),
      );
    }

    final bool showEditedMark = message.isEdited;
    final bool showStatusAndTime = byMe || (!byMe && !showEditedMark) || (!byMe && showEditedMark);

    double timeStatusReservedWidth = 0;
    double timeStampHorizontalPadding = 0;
    if (byMe) { timeStatusReservedWidth = 71; timeStampHorizontalPadding = 3.0; }
    else { timeStatusReservedWidth = 52; timeStampHorizontalPadding = 0; }
    timeStatusReservedWidth = timeStatusReservedWidth.clamp(32.0, 75.0);


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
                right: showStatusAndTime ? timeStatusReservedWidth : 0.0,
                bottom: showStatusAndTime ? 4.0 : 0.0,
              ),
              child: MarkdownBody(
                data: message.text,
                selectable: true,
                styleSheet: mainMarkdownStyleSheet,
              ),
            ),
            if (showStatusAndTime)
              Positioned(
                bottom: 0,
                right: 0,
                child: Padding(
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
        color: isHighlighted
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
        border: isHighlighted
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
                left: byMe ? avatarSpace : 0,
              ),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}