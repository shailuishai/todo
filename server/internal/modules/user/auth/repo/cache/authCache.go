package cache

import (
	"context"
	"errors"
	"github.com/go-redis/redis/v8" // Убедись, что импорт правильный
	"server/internal/init/cache"   // Твой пакет инициализации кэша
	"server/internal/modules/user" // Твой пакет с ошибками user
	"time"
)

type AuthCache struct {
	ch *cache.Cache // Экземпляр твоего Cache из init
}

func NewAuthCache(ch *cache.Cache) *AuthCache {
	return &AuthCache{
		ch: ch,
	}
}

// SaveStateCode сохраняет OAuth state в Redis.
// providerData может быть пустой строкой, если не используется.
func (c *AuthCache) SaveStateCode(state string, providerData string) error {
	// Ключ в Redis будет сам state, значением будет providerData или специальный маркер, если providerData пуст.
	// Если providerData не используется, можно просто сохранять "true", как раньше.
	// Для примера, если providerData важен:
	valueToStore := providerData
	if valueToStore == "" {
		valueToStore = "empty_provider_data_marker" // Чтобы отличить от реальных данных
	}

	err := c.ch.Client.Set(context.Background(), state, valueToStore, c.ch.StateExpiration).Err()
	if err != nil {
		// Логирование ошибки здесь может быть полезно, но UseCase должен вернуть user.ErrInternal
		return user.ErrInternal // Возвращаем стандартизированную ошибку
	}
	return nil
}

// VerifyStateCode проверяет OAuth state в Redis.
// Возвращает providerData (если был сохранен), флаг валидности и ошибку.
func (c *AuthCache) VerifyStateCode(state string) (providerData string, isValid bool, err error) {
	storedValue, redisErr := c.ch.Client.Get(context.Background(), state).Result()

	if redisErr != nil {
		if redisErr == redis.Nil { // Ключ не найден
			return "", false, user.ErrInvalidState // State не найден или истек
		}
		// Другая ошибка Redis
		return "", false, user.ErrInternal
	}

	// Если state найден, удаляем его, чтобы предотвратить повторное использование
	delErr := c.ch.Client.Del(context.Background(), state).Err()
	if delErr != nil {
		// Ошибка удаления не должна блокировать верификацию, но ее стоит залогировать
		// Можно решить, возвращать ли здесь user.ErrInternal или продолжать.
		// Для безопасности, если не можем удалить, лучше считать это проблемой.
		// Однако, это может помешать логину, если Redis временно недоступен для записи.
		// Пока что продолжим, но залогируем.
		// log.Printf("Warning: failed to delete OAuth state '%s' from cache: %v", state, delErr)
		// Если строго: return "", false, user.ErrInternal
	}

	// Возвращаем сохраненное значение. Если это был маркер, возвращаем пустую строку.
	if storedValue == "empty_provider_data_marker" {
		return "", true, nil
	}

	return storedValue, true, nil
}

func (c *AuthCache) StoreFinalizeTokens(code, tokens string) error {
	finalizeCodePrefix := "finalize_code:"
	key := finalizeCodePrefix + code
	finalizeCodeExpiration := 1 * time.Minute
	err := c.ch.Client.Set(context.Background(), key, tokens, finalizeCodeExpiration).Err()
	if err != nil {
		return user.ErrInternal
	}
	return nil
}

func (c *AuthCache) RetrieveFinalizeTokens(code string) (string, error) {
	finalizeCodePrefix := "finalize_code:"
	key := finalizeCodePrefix + code
	tokens, err := c.ch.Client.Get(context.Background(), key).Result()
	if err == redis.Nil {
		return "", errors.New("invalid or expired code")
	} else if err != nil {
		return "", user.ErrInternal
	}

	// Удаляем ключ после использования
	c.ch.Client.Del(context.Background(), key)

	return tokens, nil
}
