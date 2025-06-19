// internal/modules/chat/entity.go
package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"server/internal/modules/team"
	"server/internal/modules/user/profile"
	"time"
)

// --- GORM Модели (без изменений) ---
type ChatMessage struct {
	MessageID        uint       `gorm:"primaryKey;column:message_id;autoIncrement"`
	TeamID           uint       `gorm:"column:team_id;not null"`
	SenderUserID     uint       `gorm:"column:sender_user_id;not null"`
	Content          string     `gorm:"column:content;type:text;not null"`
	ReplyToMessageID *uint      `gorm:"column:reply_to_message_id"`
	SentAt           time.Time  `gorm:"column:sent_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt        time.Time  `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
	EditedAt         *time.Time `gorm:"column:edited_at"`
	IsDeleted        bool       `gorm:"column:is_deleted;default:false;not null"`
}

func (ChatMessage) TableName() string {
	return "chatmessages"
}

type MessageReadReceipt struct {
	MessageID uint      `gorm:"primaryKey;column:message_id"`
	UserID    uint      `gorm:"primaryKey;column:user_id"`
	ReadAt    time.Time `gorm:"column:read_at;not null;default:CURRENT_TIMESTAMP"`
}

func (MessageReadReceipt) TableName() string {
	return "messagereadreceipts"
}

// --- DTO для ответов API и WebSocket ---
type UserLiteResponse struct {
	UserID      uint    `json:"userId"`
	Login       string  `json:"login"`
	AccentColor *string `json:"accentColor,omitempty"`
	AvatarURL   *string `json:"avatarUrl,omitempty"`
}

type ChatMessageResponse struct {
	ID               string            `json:"id"`
	TeamID           uint              `json:"teamId"`
	Text             string            `json:"text"`
	Sender           UserLiteResponse  `json:"sender"`
	Timestamp        time.Time         `json:"timestamp"`
	IsCurrentUser    bool              `json:"isCurrentUser"`
	Status           string            `json:"status"`
	ReplyToMessageID *string           `json:"replyToMessageId,omitempty"`
	ReplyToText      *string           `json:"replyToText,omitempty"`
	ReplyToSender    *UserLiteResponse `json:"replyToSender,omitempty"`
	EditedAt         *time.Time        `json:"editedAt,omitempty"`
	ClientMessageID  *string           `json:"clientMessageId,omitempty"`
}

func ToChatMessageResponse(
	msg *ChatMessage,
	currentUserID uint,
	senderProfile *profile.UserProfileResponse,
	repliedToMsg *ChatMessage,
	repliedToSenderProfile *profile.UserProfileResponse,
	clientMsgID *string,
) *ChatMessageResponse {
	if msg == nil {
		return nil
	}

	var sender UserLiteResponse
	if senderProfile != nil {
		sender = UserLiteResponse{
			UserID:      senderProfile.UserID,
			Login:       senderProfile.Login,
			AccentColor: &senderProfile.AccentColor,
			AvatarURL:   senderProfile.AvatarURL,
		}
	} else {
		sender = UserLiteResponse{UserID: msg.SenderUserID, Login: "Unknown User"}
	}

	resp := &ChatMessageResponse{
		ID:              fmt.Sprintf("%d", msg.MessageID),
		TeamID:          msg.TeamID,
		Text:            msg.Content,
		Timestamp:       msg.SentAt,
		IsCurrentUser:   msg.SenderUserID == currentUserID,
		Status:          "sent",
		EditedAt:        msg.EditedAt,
		Sender:          sender,
		ClientMessageID: clientMsgID,
	}

	if msg.ReplyToMessageID != nil && repliedToMsg != nil {
		replyIDStr := fmt.Sprintf("%d", *msg.ReplyToMessageID)
		resp.ReplyToMessageID = &replyIDStr
		resp.ReplyToText = &repliedToMsg.Content
		if repliedToSenderProfile != nil {
			resp.ReplyToSender = &UserLiteResponse{
				UserID:      repliedToSenderProfile.UserID,
				Login:       repliedToSenderProfile.Login,
				AccentColor: &repliedToSenderProfile.AccentColor,
				AvatarURL:   repliedToSenderProfile.AvatarURL,
			}
		} else {
			resp.ReplyToSender = &UserLiteResponse{UserID: repliedToMsg.SenderUserID, Login: "Unknown User"}
		}
	}

	return resp
}

