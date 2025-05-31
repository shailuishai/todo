package database

import (
	"errors"
	"fmt"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/task" // Пакет с GORM моделью Task, GetTasksParams и ошибками (если будут специфичные для task)
	"strings"
	"time"
)

// TaskDatabase реализует интерфейс repo.TaskDb
type TaskDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

// NewTaskDatabase создает новый экземпляр TaskDatabase.
func NewTaskDatabase(db *gorm.DB, log *slog.Logger) *TaskDatabase {
	return &TaskDatabase{
		db:  db,
		log: log,
	}
}

// CreateTask создает новую задачу в БД.
func (r *TaskDatabase) CreateTask(taskModel *task.Task) (*task.Task, error) {
	op := "TaskDatabase.CreateTask"
	log := r.log.With(slog.String("op", op), slog.String("title", taskModel.Title))

	if err := r.db.Create(taskModel).Error; err != nil {
		log.Error("failed to create task in DB", "error", err)
		// Здесь можно добавить обработку специфичных ошибок БД, если необходимо
		return nil, task.ErrTaskInternal // Используем общую внутреннюю ошибку
	}

	log.Info("task created successfully in DB", slog.Uint64("taskID", uint64(taskModel.TaskID)))
	return taskModel, nil
}

// GetTaskByID находит задачу по ID.
// userID используется для первичной фильтрации личных задач (если team_id is NULL).
// Основная проверка прав (состоит ли пользователь в команде и т.д.) должна быть в UseCase.
func (r *TaskDatabase) GetTaskByID(taskID uint, userID uint) (*task.Task, error) {
	op := "TaskDatabase.GetTaskByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))
	var taskModel task.Task

	// Запрос должен учитывать, что личная задача (team_id IS NULL) должна принадлежать userID.
	// Для командных задач (team_id IS NOT NULL) эта проверка userID здесь не так важна,
	// т.к. UseCase проверит членство в команде.
	// Однако, чтобы избежать путаницы, можно сделать запрос, который всегда вернет задачу по ID,
	// а UseCase уже разберется с правами.
	// Или, как ты указал "userID для базовой проверки личных задач":
	// dbQuery := r.db.Where("task_id = ?", taskID).
	// 	Where("(team_id IS NULL AND created_by_user_id = ?) OR team_id IS NOT NULL", userID)
	// Пока сделаем проще: получаем по ID, UseCase делает все проверки.
	// Если задача не будет найдена, или права не пройдут в UseCase, вернется ошибка.

	if err := r.db.First(&taskModel, taskID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("task not found by ID")
			return nil, task.ErrTaskNotFound // Используем общую ошибку "не найдено"
		}
		log.Error("failed to get task by ID from DB", "error", err)
		return nil, task.ErrTaskInternal
	}

	log.Debug("task found by ID")
	return &taskModel, nil
}

