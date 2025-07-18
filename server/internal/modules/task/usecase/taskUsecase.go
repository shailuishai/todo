package usecase

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"server/internal/modules/tag"
	"server/internal/modules/task" // Пакет task (entity, repo, errors)
	"strconv"
	"strings"
	"time"
)

// --- Заглушка для TeamService ---
// В будущем это будет реальный сервис/usecase из модуля team
type TeamService interface {
	IsUserMember(userID, teamID uint) (bool, error)
	CanUserCreateTeamTask(userID, teamID uint) (bool, error)
	CanUserEditTeamTaskDetails(userID, teamID uint) (bool, error)
	CanUserChangeTeamTaskStatus(userID, teamID uint, taskAssignedToUserID *uint) (bool, error) // Обычно все участники могут менять статус
	CanUserDeleteTeamTask(userID, teamID uint, taskCreatorID uint) (bool, error)
	IsUserTeamMemberWithUserID(teamID uint, targetUserID uint) (bool, error) // Проверяет, является ли targetUserID участником teamID
}

// --- Конец заглушки для TeamService ---

// TaskUseCase реализует интерфейс task.UseCase
type TaskUseCase struct {
	repo        task.Repo // Интерфейс репозитория (который включает TaskDb и TaskCache)
	tagUC       tag.UseCase
	tagRepo     tag.Repo
	log         *slog.Logger
	teamService TeamService   // Зависимость от сервиса команд (пока заглушка)
	cacheTTL    time.Duration // TTL для кэша списков задач
}

// NewTaskUseCase создает новый экземпляр TaskUseCase.
func NewTaskUseCase(
	repo task.Repo,
	tagUC tag.UseCase,
	tagRepo tag.Repo,
	teamService TeamService,
	log *slog.Logger,
	cacheTTL time.Duration,
) task.UseCase {
	if cacheTTL == 0 {
		cacheTTL = 5 * time.Minute // TTL по умолчанию для списков
	}
	return &TaskUseCase{
		repo:        repo,
		tagUC:       tagUC,
		tagRepo:     tagRepo,
		log:         log,
		teamService: teamService,
		cacheTTL:    cacheTTL,
	}
}

// generateTasksCacheKey создает ключ для кэширования списка задач
func (uc *TaskUseCase) generateTasksCacheKey(userID uint, reqParams task.GetTasksRequest) string {
	var keyParts []string
	keyParts = append(keyParts, "tasks", "user", strconv.FormatUint(uint64(userID), 10))

	if reqParams.TeamID != nil {
		keyParts = append(keyParts, "team", strconv.FormatUint(uint64(*reqParams.TeamID), 10))
	} else {
		keyParts = append(keyParts, "personal")
	}

	if reqParams.IsDeleted != nil && *reqParams.IsDeleted {
		keyParts = append(keyParts, "deleted") // <<< ВАЖНО для корзины
	}

	if reqParams.Status != nil {
		keyParts = append(keyParts, "status", *reqParams.Status)
	}
	// ... остальная часть функции без изменений
	if reqParams.Priority != nil {
		keyParts = append(keyParts, "priority", strconv.Itoa(*reqParams.Priority))
	}
	if reqParams.AssignedToUserID != nil {
		keyParts = append(keyParts, "assignee", strconv.FormatUint(uint64(*reqParams.AssignedToUserID), 10))
	}
	if reqParams.DeadlineFrom != nil {
		keyParts = append(keyParts, "dfrom", reqParams.DeadlineFrom.Format("20060102"))
	}
	if reqParams.DeadlineTo != nil {
		keyParts = append(keyParts, "dto", reqParams.DeadlineTo.Format("20060102"))
	}
	if reqParams.Search != nil {
		h := sha256.New()
		h.Write([]byte(*reqParams.Search))
		keyParts = append(keyParts, "search", hex.EncodeToString(h.Sum(nil))[:16])
	}
	if reqParams.SortBy != nil {
		keyParts = append(keyParts, "sort", string(*reqParams.SortBy))
		if reqParams.SortOrder != nil {
			keyParts = append(keyParts, string(*reqParams.SortOrder))
		} else {
			keyParts = append(keyParts, string(task.SortDirectionAsc))
		}
	}
	return strings.Join(keyParts, ":")
}

