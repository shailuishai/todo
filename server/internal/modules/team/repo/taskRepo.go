package repo

import (
	"log/slog"
	"server/internal/modules/team" // Импортируем пакет team для доступа к team.Team, team.UserTeamMembership и т.д.
	usermodels "server/internal/modules/user"
	"time"
)

// TeamDb определяет методы для работы с базой данных для команд.
type TeamDb interface {
	// Team CRUD
	CreateTeam(teamModel *team.Team) (*team.Team, error)
	GetTeamByID(teamID uint) (*team.Team, error)
	GetTeamsByUserID(userID uint, searchName *string) ([]*team.Team, error)
	UpdateTeam(teamModel *team.Team) (*team.Team, error)
	// Логическое удаление команды будет частью UpdateTeam (установка IsDeleted)

	// Membership
	CreateMembership(membership *team.UserTeamMembership) error // Создание первой записи о членстве (owner)
	GetMembership(userID, teamID uint) (*team.UserTeamMembership, error)
	GetTeamMembershipsCount(teamID uint) (int, error)
	GetTeamMemberships(teamID uint) ([]*team.UserTeamMembership, error)
	// GetTeamMembersWithUserDetails(teamID uint) ([]*team.TeamMemberResponse, error)
	UpdateTeamMemberRole(userID, teamID uint, newRole team.TeamMemberRole) (*team.UserTeamMembership, error)
	RemoveTeamMember(userID, teamID uint) error
	IsTeamMember(userID, teamID uint) (bool, error) // Проверка, является ли пользователь участником

	// Задачи (для каскадного логического удаления при удалении команды)
	LogicallyDeleteTasksByTeamID(teamID uint, deletedByUserID uint) error

	GetUserLiteByID(userID uint) (*team.UserLiteResponse, error)
	GetUserByLoginOrEmail(identifier string) (*usermodels.User, error)
}

// TeamCache определяет методы для работы с кэшем для команд.
type TeamCache interface {
	GetTeam(teamID uint) (*team.Team, error)
	SaveTeam(teamModel *team.Team) error
	DeleteTeam(teamID uint) error

	GetTeamMembers(teamID uint) ([]*team.UserTeamMembership, error)
	SaveTeamMembers(teamID uint, members []*team.UserTeamMembership) error
	DeleteTeamMembers(teamID uint) error

	GetUserTeams(userID uint) ([]*team.Team, error) // Список команд пользователя
	SaveUserTeams(userID uint, teams []*team.Team) error
	DeleteUserTeams(userID uint) error

	SaveInviteToken(token string, teamID uint, roleToAssign team.TeamMemberRole, expiresAt time.Time) error
	GetInviteTokenData(token string) (teamID uint, roleToAssign team.TeamMemberRole, isValid bool, err error)
	DeleteInviteToken(token string) error
}

// TeamS3 определяет методы для работы с S3 для изображений команд.
type TeamS3 interface {
	UploadTeamImage(bucketName string, s3Key string, imageBytes []byte, contentType string) error
	DeleteTeamImage(bucketName string, s3Key string) error
	GetTeamImagePublicURL(s3Key string) string // Формирует URL на основе базового URL и ключа
}

// repo реализует интерфейс team.Repo (из team/entity.go).
type repo struct {
	db                TeamDb
	ch                TeamCache
	s3                TeamS3
	log               *slog.Logger
	s3TeamImageBucket string // Имя бакета можно передавать сюда или в каждый метод S3
	s3BaseURL         string
}

// NewRepo создает новый экземпляр репозитория команд.
func NewRepo(db TeamDb, ch TeamCache, s3 TeamS3, log *slog.Logger, s3Bucket, s3Base string) team.Repo {
	return &repo{
		db:                db,
		ch:                ch,
		s3:                s3,
		log:               log,
		s3TeamImageBucket: s3Bucket,
		s3BaseURL:         s3Base,
	}
}

// --- Реализация методов интерфейса team.Repo ---

func (r *repo) GetUserLiteByID(userID uint) (*team.UserLiteResponse, error) {
	return r.db.GetUserLiteByID(userID)
}
func (r *repo) GetUserByLoginOrEmail(identifier string) (*usermodels.User, error) {
	return r.db.GetUserByLoginOrEmail(identifier)
}

// Team CRUD
func (r *repo) CreateTeam(teamModel *team.Team) (*team.Team, error) {
	// При создании команды, инвалидируем кэш списка команд пользователя, который ее создал.
	// defer r.ch.DeleteUserTeams(teamModel.CreatedByUserID) // Пример инвалидации
	return r.db.CreateTeam(teamModel)
}

