package fcm

import (
	"context"
	"errors"
	"fmt" // Добавлен для fmt.Errorf
	"log/slog"
	"server/config"

	firebase "firebase.google.com/go/v4"  // Основной пакет Firebase
	"firebase.google.com/go/v4/messaging" // Пакет для Cloud Messaging
	"google.golang.org/api/option"        // Пакет для опций клиента, включая аутентификацию

	"server/pkg/lib/pushsender" // Наш интерфейс
)

// FCMSender реализует интерфейс pushsender.Sender для Firebase Cloud Messaging.
type FCMSender struct {
	client *messaging.Client // Клиент Firebase Cloud Messaging
	log    *slog.Logger
}

// NewFCMSender создает новый FCMSender.
// serviceAccountKeyJSON: содержимое JSON файла ключа сервис-аккаунта Firebase.
// projectID: ID вашего Firebase проекта.
// Если serviceAccountKeyJSON пустой, будет попытка использовать Google Application Default Credentials (ADC).
// В этом случае projectID может быть не нужен, если ADC могут его определить, но лучше указать.
func NewFCMSender(ctx context.Context, config config.FCMConfig, logger *slog.Logger) (*FCMSender, error) {
	log := logger.With(slog.String("component", "FCMSender"))

	opt := option.WithCredentialsFile(config.ServiceAccountKeyJSONPath)
	fbConfig := &firebase.Config{ProjectID: config.ProjectID}

	app, err := firebase.NewApp(ctx, fbConfig, opt) // Передаем слайс опций

	if err != nil {
		log.Error("Error initializing Firebase App for FCM", "error", err, "projectID", config.ProjectID)
		return nil, fmt.Errorf("initializing Firebase App: %w", err)
	}

	messagingClient, err := app.Messaging(ctx)
	if err != nil {
		log.Error("Error getting Firebase Messaging client", "error", err)
		return nil, fmt.Errorf("getting Firebase Messaging client: %w", err)
	}

	log.Info("FCMSender initialized successfully")
	return &FCMSender{
		client: messagingClient,
		log:    log,
	}, nil
}

// Send отправляет Push-сообщение через FCM.
func (s *FCMSender) Send(ctx context.Context, msg pushsender.PushMessage) (*pushsender.SendResult, error) {
	op := "FCMSender.Send"
	log := s.log.With(slog.String("op", op))

	if len(msg.Tokens) == 0 {
		log.Warn("No device tokens provided for sending push notification")
		return &pushsender.SendResult{}, nil
	}

	fcmNotification := &messaging.Notification{
		Title: msg.Title,
		Body:  msg.Body,
	}
	if msg.ImageURL != nil && *msg.ImageURL != "" {
		fcmNotification.ImageURL = *msg.ImageURL
	}

	// Создаем сообщение для SendEachForMulticast, чтобы получить индивидуальные результаты для каждого токена
	// Однако, SendMulticast возвращает BatchResponse, который тоже содержит индивидуальные результаты.
	// SendMulticast проще в использовании для одной и той же нотификации на много токенов.
	fcmMessage := &messaging.MulticastMessage{
		Notification: fcmNotification,
		Data:         msg.Data,
		Tokens:       msg.Tokens,
		// Пример настройки для Android (можно вынести в конфигурацию или передавать в PushMessage)
		Android: &messaging.AndroidConfig{
			Priority: "high", // "normal" или "high"
			Notification: &messaging.AndroidNotification{
				Sound: "default", // Использовать звук по умолчанию на устройстве
				// Icon: "ic_notification", // Имя ресурса иконки в drawable
				// Color: "#FF0000", // Цвет иконки
			},
		},
		// Пример настройки для APNS (iOS)
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Sound: "default", // Звук по умолчанию
					// Badge: messaging.Int(1), // Число на иконке приложения (если нужно)
					// MutableContent: true, // Для Service Extensions
				},
			},
		},
		// WebpushConfig, если поддерживается веб-пуши
		// Webpush: &messaging.WebpushConfig{
		//  Notification: &messaging.WebpushNotification{ ... }
		// },
	}

	br, err := s.client.SendMulticast(ctx, fcmMessage)
	if err != nil {
		log.Error("Error sending multicast message via FCM", "error", err)
		// Возвращаем результат с количеством ошибок, равным количеству токенов
		return &pushsender.SendResult{FailureCount: len(msg.Tokens), FailedTokens: msg.Tokens}, fmt.Errorf("fcm send multicast: %w", err)
	}

	result := &pushsender.SendResult{
		SuccessCount: br.SuccessCount,
		FailureCount: br.FailureCount,
	}

	if br.FailureCount > 0 {
		log.Warn("Some messages failed to send via FCM", "success_count", br.SuccessCount, "failure_count", br.FailureCount)
		for idx, resp := range br.Responses {
			if !resp.Success && idx < len(msg.Tokens) { // Проверка на выход за пределы слайса msg.Tokens
				failedToken := msg.Tokens[idx]
				result.FailedTokens = append(result.FailedTokens, failedToken)
				// resp.Error может быть nil, если Success false по другой причине, но обычно он есть
				var errMsg string
				if resp.Error != nil {
					errMsg = resp.Error.Error()
				} else {
					errMsg = "unknown FCM send error"
				}
				log.Warn("FCM send failure details",
					// Не логируем сам токен "token", failedToken,
					slog.String("error_code", errMsg),         // Код ошибки от FCM
					slog.String("message_id", resp.MessageID), // ID, если FCM его присвоил
				)
			}
		}
	}

	if br.SuccessCount > 0 {
		log.Info("FCM multicast message processing summary", "success_count", br.SuccessCount, "failure_count", br.FailureCount)
	}
	return result, nil
}

// Ping проверяет базовую конфигурацию и возможность инициализации клиента.
// Не отправляет реальное сообщение, чтобы избежать зависимости от фейковых токенов.
func (s *FCMSender) Ping(ctx context.Context) error {
	op := "FCMSender.Ping"
	log := s.log.With(slog.String("op", op))

	// Простая проверка: если s.client не nil, значит NewFCMSender отработал успешно.
	if s.client == nil {
		log.Error("FCM client is not initialized.")
		return errors.New("FCM client not initialized, check NewFCMSender logs for errors")
	}

	// Можно попытаться сделать очень легкий вызов, если такой существует,
	// но обычно проверка при инициализации достаточна для "пинга".
	// Например, SendMulticast с DryRun = true и пустым списком токенов (если API это позволяет без ошибки).
	// _, err := s.client.SendMulticast(ctx, &messaging.MulticastMessage{Tokens: []string{}, DryRun: true})
	// if err != nil {
	//    log.Error("FCM Ping (dry run) failed", "error", err)
	//    return fmt.Errorf("FCM ping (dry run) failed: %w", err)
	// }

	log.Info("FCM Ping check successful (client initialized).")
	return nil
}
