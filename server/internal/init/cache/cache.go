package cache

import (
	"context"
	"errors"
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

	client := redis.NewClient(&redis.Options{
		Addr:     cfg.Address,
		DB:       cfg.Db,
		Password: os.Getenv("REDIS_PASSWORD"),
	})

	if _, err := client.Ping(context.Background()).Result(); err != nil {
		return nil, errors.New(os.Getenv("REDIS_PASSWORD"))
	}

	return &Cache{client, cfg.StateExpiration, cfg.EmailConfirmedCodeExpiration}, nil
}
