package team

import (
	"database/sql/driver"
	"fmt"
	"net/http"
	usermodels "server/internal/modules/user"

	"time"
)

// --- Enums ---

// TeamMemberRole - кастомный тип для ролей в команде
type TeamMemberRole string

const (
	RoleOwner  TeamMemberRole = "owner"
	RoleAdmin  TeamMemberRole = "admin"
	RoleEditor TeamMemberRole = "editor" // Может управлять задачами команды
	RoleMember TeamMemberRole = "member" // Может создавать задачи и менять статус назначенных ему
)

// Scan Yemeni, чтобы GORM мог читать enum из БД
func (r *TeamMemberRole) Scan(value interface{}) error {
	strVal, ok := value.(string)
	if !ok {
		byteVal, okByte := value.([]byte)
		if !okByte {
			return fmt.Errorf("failed to scan TeamMemberRole: value is not string or []byte, got %T", value)
		}
		strVal = string(byteVal)
	}
	switch strVal {
	case "owner", "admin", "editor", "member":
		*r = TeamMemberRole(strVal)
		return nil
	default:
		return fmt.Errorf("invalid value for TeamMemberRole: %s", strVal)
	}
}

// Value Yemeni, чтобы GORM мог записывать enum в БД
func (r TeamMemberRole) Value() (driver.Value, error) {
	switch r {
	case RoleOwner, RoleAdmin, RoleEditor, RoleMember:
		return string(r), nil
	default:
		return nil, fmt.Errorf("invalid TeamMemberRole value: %s", r)
	}
}

// IsValid проверяет, является ли значение TeamMemberRole допустимым
func (r TeamMemberRole) IsValid() bool {
	switch r {
	case RoleOwner, RoleAdmin, RoleEditor, RoleMember:
		return true
	}
	return false
}

// --- GORM Модели ---

// Team - GORM модель для таблицы 'teams'
type Team struct {
	TeamID          uint       `gorm:"primaryKey;column:team_id;autoIncrement"`
	Name            string     `gorm:"type:varchar(100);not null;column:name"`
	Description     *string    `gorm:"type:text;column:description"`
	Color           *string    `gorm:"type:varchar(7);column:color"`
	ImageURLS3Key   *string    `gorm:"type:varchar(255);column:image_url_s3_key"`
	CreatedByUserID uint       `gorm:"column:created_by_user_id"` // Внешний ключ к Users
	CreatedAt       time.Time  `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt       time.Time  `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
	IsDeleted       bool       `gorm:"default:false;not null;column:is_deleted"`
	DeletedAt       *time.Time `gorm:"column:deleted_at"`

	// Отношения для GORM (если нужны для Preload/Joins)
	// Members []UserTeamMembership `gorm:"foreignKey:TeamID"`
	// Tasks   []task.Task          `gorm:"foreignKey:TeamID"` // Потребует импорта task
}

func (Team) TableName() string {
	return "teams"
}

// UserTeamMembership - GORM модель для таблицы 'user_team_memberships'
type UserTeamMembership struct {
	UserID   uint           `gorm:"primaryKey;column:user_id;not null"` // Внешний ключ к Users
	TeamID   uint           `gorm:"primaryKey;column:team_id;not null"` // Внешний ключ к Teams
	Role     TeamMemberRole `gorm:"type:team_member_role;not null;default:'member';column:role"`
	JoinedAt time.Time      `gorm:"column:joined_at;not null;default:CURRENT_TIMESTAMP"`

	// Отношения для GORM
	// User User `gorm:"foreignKey:UserID"` // Потребует импорта user
	// Team Team `gorm:"foreignKey:TeamID"`
}

func (UserTeamMembership) TableName() string {
	return "userteammemberships" // Обязательно с двойными кавычками
}

// --- DTO для Ответов API ---

// UserLiteResponse - упрощенное DTO для отображения информации о пользователе (например, в списке участников)
type UserLiteResponse struct {
	UserID      uint    `json:"user_id"`
	Login       string  `json:"login"`
	AvatarURL   *string `json:"avatar_url,omitempty" gorm:"type:varchar(255);column:avatar_s3_key"`
	AccentColor *string `json:"accent_color,omitempty"`
}