func (r *repo) CreateMembership(membership *team.UserTeamMembership) error {
	// При добавлении участника (включая owner-а при создании),
	// инвалидируем кэш участников команды и кэш списка команд этого пользователя.
	// defer r.ch.DeleteTeamMembers(membership.TeamID)
	// defer r.ch.DeleteUserTeams(membership.UserID)
	return r.db.CreateMembership(membership)
}

func (r *repo) GetTeamByID(teamID uint) (*team.Team, error) {
	// Попытка получить из кэша
	// cachedTeam, err := r.ch.GetTeam(teamID)
	// if err == nil && cachedTeam != nil {
	// 	return cachedTeam, nil
	// }
	//
	// dbTeam, err := r.db.GetTeamByID(teamID)
	// if err == nil && dbTeam != nil {
	// 	go r.ch.SaveTeam(dbTeam)
	// }
	// return dbTeam, err
	return r.db.GetTeamByID(teamID)
}

func (r *repo) GetTeamsByUserID(userID uint, searchName *string) ([]*team.Team, error) {
	// Логика кэширования списка команд пользователя может быть здесь или в UseCase
	// cacheKey := fmt.Sprintf("user:%d:teams:search:%s", userID,ปลอดภัย_хеш(*searchName))
	// cachedTeams, err := r.ch.GetUserTeams(userID, cacheKey) // или похожий метод
	// if err == nil && cachedTeams != nil {
	//  return cachedTeams, nil
	// }
	//
	// dbTeams, err := r.db.GetTeamsByUserID(userID, searchName)
	// if err == nil && len(dbTeams) > 0 { // Кэшируем непустые списки
	// 	go r.ch.SaveUserTeams(userID, cacheKey, dbTeams)
	// }
	// return dbTeams, err
	return r.db.GetTeamsByUserID(userID, searchName)
}

func (r *repo) UpdateTeam(teamModel *team.Team) (*team.Team, error) {
	// Инвалидация кэша для этой команды и списков команд пользователей-участников
	// defer r.ch.DeleteTeam(teamModel.TeamID)
	// Если IsDeleted меняется, нужно инвалидировать кэши списков команд, где она могла быть.
	// Это сложнее и лучше делать в UseCase, который знает контекст.
	updatedTeam, err := r.db.UpdateTeam(teamModel)
	// if err == nil && updatedTeam != nil {
	// 	go r.ch.SaveTeam(updatedTeam) // Обновить в кэше
	// }
	return updatedTeam, err
}

// Membership
func (r *repo) GetMembership(userID, teamID uint) (*team.UserTeamMembership, error) {
	// Кэширование отдельного членства может быть избыточным,
	// чаще кэшируют список всех участников команды.
	return r.db.GetMembership(userID, teamID)
}

func (r *repo) GetTeamMemberships(teamID uint) ([]*team.UserTeamMembership, error) {
	// cachedMembers, err := r.ch.GetTeamMembers(teamID)
	// if err == nil && cachedMembers != nil {
	// 	return cachedMembers, nil
	// }
	// dbMembers, err := r.db.GetTeamMemberships(teamID)
	// if err == nil && len(dbMembers) > 0 {
	// 	go r.ch.SaveTeamMembers(teamID, dbMembers)
	// }
	// return dbMembers, err
	return r.db.GetTeamMemberships(teamID)
}

func (r *repo) AddTeamMember(membership *team.UserTeamMembership) (*team.UserTeamMembership, error) {
	// Логика инвалидации кэша, если нужно на этом уровне
	//defer r.ch.DeleteTeamMembers(membership.TeamID)
	//defer r.ch.DeleteUserTeams(membership.UserID)

	err := r.db.CreateMembership(membership) // Используем CreateMembership
	if err != nil {
		return nil, err // Он вернет ErrUserAlreadyMember или ErrTeamInternal
	}
	// Так как CreateMembership не возвращает модель, а AddTeamMember в интерфейсе Repo должен,
	// нам нужно либо изменить сигнатуру CreateMembership в TeamDb, либо здесь получить только что созданную.
	// Проще изменить CreateMembership. Но пока, чтобы соответствовать интерфейсу Repo:
	// Это не очень хорошо, т.к. JoinedAt может быть неактуальным, если БД его генерирует.
	// Правильнее, чтобы CreateMembership возвращал созданную сущность, или AddTeamMember в Repo - только ошибку.
	// Для быстрого исправления, предполагаем, что `membership` был обновлен GORM (если PK - не составной).
	// Но для составного PK, это не сработает без явного `First`.
	// Давайте пока вернем как есть, а потом решим, как лучше:
	// Вернем ошибку, если CreateMembership вернул ошибку, иначе вернем переданный membership
	// Это не идеально, но соответствует сигнатуре.
	// TODO: Рассмотреть возврат *UserTeamMembership из TeamDb.CreateMembership
	return membership, nil
}