func (uc *TaskUseCase) updateTaskTags(taskID uint, userID uint, teamID *uint, userTagIDs []uint, teamTagIDs []uint) error {
	op := "TaskUseCase.updateTaskTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))

	if err := uc.tagRepo.ClearTaskTags(taskID); err != nil {
		log.Error("failed to clear existing task tags", "error", err)
		return task.ErrTaskInternal // Используем ошибку из task модуля
	}

	// Обработка пользовательских тегов
	if len(userTagIDs) > 0 {
		if teamID != nil { // Командным задачам не должны присваиваться пользовательские теги (согласно нашему решению)
			log.Warn("attempted to assign user tags to a team task", "userTagIDs", userTagIDs)
			return task.ErrTaskInvalidInput // Или более специфичная ошибка
		}
		validUserTags, err := uc.tagUC.ValidateAndGetUserTags(userID, userTagIDs)
		if err != nil {
			log.Error("user tags validation failed", "error", err, "userTagIDs", userTagIDs)
			return err // Ошибку вернет TagUseCase (ErrTagNotFound или ErrTagInternal)
		}
		for _, t := range validUserTags {
			if err := uc.tagRepo.AddTaskUserTag(taskID, t.UserTagID); err != nil {
				log.Error("failed to add user tag to task", "error", err, "userTagID", t.UserTagID)
				return task.ErrTaskInternal // Ошибка привязки
			}
		}
	}

	// Обработка командных тегов
	if len(teamTagIDs) > 0 {
		if teamID == nil { // Личным задачам не должны присваиваться командные теги
			log.Warn("attempted to assign team tags to a personal task", "teamTagIDs", teamTagIDs)
			return task.ErrTaskInvalidInput
		}
		validTeamTags, err := uc.tagUC.ValidateAndGetTeamTags(*teamID, userID, teamTagIDs) // userID для проверки прав на команду
		if err != nil {
			log.Error("team tags validation failed", "error", err, "teamTagIDs", teamTagIDs)
			return err // Ошибку вернет TagUseCase (ErrTagNotFound, ErrTeamAccessDenied или ErrTagInternal)
		}
		for _, t := range validTeamTags {
			if err := uc.tagRepo.AddTaskTeamTag(taskID, t.TeamTagID); err != nil {
				log.Error("failed to add team tag to task", "error", err, "teamTagID", t.TeamTagID)
				return task.ErrTaskInternal
			}
		}
	}
	return nil
}

// --- Приватный метод для получения тегов задачи ---
func (uc *TaskUseCase) getTaskTags(taskID uint, ownerOrTeamUserID uint, teamID *uint) ([]*tag.TagResponse, error) {
	op := "TaskUseCase.getTaskTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))

	taskTagLinks, err := uc.tagRepo.GetTaskTags(taskID)
	if err != nil {
		log.Error("failed to get task_tags links", "error", err)
		return nil, task.ErrTaskInternal
	}

	var tagResponses []*tag.TagResponse
	if len(taskTagLinks) == 0 {
		return tagResponses, nil // Пустой срез, если нет тегов
	}

	var userTagIDs []uint
	var teamTagIDs []uint
	for _, link := range taskTagLinks {
		if link.UserTagID != nil {
			userTagIDs = append(userTagIDs, *link.UserTagID)
		} else if link.TeamTagID != nil {
			teamTagIDs = append(teamTagIDs, *link.TeamTagID)
		}
	}

	if len(userTagIDs) > 0 {
		// ownerOrTeamUserID здесь - это userID владельца задачи (для личных задач)
		userTags, err := uc.tagUC.ValidateAndGetUserTags(ownerOrTeamUserID, userTagIDs) // Валидация не нужна, если мы просто читаем
		// Лучше использовать прямой вызов репо, если GetUserTags в TagUseCase делает доп. проверки, не нужные здесь
		// userTags, err := uc.tagRepo.FindUserTagsByIDs(ownerOrTeamUserID, userTagIDs)
		if err != nil {
			log.Error("failed to get user tag details for task", "error", err)
			// Продолжаем, чтобы не терять командные теги, но логируем
		} else {
			for _, ut := range userTags {
				tagResponses = append(tagResponses, &tag.TagResponse{
					ID: ut.UserTagID, Name: ut.Name, Color: ut.Color, Type: "user", OwnerID: ut.OwnerUserID,
					CreatedAt: ut.CreatedAt, UpdatedAt: ut.UpdatedAt,
				})
			}
		}
	}

	if len(teamTagIDs) > 0 && teamID != nil {
		// ownerOrTeamUserID здесь - это userID текущего пользователя, для проверки доступа к командным тегам
		teamTags, err := uc.tagUC.ValidateAndGetTeamTags(*teamID, ownerOrTeamUserID, teamTagIDs)
		// teamTags, err := uc.tagRepo.FindTeamTagsByIDs(*teamID, teamTagIDs)
		if err != nil {
			log.Error("failed to get team tag details for task", "error", err)
		} else {
			for _, tt := range teamTags {
				tagResponses = append(tagResponses, &tag.TagResponse{
					ID: tt.TeamTagID, Name: tt.Name, Color: tt.Color, Type: "team", OwnerID: tt.TeamID,
					CreatedAt: tt.CreatedAt, UpdatedAt: tt.UpdatedAt,
				})
			}
		}
	}
	return tagResponses, nil
}

