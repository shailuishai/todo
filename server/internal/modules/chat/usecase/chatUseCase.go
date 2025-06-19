// internal/modules/chat/usecase/chatUseCase.go
package usecase

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"server/internal/modules/chat"
	"server/internal/modules/notification"
	"server/internal/modules/user/profile"
	"time"
)

var mentionRegex = regexp.MustCompile(`@(\w+)`)

type chatUseCase struct {
	chatRepo           chat.Repo
	teamService        chat.TeamServiceProvider // ИЗМЕНЕНИЕ: Используем новый интерфейс
	userProfileService chat.UserInfoProvider
	log                *slog.Logger
	dispatcher         notification.Dispatcher
}

func NewUseCase(
	log *slog.Logger,
	chatRepo chat.Repo,
	teamService chat.TeamServiceProvider, // ИЗМЕНЕНИЕ: Используем новый интерфейс
	userProfileService chat.UserInfoProvider,
	dispatcher notification.Dispatcher,
) chat.UseCase {
	return &chatUseCase{
		log:                log,
		chatRepo:           chatRepo,
		teamService:        teamService,
		userProfileService: userProfileService,
		dispatcher:         dispatcher,
	}
}

func (uc *chatUseCase) HandleNewMessage(ctx context.Context, userID, teamID uint, payload chat.IncomingNewMessagePayload) (*chat.ChatMessageResponse, error) {
	op := "chatUseCase.HandleNewMessage"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("teamID", uint64(teamID)))

	if isMember, err := uc.teamService.IsUserMember(userID, teamID); err != nil || !isMember {
		if err != nil {
			log.Error("Failed to check team membership", "error", err)
			return nil, chat.ErrInternalChatService
		}
		log.Warn("User not member of team")
		return nil, chat.ErrUserNotInTeamChat
	}

	chatMsgModel := &chat.ChatMessage{
		TeamID:           teamID,
		SenderUserID:     userID,
		Content:          payload.Text,
		ReplyToMessageID: payload.ReplyToMessageID,
		SentAt:           time.Now().UTC(),
	}

	savedMsg, err := uc.chatRepo.CreateMessage(ctx, chatMsgModel)
	if err != nil {
		return nil, err
	}

	// ИЗМЕНЕНИЕ: После успешного сохранения, парсим упоминания и отправляем события
	if uc.dispatcher != nil {
		uc.dispatchMentions(ctx, savedMsg)
	}

	senderProfile, _ := uc.userProfileService.GetUser(userID)

	var repliedToMsg *chat.ChatMessage
	var repliedToSenderProfile *profile.UserProfileResponse
	if savedMsg.ReplyToMessageID != nil {
		repliedToMsg, _ = uc.chatRepo.GetMessageByID(ctx, *savedMsg.ReplyToMessageID)
		if repliedToMsg != nil && !repliedToMsg.IsDeleted {
			repliedToSenderProfile, _ = uc.userProfileService.GetUser(repliedToMsg.SenderUserID)
		} else {
			repliedToMsg = nil
		}
	}

	var clientMsgIDPtr *string
	if payload.ClientMessageID != "" {
		clientMsgIDPtr = &payload.ClientMessageID
	}

	return chat.ToChatMessageResponse(savedMsg, userID, senderProfile, repliedToMsg, repliedToSenderProfile, clientMsgIDPtr), nil
}

