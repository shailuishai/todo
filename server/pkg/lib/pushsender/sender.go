package pushsender

import (
	"context"
)

// PushMessage содержит информацию для отправки одного Push-уведомления.
type PushMessage struct {
	Title    string            // Заголовок уведомления
	Body     string            // Текст уведомления
	Tokens   []string          // Список токенов устройств для отправки (может быть один)
	Data     map[string]string // Дополнительные данные (payload) для deep-linking или обработки на клиенте
	ImageURL *string           // URL изображения для уведомления (опционально)
	// Можно добавить другие поля, если нужны: Badge, Sound, Priority, TTL и т.д.
}

// SendResult содержит информацию о результатах отправки.
type SendResult struct {
	SuccessCount int      // Количество успешно отправленных сообщений
	FailureCount int      // Количество неуспешно отправленных сообщений
	FailedTokens []string // Список токенов, на которые не удалось отправить (из-за недействительности токена и т.д.)
	// Можно добавить поле с ошибками для каждого FailedToken, если это предоставляет провайдер
}

// Sender определяет интерфейс для отправки Push-уведомлений.
type Sender interface {
	// Send отправляет Push-сообщение на указанные токены.
	// Возвращает результат отправки и ошибку, если произошла критическая ошибка при взаимодействии с сервисом Push.
	Send(ctx context.Context, msg PushMessage) (*SendResult, error)
	// Ping проверяет доступность и конфигурацию сервиса отправки.
	Ping(ctx context.Context) error
}
