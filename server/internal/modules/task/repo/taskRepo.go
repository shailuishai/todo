package repo

import (
	"context"
	"server/internal/modules/task" // Импортируем пакет task для доступа к task.Task, task.GetTasksParams, task.Repo
	"time"
)

type TaskDb interface {
	CreateTask(taskModel *task.Task) (*task.Task, error)
	GetTaskByID(taskID uint, userID uint) (*task.Task, error)
	GetTaskByIDIncludingDeleted(taskID uint) (*task.Task, error) // <<< ДОБАВЛЕНО
	GetTasks(params task.GetTasksParams) ([]*task.Task, error)   // Без totalCount
	UpdateTask(taskModel *task.Task) (*task.Task, error)
	DeleteTask(taskID uint, userID uint, isTeamTask bool, deletedByUserID *uint) error
	DeleteTaskPermanently(taskID uint) error // <<< ДОБАВЛЕНО
	GetTasksForDeadlineCheck(ctx context.Context, checkTime time.Time) ([]*task.Task, error)
	MarkDeadlineNotificationSent(ctx context.Context, taskID uint, sentTime time.Time) error
}

type TaskCache interface {
	GetTask(taskID uint) (*task.Task, error)
	SaveTask(task *task.Task) error
	DeleteTaskCache(taskID uint) error
	GetTasksCache(cacheKey string) ([]*task.Task, error)
	SaveTasks(cacheKey string, tasks []*task.Task) error
	InvalidateTasks(keys ...string) error
}

type repo struct {
	db TaskDb    // Реализация для работы с БД
	ch TaskCache // Реализация для работы с кэшем (пока не используется активно)
}

func NewRepo(db TaskDb, ch TaskCache) task.Repo {
	return &repo{
		db: db,
		ch: ch,
	}
}

// --- Реализация методов интерфейса task.Repo ---

func (r *repo) CreateTask(taskModel *task.Task) (*task.Task, error) {
	return r.db.CreateTask(taskModel)
}

func (r *repo) GetTaskByID(taskID uint, userID uint) (*task.Task, error) {
	return r.db.GetTaskByID(taskID, userID)
}

func (r *repo) GetTaskByIDIncludingDeleted(taskID uint) (*task.Task, error) {
	return r.db.GetTaskByIDIncludingDeleted(taskID)
}

func (r *repo) GetTasks(params task.GetTasksParams) ([]*task.Task, error) {
	return r.db.GetTasks(params)
}

func (r *repo) UpdateTask(taskModel *task.Task) (*task.Task, error) {
	return r.db.UpdateTask(taskModel)
}

func (r *repo) DeleteTask(taskID uint, userID uint, isTeamTask bool, deletedByUserID *uint) error {
	return r.db.DeleteTask(taskID, userID, isTeamTask, deletedByUserID)
}

func (r *repo) DeleteTaskPermanently(taskID uint) error {
	return r.db.DeleteTaskPermanently(taskID)
}

func (r *repo) GetTasksForDeadlineCheck(ctx context.Context, checkTime time.Time) ([]*task.Task, error) {
	return r.db.GetTasksForDeadlineCheck(ctx, checkTime)
}

func (r *repo) MarkDeadlineNotificationSent(ctx context.Context, taskID uint, sentTime time.Time) error {
	return r.db.MarkDeadlineNotificationSent(ctx, taskID, sentTime)
}

func (r *repo) GetTask(taskID uint) (*task.Task, error) {
	return r.ch.GetTask(taskID)
}
func (r *repo) SaveTask(task *task.Task) error {
	return r.ch.SaveTask(task)
}
func (r *repo) DeleteTaskCache(taskID uint) error {
	return r.ch.DeleteTaskCache(taskID)
}
func (r *repo) GetTasksCache(cacheKey string) ([]*task.Task, error) {
	return r.ch.GetTasksCache(cacheKey)
}
func (r *repo) SaveTasks(cacheKey string, tasks []*task.Task) error {
	return r.ch.SaveTasks(cacheKey, tasks)
}
func (r *repo) InvalidateTasks(keys ...string) error {
	return r.ch.InvalidateTasks(keys...)
}