// --- WebSocket Message Structures ---
const (
	MessageTypeNewMessage          = "NEW_MESSAGE"
	MessageTypeMessageReceived     = "MESSAGE_RECEIVED"
	MessageTypeEditMessage         = "EDIT_MESSAGE"
	MessageTypeMessageEdited       = "MESSAGE_EDITED"
	MessageTypeDeleteMessage       = "DELETE_MESSAGE"
	MessageTypeMessageDeleted      = "MESSAGE_DELETED"
	MessageTypeMarkAsRead          = "MARK_AS_READ"
	MessageTypeMessageStatusUpdate = "MESSAGE_STATUS_UPDATE"
	MessageTypeError               = "ERROR"
	MessageTypeLoadHistoryRequest  = "LOAD_HISTORY_REQUEST"
	MessageTypeHistoryLoaded       = "HISTORY_LOADED"
)

type WebSocketMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type IncomingNewMessagePayload struct {
	Text             string `json:"text" validate:"required,min=1,max=4096"`
	ReplyToMessageID *uint  `json:"reply_to_message_id,omitempty"`
	ClientMessageID  string `json:"client_message_id,omitempty"`
}

type EditMessagePayload struct {
	MessageID uint   `json:"message_id" validate:"required"`
	NewText   string `json:"new_text" validate:"required,min=1,max=4096"`
}

type MessageEditedPayload struct {
	MessageID string    `json:"id"`
	TeamID    uint      `json:"teamId"`
	NewText   string    `json:"text"`
	EditedAt  time.Time `json:"editedAt"`
}

type DeleteMessagePayload struct {
	MessageID uint `json:"message_id" validate:"required"`
}

type MessageDeletedPayload struct {
	MessageID string `json:"id"`
	TeamID    uint   `json:"teamId"`
}

type MarkAsReadPayload struct {
	MessageIDs []uint `json:"message_ids" validate:"required,min=1"`
}

type MessageStatusUpdatePayload struct {
	MessageID    uint   `json:"message_id"`
	TeamID       uint   `json:"team_id"`
	Status       string `json:"status"`
	TargetUserID uint   `json:"-"`
}

type ErrorPayload struct {
	Message         string `json:"message"`
	OriginalType    string `json:"original_type,omitempty"`
	ClientMessageID string `json:"client_message_id,omitempty"`
}

type HistoryRequestPayload struct {
	BeforeMessageID *uint `json:"before_message_id,omitempty"`
	Limit           int   `json:"limit,omitempty" validate:"omitempty,min=1,max=100"`
}

type HistoryLoadedPayload struct {
	Messages []*ChatMessageResponse `json:"messages"`
	HasMore  bool                   `json:"has_more"`
	TeamID   uint                   `json:"team_id"`
}

type HTTPGetHistoryParams struct {
	TeamID          uint
	BeforeMessageID *uint
	Limit           int
}
type HTTPGetHistoryResponse struct {
	Messages []*ChatMessageResponse `json:"messages"`
	HasMore  bool                   `json:"has_more"`
}

// --- Интерфейсы ---

// ИЗМЕНЕНИЕ: Переименовываем и расширяем интерфейс
type TeamServiceProvider interface {
	IsUserMember(userID uint, teamID uint) (bool, error)
	IsUserMemberByLogin(teamID uint, userLogin string) (bool, *team.UserLiteResponse, error)
	GetTeamName(teamID uint) (string, error)
}
type UserInfoProvider interface {
	GetUser(userID uint) (*profile.UserProfileResponse, error)
}

type Controller interface {
	ServeWs(w http.ResponseWriter, r *http.Request)
	GetChatHistory(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	HandleNewMessage(ctx context.Context, userID, teamID uint, payload IncomingNewMessagePayload) (*ChatMessageResponse, error)
	HandleEditMessage(ctx context.Context, userID, teamID uint, payload EditMessagePayload) (*MessageEditedPayload, error)
	HandleDeleteMessage(ctx context.Context, userID, teamID, messageID uint) (*MessageDeletedPayload, error)
	HandleMarkAsRead(ctx context.Context, userID, teamID uint, messageIDs []uint) ([]MessageStatusUpdatePayload, error)
	GetMessagesForHistory(ctx context.Context, userID uint, params HTTPGetHistoryParams) (*HTTPGetHistoryResponse, error)
}

type Repo interface {
	CreateMessage(ctx context.Context, msg *ChatMessage) (*ChatMessage, error)
	GetMessageByID(ctx context.Context, messageID uint) (*ChatMessage, error)
	UpdateMessageText(ctx context.Context, messageID uint, newText string, editedAt time.Time) (*ChatMessage, error)
	MarkMessageAsDeleted(ctx context.Context, messageID uint) error
	GetMessagesByTeamID(ctx context.Context, teamID uint, beforeMessageID *uint, limit int) ([]*ChatMessage, error)
	MarkMessagesAsReadByReceipts(ctx context.Context, userID uint, messageIDs []uint) error
	GetMessageReadStatusForUserMap(ctx context.Context, userID uint, messageIDs []uint) (map[uint]bool, error)
}
