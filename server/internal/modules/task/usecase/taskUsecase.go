// internal/modules/task/usecase/task_usecase.go
package usecase

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"server/internal/modules/notification"
	"server/internal/modules/tag"
	"server/internal/modules/task"
	gouser "server/internal/modules/user"
	"strconv"
	"strings"
	"time"
)

// TeamService ... (без изменений)
type TeamService interface {
	IsUserMember(userID, teamID uint) (bool, error)
	CanUserCreateTeamTask(userID, teamID uint) (bool, error)
	CanUserEditTeamTaskDetails(userID, teamID uint) (bool, error)
	CanUserChangeTeamTaskStatus(userID, teamID uint, taskAssignedToUserID *uint) (bool, error)
	CanUserDeleteTeamTask(userID, teamID uint, taskCreatorID uint) (bool, error)
	IsUserTeamMemberWithUserID(teamID uint, targetUserID uint) (bool, error)
	GetTeamName(teamID uint) (string, error)
}

// TaskUseCase ... (без изменений)
type TaskUseCase struct {
	repo             task.Repo
	tagUC            tag.UseCase
	tagRepo          tag.Repo
	log              *slog.Logger
	teamService      TeamService
	cacheTTL         time.Duration
	dispatcher       notification.Dispatcher
	userInfoProvider notification.UserNotificationInfoProvider
}

// NewTaskUseCase ... (без изменений)
func NewTaskUseCase(
	repo task.Repo,
	tagUC tag.UseCase,
	tagRepo tag.Repo,
	teamService TeamService,
	log *slog.Logger,
	cacheTTL time.Duration,
	userInfoProvider notification.UserNotificationInfoProvider,
	dispatcher notification.Dispatcher,
) task.UseCase {
	if cacheTTL == 0 {
		cacheTTL = 5 * time.Minute
	}
	return &TaskUseCase{
		repo:             repo,
		tagUC:            tagUC,
		tagRepo:          tagRepo,
		log:              log,
		teamService:      teamService,
		cacheTTL:         cacheTTL,
		userInfoProvider: userInfoProvider,
		dispatcher:       dispatcher,
	}
}

// ProcessDeadlineChecks ... (без изменений)
func (uc *TaskUseCase) ProcessDeadlineChecks(ctx context.Context) error {
	op := "TaskUseCase.ProcessDeadlineChecks"
	log := uc.log.With(slog.String("op", op))
	log.Info("Starting deadline check process")

	now := time.Now()

	tasks, err := uc.repo.GetTasksForDeadlineCheck(ctx, now)
	if err != nil {
		log.Error("failed to get tasks for deadline check from repo", "error", err)
		return err
	}

	if len(tasks) == 0 {
		log.Info("No pending tasks found for deadline notification check.")
		return nil
	}

	for _, t := range tasks {
		if t.AssignedToUserID == nil {
			continue
		}
		assigneeID := *t.AssignedToUserID

		settings, err := uc.userInfoProvider.GetUserNotificationSettings(assigneeID)
		if err != nil {
			log.Error("failed to get user settings for deadline check", "userID", assigneeID, "taskID", t.TaskID, "error", err)
			continue
		}

		if !settings.TaskDeadlineRemindersEnabled {
			continue
		}

		var notifyTime time.Time
		switch settings.TaskDeadlineReminderTimePreference {
		case gouser.DeadlineReminderPreferenceOneHour:
			notifyTime = t.Deadline.Add(-1 * time.Hour)
		case gouser.DeadlineReminderPreferenceOneDay:
			notifyTime = t.Deadline.Add(-24 * time.Hour)
		case gouser.DeadlineReminderPreferenceTwoDays:
			notifyTime = t.Deadline.Add(-48 * time.Hour)
		default:
			log.Warn("unknown deadline reminder preference", "preference", settings.TaskDeadlineReminderTimePreference)
			continue
		}

		if now.After(notifyTime) || now.Equal(notifyTime) {
			log.Info("Dispatching deadline notification", "taskID", t.TaskID, "userID", assigneeID)

			if uc.dispatcher != nil {
				event := notification.Event{
					Type: notification.EventTaskDeadlineDue,
					Payload: notification.TaskDeadlineEventPayload{
						TaskID:     t.TaskID,
						TaskTitle:  t.Title,
						AssigneeID: assigneeID,
						Deadline:   *t.Deadline,
					},
				}
				uc.dispatcher.Dispatch(ctx, event)
			}

			if err := uc.repo.MarkDeadlineNotificationSent(ctx, t.TaskID, now); err != nil {
				log.Error("failed to mark deadline notification as sent", "taskID", t.TaskID, "error", err)
			}
		}
	}
	log.Info("Deadline check process finished")
	return nil
}

