// internal/modules/task/repo/database/taskDatabase.go
package database

import (
	"errors"
	"fmt"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/task"
	"strings"
	"time"
)

type TaskDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewTaskDatabase(db *gorm.DB, log *slog.Logger) *TaskDatabase {
	return &TaskDatabase{
		db:  db,
		log: log,
	}
}

func (r *TaskDatabase) CreateTask(taskModel *task.Task) (*task.Task, error) {
	op := "TaskDatabase.CreateTask"
	log := r.log.With(slog.String("op", op), slog.String("title", taskModel.Title))

	if err := r.db.Create(taskModel).Error; err != nil {
		log.Error("failed to create task in DB", "error", err)
		return nil, task.ErrTaskInternal
	}

	log.Info("task created successfully in DB", slog.Uint64("taskID", uint64(taskModel.TaskID)))
	return taskModel, nil
}

func (r *TaskDatabase) GetTaskByID(taskID uint, userID uint) (*task.Task, error) {
	op := "TaskDatabase.GetTaskByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))
	var taskModel task.Task

	// Этот метод ищет только НЕ удаленные задачи
	if err := r.db.Where("is_deleted = ?", false).First(&taskModel, taskID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("active task not found by ID")
			return nil, task.ErrTaskNotFound
		}
		log.Error("failed to get active task by ID from DB", "error", err)
		return nil, task.ErrTaskInternal
	}

	log.Debug("active task found by ID")
	return &taskModel, nil
}

// GetTaskByIDIncludingDeleted ищет задачу по ID вне зависимости от флага is_deleted.
func (r *TaskDatabase) GetTaskByIDIncludingDeleted(taskID uint) (*task.Task, error) {
	op := "TaskDatabase.GetTaskByIDIncludingDeleted"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))
	var taskModel task.Task

	if err := r.db.First(&taskModel, taskID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("task not found by ID (including deleted)")
			return nil, task.ErrTaskNotFound
		}
		log.Error("failed to get task by ID from DB (including deleted)", "error", err)
		return nil, task.ErrTaskInternal
	}

	log.Debug("task found by ID (including deleted)")
	return &taskModel, nil
}

func (r *TaskDatabase) GetTasks(params task.GetTasksParams) ([]*task.Task, error) {
	op := "TaskDatabase.GetTasks"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(params.UserID)))
	var tasks []*task.Task

	query := r.db.Model(&task.Task{})

	// <<< ИЗМЕНЕНИЕ: фильтрация по is_deleted стала динамической >>>
	if params.IsDeleted != nil {
		query = query.Where("is_deleted = ?", *params.IsDeleted)
		log = log.With(slog.Bool("filter_is_deleted", *params.IsDeleted))
	} else {
		// По умолчанию всегда ищем только активные задачи
		query = query.Where("is_deleted = ?", false)
	}

	switch params.ViewType {
	case task.ViewTypeUserCentricGlobal:
		query = query.Where("(created_by_user_id = ? OR assigned_to_user_id = ?)", params.UserID, params.UserID)
		log = log.With(slog.String("filter_logic", "global_user_centric"))

	case task.ViewTypeUserPersonal:
		query = query.Where("team_id IS NULL AND (created_by_user_id = ? OR assigned_to_user_id = ?)", params.UserID, params.UserID)
		log = log.With(slog.String("filter_logic", "personal_user_centric"))

	default:
		if params.TeamID != nil {
			query = query.Where("team_id = ?", *params.TeamID)
			log = log.With(slog.Uint64("filter_teamID", uint64(*params.TeamID)))
		} else {
			// Поведение по умолчанию: личные задачи, созданные пользователем или назначенные ему
			query = query.Where("team_id IS NULL AND (created_by_user_id = ? OR assigned_to_user_id = ?)", params.UserID, params.UserID)
			log = log.With(slog.String("filter_logic", "default_personal_created_or_assigned"))
		}
	}

	if params.Status != nil && *params.Status != "" {
		query = query.Where("status = ?", *params.Status)
		log = log.With(slog.String("filter_status", *params.Status))
	}
	if params.Priority != nil {
		query = query.Where("priority = ?", *params.Priority)
		log = log.With(slog.Int("filter_priority", *params.Priority))
	}
	if params.AssignedToUserID != nil {
		query = query.Where("assigned_to_user_id = ?", *params.AssignedToUserID)
		log = log.With(slog.Uint64("filter_assigned_to_explicit", uint64(*params.AssignedToUserID)))
	}
	if params.DeadlineFrom != nil {
		query = query.Where("deadline >= ?", params.DeadlineFrom.Format(time.RFC3339))
		log = log.With(slog.String("filter_deadline_from", params.DeadlineFrom.Format(time.RFC3339)))
	}
	if params.DeadlineTo != nil {
		dateEnd := *params.DeadlineTo
		if dateEnd.Hour() == 0 && dateEnd.Minute() == 0 && dateEnd.Second() == 0 {
			dateEnd = dateEnd.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
		}
		query = query.Where("deadline <= ?", dateEnd.Format(time.RFC3339))
		log = log.With(slog.String("filter_deadline_to", dateEnd.Format(time.RFC3339)))
	}
	if params.SearchQuery != nil && *params.SearchQuery != "" {
		searchVal := "%" + strings.ToLower(*params.SearchQuery) + "%"
		query = query.Where("LOWER(title) LIKE ? OR LOWER(description) LIKE ?", searchVal, searchVal)
		log = log.With(slog.String("filter_search", *params.SearchQuery))
	}

	// <<< ИЗМЕНЕНИЕ: для удаленных сортируем по дате удаления по убыванию >>>
	orderByClause := "updated_at DESC" // Сортировка по умолчанию
	if params.IsDeleted != nil && *params.IsDeleted {
		orderByClause = "deleted_at DESC"
	} else if params.SortBy != "" {
		orderDirection := "ASC"
		if params.SortOrder == task.SortDirectionDesc {
			orderDirection = "DESC"
		}
		if params.SortBy == task.FieldDeadline {
			if orderDirection == "ASC" {
				orderByClause = fmt.Sprintf("CASE WHEN %s IS NULL THEN 1 ELSE 0 END, %s %s", string(params.SortBy), string(params.SortBy), orderDirection)
			} else {
				orderByClause = fmt.Sprintf("CASE WHEN %s IS NULL THEN 0 ELSE 1 END, %s %s", string(params.SortBy), string(params.SortBy), orderDirection)
			}
		} else {
			orderByClause = fmt.Sprintf("%s %s", string(params.SortBy), orderDirection)
		}
		log = log.With(slog.String("sort_by", string(params.SortBy)), slog.String("sort_order", orderDirection))
	}
	query = query.Order(orderByClause)

	if err := query.Find(&tasks).Error; err != nil {
		log.Error("failed to get tasks from DB", "error", err)
		return nil, task.ErrTaskInternal
	}

	log.Info("tasks retrieved successfully from DB", slog.Int("count", len(tasks)))
	return tasks, nil
}