// GetTasks получает список задач на основе параметров фильтрации и сортировки.
func (r *TaskDatabase) GetTasks(params task.GetTasksParams) ([]*task.Task, error) {
	op := "TaskDatabase.GetTasks"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(params.UserID)), slog.String("viewType", string(params.ViewType)))
	var tasks []*task.Task

	query := r.db.Model(&task.Task{})
	query = query.Where("is_deleted = ?", false)

	// Основная логика выборки в зависимости от ViewType
	switch params.ViewType {
	case task.ViewTypeUserCentricGlobal:
		// Задачи, где пользователь либо создатель, либо исполнитель.
		// Доступ к командным задачам будет проверен в UseCase через teamService.IsUserMember.
		query = query.Where("(created_by_user_id = ? OR assigned_to_user_id = ?)", params.UserID, params.UserID)
		log = log.With(slog.String("filter_logic", "global_user_centric"))

	case task.ViewTypeUserPersonal:
		// Личные задачи, где пользователь либо создатель, либо исполнитель.
		query = query.Where("team_id IS NULL AND (created_by_user_id = ? OR assigned_to_user_id = ?)", params.UserID, params.UserID)
		log = log.With(slog.String("filter_logic", "personal_user_centric"))

	default: // Включая ViewTypeDefault и случаи, когда указан TeamID
		if params.TeamID != nil {
			// Задачи конкретной команды. Доступ к команде проверяется в UseCase.
			query = query.Where("team_id = ?", *params.TeamID)
			log = log.With(slog.Uint64("filter_teamID", uint64(*params.TeamID)))
			// Если для командных задач нужен фильтр по assigned_to_user_id или created_by_user_id (помимо ViewType),
			// он будет применен ниже.
		} else {
			// Поведение по умолчанию: личные задачи, созданные пользователем
			query = query.Where("team_id IS NULL AND created_by_user_id = ?", params.UserID)
			log = log.With(slog.String("filter_logic", "default_personal_created_by_user"))
		}
	}

	// Применение дополнительных фильтров
	if params.Status != nil && *params.Status != "" {
		query = query.Where("status = ?", *params.Status)
		log = log.With(slog.String("filter_status", *params.Status))
	}
	if params.Priority != nil {
		query = query.Where("priority = ?", *params.Priority)
		log = log.With(slog.Int("filter_priority", *params.Priority))
	}

	// Фильтр AssignedToUserID применяется как дополнительный, если он указан.
	// Он не будет конфликтовать с ViewType, т.к. ViewType уже задал основное условие.
	if params.AssignedToUserID != nil {
		query = query.Where("assigned_to_user_id = ?", *params.AssignedToUserID)
		log = log.With(slog.Uint64("filter_assigned_to_explicit", uint64(*params.AssignedToUserID)))
	}

	if params.DeadlineFrom != nil {
		query = query.Where("deadline >= ?", params.DeadlineFrom.Format(time.RFC3339))
		log = log.With(slog.String("filter_deadline_from", params.DeadlineFrom.Format(time.RFC3339)))
	}
	if params.DeadlineTo != nil {
		// Чтобы включить весь день, если передана только дата
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

	// Применение сортировки
	orderByClause := "updated_at DESC" // Сортировка по умолчанию
	if params.SortBy != "" {
		orderDirection := "ASC"
		if params.SortOrder == task.SortDirectionDesc {
			orderDirection = "DESC"
		}
		// Для deadline сортируем так, чтобы NULL были в конце при ASC, и в начале при DESC
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

// UpdateTask обновляет существующую задачу в БД.
// taskModel должен содержать TaskID и поля для обновления.
func (r *TaskDatabase) UpdateTask(taskModel *task.Task) (*task.Task, error) {
	op := "TaskDatabase.UpdateTask"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskModel.TaskID)))

	// Используем Save для обновления всех полей, если они изменены.
	// GORM автоматически обрабатывает `updated_at`.
	// Убедимся, что `created_at` не перезаписывается, если оно не должно меняться.
	// GORM Save() обновляет все поля, если они не zero-value, или если это полная структура.
	// Чтобы обновлять только измененные поля, лучше использовать Updates() с map[string]interface{} или структурой с указателями.
	// Но если UseCase готовит полную модель taskModel для сохранения, Save() подойдет.
	// Для PATCH-запросов, UseCase должен будет загрузить модель, применить изменения и затем вызвать Save() или Updates().
	// Пока оставим Save(), предполагая, что taskModel - это актуальная модель с изменениями.

	// Перед сохранением, если CompletedAt меняется, нужно логически его обработать.
	// Если status становится "done" и CompletedAt еще не установлен, устанавливаем его.
	// Если status меняется с "done" на другой и CompletedAt установлен, его можно очистить (сделать NULL).
	// Эта логика лучше разместится в UseCase перед вызовом UpdateTask.
	// Здесь репозиторий просто сохраняет то, что ему передали.

	result := r.db.Save(taskModel)
	if result.Error != nil {
		log.Error("failed to update task in DB", "error", result.Error)
		return nil, task.ErrTaskInternal
	}

	if result.RowsAffected == 0 {
		// Это может произойти, если задача с таким ID не найдена,
		// или если данные в taskModel идентичны данным в БД.
		// Проверим, существует ли задача, чтобы отличить "не найдено" от "нет изменений".
		var checkTask task.Task
		if errCheck := r.db.First(&checkTask, taskModel.TaskID).Error; errCheck != nil {
			if errors.Is(errCheck, gorm.ErrRecordNotFound) {
				log.Warn("task not found for update", "taskID", taskModel.TaskID)
				return nil, task.ErrTaskNotFound
			}
		}
		log.Warn("UpdateTask: no rows affected, task data might be the same or task not found", "taskID", taskModel.TaskID)
		// Возвращаем обновленную модель, даже если RowsAffected 0, но ошибки не было (данные не изменились)
	}

	log.Info("task updated successfully in DB")
	return taskModel, nil // Возвращаем переданную (возможно, обновленную GORM) модель
}

// DeleteTask выполняет логическое удаление задачи.
// userID - ID пользователя, выполняющего действие.
// isTeamTask - флаг, является ли задача командной.
// deletedByUserID - ID пользователя, который удалил (актуально для командных задач).
func (r *TaskDatabase) DeleteTask(taskID uint, userID uint, isTeamTask bool, deletedByUserID *uint) error {
	op := "TaskDatabase.DeleteTask"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("deleter_userID", uint64(userID)))

	var taskToUpdate task.Task
	// Сначала найдем задачу, чтобы убедиться, что она существует и не удалена
	// и чтобы применить правильные условия для удаления (например, создатель для личной задачи)
	// Эта проверка прав будет в UseCase, здесь мы просто выполняем обновление.
	// UseCase должен передать правильные taskID и userID (который имеет право удалить).

	// Находим задачу по ID. UseCase уже должен был проверить права.
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
		return nil // Уже удалена, ошибки нет
	}

	updates := map[string]interface{}{
		"is_deleted": true,
		"deleted_at": time.Now(),
	}
	if isTeamTask && deletedByUserID != nil {
		updates["deleted_by_user_id"] = *deletedByUserID
		log = log.With(slog.Uint64("deleted_by_specific_user_id", uint64(*deletedByUserID)))
	} else if !isTeamTask {
		// Для личных задач deleted_by_user_id может быть userID (создателя) или NULL.
		// Если следовать твоей схеме, где deleted_by_user_id - это ссылка на Users,
		// то для личных задач можно ставить userID.
		updates["deleted_by_user_id"] = userID
	}

	// Обновляем только нужные поля
	result := r.db.Model(&task.Task{}).Where("task_id = ?", taskID).Updates(updates)
	if result.Error != nil {
		log.Error("failed to logically delete task in DB", "error", result.Error)
		return task.ErrTaskInternal
	}

	if result.RowsAffected == 0 {
		log.Warn("logical delete task: no rows affected, task might have been deleted concurrently", "taskID", taskID)
		// Это маловероятно, если мы предварительно проверили IsDeleted, но возможно.
		// Можно вернуть ErrNotFound или считать успешным, если задача уже удалена.
		// Т.к. мы проверили IsDeleted выше, это, скорее всего, ошибка или конкурентное удаление.
		return task.ErrTaskNotFound // Если строка не найдена для обновления после всех проверок
	}

	log.Info("task logically deleted successfully in DB")
	return nil
}
