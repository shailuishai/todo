package repo

import (
	"errors"
	"log/slog"
	"server/internal/modules/tag"
)

// TagDb определяет методы для работы с базой данных для тегов.
type TagDb interface {
	// User Tags
	CreateUserTag(tag *tag.UserTag) (*tag.UserTag, error)
	GetUserTagByID(tagID uint, ownerUserID uint) (*tag.UserTag, error)
	GetUserTagsByOwnerID(ownerUserID uint) ([]*tag.UserTag, error)
	UpdateUserTag(tag *tag.UserTag) (*tag.UserTag, error)
	DeleteUserTag(tagID uint, ownerUserID uint) error
	FindUserTagsByIDs(ownerUserID uint, tagIDs []uint) ([]*tag.UserTag, error)

	// Team Tags
	CreateTeamTag(tag *tag.TeamTag) (*tag.TeamTag, error)
	GetTeamTagByID(tagID uint, teamID uint) (*tag.TeamTag, error)
	GetTeamTagsByTeamID(teamID uint) ([]*tag.TeamTag, error)
	UpdateTeamTag(tag *tag.TeamTag) (*tag.TeamTag, error)
	DeleteTeamTag(tagID uint, teamID uint) error
	FindTeamTagsByIDs(teamID uint, tagIDs []uint) ([]*tag.TeamTag, error)

	// TaskTags
	ClearTaskTags(taskID uint) error
	AddTaskUserTag(taskID uint, userTagID uint) error
	AddTaskTeamTag(taskID uint, teamTagID uint) error
	GetTaskTags(taskID uint) ([]*tag.TaskTag, error) // Возвращает записи из связующей таблицы
	// Для получения полных TagResponse для задачи, UseCase должен будет сначала получить TaskTag,
	// а затем UserTag/TeamTag по ID из TaskTag.
}

// TagCache определяет методы для работы с кэшем для тегов.
type TagCache interface {
	GetUserTags(ownerUserID uint) ([]*tag.UserTag, error)
	SaveUserTags(ownerUserID uint, tags []*tag.UserTag) error
	DeleteUserTags(ownerUserID uint) error // При создании/удалении/изменении пользовательского тега

	GetTeamTags(teamID uint) ([]*tag.TeamTag, error)
	SaveTeamTags(teamID uint, tags []*tag.TeamTag) error
	DeleteTeamTags(teamID uint) error // При создании/удалении/изменении командного тега
}

// repo реализует интерфейс tag.Repo.
type repo struct {
	db  TagDb
	ch  TagCache // Может быть nil, если кэширование не используется на этом уровне
	log *slog.Logger
}

// NewRepo создает новый экземпляр репозитория тегов.
func NewRepo(db TagDb, ch TagCache, log *slog.Logger) tag.Repo {
	return &repo{
		db:  db,
		ch:  ch,
		log: log,
	}
}

// --- User Tags ---
func (r *repo) CreateUserTag(tag *tag.UserTag) (*tag.UserTag, error) {
	// Инвалидация кэша списка тегов пользователя
	if r.ch != nil {
		defer r.ch.DeleteUserTags(tag.OwnerUserID)
	}
	return r.db.CreateUserTag(tag)
}
func (r *repo) GetUserTagByID(tagID uint, ownerUserID uint) (*tag.UserTag, error) {
	return r.db.GetUserTagByID(tagID, ownerUserID)
}
func (r *repo) GetUserTagsByOwnerID(ownerUserID uint) ([]*tag.UserTag, error) {
	if r.ch != nil {
		cachedTags, err := r.ch.GetUserTags(ownerUserID)
		if err == nil && cachedTags != nil { // Кэш хит (даже если пустой список)
			r.log.Debug("user tags retrieved from cache", "ownerUserID", ownerUserID, "count", len(cachedTags))
			return cachedTags, nil
		}
		// Если ошибка кэша, не связанная с "не найдено", логируем и идем в БД
		if err != nil && !errors.Is(err, tag.ErrTagNotFound) { // Предполагаем, что Cache может вернуть ErrTagNotFound
			r.log.Warn("error getting user tags from cache, proceeding to DB", "error", err, "ownerUserID", ownerUserID)
		}
	}
	dbTags, err := r.db.GetUserTagsByOwnerID(ownerUserID)
	if err == nil && r.ch != nil {
		if errSave := r.ch.SaveUserTags(ownerUserID, dbTags); errSave != nil {
			r.log.Warn("failed to save user tags to cache", "error", errSave, "ownerUserID", ownerUserID)
		}
	}
	return dbTags, err
}
func (r *repo) UpdateUserTag(tag *tag.UserTag) (*tag.UserTag, error) {
	if r.ch != nil {
		defer r.ch.DeleteUserTags(tag.OwnerUserID)
	}
	return r.db.UpdateUserTag(tag)
}
func (r *repo) DeleteUserTag(tagID uint, ownerUserID uint) error {
	if r.ch != nil {
		defer r.ch.DeleteUserTags(ownerUserID)
	}
	return r.db.DeleteUserTag(tagID, ownerUserID)
}
func (r *repo) FindUserTagsByIDs(ownerUserID uint, tagIDs []uint) ([]*tag.UserTag, error) {
	return r.db.FindUserTagsByIDs(ownerUserID, tagIDs)
}

