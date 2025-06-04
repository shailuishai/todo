package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"server/internal/init/cache" // Ваш пакет инициализации кэша
	"server/internal/modules/tag"
	usermodels "server/internal/modules/user" // Для общих ошибок (ErrNotFound, ErrInternal)
	"time"

	"github.com/go-redis/redis/v8"
)

// TagCache реализует интерфейс repo.TagCache
type TagCache struct {
	rdb     *redis.Client
	log     *slog.Logger
	listTTL time.Duration // TTL для списков тегов
}

// NewTagCache создает новый экземпляр TagCache.
func NewTagCache(appCache *cache.Cache, log *slog.Logger, listTTL time.Duration) *TagCache {
	if listTTL == 0 {
		listTTL = 10 * time.Minute // TTL по умолчанию для списков тегов
	}
	return &TagCache{
		rdb:     appCache.Client,
		log:     log,
		listTTL: listTTL,
	}
}

// --- Ключи кэша ---
func userTagsKey(ownerUserID uint) string {
	return fmt.Sprintf("user:%d:tags", ownerUserID)
}

func teamTagsKey(teamID uint) string {
	return fmt.Sprintf("team:%d:tags", teamID)
}

// --- User Tags Cache ---

func (c *TagCache) GetUserTags(ownerUserID uint) ([]*tag.UserTag, error) {
	op := "TagCache.GetUserTags"
	key := userTagsKey(ownerUserID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("user tags not found in cache")
			return nil, tag.ErrTagNotFound // Используем специфичную ошибку, чтобы repo.Get мог отличить от ошибки Redis
		}
		log.Error("failed to get user tags from cache", "error", err)
		return nil, usermodels.ErrInternal // Общая внутренняя
	}

	var tags []*tag.UserTag
	if err := json.Unmarshal(val, &tags); err != nil {
		log.Error("failed to unmarshal user tags from cache", "error", err)
		_ = c.rdb.Del(context.Background(), key) // Удаляем поврежденные данные
		return nil, usermodels.ErrInternal
	}
	log.Debug("user tags retrieved from cache", slog.Int("count", len(tags)))
	return tags, nil
}

func (c *TagCache) SaveUserTags(ownerUserID uint, tags []*tag.UserTag) error {
	op := "TagCache.SaveUserTags"
	key := userTagsKey(ownerUserID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	// Можно кэшировать пустой список, чтобы избежать повторных запросов к БД
	// if len(tags) == 0 { log.Debug("saving empty user tags list to cache"); }

	val, err := json.Marshal(tags)
	if err != nil {
		log.Error("failed to marshal user tags for cache", "error", err)
		return usermodels.ErrInternal
	}

	if err := c.rdb.Set(context.Background(), key, val, c.listTTL).Err(); err != nil {
		log.Error("failed to save user tags to cache", "error", err)
		return usermodels.ErrInternal
	}
	log.Debug("user tags saved to cache", slog.Int("count", len(tags)))
	return nil
}

func (c *TagCache) DeleteUserTags(ownerUserID uint) error {
	op := "TagCache.DeleteUserTags"
	key := userTagsKey(ownerUserID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		if !errors.Is(err, redis.Nil) { // Не ошибка, если ключа и так не было
			log.Error("failed to delete user tags from cache", "error", err)
		}
	} else {
		log.Debug("user tags deleted from cache")
	}
	return nil // Обычно не возвращаем ошибку при инвалидации, чтобы не прерывать основной поток
}

// --- Team Tags Cache ---

func (c *TagCache) GetTeamTags(teamID uint) ([]*tag.TeamTag, error) {
	op := "TagCache.GetTeamTags"
	key := teamTagsKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("team tags not found in cache")
			return nil, tag.ErrTagNotFound
		}
		log.Error("failed to get team tags from cache", "error", err)
		return nil, usermodels.ErrInternal
	}

	var tags []*tag.TeamTag
	if err := json.Unmarshal(val, &tags); err != nil {
		log.Error("failed to unmarshal team tags from cache", "error", err)
		_ = c.rdb.Del(context.Background(), key)
		return nil, usermodels.ErrInternal
	}
	log.Debug("team tags retrieved from cache", slog.Int("count", len(tags)))
	return tags, nil
}

func (c *TagCache) SaveTeamTags(teamID uint, tags []*tag.TeamTag) error {
	op := "TagCache.SaveTeamTags"
	key := teamTagsKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := json.Marshal(tags)
	if err != nil {
		log.Error("failed to marshal team tags for cache", "error", err)
		return usermodels.ErrInternal
	}
	if err := c.rdb.Set(context.Background(), key, val, c.listTTL).Err(); err != nil {
		log.Error("failed to save team tags to cache", "error", err)
		return usermodels.ErrInternal
	}
	log.Debug("team tags saved to cache", slog.Int("count", len(tags)))
	return nil
}

func (c *TagCache) DeleteTeamTags(teamID uint) error {
	op := "TagCache.DeleteTeamTags"
	key := teamTagsKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		if !errors.Is(err, redis.Nil) {
			log.Error("failed to delete team tags from cache", "error", err)
		}
	} else {
		log.Debug("team tags deleted from cache")
	}
	return nil
}
