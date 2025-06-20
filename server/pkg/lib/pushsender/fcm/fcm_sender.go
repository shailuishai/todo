// pkg/lib/pushsender/fcm/fcm_sender.go
package fcm

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"

	"server/config"
	"server/pkg/lib/pushsender"
)

type FCMSender struct {
	client *messaging.Client
	log    *slog.Logger
}

func NewFCMSender(ctx context.Context, config config.FCMConfig, logger *slog.Logger) (*FCMSender, error) {
	log := logger.With(slog.String("component", "FCMSender"))

	// Проверяем, что хотя бы что-то для аутентификации предоставлено
	if config.ProjectID == "" && config.ServiceAccountKeyJSONPath == "" {
		log.Error("Either ProjectID (for ADC) or ServiceAccountKeyJSONPath must be provided for FCM")
		return nil, errors.New("FCM configuration error: ProjectID or ServiceAccountKeyJSONPath is missing")
	}

	var clientOpt option.ClientOption

	if config.ServiceAccountKeyJSONPath != "" {
		log.Info("Using service account key from file path for FCM authentication.", "path", config.ServiceAccountKeyJSONPath)
		clientOpt = option.WithCredentialsFile(config.ServiceAccountKeyJSONPath)
	} else {
		log.Info("Service account key path not provided, attempting to use Application Default Credentials for FCM.")
		// Для ADC опция не нужна, SDK подхватит автоматически
	}

	// ИЗМЕНЕНИЕ: Второй аргумент (firebase.Config) должен быть nil,
	// чтобы SDK использовал эндпоинты по умолчанию.
	// ProjectID будет взят из ключа сервисного аккаунта или ADC.
	app, err := firebase.NewApp(ctx, nil, clientOpt)

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

// ... (остальные методы Send и Ping без изменений)
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

	fcmMessage := &messaging.MulticastMessage{
		Notification: fcmNotification,
		Data:         msg.Data,
		Tokens:       msg.Tokens,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Sound: "default",
			},
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Sound: "default",
				},
			},
		},
	}

	br, err := s.client.SendMulticast(ctx, fcmMessage)
	if err != nil {
		log.Error("Error sending multicast message via FCM", "error", err)
		return &pushsender.SendResult{FailureCount: len(msg.Tokens), FailedTokens: msg.Tokens}, fmt.Errorf("fcm send multicast: %w", err)
	}

	result := &pushsender.SendResult{
		SuccessCount: br.SuccessCount,
		FailureCount: br.FailureCount,
	}

	if br.FailureCount > 0 {
		log.Warn("Some messages failed to send via FCM", "success_count", br.SuccessCount, "failure_count", br.FailureCount)
		for idx, resp := range br.Responses {
			if !resp.Success && idx < len(msg.Tokens) {
				failedToken := msg.Tokens[idx]
				result.FailedTokens = append(result.FailedTokens, failedToken)
				var errMsg string
				if resp.Error != nil {
					errMsg = resp.Error.Error()
				} else {
					errMsg = "unknown FCM send error"
				}
				log.Warn("FCM send failure details",
					slog.String("error_code", errMsg),
					slog.String("message_id", resp.MessageID),
				)
			}
		}
	}

	if br.SuccessCount > 0 {
		log.Info("FCM multicast message processing summary", "success_count", br.SuccessCount, "failure_count", br.FailureCount)
	}
	return result, nil
}

func (s *FCMSender) Ping(ctx context.Context) error {
	op := "FCMSender.Ping"
	log := s.log.With(slog.String("op", op))

	if s.client == nil {
		log.Error("FCM client is not initialized.")
		return errors.New("FCM client not initialized, check NewFCMSender logs for errors")
	}

	log.Info("FCM Ping check successful (client initialized).")
	return nil
}
