// internal/modules/notification/entity.go
package notification

import (
	"context"
	gouser "server/internal/modules/user"
	"time"
)

// --- Типы событий ---
type EventType string

const (
	EventTaskAssigned    EventType = "TASK_ASSIGNED"
	EventUserMentioned   EventType = "USER_MENTIONED"
	EventTaskDeadlineDue EventType = "TASK_DEADLINE_DUE"
)

// --- Структуры событий ---

// Event - общая структура для всех событий, которые могут триггерить уведомление.
type Event struct {
	Type    EventType
	Payload interface{} // Данные, специфичные для каждого типа события
}

// TaskAssignedEventPayload - данные для события назначения задачи.
type TaskAssignedEventPayload struct {
	TaskID     uint
	TaskTitle  string
	AssignerID uint  // Кто назначил задачу
	AssigneeID uint  // Кому назначили задачу
	TeamID     *uint // ID команды, если это командная задача
	TeamName   *string
}

// UserMentionedEventPayload - данные для события упоминания в чате.
type UserMentionedEventPayload struct {
	MentionerID    uint // Кто упомянул
	MentionedID    uint // Кого упомянули
	TeamID         uint
	TeamName       string
	MessagePreview string // Превью сообщения для контекста
	MessageID      uint
}

type TaskDeadlineEventPayload struct {
	TaskID     uint
	TaskTitle  string
	AssigneeID uint
	Deadline   time.Time
}

// --- Интерфейсы ---

// UserNotificationInfoProvider определяет методы для получения данных, необходимых для отправки уведомления.
// Эту роль будет выполнять ProfileUseCase.
type UserNotificationInfoProvider interface {
	GetUserNotificationSettings(userID uint) (*gouser.UserSetting, error)
	GetUserDeviceTokens(userID uint) ([]gouser.UserDeviceToken, error)
	GetUserEmail(userID uint) (email string, isVerified bool, err error)
}

// Dispatcher - основной интерфейс нашего сервиса уведомлений.
type Dispatcher interface {
	Dispatch(ctx context.Context, event Event)
}