func (uc *TaskUseCase) CreateTask(userID uint, req task.CreateTaskRequest) (*task.TaskResponse, error) {
	op := "TaskUseCase.CreateTask"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	taskModel := task.Task{
		Title:            req.Title,
		Description:      req.Description,
		Deadline:         req.Deadline,
		CreatedByUserID:  userID,
		TeamID:           req.TeamID,
		AssignedToUserID: req.AssignedToUserID,
	}
	if req.Status != nil {
		taskModel.Status = *req.Status
	} else {
		taskModel.Status = "todo"
	}
	if req.Priority != nil {
		taskModel.Priority = *req.Priority
	} else {
		taskModel.Priority = 1 // Default priority
	}

	if req.TeamID != nil {
		teamID := *req.TeamID
		canCreate, err := uc.teamService.CanUserCreateTeamTask(userID, teamID)
		if err != nil {
			log.Error("failed to check team create permission", "error", err)
			return nil, task.ErrTaskInternal
		}
		if !canCreate {
			log.Warn("user no permission to create task in team")
			return nil, task.ErrTaskAccessDenied
		}
		if req.AssignedToUserID != nil {
			isMember, err := uc.teamService.IsUserTeamMemberWithUserID(teamID, *req.AssignedToUserID)
			if err != nil {
				log.Error("failed to check assignee team member", "error", err)
				return nil, task.ErrTaskInternal
			}
			if !isMember {
				log.Warn("assignee not team member")
				return nil, task.ErrTaskAssigneeNotInTeam
			}
		}
	} else {
		if req.AssignedToUserID != nil && *req.AssignedToUserID != userID {
			log.Warn("attempt assign personal task to another user")
			return nil, task.ErrTaskInvalidInput
		}
	}

	createdTask, err := uc.repo.CreateTask(&taskModel)
	if err != nil {
		log.Error("failed to create task in repo", "error", err)
		return nil, err
	}

	if err := uc.updateTaskTags(createdTask.TaskID, userID, createdTask.TeamID, req.UserTagIDs, req.TeamTagIDs); err != nil {
		log.Error("failed to update tags for new task, but task created", "error", err, "taskID", createdTask.TaskID)
		return nil, err
	}

	// Инвалидация кэша списков задач
	uc.invalidateTaskListsCache(userID, createdTask.TeamID)
	log.Info("task lists cache invalidated", slog.Uint64("userID", uint64(userID)), slog.Any("teamID", createdTask.TeamID))

	taskResp, err := uc.buildTaskResponse(createdTask, userID)
	if err != nil {
		log.Error("failed to build task response after create, returning basic task", "error", err, "taskID", createdTask.TaskID)
		return task.ToTaskResponse(createdTask), nil
	}

	log.Info("task created successfully", slog.Uint64("taskID", uint64(createdTask.TaskID)))
	return taskResp, nil
}

// buildTaskResponse - вспомогательная функция для сборки TaskResponse с тегами
func (uc *TaskUseCase) buildTaskResponse(taskModel *task.Task, currentUserID uint) (*task.TaskResponse, error) {
	if taskModel == nil {
		return nil, nil
	}
	resp := task.ToTaskResponse(taskModel)

	// Для личных задач ownerOrTeamUserID = taskModel.CreatedByUserID
	// Для командных задач ownerOrTeamUserID = currentUserID (для проверки доступа к командным тегам)
	var ownerOrTeamUserIDForTags uint
	if taskModel.TeamID != nil {
		ownerOrTeamUserIDForTags = currentUserID
	} else {
		ownerOrTeamUserIDForTags = taskModel.CreatedByUserID
	}

	tags, err := uc.getTaskTags(taskModel.TaskID, ownerOrTeamUserIDForTags, taskModel.TeamID)
	if err != nil {
		// Не фатальная ошибка, если теги не удалось загрузить, но логируем
		uc.log.Warn("failed to get tags for task response", "taskID", taskModel.TaskID, "error", err)
	}
	resp.Tags = tags
	return resp, nil
}

