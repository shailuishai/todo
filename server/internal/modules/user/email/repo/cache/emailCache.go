package cache

import (
	"context"
	"server/internal/init/cache"
	u "server/internal/modules/user"
)

type EmailCache struct {
	ch *cache.Cache
}

func NewEmailCache(ch *cache.Cache) *EmailCache {
	return &EmailCache{
		ch: ch,
	}
}

func (c *EmailCache) SaveEmailConfirmedCode(email string, code string) error {
	if err := c.ch.Client.Set(context.Background(), email, code, c.ch.EmailConfirmedCodeExpiration).Err(); err != nil {
		return u.ErrInternal
	}
	return nil
}

func (c *EmailCache) GetEmailConfirmedCode(email string) (string, error) {
	code, err := c.ch.Client.Get(context.Background(), email).Result()
	if err != nil {
		return "", u.ErrInternal
	}
	return code, nil
}
