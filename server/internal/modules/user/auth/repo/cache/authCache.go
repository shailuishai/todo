package cache

import (
	"context"
	"server/internal/init/cache"
	"server/internal/modules/user"
)

type AuthCache struct {
	ch *cache.Cache
}

func NewAuthCache(ch *cache.Cache) *AuthCache {
	return &AuthCache{
		ch: ch,
	}
}

func (c *AuthCache) SaveStateCode(state string) error {
	if err := c.ch.Client.Set(context.Background(), state, "true", c.ch.StateExpiration).Err(); err != nil {
		return user.ErrInternal
	}
	return nil
}

func (c *AuthCache) VerifyStateCode(state string) (bool, error) {
	state, err := c.ch.Client.Get(context.Background(), state).Result()
	if err != nil {
		return false, user.ErrInvalidState
	}

	if state == "true" {
		if err := c.ch.Client.Del(context.Background(), state).Err(); err != nil {
			return false, user.ErrInternal
		}
		return true, nil
	}

	return false, nil
}