func (uc *TaskUseCase) GetTask(taskID uint, userID uint) (*task.TaskResponse, error) {
	op := "TaskUseCase.GetTask"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	cachedTaskModel, err := uc.repo.GetTask(taskID)
	if err == nil && cachedTaskModel != nil {
		if errAccess := uc.checkTaskAccess(cachedTaskModel, userID); errAccess != nil {
			return nil, errAccess
		}
		if cachedTaskModel.IsDeleted {
			_ = uc.repo.DeleteTaskCache(taskID) // Удаляем из кэша, если помечен как удаленный
			log.Warn("task found in cache but is deleted", "taskID", taskID)
			return nil, task.ErrTaskNotFound
		}

		log.Info("task model retrieved from cache, building full response")
		return uc.buildTaskResponse(cachedTaskModel, userID)
	}
	if err != nil && !errors.Is(err, task.ErrTaskNotFound) { // Log only if not "not found"
		log.Error("error getting task from cache", "error", err)
	}

	dbTaskModel, err := uc.repo.GetTaskByID(taskID, userID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			log.Warn("task not found in DB")
			return nil, task.ErrTaskNotFound
		}
		log.Error("failed to get task from DB", "error", err)
		return nil, task.ErrTaskInternal
	}

	if errAccess := uc.checkTaskAccess(dbTaskModel, userID); errAccess != nil {
		return nil, errAccess
	}

	// Кэшируем только если не удалена (GetTaskByID уже должен это проверять, но для надежности)
	if !dbTaskModel.IsDeleted {
		if errSave := uc.repo.SaveTask(dbTaskModel); errSave != nil {
			log.Warn("failed to save task model to cache", "error", errSave)
		}
	}
	log.Info("task model retrieved from DB, building full response")
	return uc.buildTaskResponse(dbTaskModel, userID)
}

// checkTaskAccess - приватный метод для проверки прав доступа к задаче
func (uc *TaskUseCase) checkTaskAccess(taskModel *task.Task, userID uint) error {
	if taskModel.TeamID == nil { // Личная задача
		if taskModel.CreatedByUserID != userID {
			uc.log.Warn("access denied to personal task", "ownerID", taskModel.CreatedByUserID, "accessorID", userID)
			return task.ErrTaskAccessDenied
		}
	} else { // Командная задача
		isMember, teamErr := uc.teamService.IsUserMember(userID, *taskModel.TeamID)
		if teamErr != nil {
			uc.log.Error("failed to check team membership for task access", "error", teamErr)
			return task.ErrTaskInternal
		}
		if !isMember {
			uc.log.Warn("user not member of team for task access", "teamID", *taskModel.TeamID)
			return task.ErrTaskAccessDenied
		}
	}
	return nil
}