// generateTasksCacheKey ... (оставляем исправленную версию)
func (uc *TaskUseCase) generateTasksCacheKey(userID uint, reqParams task.GetTasksRequest) string {
	var keyParts []string
	keyParts = append(keyParts, "tasks", "user", strconv.FormatUint(uint64(userID), 10))

	if reqParams.ViewType != nil {
		keyParts = append(keyParts, "view", string(*reqParams.ViewType))
	} else {
		keyParts = append(keyParts, "view", string(task.ViewTypeDefault))
	}

	if reqParams.TeamID != nil {
		keyParts = append(keyParts, "team", strconv.FormatUint(uint64(*reqParams.TeamID), 10))
	}

	if reqParams.IsDeleted != nil && *reqParams.IsDeleted {
		keyParts = append(keyParts, "deleted")
	}

	if reqParams.Status != nil {
		keyParts = append(keyParts, "status", *reqParams.Status)
	}
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

	// Важно, чтобы сортировка по умолчанию также была частью ключа
	sortBy := task.FieldUpdatedAt
	sortOrder := task.SortDirectionDesc
	if reqParams.SortBy != nil {
		sortBy = *reqParams.SortBy
		if reqParams.SortOrder != nil {
			sortOrder = *reqParams.SortOrder
		} else {
			sortOrder = task.SortDirectionAsc // Явно указываем
		}
	}
	keyParts = append(keyParts, "sort", string(sortBy), string(sortOrder))

	return strings.Join(keyParts, ":")
}