// TeamMemberResponse - DTO для отображения участника команды с его ролью
type TeamMemberResponse struct {
	User     UserLiteResponse `json:"user"` // Информация о пользователе
	Role     TeamMemberRole   `json:"role"`
	JoinedAt time.Time        `json:"joined_at"`
}

// TeamResponse - DTO для ответа API при получении информации о команде (без списка участников/задач)
type TeamResponse struct {
	TeamID          uint            `json:"team_id"`
	Name            string          `json:"name"`
	Description     *string         `json:"description,omitempty"`
	Color           *string         `json:"color,omitempty"`
	ImageURL        *string         `json:"image_url,omitempty"` // Полный URL, будет формироваться в UseCase
	CreatedByUserID uint            `json:"created_by_user_id"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
	IsDeleted       bool            `json:"is_deleted"`
	CurrentUserRole *TeamMemberRole `json:"current_user_role,omitempty"` // Роль текущего пользователя в этой команде
	MemberCount     int             `json:"member_count"`
}

// TeamDetailResponse - DTO для ответа API при получении детальной информации о команде (с участниками)
type TeamDetailResponse struct {
	TeamResponse                       // Встраиваем базовую информацию о команде
	Members      []*TeamMemberResponse `json:"members,omitempty"`
	// TODO: Возможно, добавить сюда количество активных задач или другую сводную информацию
}

// TeamInviteLinkResponse - DTO для ответа при генерации ссылки-приглашения
type TeamInviteLinkResponse struct {
	InviteLink string    `json:"invite_link"`
	ExpiresAt  time.Time `json:"expires_at"` // Когда ссылка перестанет действовать
}

// TeamInviteTokenResponse - DTO для ответа при генерации токена-приглашения
type TeamInviteTokenResponse struct {
	InviteToken string         `json:"invite_token"` // Сам токен
	InviteLink  string         `json:"invite_link"`  // Полная ссылка-приглашение (формируется на фронте или здесь)
	ExpiresAt   time.Time      `json:"expires_at"`   // Когда токен перестанет действовать
	RoleOnJoin  TeamMemberRole `json:"role_on_join"` // Роль, которая будет назначена при вступлении
}

// --- Конвертеры (примеры, будут расширяться) ---

func ToTeamResponse(team *Team, imageBaseURL string, currentUserRole *TeamMemberRole) *TeamResponse {
	if team == nil {
		return nil
	}
	var fullImageURL *string
	if team.ImageURLS3Key != nil && *team.ImageURLS3Key != "" && imageBaseURL != "" {
		// Логика формирования полного URL аналогична аватару пользователя
		// cleanBaseURL := strings.TrimSuffix(imageBaseURL, "/")
		// cleanKey := strings.TrimPrefix(*team.ImageURLS3Key, "/")
		// urlValue := cleanBaseURL + "/" + cleanKey
		// fullImageURL = &urlValue
		// Пока что заглушка, т.к. нет s3BaseURL для командных картинок
		urlValue := imageBaseURL + "/" + *team.ImageURLS3Key // Упрощенно
		fullImageURL = &urlValue

	}
	return &TeamResponse{
		TeamID:          team.TeamID,
		Name:            team.Name,
		Description:     team.Description,
		Color:           team.Color,
		ImageURL:        fullImageURL,
		CreatedByUserID: team.CreatedByUserID,
		CreatedAt:       team.CreatedAt,
		UpdatedAt:       team.UpdatedAt,
		IsDeleted:       team.IsDeleted,
		CurrentUserRole: currentUserRole,
	}
}

// ToTeamMemberResponse (потребует User GORM модель или UserLiteResponse как входной параметр)
// func ToTeamMemberResponse(membership *UserTeamMembership, user *user.User, avatarBaseURL string) *TeamMemberResponse { ... }

// --- Параметры для фильтрации и сортировки (если нужны для списков команд) ---
type GetTeamsRequestParams struct {
	UserID     uint    // Для получения команд, где пользователь является участником
	SearchName *string // Для поиска команд по названию
	// TODO: Добавить сортировку, если нужно
}

type CreateTeamRequest struct {
	Name        string  `json:"name" validate:"required,min=1,max=100"`
	Description *string `json:"description,omitempty" validate:"omitempty,max=65535"`   // Max length для TEXT
	Color       *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"` // Валидация цвета
}