func (uc *TaskUseCase) GetTasks(userID uint, reqParams task.GetTasksRequest) ([]*task.TaskResponse, error) {
	// ... (в основном без изменений, кроме передачи IsDeleted) ...
	op := "TaskUseCase.GetTasks"
	viewTypeToUse := task.ViewTypeDefault
	if reqParams.ViewType != nil {
		viewTypeToUse = *reqParams.ViewType
	}
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.String("viewType", string(viewTypeToUse)))

	if reqParams.TeamID != nil {
		isMember, teamErr := uc.teamService.IsUserMember(userID, *reqParams.TeamID)
		if teamErr != nil {
			log.Error("failed to check team membership for GetTasks", "error", teamErr, "teamID", *reqParams.TeamID)
			return nil, task.ErrTaskInternal
		}
		if !isMember {
			log.Warn("user not member of requested team for GetTasks", "teamID", *reqParams.TeamID)
			return []*task.TaskResponse{}, nil
		}
	}
	paramsForRepo := task.GetTasksParams{
		UserID:           userID,
		ViewType:         viewTypeToUse,
		TeamID:           reqParams.TeamID,
		Status:           reqParams.Status,
		Priority:         reqParams.Priority,
		AssignedToUserID: reqParams.AssignedToUserID,
		DeadlineFrom:     reqParams.DeadlineFrom,
		DeadlineTo:       reqParams.DeadlineTo,
		SearchQuery:      reqParams.Search,
		IsDeleted:        reqParams.IsDeleted, // <<< ПЕРЕДАЕМ IsDeleted
	}
	if reqParams.SortBy != nil {
		paramsForRepo.SortBy = *reqParams.SortBy
		if reqParams.SortOrder != nil {
			paramsForRepo.SortOrder = *reqParams.SortOrder
		} else {
			paramsForRepo.SortOrder = task.SortDirectionAsc // По умолчанию ASC, если поле сортировки указано
		}
	} else {
		paramsForRepo.SortBy = task.FieldUpdatedAt // Сортировка по умолчанию
		paramsForRepo.SortOrder = task.SortDirectionDesc
	}

	cacheKey := uc.generateTasksCacheKey(userID, reqParams)
	log = log.With(slog.String("cacheKey", cacheKey))

	cachedTaskModels, errCache := uc.repo.GetTasksCache(cacheKey)
	if errCache == nil && cachedTaskModels != nil {
		log.Info("task models list retrieved from cache", slog.Int("count", len(cachedTaskModels)))

		var accessibleCachedTasks []*task.Task
		for _, tm := range cachedTaskModels {
			// Проверяем, не удалена ли задача в кеше, если мы ищем не удаленные
			if reqParams.IsDeleted == nil || !*reqParams.IsDeleted {
				if tm.IsDeleted {
					continue
				}
			}
			if tm.TeamID != nil {
				isMember, teamErr := uc.teamService.IsUserMember(userID, *tm.TeamID)
				if teamErr != nil || !isMember {
					continue
				}
			}
			accessibleCachedTasks = append(accessibleCachedTasks, tm)
		}
		// ... остальная часть кеш-логики ...
		responses := make([]*task.TaskResponse, 0, len(accessibleCachedTasks))
		for _, tm := range accessibleCachedTasks {
			resp, buildErr := uc.buildTaskResponse(tm, userID)
			if buildErr != nil {
				log.Warn("failed to build task response for cached task, skipping", "taskID", tm.TaskID, "error", buildErr)
				continue
			}
			if resp != nil {
				responses = append(responses, resp)
			}
		}
		return responses, nil
	}

	dbTaskModels, err := uc.repo.GetTasks(paramsForRepo)
	if err != nil {
		log.Error("failed to get tasks from DB repo", "error", err)
		return nil, task.ErrTaskInternal
	}

	var finalTasksToRespond []*task.Task
	if viewTypeToUse == task.ViewTypeUserCentricGlobal || reqParams.TeamID != nil {
		for _, tm := range dbTaskModels {
			if tm.TeamID != nil {
				isMember, teamErr := uc.teamService.IsUserMember(userID, *tm.TeamID)
				if teamErr != nil {
					log.Error("error checking team membership for task in GetTasks", "taskID", tm.TaskID, "teamID", *tm.TeamID, "error", teamErr)
					continue
				}
				if !isMember {
					continue
				}
			}
			finalTasksToRespond = append(finalTasksToRespond, tm)
		}
	} else {
		finalTasksToRespond = dbTaskModels
	}

	if errSave := uc.repo.SaveTasks(cacheKey, finalTasksToRespond); errSave != nil {
		log.Warn("failed to save tasks list (models) to cache", "error", errSave)
	}

	responses := make([]*task.TaskResponse, 0, len(finalTasksToRespond))
	for _, tm := range finalTasksToRespond {
		resp, buildErr := uc.buildTaskResponse(tm, userID)
		if buildErr != nil {
			log.Warn("failed to build task response for DB task, skipping", "taskID", tm.TaskID, "error", buildErr)
			continue
		}
		if resp != nil {
			responses = append(responses, resp)
		}
	}
	log.Info("tasks list retrieved from DB", slog.Int("count", len(responses)))
	return responses, nil
}

