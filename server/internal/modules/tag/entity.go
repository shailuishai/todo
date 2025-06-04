package tag

import (
	"net/http"
	"time"
	// "server/internal/modules/user" // Понадобится для UserLiteResponse в TagResponse, если тег создается пользователем
)

// --- GORM Модели ---

// UserTag - GORM модель для таблицы 'user_tags'
type UserTag struct {
	UserTagID   uint      `gorm:"primaryKey;column:user_tag_id;autoIncrement"`
	OwnerUserID uint      `gorm:"not null;column:owner_user_id"` // Внешний ключ к Users
	Name        string    `gorm:"type:varchar(50);not null;column:name"`
	Color       *string   `gorm:"type:varchar(7);column:color"` // HEX color, nullable
	CreatedAt   time.Time `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt   time.Time `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`

	//CONSTRAINT unique_user_tag_name_per_owner UNIQUE (owner_user_id, name) - обрабатывается в БД
}

func (UserTag) TableName() string {
	return "usertags"
}

// TeamTag - GORM модель для таблицы 'team_tags'
type TeamTag struct {
	TeamTagID uint    `gorm:"primaryKey;column:team_tag_id;autoIncrement"`
	TeamID    uint    `gorm:"not null;column:team_id"` // Внешний ключ к Teams
	Name      string  `gorm:"type:varchar(50);not null;column:name"`
	Color     *string `gorm:"type:varchar(7);column:color"` // HEX color, nullable
	// CreatedByUserID *uint     `gorm:"column:created_by_user_id"` // Опционально, кто создал тег в команде
	CreatedAt time.Time `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt time.Time `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`

	//CONSTRAINT unique_team_tag_name_per_team UNIQUE (team_id, name) - обрабатывается в БД
}

func (TeamTag) TableName() string {
	return "teamtags"
}

// TaskTag - GORM модель для таблицы 'task_tags' (связующая таблица)
// Эту модель мы уже определили в схеме, здесь ее дублировать не обязательно,
// GORM может работать со связями "многие-ко-многим" через JoinTable.
// Однако, если есть дополнительные поля в связующей таблице или мы хотим явно ею управлять,
// то модель нужна. В нашем случае есть task_tag_id, user_tag_id, team_tag_id.
// Для простоты управления через GORM, явная модель TaskTag будет полезна.
type TaskTag struct {
	TaskTagID uint  `gorm:"primaryKey;column:task_tag_id;autoIncrement"`
	TaskID    uint  `gorm:"not null;column:task_id"`
	UserTagID *uint `gorm:"column:user_tag_id"` // Nullable
	TeamTagID *uint `gorm:"column:team_tag_id"` // Nullable

	// Связи для GORM, если нужны для Preload
	// UserTag   UserTag `gorm:"foreignKey:UserTagID"`
	// TeamTag   TeamTag `gorm:"foreignKey:TeamTagID"`
	// Task      task.Task `gorm:"foreignKey:TaskID"` // Потребует импорта task
}

func (TaskTag) TableName() string {
	return "tasktags"
}

// --- DTO для Ответов API ---

