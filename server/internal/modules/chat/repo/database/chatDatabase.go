// internal/modules/chat/repo/database/chatDatabase.go
package database

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"log/slog"
	"server/internal/modules/chat"
	"time"
)

type chatDB struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewDBRepo(db *gorm.DB, log *slog.Logger) chat.Repo {
	return &chatDB{
		db:  db,
		log: log,
	}
}

func (r *chatDB) CreateMessage(ctx context.Context, msg *chat.ChatMessage) (*chat.ChatMessage, error) {
	op := "chatDB.CreateMessage"
	log := r.log.With(slog.String("op", op))

	if err := r.db.WithContext(ctx).Create(msg).Error; err != nil {
		log.Error("failed to create message", "error", err)
		return nil, chat.ErrInternalChatService
	}
	return msg, nil
}

func (r *chatDB) GetMessageByID(ctx context.Context, messageID uint) (*chat.ChatMessage, error) {
	op := "chatDB.GetMessageByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("messageID", uint64(messageID)))
	var msg chat.ChatMessage

	if err := r.db.WithContext(ctx).Where("is_deleted = ?", false).First(&msg, messageID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("message not found")
			return nil, chat.ErrMessageNotFound
		}
		log.Error("failed to get message", "error", err)
		return nil, chat.ErrInternalChatService
	}
	return &msg, nil
}

func (r *chatDB) UpdateMessageText(ctx context.Context, messageID uint, newText string, editedAt time.Time) (*chat.ChatMessage, error) {
	op := "chatDB.UpdateMessageText"
	log := r.log.With(slog.String("op", op), slog.Uint64("messageID", uint64(messageID)))

	var msg chat.ChatMessage
	updates := map[string]interface{}{
		"content":   newText,
		"edited_at": editedAt,
	}

	result := r.db.WithContext(ctx).Model(&msg).Where("message_id = ? AND is_deleted = ?", messageID, false).Updates(updates)

	if result.Error != nil {
		log.Error("failed to update message", "error", result.Error)
		return nil, chat.ErrInternalChatService
	}
	if result.RowsAffected == 0 {
		return nil, chat.ErrMessageNotFound
	}

	if err := r.db.WithContext(ctx).First(&msg, messageID).Error; err != nil {
		return nil, chat.ErrInternalChatService
	}

	return &msg, nil
}

func (r *chatDB) MarkMessageAsDeleted(ctx context.Context, messageID uint) error {
	op := "chatDB.MarkMessageAsDeleted"
	log := r.log.With(slog.String("op", op), slog.Uint64("messageID", uint64(messageID)))

	result := r.db.WithContext(ctx).Model(&chat.ChatMessage{}).
		Where("message_id = ? AND is_deleted = ?", messageID, false).
		Update("is_deleted", true)

	if result.Error != nil {
		log.Error("failed to mark message as deleted", "error", result.Error)
		return chat.ErrInternalChatService
	}
	if result.RowsAffected == 0 {
		return chat.ErrMessageNotFound
	}
	return nil
}

func (r *chatDB) GetMessagesByTeamID(ctx context.Context, teamID uint, beforeMessageID *uint, limit int) ([]*chat.ChatMessage, error) {
	op := "chatDB.GetMessagesByTeamID"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)))
	var messages []*chat.ChatMessage

	query := r.db.WithContext(ctx).
		Where("team_id = ? AND is_deleted = ?", teamID, false).
		Order("sent_at DESC, message_id DESC").
		Limit(limit)

	if beforeMessageID != nil && *beforeMessageID > 0 {
		var cursorMsg chat.ChatMessage
		if err := r.db.WithContext(ctx).Select("sent_at").First(&cursorMsg, *beforeMessageID).Error; err == nil {
			query = query.Where("(sent_at, message_id) < (?, ?)", cursorMsg.SentAt, *beforeMessageID)
		} else {
			log.Warn("could not find cursor message for pagination", "beforeMessageID", *beforeMessageID, "error", err)
		}
	}

	if err := query.Find(&messages).Error; err != nil {
		log.Error("failed to get messages by team ID", "error", err)
		return nil, chat.ErrInternalChatService
	}

	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	log.Debug("messages retrieved", "count", len(messages))
	return messages, nil
}

func (r *chatDB) MarkMessagesAsReadByReceipts(ctx context.Context, userID uint, messageIDs []uint) error {
	op := "chatDB.MarkMessagesAsReadByReceipts"
	if len(messageIDs) == 0 {
		return nil
	}
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	var receipts []chat.MessageReadReceipt
	now := time.Now().UTC()
	for _, msgID := range messageIDs {
		receipts = append(receipts, chat.MessageReadReceipt{
			MessageID: msgID,
			UserID:    userID,
			ReadAt:    now,
		})
	}

	if err := r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&receipts).Error; err != nil {
		log.Error("failed to mark messages as read", "error", err)
		return chat.ErrInternalChatService
	}
	return nil
}

func (r *chatDB) GetMessageReadStatusForUserMap(ctx context.Context, userID uint, messageIDs []uint) (map[uint]bool, error) {
	op := "chatDB.GetMessageReadStatusForUserMap"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	if len(messageIDs) == 0 {
		return map[uint]bool{}, nil
	}

	var readMessageIDs []uint
	err := r.db.WithContext(ctx).Model(&chat.MessageReadReceipt{}).
		Where("user_id = ? AND message_id IN ?", userID, messageIDs).
		Pluck("message_id", &readMessageIDs).Error
	if err != nil {
		log.Error("failed to get read receipts", "error", err)
		return nil, chat.ErrInternalChatService
	}

	receiptsMap := make(map[uint]bool, len(messageIDs))
	for _, id := range messageIDs {
		receiptsMap[id] = false
	}
	for _, id := range readMessageIDs {
		receiptsMap[id] = true
	}
	return receiptsMap, nil
}