func (r *repo) UpdateTeamMemberRole(userID, teamID uint, newRole team.TeamMemberRole) (*team.UserTeamMembership, error) {
	// defer r.ch.DeleteTeamMembers(teamID)
	// defer r.ch.DeleteUserTeams(userID) // Если роль влияет на то, как команды отображаются для пользователя
	return r.db.UpdateTeamMemberRole(userID, teamID, newRole)
}

func (r *repo) RemoveTeamMember(userID, teamID uint) error {
	// defer r.ch.DeleteTeamMembers(teamID)
	// defer r.ch.DeleteUserTeams(userID)
	return r.db.RemoveTeamMember(userID, teamID)
}

func (r *repo) IsTeamMember(userID, teamID uint) (bool, error) {
	// Эта проверка может кэшироваться, но часто она быстрая на уровне БД.
	return r.db.IsTeamMember(userID, teamID)
}

// Задачи
func (r *repo) LogicallyDeleteTasksByTeamID(teamID uint, deletedByUserID uint) error {
	// Эта операция модифицирует много задач, инвалидация кэша задач должна быть обширной.
	// Лучше если UseCase команды вызовет UseCase задач для инвалидации.
	// Или здесь происходит "грубая" инвалидация кэша задач по teamID.
	// defer r.taskCache.InvalidateTasksByTeam(teamID) // если бы был такой метод
	return r.db.LogicallyDeleteTasksByTeamID(teamID, deletedByUserID)
}

func (r *repo) GetTeam(teamID uint) (*team.Team, error) {
	return r.ch.GetTeam(teamID)
}
func (r *repo) SaveTeam(teamModel *team.Team) error {
	return r.ch.SaveTeam(teamModel)
}
func (r *repo) DeleteTeam(teamID uint) error {
	return r.ch.DeleteTeam(teamID)
}

func (r *repo) GetTeamMembers(teamID uint) ([]*team.UserTeamMembership, error) {
	return r.ch.GetTeamMembers(teamID)
}
func (r *repo) GetTeamMembershipsCount(teamID uint) (int, error) {
	return r.db.GetTeamMembershipsCount(teamID)
}
func (r *repo) SaveTeamMembers(teamID uint, members []*team.UserTeamMembership) error {
	return r.ch.SaveTeamMembers(teamID, members)
}
func (r *repo) DeleteTeamMembers(teamID uint) error {
	return r.ch.DeleteTeamMembers(teamID)
}

func (r *repo) GetUserTeams(userID uint) ([]*team.Team, error) {
	return r.ch.GetUserTeams(userID)
} // Список команд пользователя
func (r *repo) SaveUserTeams(userID uint, teams []*team.Team) error {
	return r.ch.SaveUserTeams(userID, teams)
}
func (r *repo) DeleteUserTeams(userID uint) error {
	return r.ch.DeleteUserTeams(userID)
}

func (r *repo) SaveInviteToken(token string, teamID uint, roleToAssign team.TeamMemberRole, expiresAt time.Time) error {
	return r.ch.SaveInviteToken(token, teamID, roleToAssign, expiresAt)
}
func (r *repo) GetInviteTokenData(token string) (teamID uint, roleToAssign team.TeamMemberRole, isValid bool, err error) {
	return r.ch.GetInviteTokenData(token)
}
func (r *repo) DeleteInviteToken(token string) error {
	return r.ch.DeleteInviteToken(token)
}

func (r *repo) UploadTeamImage(bucketName string, s3Key string, imageBytes []byte, contentType string) error {
	return r.s3.UploadTeamImage(bucketName, s3Key, imageBytes, contentType)
}
func (r *repo) DeleteTeamImage(bucketName string, s3Key string) error {
	return r.s3.DeleteTeamImage(bucketName, s3Key)
}
func (r *repo) GetTeamImagePublicURL(s3Key string) string {
	return r.s3.GetTeamImagePublicURL(s3Key)
}