// TagResponse - общее DTO для ответа API при получении тега (пользовательского или командного)
type TagResponse struct {
	ID        uint      `json:"id"` // UserTagID или TeamTagID
	Name      string    `json:"name"`
	Color     *string   `json:"color,omitempty"`
	Type      string    `json:"type"`     // "user" или "team"
	OwnerID   uint      `json:"owner_id"` // OwnerUserID для "user", TeamID для "team"
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// --- DTO для Запросов API (размещаем здесь согласно твоему уточнению) ---

// CreateUserTagRequest - DTO для создания пользовательского тега.
type CreateUserTagRequest struct {
	Name  string  `json:"name" validate:"required,min=1,max=50"`
	Color *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
}

// UpdateUserTagRequest - DTO для обновления пользовательского тега.
type UpdateUserTagRequest struct {
	Name  *string `json:"name,omitempty" validate:"omitempty,min=1,max=50"`
	Color *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
}

// CreateTeamTagRequest - DTO для создания командного тега.
type CreateTeamTagRequest struct {
	Name  string  `json:"name" validate:"required,min=1,max=50"`
	Color *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
}

// UpdateTeamTagRequest - DTO для обновления командного тега.
type UpdateTeamTagRequest struct {
	Name  *string `json:"name,omitempty" validate:"omitempty,min=1,max=50"`
	Color *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
}

// --- Интерфейсы для модуля tag ---

type Controller interface {
	// User Tags
	CreateUserTag(w http.ResponseWriter, r *http.Request)
	GetUserTags(w http.ResponseWriter, r *http.Request)
	UpdateUserTag(w http.ResponseWriter, r *http.Request)
	DeleteUserTag(w http.ResponseWriter, r *http.Request)

	// Team Tags
	CreateTeamTag(w http.ResponseWriter, r *http.Request)
	GetTeamTags(w http.ResponseWriter, r *http.Request)
	UpdateTeamTag(w http.ResponseWriter, r *http.Request)
	DeleteTeamTag(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	// User Tags
	CreateUserTag(userID uint, req CreateUserTagRequest) (*TagResponse, error)
	GetUserTags(userID uint) ([]*TagResponse, error)
	UpdateUserTag(tagID uint, userID uint, req UpdateUserTagRequest) (*TagResponse, error)
	DeleteUserTag(tagID uint, userID uint) error

	// Team Tags
	CreateTeamTag(teamID uint, userID uint, req CreateTeamTagRequest) (*TagResponse, error) // userID - кто создает/имеет права
	GetTeamTags(teamID uint, userID uint) ([]*TagResponse, error)                           // userID - для проверки членства в команде
	UpdateTeamTag(tagID uint, teamID uint, userID uint, req UpdateTeamTagRequest) (*TagResponse, error)
	DeleteTeamTag(tagID uint, teamID uint, userID uint) error

	// Методы для использования TaskUseCase (валидация и получение тегов для привязки)
	// Возвращают полные модели, чтобы TaskUseCase мог получить ID.
	ValidateAndGetUserTags(userID uint, tagIDs []uint) ([]*UserTag, error)
	ValidateAndGetTeamTags(teamID uint, userID uint, tagIDs []uint) ([]*TeamTag, error) // userID для проверки прав на команду
}

// Repo определяет методы для взаимодействия с хранилищем данных для тегов.
// В файле internal/modules/tag/entity.go

type Repo interface {
	// User Tags
	CreateUserTag(tag *UserTag) (*UserTag, error)
	GetUserTagByID(tagID uint, ownerUserID uint) (*UserTag, error)
	GetUserTagsByOwnerID(ownerUserID uint) ([]*UserTag, error)
	UpdateUserTag(tag *UserTag) (*UserTag, error)
	DeleteUserTag(tagID uint, ownerUserID uint) error
	FindUserTagsByIDs(ownerUserID uint, tagIDs []uint) ([]*UserTag, error)

	// Team Tags
	CreateTeamTag(tag *TeamTag) (*TeamTag, error)
	GetTeamTagByID(tagID uint, teamID uint) (*TeamTag, error)
	GetTeamTagsByTeamID(teamID uint) ([]*TeamTag, error)
	UpdateTeamTag(tag *TeamTag) (*TeamTag, error)
	DeleteTeamTag(tagID uint, teamID uint) error
	FindTeamTagsByIDs(teamID uint, tagIDs []uint) ([]*TeamTag, error)

	// TaskTags
	ClearTaskTags(taskID uint) error
	AddTaskUserTag(taskID uint, userTagID uint) error
	AddTaskTeamTag(taskID uint, teamTagID uint) error
	GetTaskTags(taskID uint) ([]*TaskTag, error)
}