func (uc *chatUseCase) dispatchMentions(ctx context.Context, msg *chat.ChatMessage) {
	matches := mentionRegex.FindAllStringSubmatch(msg.Content, -1)
	if len(matches) == 0 {
		return
	}

	log := uc.log.With("op", "dispatchMentions", "messageID", msg.MessageID)

	teamName, err := uc.teamService.GetTeamName(msg.TeamID)
	if err != nil {
		log.Error("could not get team name for notification", "error", err, "teamID", msg.TeamID)
		teamName = "команде" // Fallback
	}

	// Получаем профиль отправителя один раз
	mentionerProfile, err := uc.userProfileService.GetUser(msg.SenderUserID)
	if err != nil {
		log.Error("could not get mentioner profile", "error", err)
		return // Не можем продолжить без данных об отправителе
	}

	uniqueLogins := make(map[string]struct{})
	for _, match := range matches {
		if len(match) > 1 {
			login := match[1]
			// Не отправляем уведомление, если пользователь упомянул сам себя
			if login != mentionerProfile.Login {
				uniqueLogins[login] = struct{}{}
			}
		}
	}

	for login := range uniqueLogins {
		isMember, mentionedUser, err := uc.teamService.IsUserMemberByLogin(msg.TeamID, login)
		if err != nil {
			log.Error("failed to check membership by login", "login", login, "error", err)
			continue
		}

		if !isMember || mentionedUser == nil {
			log.Debug("user mentioned is not a member or not found", "login", login)
			continue
		}

		// Формируем превью сообщения
		messagePreview := fmt.Sprintf("%s: %s", mentionerProfile.Login, msg.Content)
		if len(messagePreview) > 100 { // Ограничиваем длину превью
			messagePreview = messagePreview[:97] + "..."
		}

		event := notification.Event{
			Type: notification.EventUserMentioned,
			Payload: notification.UserMentionedEventPayload{
				MentionerID:    msg.SenderUserID,
				MentionedID:    mentionedUser.UserID,
				TeamID:         msg.TeamID,
				TeamName:       teamName,
				MessagePreview: messagePreview,
				MessageID:      msg.MessageID,
			},
		}
		uc.dispatcher.Dispatch(ctx, event)
		log.Info("mention event dispatched", "mentioned_login", login, "mentioned_userID", mentionedUser.UserID)
	}
}

func (uc *chatUseCase) HandleEditMessage(ctx context.Context, userID, teamID uint, payload chat.EditMessagePayload) (*chat.MessageEditedPayload, error) {
	op := "chatUseCase.HandleEditMessage"
	log := uc.log.With(slog.String("op", op), slog.Uint64("messageID", uint64(payload.MessageID)))

	existingMsg, err := uc.chatRepo.GetMessageByID(ctx, payload.MessageID)
	if err != nil {
		return nil, err
	}

	if existingMsg.SenderUserID != userID {
		log.Warn("User is not the sender of the message to edit")
		return nil, chat.ErrCannotEditMessage
	}
	if existingMsg.TeamID != teamID {
		return nil, chat.ErrChatAccessDenied
	}
	if existingMsg.IsDeleted {
		return nil, chat.ErrMessageNotFound
	}

	editedAt := time.Now().UTC()
	updatedMsg, err := uc.chatRepo.UpdateMessageText(ctx, payload.MessageID, payload.NewText, editedAt)
	if err != nil {
		return nil, err
	}

	return &chat.MessageEditedPayload{
		MessageID: fmt.Sprintf("%d", updatedMsg.MessageID),
		TeamID:    updatedMsg.TeamID,
		NewText:   updatedMsg.Content,
		EditedAt:  *updatedMsg.EditedAt,
	}, nil
}

func (uc *chatUseCase) HandleDeleteMessage(ctx context.Context, userID, teamID, messageID uint) (*chat.MessageDeletedPayload, error) {
	existingMsg, err := uc.chatRepo.GetMessageByID(ctx, messageID)
	if err != nil {
		return nil, err
	}

	if existingMsg.SenderUserID != userID {
		return nil, chat.ErrCannotDeleteMessage
	}
	if existingMsg.TeamID != teamID {
		return nil, chat.ErrChatAccessDenied
	}

	if err = uc.chatRepo.MarkMessageAsDeleted(ctx, messageID); err != nil {
		return nil, err
	}

	return &chat.MessageDeletedPayload{
		MessageID: fmt.Sprintf("%d", messageID),
		TeamID:    teamID,
	}, nil
}