func (uc *TaskUseCase) UpdateTask(taskID uint, userID uint, req task.UpdateTaskRequest) (*task.TaskResponse, error) {
	op := "TaskUseCase.UpdateTask (PUT)"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	existingTask, err := uc.repo.GetTaskByID(taskID, userID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return nil, task.ErrTaskNotFound
		}
		log.Error("failed to get task for update", "error", err)
		return nil, task.ErrTaskInternal
	}

	if errAccess := uc.checkTaskEditAccess(existingTask, userID, false); errAccess != nil {
		return nil, errAccess
	}

	if existingTask.TeamID != nil && req.AssignedToUserID != nil {
		isMember, teamErr := uc.teamService.IsUserTeamMemberWithUserID(*existingTask.TeamID, *req.AssignedToUserID)
		if teamErr != nil {
			log.Error("failed to check assignee in team", "error", teamErr)
			return nil, task.ErrTaskInternal
		}
		if !isMember {
			return nil, task.ErrTaskAssigneeNotInTeam
		}
	} else if existingTask.TeamID == nil && req.AssignedToUserID != nil && *req.AssignedToUserID != userID {
		return nil, task.ErrTaskInvalidInput
	}

	existingTask.Title = req.Title
	existingTask.Description = req.Description
	existingTask.Deadline = req.Deadline
	existingTask.Status = req.Status
	existingTask.Priority = req.Priority
	existingTask.AssignedToUserID = req.AssignedToUserID

	if existingTask.Status == "done" && existingTask.CompletedAt == nil {
		now := time.Now()
		existingTask.CompletedAt = &now
	}
	if existingTask.Status != "done" && existingTask.CompletedAt != nil {
		existingTask.CompletedAt = nil
	}

	updatedTaskModel, err := uc.repo.UpdateTask(existingTask)
	if err != nil {
		log.Error("failed to update task in repo", "error", err)
		return nil, err
	}

	var userTagsToUpdate []uint
	var teamTagsToUpdate []uint
	if req.UserTagIDs != nil {
		userTagsToUpdate = *req.UserTagIDs
	}
	if req.TeamTagIDs != nil {
		teamTagsToUpdate = *req.TeamTagIDs
	}

	if errTags := uc.updateTaskTags(updatedTaskModel.TaskID, userID, updatedTaskModel.TeamID, userTagsToUpdate, teamTagsToUpdate); errTags != nil {
		log.Error("failed to update tags for task, but task core updated", "error", errTags)
		return nil, errTags
	}

	_ = uc.repo.DeleteTaskCache(taskID)
	uc.invalidateTaskListsCache(userID, existingTask.TeamID)

	log.Info("task updated successfully (PUT)")
	return uc.buildTaskResponse(updatedTaskModel, userID)
}

func (uc *TaskUseCase) PatchTask(taskID uint, userID uint, req task.PatchTaskRequest) (*task.TaskResponse, error) {
	op := "TaskUseCase.PatchTask (PATCH)"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	// Ищем задачу, включая удаленные, так как мы можем восстанавливать
	existingTask, err := uc.repo.GetTaskByIDIncludingDeleted(taskID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return nil, task.ErrTaskNotFound
		}
		return nil, task.ErrTaskInternal
	}

	// Если задача удалена, и запрос не на восстановление, запрещаем
	if existingTask.IsDeleted && (req.IsDeleted == nil || *req.IsDeleted) {
		return nil, task.ErrTaskAlreadyDeleted
	}

	madeChangesToDetails := false
	statusChanged := false

	if req.Title != nil {
		existingTask.Title = *req.Title
		madeChangesToDetails = true
	}
	if req.Description != nil {
		existingTask.Description = req.Description
		madeChangesToDetails = true
	}
	if req.ClearDeadline != nil && *req.ClearDeadline {
		existingTask.Deadline = nil
		madeChangesToDetails = true
	} else if req.Deadline != nil {
		existingTask.Deadline = req.Deadline
		madeChangesToDetails = true
	}
	if req.Priority != nil {
		existingTask.Priority = *req.Priority
		madeChangesToDetails = true
	}
	if req.ClearAssignedTo != nil && *req.ClearAssignedTo {
		existingTask.AssignedToUserID = nil
		madeChangesToDetails = true
	} else if req.AssignedToUserID != nil {
		existingTask.AssignedToUserID = req.AssignedToUserID
		madeChangesToDetails = true
	}

	// <<< НОВАЯ ЛОГИКА для is_deleted >>>
	if req.IsDeleted != nil {
		if !*req.IsDeleted { // Это запрос на ВОССТАНОВЛЕНИЕ
			// Права на восстановление = права на редактирование
			if errAccess := uc.checkTaskEditAccess(existingTask, userID, false); errAccess != nil {
				return nil, errAccess
			}
			existingTask.IsDeleted = false
			existingTask.DeletedAt = nil
			existingTask.DeletedByUserID = nil
		} else if !existingTask.IsDeleted { // Это запрос на УДАЛЕНИЕ через PATCH
			// Используем существующую логику DeleteTask для проверки прав
			return nil, uc.DeleteTask(taskID, userID) // Делегируем удаление
		}
	}

	if existingTask.Status == "done" && existingTask.CompletedAt == nil {
		now := time.Now()
		existingTask.CompletedAt = &now
	}
	if existingTask.Status != "done" && existingTask.CompletedAt != nil {
		existingTask.CompletedAt = nil
	}

	updatedTaskModel, err := uc.repo.UpdateTask(existingTask)
	if err != nil {
		return nil, err
	}

	tagsUpdated := false
	if req.UserTagIDs != nil || req.TeamTagIDs != nil {
		var userTagsToUpdate []uint
		var teamTagsToUpdate []uint
		if req.UserTagIDs != nil {
			userTagsToUpdate = *req.UserTagIDs
		}
		if req.TeamTagIDs != nil {
			teamTagsToUpdate = *req.TeamTagIDs
		}

		if errTags := uc.updateTaskTags(updatedTaskModel.TaskID, userID, updatedTaskModel.TeamID, userTagsToUpdate, teamTagsToUpdate); errTags != nil {
			log.Error("failed to update tags for patched task, but task core updated", "error", errTags)
			return nil, errTags
		}
		tagsUpdated = true
	}

	if !madeChangesToDetails && !statusChanged && !tagsUpdated {
		log.Info("no effective changes in patch request")
		return uc.buildTaskResponse(updatedTaskModel, userID)
	}

	_ = uc.repo.DeleteTaskCache(taskID)
	uc.invalidateTaskListsCache(userID, existingTask.TeamID)

	log.Info("task patched successfully")
	return uc.buildTaskResponse(updatedTaskModel, userID)
}

