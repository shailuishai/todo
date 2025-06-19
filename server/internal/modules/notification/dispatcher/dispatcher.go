// internal/modules/notification/dispatcher/dispatcher.go
package dispatcher

import (
	"context"
	"fmt"
	"log/slog"
	"server/internal/modules/notification"
	gouser "server/internal/modules/user" // <<< ДОБАВЛЯЕМ ИМПОРТ
	"server/pkg/lib/pushsender"
	"time" // <<< ДОБАВЛЯЕМ ИМПОРТ
)

type NotificationDispatcher struct {
	sender           pushsender.Sender
	userInfoProvider notification.UserNotificationInfoProvider
	log              *slog.Logger
}

func New(sender pushsender.Sender, userInfoProvider notification.UserNotificationInfoProvider, log *slog.Logger) *NotificationDispatcher {
	return &NotificationDispatcher{
		sender:           sender,
		userInfoProvider: userInfoProvider,
		log:              log.With(slog.String("service", "NotificationDispatcher")),
	}
}

// Dispatch - главный метод, который запускается в отдельной горутине, чтобы не блокировать основной поток.
func (d *NotificationDispatcher) Dispatch(ctx context.Context, event notification.Event) {
	go d.processEvent(ctx, event)
}

func (d *NotificationDispatcher) processEvent(ctx context.Context, event notification.Event) {
	log := d.log.With(slog.String("op", "processEvent"), slog.String("eventType", string(event.Type)))

	switch event.Type {
	case notification.EventTaskAssigned:
		payload, ok := event.Payload.(notification.TaskAssignedEventPayload)
		if !ok {
			log.Error("invalid payload type for EventTaskAssigned")
			return
		}
		d.handleTaskAssigned(ctx, payload, log)

	case notification.EventUserMentioned:
		payload, ok := event.Payload.(notification.UserMentionedEventPayload)
		if !ok {
			log.Error("invalid payload type for EventUserMentioned")
			return
		}
		d.handleUserMentioned(ctx, payload, log)

	// ИЗМЕНЕНИЕ: Добавляем обработку нового события
	case notification.EventTaskDeadlineDue:
		payload, ok := event.Payload.(notification.TaskDeadlineEventPayload)
		if !ok {
			log.Error("invalid payload type for EventTaskDeadlineDue")
			return
		}
		d.handleTaskDeadlineDue(ctx, payload, log)

	default:
		log.Warn("unhandled event type")
	}
}

// ... (handleTaskAssigned и handleUserMentioned без изменений) ...

func (d *NotificationDispatcher) handleTaskAssigned(ctx context.Context, payload notification.TaskAssignedEventPayload, log *slog.Logger) {
	if payload.AssignerID == payload.AssigneeID {
		log.Info("Skipping notification: user assigned task to themselves", "userID", payload.AssigneeID)
		return
	}

	settings, err := d.userInfoProvider.GetUserNotificationSettings(payload.AssigneeID)
	if err != nil {
		log.Error("failed to get user notification settings", "userID", payload.AssigneeID, "error", err)
		return
	}

	if settings.PushNotificationsTasksLevel == gouser.PushTaskNotificationLevelNone {
		log.Info("Skipping push: user has disabled notifications for assigned tasks", "userID", payload.AssigneeID)
		return
	}

	tokens, err := d.userInfoProvider.GetUserDeviceTokens(payload.AssigneeID)
	if err != nil || len(tokens) == 0 {
		log.Warn("no device tokens found or failed to get them for user", "userID", payload.AssigneeID, "error", err)
		return
	}

	deviceTokenValues := make([]string, 0, len(tokens))
	for _, t := range tokens {
		deviceTokenValues = append(deviceTokenValues, t.DeviceToken)
	}

	title := "Вам назначена новая задача"
	body := fmt.Sprintf("Задача: %s", payload.TaskTitle)
	if payload.TeamName != nil {
		body = fmt.Sprintf("Задача в команде '%s': %s", *payload.TeamName, payload.TaskTitle)
	}

	pushMsg := pushsender.PushMessage{
		Title:  title,
		Body:   body,
		Tokens: deviceTokenValues,
		Data: map[string]string{
			"type":   "task_assigned",
			"taskId": fmt.Sprintf("%d", payload.TaskID),
		},
	}

	log.Info("Sending task assigned push notification", "userID", payload.AssigneeID, "taskID", payload.TaskID)
	if _, err := d.sender.Send(ctx, pushMsg); err != nil {
		log.Error("failed to send push notification", "userID", payload.AssigneeID, "error", err)
	}
}

