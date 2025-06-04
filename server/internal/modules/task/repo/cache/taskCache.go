package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/go-redis/redis/v8"
	"log/slog"
	"server/config"
	"server/internal/init/cache"
	"server/internal/modules/task"
)

// TaskCache реализует интерфейс repo.TaskCache
type TaskCache struct {
	rdb    *redis.Client // Клиент Redis из вашего Cache
	log    *slog.Logger
	ttlCfg config.CacheConfig // Стандартное время жизни для кэша задач
}

// NewTaskCache создает новый экземпляр TaskCache.
func NewTaskCache(appCache *cache.Cache, log *slog.Logger, ttlCfg config.CacheConfig) *TaskCache {
	return &TaskCache{
		rdb:    appCache.Client, // Используем непосредственно redis.Client
		log:    log,
		ttlCfg: ttlCfg,
	}
}

func (c *TaskCache) taskKey(taskID uint) string {
	return fmt.Sprintf("task:%d", taskID)
}

// GetTask получает задачу из кэша.
func (c *TaskCache) GetTask(taskID uint) (*task.Task, error) {
	op := "TaskCache.GetTask"
	key := c.taskKey(taskID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("task not found in cache")
			return nil, task.ErrTaskNotFound // Используем общую ошибку "не найдено" для кэша тоже
		}
		log.Error("failed to get task from cache", "error", err)
		return nil, task.ErrTaskInternal
	}

	var taskModel task.Task
	if err := json.Unmarshal(val, &taskModel); err != nil {
		log.Error("failed to unmarshal task from cache", "error", err)
		// Если не удалось десериализовать, лучше удалить ключ, чтобы не получать ошибку постоянно
		_ = c.rdb.Del(context.Background(), key)
		return nil, task.ErrTaskInternal
	}

	log.Debug("task retrieved from cache")
	return &taskModel, nil
}

// SaveTask сохраняет задачу в кэш.
func (c *TaskCache) SaveTask(taskModel *task.Task) error {
	op := "TaskCache.SaveTask"
	key := c.taskKey(taskModel.TaskID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := json.Marshal(taskModel)
	if err != nil {
		log.Error("failed to marshal task for cache", "error", err)
		return task.ErrTaskInternal
	}

	if err := c.rdb.Set(context.Background(), key, val, c.ttlCfg.DefaultTaskCacheTtl).Err(); err != nil {
		log.Error("failed to save task to cache", "error", err)
		return task.ErrTaskInternal
	}

	log.Debug("task saved to cache")
	return nil
}

// DeleteTaskCache удаляет задачу из кэша.
func (c *TaskCache) DeleteTaskCache(taskID uint) error {
	op := "TaskCache.DeleteTaskCache"
	key := c.taskKey(taskID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		// Ошибка удаления из кэша может быть не критичной для основной операции,
		// но ее нужно залогировать.
		log.Error("failed to delete task from cache", "error", err)
		// Не возвращаем ошибку, чтобы не прерывать основной поток, если инвалидация не удалась.
		// return usermodels.ErrInternal // Если нужна строгая обработка
	} else {
		log.Debug("task deleted from cache")
	}
	return nil
}

// GetTasksCache получает список задач из кэша по произвольному ключу.
// cacheKey должен быть уникальным для набора параметров фильтрации.
func (c *TaskCache) GetTasksCache(cacheKey string) ([]*task.Task, error) {
	op := "TaskCache.GetTasksCache"
	log := c.log.With(slog.String("op", op), slog.String("cacheKey", cacheKey))

	val, err := c.rdb.Get(context.Background(), cacheKey).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("tasks list not found in cache")
			return nil, task.ErrTaskInternal
		}
		log.Error("failed to get tasks list from cache", "error", err)
		return nil, task.ErrTaskInternal
	}

	var tasks []*task.Task
	if err := json.Unmarshal(val, &tasks); err != nil {
		log.Error("failed to unmarshal tasks list from cache", "error", err)
		_ = c.rdb.Del(context.Background(), cacheKey)
		return nil, task.ErrTaskInternal
	}

	log.Debug("tasks list retrieved from cache", slog.Int("count", len(tasks)))
	return tasks, nil
}

// SaveTasks сохраняет список задач в кэш.
func (c *TaskCache) SaveTasks(cacheKey string, tasks []*task.Task) error {
	op := "TaskCache.SaveTasks"
	log := c.log.With(slog.String("op", op), slog.String("cacheKey", cacheKey))

	if len(tasks) == 0 {
		// Можно кэшировать пустой результат, чтобы избежать повторных запросов к БД,
		// если известно, что по таким фильтрам задач нет.
		// Но TTL для такого кэша должен быть короче.
		// Пока что не будем кэшировать пустые списки через этот общий метод.
		// log.Debug("attempted to save empty tasks list to cache, skipping")
		// return nil
	}

	val, err := json.Marshal(tasks)
	if err != nil {
		log.Error("failed to marshal tasks list for cache", "error", err)
		return task.ErrTaskInternal
	}

	// Используем тот же TTL, что и для отдельных задач, или можно другой
	if err := c.rdb.Set(context.Background(), cacheKey, val, c.ttlCfg.DefaultTaskCacheTtl).Err(); err != nil {
		log.Error("failed to save tasks list to cache", "error", err)
		return task.ErrTaskInternal
	}

	log.Debug("tasks list saved to cache", slog.Int("count", len(tasks)))
	return nil
}

// InvalidateTasks удаляет ключи из кэша.
// Это может быть использовано для более гранулярной инвалидации, если UseCase формирует правильные ключи.
func (c *TaskCache) InvalidateTasks(keys ...string) error {
	op := "TaskCache.InvalidateTasks"
	if len(keys) == 0 {
		return nil
	}
	log := c.log.With(slog.String("op", op), slog.Any("keys_to_invalidate", keys))

	// Удаляем ключи пачкой, если их много, или по одному
	// pipeline := c.rdb.Pipeline()
	// for _, key := range keys {
	// 	pipeline.Del(context.Background(), key)
	// }
	// _, err := pipeline.Exec(context.Background())

	// Проще:
	deletedCount, err := c.rdb.Del(context.Background(), keys...).Result()

	if err != nil {
		log.Error("failed to invalidate task keys in cache", "error", err)
		// Опять же, не критично, если инвалидация не удалась, но нужно логировать.
		// return usermodels.ErrInternal
	} else {
		log.Debug("task keys invalidated in cache", slog.Int64("deleted_count", deletedCount))
	}
	return nil
}