// updateTaskTags ... (без изменений)
func (uc *TaskUseCase) updateTaskTags(taskID uint, userID uint, teamID *uint, userTagIDs []uint, teamTagIDs []uint) error {
	op := "TaskUseCase.updateTaskTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))

	if err := uc.tagRepo.ClearTaskTags(taskID); err != nil {
		log.Error("failed to clear existing task tags", "error", err)
		return task.ErrTaskInternal
	}

	if len(userTagIDs) > 0 {
		if teamID != nil {
			log.Warn("attempted to assign user tags to a team task", "userTagIDs", userTagIDs)
			return task.ErrTaskInvalidInput
		}
		validUserTags, err := uc.tagUC.ValidateAndGetUserTags(userID, userTagIDs)
		if err != nil {
			log.Error("user tags validation failed", "error", err, "userTagIDs", userTagIDs)
			return err
		}
		for _, t := range validUserTags {
			if err := uc.tagRepo.AddTaskUserTag(taskID, t.UserTagID); err != nil {
				log.Error("failed to add user tag to task", "error", err, "userTagID", t.UserTagID)
				return task.ErrTaskInternal
			}
		}
	}

	if len(teamTagIDs) > 0 {
		if teamID == nil {
			log.Warn("attempted to assign team tags to a personal task", "teamTagIDs", teamTagIDs)
			return task.ErrTaskInvalidInput
		}
		validTeamTags, err := uc.tagUC.ValidateAndGetTeamTags(*teamID, userID, teamTagIDs)
		if err != nil {
			log.Error("team tags validation failed", "error", err, "teamTagIDs", teamTagIDs)
			return err
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

// buildTaskResponsesInBatch - НОВАЯ ФУНКЦИЯ для пакетной загрузки тегов и сборки ответов
func (uc *TaskUseCase) buildTaskResponsesInBatch(tasks []*task.Task, userID uint) ([]*task.TaskResponse, error) {
	op := "TaskUseCase.buildTaskResponsesInBatch"
	log := uc.log.With(slog.String("op", op), slog.Int("task_count", len(tasks)))

	if len(tasks) == 0 {
		return []*task.TaskResponse{}, nil
	}

	// 1. Собираем все ID
	taskIDs := make([]uint, len(tasks))
	tasksByTeam := make(map[uint][]*task.Task) // Группируем задачи по командам
	for i, t := range tasks {
		taskIDs[i] = t.TaskID
		if t.TeamID != nil {
			tasksByTeam[*t.TeamID] = append(tasksByTeam[*t.TeamID], t)
		}
	}

	// 2. Один запрос на все связи task-tag
	links, err := uc.tagRepo.GetLinksForTaskIDs(taskIDs) // Используем новый метод репо
	if err != nil {
		log.Error("failed to get links for task IDs", "error", err)
		return nil, task.ErrTaskInternal
	}

	// 3. Распределяем ID тегов по типам и собираем их для пакетных запросов
	userTagIDsToFetch := make([]uint, 0)
	teamTagIDsByTeam := make(map[uint][]uint) // map[teamID][]tagID
	linksByTaskID := make(map[uint][]*tag.TaskTag)

	for i := range links {
		link := links[i]
		linksByTaskID[link.TaskID] = append(linksByTaskID[link.TaskID], link)
		if link.UserTagID != nil {
			userTagIDsToFetch = append(userTagIDsToFetch, *link.UserTagID)
		} else if link.TeamTagID != nil {
			// Находим TeamID для этого тега
			for _, t := range tasks {
				if t.TaskID == link.TaskID && t.TeamID != nil {
					teamTagIDsByTeam[*t.TeamID] = append(teamTagIDsByTeam[*t.TeamID], *link.TeamTagID)
					break
				}
			}
		}
	}

	// 4. Пакетно загружаем все теги
	userTagsMap := make(map[uint]*tag.UserTag)
	if len(userTagIDsToFetch) > 0 {
		// Используем ValidateAndGetUserTags, который у нас уже есть
		validUserTags, err := uc.tagUC.ValidateAndGetUserTags(userID, userTagIDsToFetch)
		if err != nil {
			log.Warn("could not validate all user tags, some may be missing", "error", err)
		}
		for _, ut := range validUserTags {
			userTagsMap[ut.UserTagID] = ut
		}
	}

	teamTagsMap := make(map[uint]*tag.TeamTag)
	for teamID, tagIDs := range teamTagIDsByTeam {
		// Используем ValidateAndGetTeamTags для каждой команды
		validTeamTags, err := uc.tagUC.ValidateAndGetTeamTags(teamID, userID, tagIDs)
		if err != nil {
			log.Warn("could not validate all team tags for a team, some may be missing", "teamID", teamID, "error", err)
		}
		for _, tt := range validTeamTags {
			teamTagsMap[tt.TeamTagID] = tt
		}
	}

	// 5. Собираем финальные ответы
	responses := make([]*task.TaskResponse, len(tasks))
	for i, t := range tasks {
		resp := task.ToTaskResponse(t)
		tagResponses := make([]*tag.TagResponse, 0)
		for _, link := range linksByTaskID[t.TaskID] {
			if link.UserTagID != nil {
				if ut, ok := userTagsMap[*link.UserTagID]; ok {
					tagResponses = append(tagResponses, &tag.TagResponse{
						ID: ut.UserTagID, Name: ut.Name, Color: ut.Color, Type: "user", OwnerID: ut.OwnerUserID,
						CreatedAt: ut.CreatedAt, UpdatedAt: ut.UpdatedAt,
					})
				}
			} else if link.TeamTagID != nil {
				if tt, ok := teamTagsMap[*link.TeamTagID]; ok {
					tagResponses = append(tagResponses, &tag.TagResponse{
						ID: tt.TeamTagID, Name: tt.Name, Color: tt.Color, Type: "team", OwnerID: tt.TeamID,
						CreatedAt: tt.CreatedAt, UpdatedAt: tt.UpdatedAt,
					})
				}
			}
		}
		resp.Tags = tagResponses
		responses[i] = resp
	}

	return responses, nil
}

// GetTasks ИСПРАВЛЕНА: использует пакетную загрузку тегов
func (uc *TaskUseCase) GetTasks(userID uint, reqParams task.GetTasksRequest) ([]*task.TaskResponse, error) {
	op := "TaskUseCase.GetTasks"
	viewTypeToUse := task.ViewTypeDefault
	if reqParams.ViewType != nil {
		viewTypeToUse = *reqParams.ViewType
	}
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.String("viewType", string(viewTypeToUse)))

	cacheKey := uc.generateTasksCacheKey(userID, reqParams)
	log = log.With(slog.String("cacheKey", cacheKey))

	var tasksToProcess []*task.Task

	// Попытка получить из кэша
	cachedTaskModels, errCache := uc.repo.GetTasksCache(cacheKey)
	if errCache == nil && cachedTaskModels != nil {
		log.Info("task models list retrieved from cache", slog.Int("count", len(cachedTaskModels)))
		tasksToProcess = cachedTaskModels
	} else {
		// Ветка CACHE-MISS
		log.Info("no data in cache or cache error, proceeding to DB", "error", errCache)

		if reqParams.TeamID != nil {
			isMember, teamErr := uc.teamService.IsUserMember(userID, *reqParams.TeamID)
			if teamErr != nil {
				log.Error("failed to check team membership", "error", teamErr)
				return nil, task.ErrTaskInternal
			}
			if !isMember {
				log.Warn("user not member of requested team")
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
			IsDeleted:        reqParams.IsDeleted,
		}
		if reqParams.SortBy != nil {
			paramsForRepo.SortBy = *reqParams.SortBy
			if reqParams.SortOrder != nil {
				paramsForRepo.SortOrder = *reqParams.SortOrder
			} else {
				paramsForRepo.SortOrder = task.SortDirectionAsc
			}
		} else {
			paramsForRepo.SortBy = task.FieldUpdatedAt
			paramsForRepo.SortOrder = task.SortDirectionDesc
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
					if teamErr != nil || !isMember {
						continue
					}
				}
				finalTasksToRespond = append(finalTasksToRespond, tm)
			}
		} else {
			finalTasksToRespond = dbTaskModels
		}

		if errSave := uc.repo.SaveTasks(cacheKey, finalTasksToRespond); errSave != nil {
			log.Warn("failed to save tasks list to cache", "error", errSave)
		}
		tasksToProcess = finalTasksToRespond
		log.Info("tasks list retrieved from DB", slog.Int("count", len(tasksToProcess)))
	}

	// Единая точка сборки ответов с пакетной загрузкой тегов
	responses, err := uc.buildTaskResponsesInBatch(tasksToProcess, userID)
	if err != nil {
		log.Error("failed to build task responses in batch", "error", err)
		return nil, task.ErrTaskInternal
	}

	return responses, nil
}

// buildTaskResponse - старая, неэффективная версия. Оставляем для GetTask (где нужна одна задача)
func (uc *TaskUseCase) buildTaskResponse(taskModel *task.Task, currentUserID uint) (*task.TaskResponse, error) {
	if taskModel == nil {
		return nil, nil
	}
	resp := task.ToTaskResponse(taskModel)

	var ownerOrTeamUserIDForTags uint
	if taskModel.TeamID != nil {
		ownerOrTeamUserIDForTags = currentUserID
	} else {
		ownerOrTeamUserIDForTags = taskModel.CreatedByUserID
	}

	tags, err := uc.getTaskTags(taskModel.TaskID, ownerOrTeamUserIDForTags, taskModel.TeamID)
	if err != nil {
		uc.log.Warn("failed to get tags for task response", "taskID", taskModel.TaskID, "error", err)
	}
	resp.Tags = tags
	return resp, nil
}

// getTaskTags - старая, неэффективная версия. Оставляем для GetTask
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
		return tagResponses, nil
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
		userTags, err := uc.tagUC.ValidateAndGetUserTags(ownerOrTeamUserID, userTagIDs)
		if err != nil {
			log.Error("failed to get user tag details for task", "error", err)
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
		teamTags, err := uc.tagUC.ValidateAndGetTeamTags(*teamID, ownerOrTeamUserID, teamTagIDs)
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

// --- Остальные функции UseCase (Create, Update, Delete и т.д.) остаются без изменений ---

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
		taskModel.Priority = 1
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

	uc.invalidateTaskListsCache(userID, createdTask.TeamID)
	log.Info("task lists cache invalidated", slog.Uint64("userID", uint64(userID)), slog.Any("teamID", createdTask.TeamID))

	taskResp, err := uc.buildTaskResponse(createdTask, userID)
	if err != nil {
		log.Error("failed to build task response after create, returning basic task", "error", err, "taskID", createdTask.TaskID)
		return task.ToTaskResponse(createdTask), nil
	}

	if uc.dispatcher != nil && createdTask.TeamID != nil && createdTask.AssignedToUserID != nil && *createdTask.AssignedToUserID != userID {
		teamName, _ := uc.teamService.GetTeamName(*createdTask.TeamID)
		event := notification.Event{
			Type: notification.EventTaskAssigned,
			Payload: notification.TaskAssignedEventPayload{
				TaskID:     createdTask.TaskID,
				TaskTitle:  createdTask.Title,
				AssignerID: userID,
				AssigneeID: *createdTask.AssignedToUserID,
				TeamID:     createdTask.TeamID,
				TeamName:   &teamName,
			},
		}
		uc.dispatcher.Dispatch(context.Background(), event)
	}

	log.Info("task created successfully", slog.Uint64("taskID", uint64(createdTask.TaskID)))
	return taskResp, nil
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
			_ = uc.repo.DeleteTaskCache(taskID)
			log.Warn("task found in cache but is deleted", "taskID", taskID)
			return nil, task.ErrTaskNotFound
		}

		log.Info("task model retrieved from cache, building full response")
		return uc.buildTaskResponse(cachedTaskModel, userID)
	}
	if err != nil && !errors.Is(err, task.ErrTaskNotFound) {
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

	if !dbTaskModel.IsDeleted {
		if errSave := uc.repo.SaveTask(dbTaskModel); errSave != nil {
			log.Warn("failed to save task model to cache", "error", errSave)
		}
	}
	log.Info("task model retrieved from DB, building full response")
	return uc.buildTaskResponse(dbTaskModel, userID)
}

