// internal/modules/task/entity.go
package task

import (
	"net/http" // Для Controller
	"server/internal/modules/tag"
	"time"
)

// Task - GORM модель для таблицы 'tasks'
type Task struct {
	TaskID           uint       `gorm:"primaryKey;column:task_id;autoIncrement"`
	Title            string     `gorm:"type:varchar(255);not null;column:title"`
	Description      *string    `gorm:"type:text;column:description"`
	Deadline         *time.Time `gorm:"column:deadline"`
	Status           string     `gorm:"type:varchar(50);default:'todo';not null;column:status"`
	Priority         int        `gorm:"default:1;not null;column:priority"`
	CreatedByUserID  uint       `gorm:"column:created_by_user_id;not null"`
	AssignedToUserID *uint      `gorm:"column:assigned_to_user_id"`
	TeamID           *uint      `gorm:"column:team_id"`
	CreatedAt        time.Time  `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt        time.Time  `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
	CompletedAt      *time.Time `gorm:"column:completed_at"`
	IsDeleted        bool       `gorm:"default:false;not null;column:is_deleted"`
	DeletedAt        *time.Time `gorm:"column:deleted_at"`
	DeletedByUserID  *uint      `gorm:"column:deleted_by_user_id"`
}

func (Task) TableName() string {
	return "tasks"
}

// TaskResponse - DTO для ответа API (получение задачи/задач)
type TaskResponse struct {
	TaskID           uint               `json:"task_id"`
	Title            string             `json:"title"`
	Description      *string            `json:"description,omitempty"`
	Deadline         *time.Time         `json:"deadline,omitempty"`
	Status           string             `json:"status"`
	Priority         int                `json:"priority"`
	CreatedByUserID  uint               `json:"created_by_user_id"`
	AssignedToUserID *uint              `json:"assigned_to_user_id,omitempty"`
	TeamID           *uint              `json:"team_id,omitempty"`
	Tags             []*tag.TagResponse `json:"tags,omitempty"`
	CreatedAt        time.Time          `json:"created_at"`
	UpdatedAt        time.Time          `json:"updated_at"`
	CompletedAt      *time.Time         `json:"completed_at,omitempty"`
	IsDeleted        bool               `json:"is_deleted"`
	DeletedAt        *time.Time         `json:"deleted_at,omitempty"`         // <<< ДОБАВЛЕНО
	DeletedByUserID  *uint              `json:"deleted_by_user_id,omitempty"` // <<< ДОБАВЛЕНО
}

// --- Конвертеры ---
func ToTaskResponse(task *Task) *TaskResponse {
	if task == nil {
		return nil
	}
	return &TaskResponse{
		TaskID:           task.TaskID,
		Title:            task.Title,
		Description:      task.Description,
		Deadline:         task.Deadline,
		Status:           task.Status,
		Priority:         task.Priority,
		CreatedByUserID:  task.CreatedByUserID,
		AssignedToUserID: task.AssignedToUserID,
		TeamID:           task.TeamID,
		CreatedAt:        task.CreatedAt,
		UpdatedAt:        task.UpdatedAt,
		CompletedAt:      task.CompletedAt,
		IsDeleted:        task.IsDeleted,
		DeletedAt:        task.DeletedAt,       // <<< ДОБАВЛЕНО
		DeletedByUserID:  task.DeletedByUserID, // <<< ДОБАВЛЕНО
	}
}

func ToTaskResponseList(tasks []*Task) []*TaskResponse {
	if len(tasks) == 0 {
		return []*TaskResponse{}
	}
	responses := make([]*TaskResponse, len(tasks))
	for i, task := range tasks {
		responses[i] = ToTaskResponse(task)
	}
	return responses
}

// --- Параметры для фильтрации и сортировки ---
type SortDirection string

const (
	SortDirectionAsc  SortDirection = "ASC"
	SortDirectionDesc SortDirection = "DESC"
)

type TaskSortableField string

const (
	FieldCreatedAt TaskSortableField = "created_at"
	FieldUpdatedAt TaskSortableField = "updated_at"
	FieldDeadline  TaskSortableField = "deadline"
	FieldPriority  TaskSortableField = "priority"
	FieldStatus    TaskSortableField = "status"
	FieldTitle     TaskSortableField = "title"
)

type GetTasksViewType string

const (
	ViewTypeDefault           GetTasksViewType = ""
	ViewTypeUserCentricGlobal GetTasksViewType = "global"
	ViewTypeUserPersonal      GetTasksViewType = "personal"
)

type GetTasksParams struct {
	UserID           uint
	ViewType         GetTasksViewType
	TeamID           *uint
	Status           *string
	Priority         *int
	AssignedToUserID *uint
	DeadlineFrom     *time.Time
	DeadlineTo       *time.Time
	SearchQuery      *string
	SortBy           TaskSortableField
	SortOrder        SortDirection
	IsDeleted        *bool // <<< ДОБАВЛЕНО
}

