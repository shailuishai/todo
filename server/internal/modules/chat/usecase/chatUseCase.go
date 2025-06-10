// internal/modules/chat/usecase/chatUseCase.go
package usecase

import (
	"context"
	"fmt"
	"log/slog"
	"server/internal/modules/chat"
	"server/internal/modules/user/profile"
	"time"
)

type chatUseCase struct {
	chatRepo           chat.Repo
	teamService        chat.TeamChecker
	userProfileService chat.UserInfoProvider
	log                *slog.Logger
}

func NewUseCase(
	log *slog.Logger,
	chatRepo chat.Repo,
	teamService chat.TeamChecker,
	userProfileService chat.UserInfoProvider,
) chat.UseCase {
	return &chatUseCase{
		log:                log,
		chatRepo:           chatRepo,
		teamService:        teamService,
		userProfileService: userProfileService,
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
	//op := "chatUseCase.HandleDeleteMessage"
	//log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("messageID", uint64(messageID)))

	existingMsg, err := uc.chatRepo.GetMessageByID(ctx, messageID)
	if err != nil {
		return nil, err
	}

	if existingMsg.SenderUserID != userID {
		// TODO: Add role check for admins/owners to delete others' messages
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
	//op := "chatUseCase.HandleMarkAsRead"
	//log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), "count", len(messageIDs))

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
	//op := "chatUseCase.GetMessagesForHistory"
	//log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("teamID", uint64(params.TeamID)))

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
