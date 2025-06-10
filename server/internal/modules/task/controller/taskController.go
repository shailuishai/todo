package controller

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time" // Для парсинга дат, если потребуется

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"github.com/go-playground/validator/v10"
	"log/slog"

	"server/internal/modules/task" // Для task.SortDirection, task.TaskSortableField, task errors
	resp "server/pkg/lib/response" // Стандартизированные ответы
)

// TaskController обрабатывает HTTP-запросы для задач.
type TaskController struct {
	useCase  task.UseCase
	log      *slog.Logger
	validate *validator.Validate
}

// NewTaskController создает новый экземпляр TaskController.
func NewTaskController(useCase task.UseCase, log *slog.Logger) *TaskController {
	return &TaskController{
		useCase:  useCase,
		log:      log,
		validate: validator.New(),
	}
}

// CreateTask
// @Summary Create a new task
// @Tags tasks
// @Description Create a new personal or team task.
// @Accept json
// @Produce json
// @Param task body task.CreateTaskRequest true "Task creation data"
// @Success 201 {object} task.TaskResponse "Task created successfully"
// @Failure 400 {object} response.Response "Invalid request payload or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 403 {object} response.Response "Access denied (e.g., to create task in team)"
// @Failure 422 {object} response.Response "Unprocessable Entity (e.g., assignee not in team)"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /tasks [post]
// @Security ApiKeyAuth
func (c *TaskController) CreateTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.CreateTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("userID not found in context")
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var req task.CreateTaskRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	taskResponse, err := c.useCase.CreateTask(userID, req)
	if err != nil {
		log.Error("usecase CreateTask failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, task.ErrTaskAssigneeNotInTeam), errors.Is(err, task.ErrTaskInvalidInput):
			resp.SendError(w, r, http.StatusUnprocessableEntity, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to create task")
		}
		return
	}

	log.Info("task created successfully", slog.Uint64("taskID", uint64(taskResponse.TaskID)))
	resp.SendSuccess(w, r, http.StatusCreated, taskResponse)
}

// GetTask
// @Summary Get a specific task by ID
// @Tags tasks
// @Description Retrieves a task by its ID. Access is restricted based on user ownership or team membership.
// @Produce json
// @Param taskID path int true "Task ID"
// @Success 200 {object} task.TaskResponse "Task retrieved successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID} [get]
// @Security ApiKeyAuth
func (c *TaskController) GetTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.GetTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("userID not found in context")
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil {
		log.Warn("invalid taskID format", "taskIDStr", taskIDStr, "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID format")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	taskResponse, err := c.useCase.GetTask(uint(taskID), userID)
	if err != nil {
		log.Warn("usecase GetTask failed", "error", err) // Логируем как Warn, т.к. 403/404 не ошибки сервера
		switch {
		case errors.Is(err, task.ErrTaskNotFound), errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, task.ErrTaskNotFound.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			log.Error("unhandled error in usecase GetTask", "error", err) // Логируем как Error для неизвестных
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve task")
		}
		return
	}

	log.Info("task retrieved successfully")
	resp.SendSuccess(w, r, http.StatusOK, taskResponse)
}