// UpdateTeamDetailsRequest - DTO для обновления деталей команды (PUT/PATCH).
// Для PATCH все поля будут указателями. Для PUT - часть обязательна.
// В UseCase будем решать, как обрабатывать PATCH (только измененные поля).
// Этот DTO будет использоваться в multipart/form-data вместе с файлом изображения.
type UpdateTeamDetailsRequest struct {
	Name        *string `json:"name,omitempty" validate:"omitempty,min=1,max=100"`
	Description *string `json:"description,omitempty" validate:"omitempty,max=65535"`
	Color       *string `json:"color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
	ResetImage  *bool   `json:"reset_image,omitempty"` // Флаг для сброса изображения команды
}

// GetMyTeamsRequest - DTO для параметров запроса списка команд пользователя.
type GetMyTeamsRequest struct {
	Search *string `form:"search" validate:"omitempty,min=1"` // Поисковый запрос по названию команды
	// TODO: Добавить параметры сортировки, если потребуется в будущем
	// SortBy    *string `form:"sort_by"`
	// SortOrder *string `form:"sort_order"`
}

// --- DTO для Управления Участниками ---

// AddTeamMemberRequest - DTO для добавления участника в команду.
type AddTeamMemberRequest struct {
	// Пользователь будет идентифицироваться по UserID или Login/Email.
	// Пока сделаем UserID, т.к. поиск по логину/email - это отдельная логика.
	// Если добавляем по логину/email, то нужен будет UseCase пользователя для поиска.
	// Для простоты начнем с UserID.
	UserID uint            `json:"user_id" validate:"required,gt=0"`
	Role   *TeamMemberRole `json:"role,omitempty" validate:"omitempty,oneof=admin editor member"` // Owner не назначается так
}

// UpdateTeamMemberRoleRequest - DTO для изменения роли участника.
type UpdateTeamMemberRoleRequest struct {
	Role TeamMemberRole `json:"role" validate:"required,oneof=admin editor member"` // Owner не изменяется так
}

type GenerateInviteTokenRequest struct {
	// Срок действия токена в часах. Если не указан, используется значение по умолчанию.
	ExpiresInHours *uint `json:"expires_in_hours,omitempty" validate:"omitempty,min=1,max=720"` // Например, от 1 часа до 30 дней (720 часов)
	// Роль, которая будет назначена пользователю при вступлении по этому токену.
	// По умолчанию 'member'. Owner/Admin не могут быть назначены через токен.
	RoleToAssign *TeamMemberRole `json:"role_to_assign,omitempty" validate:"omitempty,oneof=editor member"`
	// Можно добавить поле для максимального количества использований токена (пока не будем усложнять)
	// MaxUses *int `json:"max_uses,omitempty" validate:"omitempty,min=1"`
}

// JoinTeamByTokenRequest - DTO для присоединения к команде по токену.
type JoinTeamByTokenRequest struct {
	InviteToken string `json:"invite_token" validate:"required"`
}

// --- Интерфейсы для модуля team ---

type Controller interface {
	CreateTeam(w http.ResponseWriter, r *http.Request)
	GetTeam(w http.ResponseWriter, r *http.Request)
	GetMyTeams(w http.ResponseWriter, r *http.Request)
	UpdateTeam(w http.ResponseWriter, r *http.Request)
	DeleteTeam(w http.ResponseWriter, r *http.Request)

	GetTeamMembers(w http.ResponseWriter, r *http.Request)
	AddTeamMember(w http.ResponseWriter, r *http.Request)
	UpdateTeamMemberRole(w http.ResponseWriter, r *http.Request)
	RemoveTeamMember(w http.ResponseWriter, r *http.Request)
	LeaveTeam(w http.ResponseWriter, r *http.Request)

	GenerateInviteToken(w http.ResponseWriter, r *http.Request) // Новый метод
	JoinTeamByToken(w http.ResponseWriter, r *http.Request)     // Новый метод
}

type UseCase interface {
	CreateTeam(userID uint, req CreateTeamRequest) (*TeamResponse, error)
	GetTeamByID(teamID uint, userID uint) (*TeamDetailResponse, error)
	GetMyTeams(userID uint, params GetMyTeamsRequest) ([]*TeamResponse, error)
	UpdateTeamDetails(teamID uint, userID uint, req UpdateTeamDetailsRequest, imageFileHeader interface{}) (*TeamResponse, error)
	DeleteTeam(teamID uint, userID uint) error

	GetTeamMembers(teamID uint, userID uint) ([]*TeamMemberResponse, error)
	AddTeamMember(teamID uint, currentUserID uint, req AddTeamMemberRequest) (*TeamMemberResponse, error)
	UpdateTeamMemberRole(teamID uint, currentUserID uint, targetUserID uint, req UpdateTeamMemberRoleRequest) (*TeamMemberResponse, error)
	RemoveTeamMember(teamID uint, currentUserID uint, targetUserID uint) error
	LeaveTeam(teamID uint, userID uint) error

	GenerateInviteToken(teamID uint, userID uint, req GenerateInviteTokenRequest) (*TeamInviteTokenResponse, error) // Новый метод
	JoinTeamByToken(tokenValue string, userID uint) (*TeamResponse, error)                                          // Новый метод

	// Методы TeamService ... (без изменений)
	IsUserMember(userID, teamID uint) (bool, error)
	GetUserRoleInTeam(userID, teamID uint) (*TeamMemberRole, error)
	CanUserCreateTeamTask(userID, teamID uint) (bool, error)
	CanUserEditTeamTaskDetails(userID, teamID uint) (bool, error)
	CanUserChangeTeamTaskStatus(userID, teamID uint, taskAssignedToUserID *uint) (bool, error)
	CanUserDeleteTeamTask(userID, teamID uint, taskCreatorID uint) (bool, error)
	IsUserTeamMemberWithUserID(teamID uint, targetUserID uint) (bool, error)
}

// Repo определяет методы для взаимодействия с хранилищем данных для команд.
type Repo interface {
	// Team CRUD ... (без изменений)
	// Membership ... (без изменений)
	// Задачи ... (без изменений)
	// S3 ... (без изменений)
	CreateTeam(teamModel *Team) (*Team, error)
	GetTeamByID(teamID uint) (*Team, error)
	GetTeamsByUserID(userID uint, searchName *string) ([]*Team, error)
	UpdateTeam(teamModel *Team) (*Team, error)
	CreateMembership(membership *UserTeamMembership) error
	GetMembership(userID, teamID uint) (*UserTeamMembership, error)
	GetTeamMemberships(teamID uint) ([]*UserTeamMembership, error)
	AddTeamMember(membership *UserTeamMembership) (*UserTeamMembership, error)
	UpdateTeamMemberRole(userID, teamID uint, newRole TeamMemberRole) (*UserTeamMembership, error)
	RemoveTeamMember(userID, teamID uint) error
	IsTeamMember(userID, teamID uint) (bool, error)
	LogicallyDeleteTasksByTeamID(teamID uint, deletedByUserID uint) error

	// Методы для кэширования (остаются для проксирования к TeamCache)
	GetTeam(teamID uint) (*Team, error)
	SaveTeam(teamModel *Team) error
	DeleteTeam(teamID uint) error
	GetTeamMembers(teamID uint) ([]*UserTeamMembership, error)
	GetTeamMembershipsCount(teamID uint) (int, error)
	SaveTeamMembers(teamID uint, members []*UserTeamMembership) error
	DeleteTeamMembers(teamID uint) error
	GetUserTeams(userID uint) ([]*Team, error)
	SaveUserTeams(userID uint, teams []*Team) error
	DeleteUserTeams(userID uint) error

	GetUserLiteByID(userID uint) (*UserLiteResponse, error)
	GetUserByLoginOrEmail(identifier string) (*usermodels.User, error)

	UploadTeamImage(bucketName string, s3Key string, imageBytes []byte, contentType string) error
	DeleteTeamImage(bucketName string, s3Key string) error
	GetTeamImagePublicURL(s3Key string) string

	// Методы для хранения и проверки токенов приглашений (могут быть реализованы через Cache)
	SaveInviteToken(token string, teamID uint, roleToAssign TeamMemberRole, expiresAt time.Time) error
	GetInviteTokenData(token string) (teamID uint, roleToAssign TeamMemberRole, isValid bool, err error)
	DeleteInviteToken(token string) error
}