func (r *TaskDatabase) UpdateTask(taskModel *task.Task) (*task.Task, error) {
	op := "TaskDatabase.UpdateTask"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskModel.TaskID)))

	// Чтобы корректно сбрасывать поля в NULL, используем Select/Omit
	result := r.db.Save(taskModel)
	if result.Error != nil {
		log.Error("failed to update task in DB", "error", result.Error)
		return nil, task.ErrTaskInternal
	}

	if result.RowsAffected == 0 {
		var checkTask task.Task
		if errCheck := r.db.First(&checkTask, taskModel.TaskID).Error; errCheck != nil {
			if errors.Is(errCheck, gorm.ErrRecordNotFound) {
				log.Warn("task not found for update", "taskID", taskModel.TaskID)
				return nil, task.ErrTaskNotFound
			}
		}
		log.Warn("UpdateTask: no rows affected, task data might be the same or task not found", "taskID", taskModel.TaskID)
	}

	log.Info("task updated successfully in DB")
	return taskModel, nil
}

func (r *TaskDatabase) DeleteTask(taskID uint, userID uint, isTeamTask bool, deletedByUserID *uint) error {
	op := "TaskDatabase.DeleteTask"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("deleter_userID", uint64(userID)))

	var taskToUpdate task.Task
	if err := r.db.First(&taskToUpdate, taskID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("task not found for deletion", "taskID", taskID)
			return task.ErrTaskNotFound
		}
		log.Error("failed to find task for deletion", "error", err)
		return task.ErrTaskInternal
	}

	if taskToUpdate.IsDeleted {
		log.Info("task already logically deleted", "taskID", taskID)
		return nil
	}

	updates := map[string]interface{}{
		"is_deleted":         true,
		"deleted_at":         time.Now(),
		"deleted_by_user_id": deletedByUserID,
	}

	result := r.db.Model(&task.Task{}).Where("task_id = ?", taskID).Updates(updates)
	if result.Error != nil {
		log.Error("failed to logically delete task in DB", "error", result.Error)
		return task.ErrTaskInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("logical delete task: no rows affected", "taskID", taskID)
		return task.ErrTaskNotFound
	}

	log.Info("task logically deleted successfully in DB")
	return nil
}

// DeleteTaskPermanently выполняет безвозвратное удаление задачи из БД.
func (r *TaskDatabase) DeleteTaskPermanently(taskID uint) error {
	op := "TaskDatabase.DeleteTaskPermanently"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))

	// Сначала удаляем все связи с тегами
	if err := r.db.Exec("DELETE FROM tasktags WHERE task_id = ?", taskID).Error; err != nil {
		log.Error("failed to delete task tag associations", "error", err)
		return task.ErrTaskInternal
	}

	// Unscoped() нужен для GORM, чтобы выполнить реальное удаление, а не логическое
	result := r.db.Unscoped().Delete(&task.Task{}, taskID)
	if result.Error != nil {
		log.Error("failed to permanently delete task from DB", "error", result.Error)
		return task.ErrTaskInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("permanent delete task: no rows affected, task may have been deleted already")
		return task.ErrTaskNotFound
	}

	log.Info("task permanently deleted successfully")
	return nil
}