// checkTaskEditAccess - приватный метод для проверки прав на редактирование/изменение статуса
func (uc *TaskUseCase) checkTaskEditAccess(taskToEdit *task.Task, userID uint, statusOnly bool) error {
	if taskToEdit.TeamID == nil { // Личная задача
		if taskToEdit.CreatedByUserID != userID {
			uc.log.Warn("user is not owner of personal task for edit/patch")
			return task.ErrTaskAccessDenied
		}
	} else { // Командная задача
		teamID := *taskToEdit.TeamID
		if statusOnly {
			canChangeStatus, teamErr := uc.teamService.CanUserChangeTeamTaskStatus(userID, teamID, taskToEdit.AssignedToUserID)
			if teamErr != nil {
				uc.log.Error("failed to check team change status permission", "error", teamErr)
				return task.ErrTaskInternal
			}
			if !canChangeStatus {
				uc.log.Warn("user lacks permission to change task status in team")
				return task.ErrTaskAccessDenied
			}
		} else {
			canEditDetails, teamErr := uc.teamService.CanUserEditTeamTaskDetails(userID, teamID)
			if teamErr != nil {
				uc.log.Error("failed to check team edit details permission", "error", teamErr)
				return task.ErrTaskInternal
			}
			if !canEditDetails {
				uc.log.Warn("user lacks permission to edit task details in team")
				return task.ErrTaskAccessDenied
			}
		}
	}
	return nil
}

// invalidateTaskListsCache - приватный метод для инвалидации кэшей списков задач
func (uc *TaskUseCase) invalidateTaskListsCache(userID uint, teamID *uint) {
	keysToInvalidate := []string{
		uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: nil}),
	}
	if teamID != nil {
		keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: teamID}))
	}

	// Дополнительно инвалидируем ключи без фильтров, но с разными сортировками, если они часто используются
	// Это упрощенный вариант, можно сделать более умную инвалидацию по паттерну, если Redis поддерживает
	// Пример:
	// commonSorts := []task.TaskSortableField{task.FieldCreatedAt, task.FieldPriority, task.FieldDeadline}
	// for _, sortBy := range commonSorts {
	// 	keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: nil, SortBy: &sortBy, SortOrder: task.SortDirectionDesc}))
	// 	if teamID != nil {
	// 		keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: teamID, SortBy: &sortBy, SortOrder: task.SortDirectionDesc}))
	// 	}
	// }

	if err := uc.repo.InvalidateTasks(keysToInvalidate...); err != nil {
		uc.log.Warn("failed to invalidate tasks list cache", "error", err, "keys", keysToInvalidate)
	} else {
		uc.log.Info("successfully invalidated task list cache keys", "keys", keysToInvalidate)
	}
}

func (uc *TaskUseCase) DeleteTask(taskID uint, userID uint) error {
	op := "TaskUseCase.DeleteTask"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	// Используем GetTaskByID, т.к. удалять можно только активные задачи
	taskToDelete, err := uc.repo.GetTaskByID(taskID, userID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return task.ErrTaskNotFound
		}
		return task.ErrTaskInternal
	}

	var isTeamTask bool
	var deletedBy *uint = &userID
	if taskToDelete.TeamID == nil {
		if taskToDelete.CreatedByUserID != userID {
			return task.ErrTaskAccessDenied
		}
		isTeamTask = false
	} else {
		teamID := *taskToDelete.TeamID
		canDelete, teamErr := uc.teamService.CanUserDeleteTeamTask(userID, teamID, taskToDelete.CreatedByUserID)
		if teamErr != nil {
			return task.ErrTaskInternal
		}
		if !canDelete {
			return task.ErrTaskAccessDenied
		}
		isTeamTask = true
	}

	err = uc.repo.DeleteTask(taskID, userID, isTeamTask, deletedBy)
	if err != nil {
		return err
	}
	_ = uc.repo.DeleteTaskCache(taskID)
	// Инвалидируем кэш для активных и удаленных задач
	uc.invalidateTaskListsCache(userID, taskToDelete.TeamID)
	uc.invalidateDeletedTasksCache(userID, taskToDelete.TeamID)

	log.Info("task deleted successfully")
	return nil
}

