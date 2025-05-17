package TaskService

import (
	"gorm.io/gorm"
	"log/slog"
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
