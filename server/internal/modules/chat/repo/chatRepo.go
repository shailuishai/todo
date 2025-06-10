package repo

import (
	"context"
	"server/internal/modules/chat"
	"time" // Добавлен импорт time
)

// Repo defines the interface for chat data storage operations.
type Repo interface {
	CreateMessage(ctx context.Context, msg *chat.ChatMessage) (*chat.ChatMessage, error)
	GetMessageByID(ctx context.Context, messageID uint) (*chat.ChatMessage, error)
	// <<< ИЗМЕНЕНИЕ: Сигнатура UpdateMessageText теперь включает editedAt >>>
	UpdateMessageText(ctx context.Context, messageID uint, newText string, editedAt time.Time) (*chat.ChatMessage, error)
	MarkMessageAsDeleted(ctx context.Context, messageID uint) error
	// <<< ИЗМЕНЕНИЕ: Убираем sortAsc, так как логика теперь одна >>>
	GetMessagesByTeamID(ctx context.Context, teamID uint, beforeMessageID *uint, limit int) ([]*chat.ChatMessage, error)
	MarkMessagesAsReadByReceipts(ctx context.Context, userID uint, messageIDs []uint) error
	GetMessageReadStatusForUserMap(ctx context.Context, userID uint, messageIDs []uint) (map[uint]bool, error)
}