// <<< НОВАЯ ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ >>>
func (uc *TaskUseCase) checkTaskDeleteAccess(taskToDelete *task.Task, userID uint) error {
	if taskToDelete.TeamID == nil { // Личная задача
		if taskToDelete.CreatedByUserID != userID {
			uc.log.Warn("user is not owner of personal task for delete")
			return task.ErrTaskAccessDenied
		}
	} else { // Командная задача
		canDelete, teamErr := uc.teamService.CanUserDeleteTeamTask(userID, *taskToDelete.TeamID, taskToDelete.CreatedByUserID)
		if teamErr != nil {
			uc.log.Error("failed to check team delete permission", "error", teamErr)
			return task.ErrTaskInternal
		}
		if !canDelete {
			uc.log.Warn("user lacks permission to delete task in team")
			return task.ErrTaskAccessDenied
		}
	}
	return nil
}

// <<< НОВАЯ ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ >>>
func (uc *TaskUseCase) invalidateDeletedTasksCache(userID uint, teamID *uint) {
	isDeleted := true
	keysToInvalidate := []string{
		uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: nil, IsDeleted: &isDeleted}),
	}
	if teamID != nil {
		keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, task.GetTasksRequest{TeamID: teamID, IsDeleted: &isDeleted}))
	}

	if err := uc.repo.InvalidateTasks(keysToInvalidate...); err != nil {
		uc.log.Warn("failed to invalidate deleted tasks list cache", "error", err, "keys", keysToInvalidate)
	} else {
		uc.log.Info("successfully invalidated deleted task list cache keys", "keys", keysToInvalidate)
	}
}

// <<< НОВЫЙ МЕТОД >>>
func (uc *TaskUseCase) RestoreTask(taskID uint, userID uint) (*task.TaskResponse, error) {
	op := "TaskUseCase.RestoreTask"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	existingTask, err := uc.repo.GetTaskByIDIncludingDeleted(taskID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return nil, task.ErrTaskNotFound
		}
		return nil, task.ErrTaskInternal
	}

	if !existingTask.IsDeleted {
		log.Warn("attempted to restore an already active task")
		return nil, task.ErrTaskInvalidInput // Задача не удалена
	}

	// Права на восстановление = права на редактирование
	if errAccess := uc.checkTaskEditAccess(existingTask, userID, false); errAccess != nil {
		return nil, errAccess
	}

	existingTask.IsDeleted = false
	existingTask.DeletedAt = nil
	existingTask.DeletedByUserID = nil

	restoredTask, err := uc.repo.UpdateTask(existingTask)
	if err != nil {
		return nil, err
	}

	_ = uc.repo.DeleteTaskCache(taskID) // Удаляем из кэша, если он там был с флагом is_deleted=true
	uc.invalidateTaskListsCache(userID, restoredTask.TeamID)
	uc.invalidateDeletedTasksCache(userID, restoredTask.TeamID)

	log.Info("task restored successfully")
	return uc.buildTaskResponse(restoredTask, userID)
}

// <<< НОВЫЙ МЕТОД >>>
func (uc *TaskUseCase) DeleteTaskPermanently(taskID uint, userID uint) error {
	op := "TaskUseCase.DeleteTaskPermanently"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	taskToDelete, err := uc.repo.GetTaskByIDIncludingDeleted(taskID)
	if err != nil {
		return err
	}

	// Права на перманентное удаление = права на обычное удаление
	if errAccess := uc.checkTaskDeleteAccess(taskToDelete, userID); errAccess != nil {
		return errAccess
	}

	if err := uc.repo.DeleteTaskPermanently(taskID); err != nil {
		return err
	}

	// Инвалидация кэшей
	_ = uc.repo.DeleteTaskCache(taskID)
	uc.invalidateDeletedTasksCache(userID, taskToDelete.TeamID) // Инвалидируем кэш корзины

	log.Info("task permanently deleted successfully")
	return nil
}