// GetTasks
// @Summary Get a list of tasks
// @Tags tasks
// @Description Retrieves a list of tasks based on filters and sorting. Returns personal tasks or tasks of a specified team.
// @Produce json
// @Param team_id query int false "Filter by Team ID (for team tasks)"
// @Param status query string false "Filter by status (todo, in_progress, deferred, done)" enums(todo,in_progress,deferred,done)
// @Param priority query int false "Filter by priority (1=low, 2=medium, 3=high)" enums(1,2,3)
// @Param assigned_to_user_id query int false "Filter by assigned user ID"
// @Param deadline_from query string false "Filter by deadline: start date (YYYY-MM-DD or RFC3339)" format(date-time)
// @Param deadline_to query string false "Filter by deadline: end date (YYYY-MM-DD or RFC3339)" format(date-time)
// @Param search query string false "Search by title or description"
// @Param sort_by query string false "Sort by field (created_at, updated_at, deadline, priority, status, title)" enums(created_at,updated_at,deadline,priority,status,title)
// @Param sort_order query string false "Sort order (ASC, DESC)" enums(ASC,DESC)
// @Success 200 {object} response.SuccessResponse{data=[]task.TaskResponse} "Tasks retrieved successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid query parameters"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied to team tasks"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks [get]
// @Security ApiKeyAuth
func (c *TaskController) GetTasks(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.GetTasks"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("userID not found in context")
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var reqParams task.GetTasksRequest

	// <<< ПАРСИНГ is_deleted >>>
	if isDeletedStr := r.URL.Query().Get("is_deleted"); isDeletedStr != "" {
		isDeleted, err := strconv.ParseBool(isDeletedStr)
		if err == nil {
			reqParams.IsDeleted = &isDeleted
		} else {
			log.Warn("invalid is_deleted query param", "value", isDeletedStr, "error", err)
		}
	}
	if viewTypeStr := r.URL.Query().Get("view_type"); viewTypeStr != "" {
		// Проверка на допустимые значения view_type (валидатор это тоже сделает)
		switch task.GetTasksViewType(viewTypeStr) {
		case task.ViewTypeUserCentricGlobal, task.ViewTypeUserPersonal, task.ViewTypeDefault:
			vt := task.GetTasksViewType(viewTypeStr)
			reqParams.ViewType = &vt
		default:
			log.Warn("invalid view_type query param", "value", viewTypeStr)
			// Можно вернуть ошибку 400 или дать валидатору это сделать
		}
	}

	// Парсинг остальных query параметров
	if teamIDStr := r.URL.Query().Get("team_id"); teamIDStr != "" {
		id, err := strconv.ParseUint(teamIDStr, 10, 32)
		if err == nil {
			uid := uint(id)
			reqParams.TeamID = &uid
		} else {
			log.Warn("invalid team_id query param", "value", teamIDStr, "error", err)
		}
	}
	if statusStr := r.URL.Query().Get("status"); statusStr != "" {
		reqParams.Status = &statusStr
	}
	if priorityStr := r.URL.Query().Get("priority"); priorityStr != "" {
		p, err := strconv.Atoi(priorityStr)
		if err == nil {
			reqParams.Priority = &p
		} else {
			log.Warn("invalid priority query param", "value", priorityStr, "error", err)
		}
	}
	if assignedIDStr := r.URL.Query().Get("assigned_to_user_id"); assignedIDStr != "" {
		id, err := strconv.ParseUint(assignedIDStr, 10, 32)
		if err == nil {
			uid := uint(id)
			reqParams.AssignedToUserID = &uid
		} else {
			log.Warn("invalid assigned_to_user_id query param", "value", assignedIDStr, "error", err)
		}
	}
	parseTimeParam := func(paramName string) *time.Time {
		valStr := r.URL.Query().Get(paramName)
		if valStr == "" {
			return nil
		}
		// Пытаемся распарсить сначала как RFC3339, потом как YYYY-MM-DD
		t, err := time.Parse(time.RFC3339, valStr)
		if err == nil {
			return &t
		}
		t, err = time.Parse("2006-01-02", valStr)
		if err == nil {
			return &t
		}
		log.Warn("invalid date format for query param", "param", paramName, "value", valStr)
		return nil
	}
	reqParams.DeadlineFrom = parseTimeParam("deadline_from")
	reqParams.DeadlineTo = parseTimeParam("deadline_to")

	if searchStr := r.URL.Query().Get("search"); searchStr != "" {
		reqParams.Search = &searchStr
	}
	if sortByStr := r.URL.Query().Get("sort_by"); sortByStr != "" {
		field := task.TaskSortableField(sortByStr)
		reqParams.SortBy = &field
	}
	if sortOrderStr := r.URL.Query().Get("sort_order"); sortOrderStr != "" {
		// Приводим к верхнему регистру для консистентности с enum
		order := task.SortDirection(strings.ToUpper(sortOrderStr))
		reqParams.SortOrder = &order
	}

	if err := c.validate.Struct(reqParams); err != nil {
		log.Warn("validation failed for GetTasksRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	tasksList, err := c.useCase.GetTasks(userID, reqParams)
	if err != nil {
		log.Error("usecase GetTasks failed", "error", err)
		if errors.Is(err, task.ErrTaskAccessDenied) {
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve tasks")
		}
		return
	}

	log.Info("tasks retrieved successfully", slog.Int("count", len(tasksList)))
	resp.SendSuccess(w, r, http.StatusOK, tasksList)
}

// UpdateTask (PUT)
// @Summary Update an existing task (full update)
// @Tags tasks
// @Description Fully updates a task by its ID. All mutable fields should be provided.
// @Accept json
// @Produce json
// @Param taskID path int true "Task ID"
// @Param task body task.UpdateTaskRequest true "Task update data"
// @Success 200 {object} task.TaskResponse "Task updated successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload, validation error, or invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 422 {object} response.ErrorResponse "Unprocessable Entity (e.g., assignee not in team, already completed/deleted)"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID} [put]
// @Security ApiKeyAuth
func (c *TaskController) UpdateTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.UpdateTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok { /* ... unauthorized ... */
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil { /* ... bad request ... */
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	var req task.UpdateTaskRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil { /* ... bad request ... */
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil { /* ... validation error ... */
		resp.SendValidationError(w, r, err)
		return
	}

	taskResponse, err := c.useCase.UpdateTask(uint(taskID), userID, req)
	if err != nil {
		log.Error("usecase UpdateTask failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskNotFound), errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, task.ErrTaskNotFound.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, task.ErrTaskAssigneeNotInTeam), errors.Is(err, task.ErrTaskAlreadyCompleted), errors.Is(err, task.ErrTaskAlreadyDeleted), errors.Is(err, task.ErrTaskInvalidInput):
			resp.SendError(w, r, http.StatusUnprocessableEntity, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to update task")
		}
		return
	}
	log.Info("task updated successfully (PUT)")
	resp.SendSuccess(w, r, http.StatusOK, taskResponse)
}

// PatchTask (PATCH)
// @Summary Partially update an existing task
// @Tags tasks
// @Description Partially updates a task by its ID. Only provided fields will be updated.
// @Accept json
// @Produce json
// @Param taskID path int true "Task ID"
// @Param task body task.PatchTaskRequest true "Task patch data (fields to update)"
// @Success 200 {object} task.TaskResponse "Task patched successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload, validation error, or invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 422 {object} response.ErrorResponse "Unprocessable Entity (e.g., assignee not in team, already completed/deleted)"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID} [patch]
// @Security ApiKeyAuth
func (c *TaskController) PatchTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.PatchTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok { /* ... unauthorized ... */
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil { /* ... bad request ... */
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	var req task.PatchTaskRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil { /* ... bad request ... */
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil { /* ... validation error ... */
		resp.SendValidationError(w, r, err)
		return
	}

	// Проверка, что хоть что-то передано для PATCH
	if isEmptyPatchRequest(req) {
		log.Warn("empty patch request received")
		resp.SendError(w, r, http.StatusBadRequest, "No fields provided for patch update")
		return
	}

	taskResponse, err := c.useCase.PatchTask(uint(taskID), userID, req)
	if err != nil {
		log.Error("usecase PatchTask failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskNotFound), errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, task.ErrTaskNotFound.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, task.ErrTaskAssigneeNotInTeam), errors.Is(err, task.ErrTaskAlreadyCompleted), errors.Is(err, task.ErrTaskAlreadyDeleted), errors.Is(err, task.ErrTaskInvalidInput):
			resp.SendError(w, r, http.StatusUnprocessableEntity, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to patch task")
		}
		return
	}
	log.Info("task patched successfully")
	resp.SendSuccess(w, r, http.StatusOK, taskResponse)
}

// isEmptyPatchRequest проверяет, все ли поля в PatchTaskRequest равны nil.
func isEmptyPatchRequest(req task.PatchTaskRequest) bool {
	return req.Title == nil &&
		req.Description == nil &&
		req.Deadline == nil &&
		req.ClearDeadline == nil &&
		req.Status == nil &&
		req.Priority == nil &&
		req.AssignedToUserID == nil &&
		req.ClearAssignedTo == nil &&
		req.IsDeleted == nil // <<< ДОБАВЛЕНО
}

// DeleteTask
// @Summary Delete a task
// @Tags tasks
// @Description Logically deletes a task by its ID.
// @Produce json
// @Param taskID path int true "Task ID"
// @Success 204 "Task deleted successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID} [delete]
// @Security ApiKeyAuth
func (c *TaskController) DeleteTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.DeleteTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok { /* ... unauthorized ... */
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil { /* ... bad request ... */
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	err = c.useCase.DeleteTask(uint(taskID), userID)
	if err != nil {
		log.Error("usecase DeleteTask failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskNotFound), errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, task.ErrTaskNotFound.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to delete task")
		}
		return
	}

	log.Info("task deleted successfully")
	resp.SendOK(w, r, http.StatusNoContent) // 204 No Content для успешного удаления
}

// <<< НОВЫЙ МЕТОД >>>
// RestoreTask
// @Summary Restore a deleted task
// @Tags tasks
// @Description Restores a logically deleted task by its ID, making it active again.
// @Produce json
// @Param taskID path int true "Task ID"
// @Success 200 {object} task.TaskResponse "Task restored successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID}/restore [post]
// @Security ApiKeyAuth
func (c *TaskController) RestoreTask(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.RestoreTask"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	taskResponse, err := c.useCase.RestoreTask(uint(taskID), userID)
	if err != nil {
		log.Error("usecase RestoreTask failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, task.ErrTaskInvalidInput):
			resp.SendError(w, r, http.StatusUnprocessableEntity, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to restore task")
		}
		return
	}
	log.Info("task restored successfully")
	resp.SendSuccess(w, r, http.StatusOK, taskResponse)
}

// <<< НОВЫЙ МЕТОД >>>
// DeleteTaskPermanently
// @Summary Permanently delete a task
// @Tags tasks
// @Description Permanently deletes a task from the database. This action is irreversible.
// @Produce json
// @Param taskID path int true "Task ID"
// @Success 204 "Task permanently deleted successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Task ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied"
// @Failure 404 {object} response.ErrorResponse "Task not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /tasks/{taskID}/permanent [delete]
// @Security ApiKeyAuth
func (c *TaskController) DeleteTaskPermanently(w http.ResponseWriter, r *http.Request) {
	op := "TaskController.DeleteTaskPermanently"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	taskIDStr := chi.URLParam(r, "taskID")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Task ID")
		return
	}
	log = log.With(slog.Uint64("taskID", taskID))

	err = c.useCase.DeleteTaskPermanently(uint(taskID), userID)
	if err != nil {
		log.Error("usecase DeleteTaskPermanently failed", "error", err)
		switch {
		case errors.Is(err, task.ErrTaskNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, task.ErrTaskAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to permanently delete task")
		}
		return
	}
	log.Info("task permanently deleted successfully")
	resp.SendOK(w, r, http.StatusNoContent)
}
