package TaskService

import (
	"fmt"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/task"
	u "server/internal/modules/user"
	"time"
)

type TaskService struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewTaskService(db *gorm.DB, log *slog.Logger) *TaskService {
	return &TaskService{db: db, log: log}
}

func (t *TaskService) CleanUnverifiedUsers() {
	threshold := time.Now().Add(-24 * time.Hour)
	result := t.db.Where("verified_email = ? AND create_at <= ?", false, threshold).Delete(&u.User{})
	if result.Error != nil {
		t.log.Error("error deleting unverified users", slog.String("error", result.Error.Error()))
	} else {
		t.log.Info("deleted unverified users", slog.Int64("count", result.RowsAffected))
	}
}

func (t *TaskService) CheckAndSendDeadlineNotifications() {
	op := "TaskService.CheckAndSendDeadlineNotifications"
	log := t.log.With(slog.String("op", op))
	log.Info("Starting check for deadline notifications")

	now := time.Now()

	// Ищем задачи, которые:
	// - Не удалены
	// - Не выполнены
	// - Уведомление еще не отправлено
	// - Дедлайн еще не прошел
	var tasks []task.Task
	err := t.db.Where("is_deleted = ? AND status != ? AND deadline_notification_sent_at IS NULL AND deadline IS NOT NULL AND deadline > ?",
		false, "done", now).Find(&tasks).Error

	if err != nil {
		log.Error("failed to fetch tasks for deadline check", "error", err)
		return
	}

	if len(tasks) == 0 {
		log.Info("No tasks found requiring deadline notification.")
		return
	}

	log.Info(fmt.Sprintf("Found %d tasks to check for deadline notifications", len(tasks)))
	// Здесь будет основная логика, которую мы передадим в UseCase.
	// На этом уровне сервис только инициирует процесс.
	// TODO: Вызвать метод из TaskUseCase, например, `taskUseCase.ProcessDeadlineChecks(tasks)`
}
