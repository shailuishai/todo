package cache

import (
	"context"
	"github.com/go-redis/redis/v8"
	"server/internal/init/cache"   // Твой пакет инициализации кэша
	"server/internal/modules/user" // Твой пакет с ошибками user
	// "log/slog" // Если нужно логирование внутри методов кэша
)

type EmailCache struct {
	ch *cache.Cache // Экземпляр твоего Cache из init
	// log *slog.Logger // Если нужно логирование
}

func NewEmailCache(ch *cache.Cache /*, log *slog.Logger */) *EmailCache {
	return &EmailCache{
		ch: ch,
		// log: log,
	}
}

// SaveEmailConfirmedCode сохраняет код подтверждения email в Redis.
func (c *EmailCache) SaveEmailConfirmedCode(email string, code string) error {
	// Ключом в Redis будет email, значением - код.
	// Используем EmailConfirmedCodeExpiration из конфигурации кэша.
	err := c.ch.Client.Set(context.Background(), email, code, c.ch.EmailConfirmedCodeExpiration).Err()
	if err != nil {
		// c.log.Error("failed to save email confirmation code to cache", "email", email, "error", err)
		return user.ErrInternal
	}
	// c.log.Info("email confirmation code saved to cache", "email", email)
	return nil
}

// GetEmailConfirmedCode извлекает код подтверждения email из Redis.
func (c *EmailCache) GetEmailConfirmedCode(email string) (string, error) {
	code, err := c.ch.Client.Get(context.Background(), email).Result()
	if err != nil {
		if err == redis.Nil { // Код не найден (возможно, истек или не был сохранен)
			// c.log.Warn("email confirmation code not found in cache", "email", email)
			return "", user.ErrInvalidConfirmCode // Или другая подходящая ошибка, например, ErrCodeNotFound
		}
		// c.log.Error("failed to get email confirmation code from cache", "email", email, "error", err)
		return "", user.ErrInternal
	}
	// c.log.Info("email confirmation code retrieved from cache", "email", email)
	return code, nil
}

// DeleteEmailConfirmedCode удаляет код подтверждения email из Redis.
// Обычно вызывается после успешного подтверждения или если код больше не нужен.
func (c *EmailCache) DeleteEmailConfirmedCode(email string) error {
	err := c.ch.Client.Del(context.Background(), email).Err()
	if err != nil {
		// Ошибка удаления может быть не критичной, но ее стоит залогировать.
		// В зависимости от требований, можно либо вернуть user.ErrInternal, либо просто залогировать и вернуть nil.
		// c.log.Error("failed to delete email confirmation code from cache", "email", email, "error", err)
		return user.ErrInternal // Для строгости
	}
	// c.log.Info("email confirmation code deleted from cache", "email", email)
	return nil
}