func (uc *chatUseCase) HandleMarkAsRead(ctx context.Context, userID, teamID uint, messageIDs []uint) ([]chat.MessageStatusUpdatePayload, error) {
	if len(messageIDs) == 0 {
		return nil, nil
	}

	if err := uc.chatRepo.MarkMessagesAsReadByReceipts(ctx, userID, messageIDs); err != nil {
		return nil, err
	}

	var senderUpdates []chat.MessageStatusUpdatePayload
	for _, msgID := range messageIDs {
		msg, errGet := uc.chatRepo.GetMessageByID(ctx, msgID)
		if errGet != nil || msg.IsDeleted || msg.TeamID != teamID {
			continue
		}
		if msg.SenderUserID != userID {
			senderUpdates = append(senderUpdates, chat.MessageStatusUpdatePayload{
				MessageID:    msg.MessageID,
				TeamID:       msg.TeamID,
				Status:       "read",
				TargetUserID: msg.SenderUserID,
			})
		}
	}
	return senderUpdates, nil
}

func (uc *chatUseCase) GetMessagesForHistory(ctx context.Context, userID uint, params chat.HTTPGetHistoryParams) (*chat.HTTPGetHistoryResponse, error) {
	if isMember, err := uc.teamService.IsUserMember(userID, params.TeamID); err != nil || !isMember {
		if err != nil {
			return nil, chat.ErrInternalChatService
		}
		return nil, chat.ErrUserNotInTeamChat
	}

	limit := params.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	messagesModels, err := uc.chatRepo.GetMessagesByTeamID(ctx, params.TeamID, params.BeforeMessageID, limit+1)
	if err != nil {
		return nil, err
	}

	hasMore := len(messagesModels) > limit
	if hasMore {
		messagesModels = messagesModels[:limit]
	}

	senderIDs := make(map[uint]struct{})
	repliedMsgIDs := make(map[uint]struct{})
	for _, msg := range messagesModels {
		senderIDs[msg.SenderUserID] = struct{}{}
		if msg.ReplyToMessageID != nil {
			repliedMsgIDs[*msg.ReplyToMessageID] = struct{}{}
		}
	}

	userProfiles := make(map[uint]*profile.UserProfileResponse)
	for uid := range senderIDs {
		if p, errP := uc.userProfileService.GetUser(uid); errP == nil {
			userProfiles[uid] = p
		}
	}

	repliedMsgModels := make(map[uint]*chat.ChatMessage)
	if len(repliedMsgIDs) > 0 {
		for msgID := range repliedMsgIDs {
			if rMsg, errR := uc.chatRepo.GetMessageByID(ctx, msgID); errR == nil && !rMsg.IsDeleted {
				repliedMsgModels[msgID] = rMsg
				if _, exists := userProfiles[rMsg.SenderUserID]; !exists {
					if p, errP := uc.userProfileService.GetUser(rMsg.SenderUserID); errP == nil {
						userProfiles[rMsg.SenderUserID] = p
					}
				}
			}
		}
	}

	messageIDsForReadStatus := make([]uint, len(messagesModels))
	for i, msg := range messagesModels {
		messageIDsForReadStatus[i] = msg.MessageID
	}
	readStatuses, _ := uc.chatRepo.GetMessageReadStatusForUserMap(ctx, userID, messageIDsForReadStatus)

	responseMessages := make([]*chat.ChatMessageResponse, 0, len(messagesModels))
	for _, msgModel := range messagesModels {
		var repliedToMsg *chat.ChatMessage
		var repliedToSenderProfile *profile.UserProfileResponse
		if msgModel.ReplyToMessageID != nil {
			if rMsg, ok := repliedMsgModels[*msgModel.ReplyToMessageID]; ok {
				repliedToMsg = rMsg
				repliedToSenderProfile = userProfiles[rMsg.SenderUserID]
			}
		}

		respMsg := chat.ToChatMessageResponse(msgModel, userID, userProfiles[msgModel.SenderUserID], repliedToMsg, repliedToSenderProfile, nil)
		if respMsg != nil {
			if msgModel.SenderUserID != userID {
				if read, ok := readStatuses[msgModel.MessageID]; ok && read {
					respMsg.Status = "read"
				} else {
					respMsg.Status = "delivered"
				}
			}
			responseMessages = append(responseMessages, respMsg)
		}
	}

	return &chat.HTTPGetHistoryResponse{Messages: responseMessages, HasMore: hasMore}, nil
}