func (uc *TaskUseCase) checkTaskAccess(taskModel *task.Task, userID uint) error {
	if taskModel.TeamID == nil {
		if taskModel.CreatedByUserID != userID {
			uc.log.Warn("access denied to personal task", "ownerID", taskModel.CreatedByUserID, "accessorID", userID)
			return task.ErrTaskAccessDenied
		}
	} else {
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

	assigneeChanged := existingTask.AssignedToUserID != nil && req.AssignedToUserID != nil && *existingTask.AssignedToUserID != *req.AssignedToUserID
	if !assigneeChanged {
		assigneeChanged = (existingTask.AssignedToUserID == nil && req.AssignedToUserID != nil) || (existingTask.AssignedToUserID != nil && req.AssignedToUserID == nil)
	}

	if uc.dispatcher != nil && assigneeChanged && updatedTaskModel.TeamID != nil && updatedTaskModel.AssignedToUserID != nil && *updatedTaskModel.AssignedToUserID != userID {
		teamName, _ := uc.teamService.GetTeamName(*updatedTaskModel.TeamID)
		event := notification.Event{
			Type: notification.EventTaskAssigned,
			Payload: notification.TaskAssignedEventPayload{
				TaskID:     updatedTaskModel.TaskID,
				TaskTitle:  updatedTaskModel.Title,
				AssignerID: userID,
				AssigneeID: *updatedTaskModel.AssignedToUserID,
				TeamID:     updatedTaskModel.TeamID,
				TeamName:   &teamName,
			},
		}
		uc.dispatcher.Dispatch(context.Background(), event)
	}

	log.Info("task updated successfully (PUT)")
	return uc.buildTaskResponse(updatedTaskModel, userID)
}

func (uc *TaskUseCase) PatchTask(taskID uint, userID uint, req task.PatchTaskRequest) (*task.TaskResponse, error) {
	op := "TaskUseCase.PatchTask (PATCH)"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	existingTask, err := uc.repo.GetTaskByIDIncludingDeleted(taskID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return nil, task.ErrTaskNotFound
		}
		return nil, task.ErrTaskInternal
	}

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

	if req.Status != nil && *req.Status != existingTask.Status {
		if errAccess := uc.checkTaskEditAccess(existingTask, userID, true); errAccess != nil {
			return nil, errAccess
		}
		existingTask.Status = *req.Status
		statusChanged = true
	}

	if req.IsDeleted != nil {
		if !*req.IsDeleted {
			if errAccess := uc.checkTaskEditAccess(existingTask, userID, false); errAccess != nil {
				return nil, errAccess
			}
			existingTask.IsDeleted = false
			existingTask.DeletedAt = nil
			existingTask.DeletedByUserID = nil
		} else if !existingTask.IsDeleted {
			return nil, uc.DeleteTask(taskID, userID)
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

func (uc *TaskUseCase) checkTaskEditAccess(taskToEdit *task.Task, userID uint, statusOnly bool) error {
	if taskToEdit.TeamID == nil {
		if taskToEdit.CreatedByUserID != userID {
			uc.log.Warn("user is not owner of personal task for edit/patch")
			return task.ErrTaskAccessDenied
		}
	} else {
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

func (uc *TaskUseCase) invalidateTaskListsCache(userID uint, teamID *uint) {
	// Эта функция инвалидирует только самые базовые представления.
	// Для 100% консистентности может потребоваться более сложная стратегия.
	// Например, удаление по префиксу "tasks:user:1:*"
	basePersonalReq := task.GetTasksRequest{ViewType: new(task.GetTasksViewType)}
	*basePersonalReq.ViewType = task.ViewTypeUserPersonal

	baseGlobalReq := task.GetTasksRequest{ViewType: new(task.GetTasksViewType)}
	*baseGlobalReq.ViewType = task.ViewTypeUserCentricGlobal

	keysToInvalidate := []string{
		uc.generateTasksCacheKey(userID, basePersonalReq),
		uc.generateTasksCacheKey(userID, baseGlobalReq),
	}

	if teamID != nil {
		baseTeamReq := task.GetTasksRequest{TeamID: teamID}
		keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, baseTeamReq))
	}

	if err := uc.repo.InvalidateTasks(keysToInvalidate...); err != nil {
		uc.log.Warn("failed to invalidate tasks list cache", "error", err, "keys", keysToInvalidate)
	} else {
		uc.log.Info("successfully invalidated task list cache keys", "keys", keysToInvalidate)
	}
}

func (uc *TaskUseCase) DeleteTask(taskID uint, userID uint) error {
	op := "TaskUseCase.DeleteTask"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

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

	uc.invalidateTaskListsCache(userID, taskToDelete.TeamID)
	uc.invalidateDeletedTasksCache(userID, taskToDelete.TeamID)

	log.Info("task deleted successfully")
	return nil
}

func (uc *TaskUseCase) checkTaskDeleteAccess(taskToDelete *task.Task, userID uint) error {
	if taskToDelete.TeamID == nil {
		if taskToDelete.CreatedByUserID != userID {
			uc.log.Warn("user is not owner of personal task for delete")
			return task.ErrTaskAccessDenied
		}
	} else {
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

func (uc *TaskUseCase) invalidateDeletedTasksCache(userID uint, teamID *uint) {
	isDeleted := true
	baseReq := task.GetTasksRequest{IsDeleted: &isDeleted}

	personalView := task.ViewTypeUserPersonal
	baseReq.ViewType = &personalView
	keysToInvalidate := []string{uc.generateTasksCacheKey(userID, baseReq)}

	globalView := task.ViewTypeUserCentricGlobal
	baseReq.ViewType = &globalView
	keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, baseReq))

	if teamID != nil {
		baseTeamReq := task.GetTasksRequest{TeamID: teamID, IsDeleted: &isDeleted}
		keysToInvalidate = append(keysToInvalidate, uc.generateTasksCacheKey(userID, baseTeamReq))
	}

	if err := uc.repo.InvalidateTasks(keysToInvalidate...); err != nil {
		uc.log.Warn("failed to invalidate deleted tasks list cache", "error", err)
	} else {
		uc.log.Info("successfully invalidated deleted task list cache keys", "keys", keysToInvalidate)
	}
}

// ... (весь код, который я предоставил в предыдущем ответе, досюда)

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
		return nil, task.ErrTaskInvalidInput
	}

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

	_ = uc.repo.DeleteTaskCache(taskID)
	uc.invalidateTaskListsCache(userID, restoredTask.TeamID)
	uc.invalidateDeletedTasksCache(userID, restoredTask.TeamID)

	log.Info("task restored successfully")
	return uc.buildTaskResponse(restoredTask, userID)
}

func (uc *TaskUseCase) DeleteTaskPermanently(taskID uint, userID uint) error {
	op := "TaskUseCase.DeleteTaskPermanently"
	log := uc.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userID", uint64(userID)))

	taskToDelete, err := uc.repo.GetTaskByIDIncludingDeleted(taskID)
	if err != nil {
		if errors.Is(err, task.ErrTaskNotFound) {
			return nil // Возвращаем nil, если задача уже удалена, это идемпотентно.
		}
		return err
	}

	if errAccess := uc.checkTaskDeleteAccess(taskToDelete, userID); errAccess != nil {
		return errAccess
	}

	if err := uc.repo.DeleteTaskPermanently(taskID); err != nil {
		return err
	}

	_ = uc.repo.DeleteTaskCache(taskID)
	uc.invalidateDeletedTasksCache(userID, taskToDelete.TeamID)

	log.Info("task permanently deleted successfully")
	return nil
}