func (d *NotificationDispatcher) handleUserMentioned(ctx context.Context, payload notification.UserMentionedEventPayload, log *slog.Logger) {
	if payload.MentionerID == payload.MentionedID {
		return
	}

	settings, err := d.userInfoProvider.GetUserNotificationSettings(payload.MentionedID)
	if err != nil {
		log.Error("failed to get user notification settings for mention", "userID", payload.MentionedID, "error", err)
		return
	}

	if !settings.PushNotificationsChatMentions {
		log.Info("Skipping push: user has disabled notifications for chat mentions", "userID", payload.MentionedID)
		return
	}

	tokens, err := d.userInfoProvider.GetUserDeviceTokens(payload.MentionedID)
	if err != nil || len(tokens) == 0 {
		log.Warn("no device tokens found or failed to get them for mention", "userID", payload.MentionedID, "error", err)
		return
	}
	deviceTokenValues := make([]string, 0, len(tokens))
	for _, t := range tokens {
		deviceTokenValues = append(deviceTokenValues, t.DeviceToken)
	}

	title := fmt.Sprintf("Вас упомянули в команде '%s'", payload.TeamName)
	body := payload.MessagePreview

	pushMsg := pushsender.PushMessage{
		Title:  title,
		Body:   body,
		Tokens: deviceTokenValues,
		Data: map[string]string{
			"type":      "chat_mention",
			"teamId":    fmt.Sprintf("%d", payload.TeamID),
			"messageId": fmt.Sprintf("%d", payload.MessageID),
		},
	}

	log.Info("Sending chat mention push notification", "userID", payload.MentionedID, "teamID", payload.TeamID)
	if _, err := d.sender.Send(ctx, pushMsg); err != nil {
		log.Error("failed to send push notification for mention", "userID", payload.MentionedID, "error", err)
	}
}

// ИЗМЕНЕНИЕ: Новый хендлер для уведомлений о дедлайне
func (d *NotificationDispatcher) handleTaskDeadlineDue(ctx context.Context, payload notification.TaskDeadlineEventPayload, log *slog.Logger) {
	// Настройки пользователя уже были проверены в TaskUseCase, здесь этого делать не нужно.
	// Нам нужно только получить токены и отправить уведомление.

	// 1. Получаем токены устройства
	tokens, err := d.userInfoProvider.GetUserDeviceTokens(payload.AssigneeID)
	if err != nil || len(tokens) == 0 {
		log.Warn("no device tokens found for deadline notification", "userID", payload.AssigneeID, "error", err)
		return
	}

	deviceTokenValues := make([]string, 0, len(tokens))
	for _, t := range tokens {
		deviceTokenValues = append(deviceTokenValues, t.DeviceToken)
	}

	// 2. Формируем сообщение
	timeLeft := time.Until(payload.Deadline)
	var timeLeftStr string
	if timeLeft.Hours() > 47 {
		timeLeftStr = fmt.Sprintf("через %d дня", int(timeLeft.Hours()/24))
	} else if timeLeft.Hours() > 23 {
		timeLeftStr = "через день"
	} else if timeLeft.Minutes() > 59 {
		timeLeftStr = "через час"
	} else {
		timeLeftStr = "скоро"
	}

	title := fmt.Sprintf("Скоро дедлайн: %s", payload.TaskTitle)
	body := fmt.Sprintf("Срок выполнения задачи истекает %s.", timeLeftStr)

	pushMsg := pushsender.PushMessage{
		Title:  title,
		Body:   body,
		Tokens: deviceTokenValues,
		Data: map[string]string{
			"type":   "task_deadline_due",
			"taskId": fmt.Sprintf("%d", payload.TaskID),
		},
	}

	// 3. Отправляем через sender
	log.Info("Sending deadline due push notification", "userID", payload.AssigneeID, "taskID", payload.TaskID)
	if _, err := d.sender.Send(ctx, pushMsg); err != nil {
		log.Error("failed to send deadline push notification", "userID", payload.AssigneeID, "error", err)
	}
}