type GetTasksRequest struct {
	ViewType         *GetTasksViewType  `form:"view_type" validate:"omitempty,oneof=global personal"`
	TeamID           *uint              `form:"team_id"`
	Status           *string            `form:"status" validate:"omitempty,oneof=todo in_progress deferred done"`
	Priority         *int               `form:"priority" validate:"omitempty,min=1,max=3"`
	AssignedToUserID *uint              `form:"assigned_to_user_id"`
	DeadlineFrom     *time.Time         `form:"deadline_from"`
	DeadlineTo       *time.Time         `form:"deadline_to"`
	Search           *string            `form:"search" validate:"omitempty,min=1"`
	SortBy           *TaskSortableField `form:"sort_by" validate:"omitempty,oneof=created_at updated_at deadline priority status title"`
	SortOrder        *SortDirection     `form:"sort_order" validate:"omitempty,oneof=ASC DESC"`
	IsDeleted        *bool              `form:"is_deleted"` // <<< ДОБАВЛЕНО
}

type CreateTaskRequest struct {
	Title            string     `json:"title" validate:"required,min=1,max=255"`
	Description      *string    `json:"description,omitempty" validate:"omitempty,max=65535"`
	Deadline         *time.Time `json:"deadline,omitempty"`
	Status           *string    `json:"status,omitempty" validate:"omitempty,oneof=todo in_progress deferred done"`
	Priority         *int       `json:"priority,omitempty" validate:"omitempty,min=1,max=3"`
	AssignedToUserID *uint      `json:"assigned_to_user_id,omitempty"`
	TeamID           *uint      `json:"team_id,omitempty"`
	UserTagIDs       []uint     `json:"user_tag_ids,omitempty"`
	TeamTagIDs       []uint     `json:"team_tag_ids,omitempty"`
}

type UpdateTaskRequest struct {
	Title            string     `json:"title" validate:"required,min=1,max=255"`
	Description      *string    `json:"description" validate:"omitempty,max=65535"`
	Deadline         *time.Time `json:"deadline"`
	Status           string     `json:"status" validate:"required,oneof=todo in_progress deferred done"`
	Priority         int        `json:"priority" validate:"required,min=1,max=3"`
	AssignedToUserID *uint      `json:"assigned_to_user_id"`
	UserTagIDs       *[]uint    `json:"user_tag_ids,omitempty"`
	TeamTagIDs       *[]uint    `json:"team_tag_ids,omitempty"`
}

type PatchTaskRequest struct {
	Title            *string    `json:"title,omitempty" validate:"omitempty,min=1,max=255"`
	Description      *string    `json:"description,omitempty" validate:"omitempty,max=65535"`
	Deadline         *time.Time `json:"deadline,omitempty"`
	ClearDeadline    *bool      `json:"clear_deadline,omitempty"`
	Status           *string    `json:"status,omitempty" validate:"omitempty,oneof=todo in_progress deferred done"`
	Priority         *int       `json:"priority,omitempty" validate:"omitempty,min=1,max=3"`
	AssignedToUserID *uint      `json:"assigned_to_user_id,omitempty"`
	ClearAssignedTo  *bool      `json:"clear_assigned_to,omitempty"`
	UserTagIDs       *[]uint    `json:"user_tag_ids,omitempty"`
	TeamTagIDs       *[]uint    `json:"team_tag_ids,omitempty"`
	IsDeleted        *bool      `json:"is_deleted,omitempty"` // <<< ДОБАВЛЕНО
}

type Controller interface {
	CreateTask(w http.ResponseWriter, r *http.Request)
	GetTask(w http.ResponseWriter, r *http.Request)
	GetTasks(w http.ResponseWriter, r *http.Request)
	UpdateTask(w http.ResponseWriter, r *http.Request)
	PatchTask(w http.ResponseWriter, r *http.Request)
	DeleteTask(w http.ResponseWriter, r *http.Request)
	RestoreTask(w http.ResponseWriter, r *http.Request)           // <<< ДОБАВЛЕНО
	DeleteTaskPermanently(w http.ResponseWriter, r *http.Request) // <<< ДОБАВЛЕНО
}

type UseCase interface {
	CreateTask(userID uint, req CreateTaskRequest) (*TaskResponse, error)
	GetTask(taskID uint, userID uint) (*TaskResponse, error)
	GetTasks(userID uint, reqParams GetTasksRequest) ([]*TaskResponse, error)
	UpdateTask(taskID uint, userID uint, req UpdateTaskRequest) (*TaskResponse, error)
	PatchTask(taskID uint, userID uint, req PatchTaskRequest) (*TaskResponse, error)
	DeleteTask(taskID uint, userID uint) error
	RestoreTask(taskID uint, userID uint) (*TaskResponse, error) // <<< ДОБАВЛЕНО
	DeleteTaskPermanently(taskID uint, userID uint) error        // <<< ДОБАВЛЕНО
}

type Repo interface {
	CreateTask(taskModel *Task) (*Task, error)
	GetTaskByID(taskID uint, userID uint) (*Task, error)
	GetTaskByIDIncludingDeleted(taskID uint) (*Task, error) // <<< ДОБАВЛЕНО
	GetTasks(params GetTasksParams) ([]*Task, error)
	UpdateTask(taskModel *Task) (*Task, error)
	DeleteTask(taskID uint, userID uint, isTeamTask bool, deletedByUserID *uint) error
	DeleteTaskPermanently(taskID uint) error // <<< ДОБАВЛЕНО

	GetTask(taskID uint) (*Task, error)
	SaveTask(task *Task) error
	DeleteTaskCache(taskID uint) error
	GetTasksCache(cacheKey string) ([]*Task, error)
	SaveTasks(cacheKey string, tasks []*Task) error
	InvalidateTasks(keys ...string) error
}
