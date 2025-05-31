package cache

import (
	"context"
	"fmt" // Изменено с errors на fmt для лучшего сообщения об ошибке
	"github.com/go-redis/redis/v8"
	"os"
	"server/config"
	"time"
)

type Cache struct {
	Client                       *redis.Client
	StateExpiration              time.Duration
	EmailConfirmedCodeExpiration time.Duration
}

func NewCache(cfg config.CacheConfig) (*Cache, error) {
	redisPassword := os.Getenv("REDIS_PASSWORD") // Получаем пароль из .env

	client := redis.NewClient(&redis.Options{
		Addr: cfg.Address,
		DB:   cfg.Db,
		// Password: redisPassword, // Раскомментируй, если используешь пароль для Redis
	})

	// Проверка соединения с Redis
	if _, err := client.Ping(context.Background()).Result(); err != nil {
		// Более информативное сообщение об ошибке
		errorMessage := fmt.Sprintf("failed to connect to Redis at %s", cfg.Address)
		if redisPassword != "" {
			// Не выводим сам пароль в лог, но указываем, что он был использован
			errorMessage += " (with password)"
		}
		errorMessage += fmt.Sprintf(": %v", err)
		return nil, fmt.Errorf(errorMessage)
	}
	fmt.Println("Successfully connected to Redis!")

	return &Cache{Client: client, StateExpiration: cfg.StateExpiration, EmailConfirmedCodeExpiration: cfg.EmailConfirmedCodeExpiration}, nil
}