// --- Team Tags ---
func (r *repo) CreateTeamTag(tag *tag.TeamTag) (*tag.TeamTag, error) {
	if r.ch != nil {
		defer r.ch.DeleteTeamTags(tag.TeamID)
	}
	return r.db.CreateTeamTag(tag)
}
func (r *repo) GetTeamTagByID(tagID uint, teamID uint) (*tag.TeamTag, error) {
	return r.db.GetTeamTagByID(tagID, teamID)
}
func (r *repo) GetTeamTagsByTeamID(teamID uint) ([]*tag.TeamTag, error) {
	if r.ch != nil {
		cachedTags, err := r.ch.GetTeamTags(teamID)
		if err == nil && cachedTags != nil {
			r.log.Debug("team tags retrieved from cache", "teamID", teamID, "count", len(cachedTags))
			return cachedTags, nil
		}
		if err != nil && !errors.Is(err, tag.ErrTagNotFound) {
			r.log.Warn("error getting team tags from cache, proceeding to DB", "error", err, "teamID", teamID)
		}
	}
	dbTags, err := r.db.GetTeamTagsByTeamID(teamID)
	if err == nil && r.ch != nil {
		if errSave := r.ch.SaveTeamTags(teamID, dbTags); errSave != nil {
			r.log.Warn("failed to save team tags to cache", "error", errSave, "teamID", teamID)
		}
	}
	return dbTags, err
}
func (r *repo) UpdateTeamTag(tag *tag.TeamTag) (*tag.TeamTag, error) {
	if r.ch != nil {
		defer r.ch.DeleteTeamTags(tag.TeamID)
	}
	return r.db.UpdateTeamTag(tag)
}
func (r *repo) DeleteTeamTag(tagID uint, teamID uint) error {
	if r.ch != nil {
		defer r.ch.DeleteTeamTags(teamID)
	}
	return r.db.DeleteTeamTag(tagID, teamID)
}
func (r *repo) FindTeamTagsByIDs(teamID uint, tagIDs []uint) ([]*tag.TeamTag, error) {
	return r.db.FindTeamTagsByIDs(teamID, tagIDs)
}

// --- TaskTags ---
// Эти методы проксируются напрямую к DB, т.к. кэширование связей Task-Tag обычно
// происходит на уровне самой задачи (кэшируется задача вместе со списком ее тегов).
// Инвалидация кэша задач при изменении TaskTags будет ответственностью TaskUseCase.
func (r *repo) ClearTaskTags(taskID uint) error {
	return r.db.ClearTaskTags(taskID)
}
func (r *repo) AddTaskUserTag(taskID uint, userTagID uint) error {
	return r.db.AddTaskUserTag(taskID, userTagID)
}
func (r *repo) AddTaskTeamTag(taskID uint, teamTagID uint) error {
	return r.db.AddTaskTeamTag(taskID, teamTagID)
}
func (r *repo) GetTaskTags(taskID uint) ([]*tag.TaskTag, error) {
	return r.db.GetTaskTags(taskID)
}

// Методы из team.Repo, которые были добавлены по ошибке в task.Repo, теперь удалены из task.Repo
// и должны быть частью team.Repo.
// Реализация для методов, которые были ошибочно добавлены в интерфейс tag.Repo (из-за копипасты)
// Эти методы относятся к team.Repo, а не tag.Repo.
// Их нужно убрать из интерфейса tag.Repo в entity.go
// Здесь я их закомментирую, предполагая, что они будут убраны из tag.Repo
/*
func (r *repo) GetTeam(teamID uint) (*tag.Team, error) { // tag.Team тут неверно, должен быть team.Team
	r.log.Error("GetTeam called on tagRepo, this is incorrect")
	return nil, errors.New("GetTeam not implemented on tagRepo")
}
func (r *repo) SaveTeam(teamModel *tag.Team) error {
	r.log.Error("SaveTeam called on tagRepo, this is incorrect")
	return errors.New("SaveTeam not implemented on tagRepo")
}
// ... и так далее для остальных ошибочных методов ...
*/
// Методы для S3 (UploadTeamImage, DeleteTeamImage, GetTeamImagePublicURL) также не относятся к TagRepo.
// Их нужно будет вызывать из TeamUseCase напрямую через TeamS3 зависимость или через TeamRepo.
