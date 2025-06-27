package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/tag" // Модели и ошибки модуля tag
	// usermodels "server/internal/modules/user" // Для общих ошибок, если понадобятся
	"strings"
	// "time" // Не используется напрямую в этом файле, но может понадобиться для других модулей
)

// TagDatabase реализует интерфейс repo.TagDb
type TagDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

// NewTagDatabase создает новый экземпляр TagDatabase.
func NewTagDatabase(db *gorm.DB, log *slog.Logger) *TagDatabase {
	return &TagDatabase{
		db:  db,
		log: log,
	}
}

// --- User Tags ---

func (r *TagDatabase) CreateUserTag(tagModel *tag.UserTag) (*tag.UserTag, error) {
	op := "TagDatabase.CreateUserTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("ownerUserID", uint64(tagModel.OwnerUserID)), slog.String("tagName", tagModel.Name))

	if err := r.db.Create(tagModel).Error; err != nil {
		log.Error("failed to create user tag in DB", "error", err)
		if strings.Contains(err.Error(), "unique_user_tag_name_per_owner") {
			return nil, tag.ErrUserTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}
	log.Info("user tag created successfully", slog.Uint64("userTagID", uint64(tagModel.UserTagID)))
	return tagModel, nil
}

func (r *TagDatabase) GetUserTagByID(tagID uint, ownerUserID uint) (*tag.UserTag, error) {
	op := "TagDatabase.GetUserTagByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("ownerUserID", uint64(ownerUserID)))
	var userTag tag.UserTag

	if err := r.db.Where("user_tag_id = ? AND owner_user_id = ?", tagID, ownerUserID).First(&userTag).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("user tag not found or access denied")
			return nil, tag.ErrTagNotFound // Или ErrTagAccessDenied, если хотим различать
		}
		log.Error("failed to get user tag by ID from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Debug("user tag found by ID")
	return &userTag, nil
}

func (r *TagDatabase) GetUserTagsByOwnerID(ownerUserID uint) ([]*tag.UserTag, error) {
	op := "TagDatabase.GetUserTagsByOwnerID"
	log := r.log.With(slog.String("op", op), slog.Uint64("ownerUserID", uint64(ownerUserID)))
	var userTags []*tag.UserTag

	if err := r.db.Where("owner_user_id = ?", ownerUserID).Order("name ASC").Find(&userTags).Error; err != nil {
		log.Error("failed to get user tags by owner ID from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Info("user tags retrieved for owner", slog.Int("count", len(userTags)))
	return userTags, nil
}

func (r *TagDatabase) UpdateUserTag(tagModel *tag.UserTag) (*tag.UserTag, error) {
	op := "TagDatabase.UpdateUserTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("userTagID", uint64(tagModel.UserTagID)))

	// Убедимся, что обновляем тег, принадлежащий этому owner_user_id, чтобы избежать случайного обновления чужого тега, если ID совпал.
	// Это лучше делать в UseCase проверкой перед вызовом Update, но и здесь не помешает.
	// Однако, если tagModel уже содержит OwnerUserID, GORM .Save() не будет его использовать в WHERE clause для поиска.
	// Лучше использовать Updates с условием.
	// result := r.db.Model(&tag.UserTag{}).Where("user_tag_id = ? AND owner_user_id = ?", tagModel.UserTagID, tagModel.OwnerUserID).
	//	Updates(map[string]interface{}{"name": tagModel.Name, "color": tagModel.Color})

	// Для простоты, предполагаем, что UseCase уже проверил принадлежность тега.
	// GORM .Save() обновит запись по PrimaryKey (UserTagID).
	result := r.db.Save(tagModel)
	if result.Error != nil {
		log.Error("failed to update user tag in DB", "error", result.Error)
		if strings.Contains(result.Error.Error(), "unique_user_tag_name_per_owner") {
			return nil, tag.ErrUserTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("UpdateUserTag: no rows affected, tag not found or data unchanged", "userTagID", tagModel.UserTagID)
		// Проверим, существует ли тег
		var checkTag tag.UserTag
		if errCheck := r.db.First(&checkTag, tagModel.UserTagID).Error; errors.Is(errCheck, gorm.ErrRecordNotFound) {
			return nil, tag.ErrTagNotFound
		}
	}
	log.Info("user tag updated successfully")
	return tagModel, nil
}

func (r *TagDatabase) DeleteUserTag(tagID uint, ownerUserID uint) error {
	op := "TagDatabase.DeleteUserTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("ownerUserID", uint64(ownerUserID)))

	// Удаляем только если тег принадлежит указанному пользователю
	result := r.db.Where("user_tag_id = ? AND owner_user_id = ?", tagID, ownerUserID).Delete(&tag.UserTag{})
	if result.Error != nil {
		log.Error("failed to delete user tag from DB", "error", result.Error)
		return tag.ErrTagInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("user tag not found for deletion or access denied")
		return tag.ErrTagNotFound // Или ErrTagAccessDenied
	}
	log.Info("user tag deleted successfully")
	return nil
}

func (r *TagDatabase) FindUserTagsByIDs(ownerUserID uint, tagIDs []uint) ([]*tag.UserTag, error) {
	op := "TagDatabase.FindUserTagsByIDs"
	log := r.log.With(slog.String("op", op), slog.Uint64("ownerUserID", uint64(ownerUserID)), slog.Any("tagIDs", tagIDs))
	var userTags []*tag.UserTag

	if len(tagIDs) == 0 {
		return userTags, nil
	}
	if err := r.db.Where("owner_user_id = ? AND user_tag_id IN ?", ownerUserID, tagIDs).Find(&userTags).Error; err != nil {
		log.Error("failed to find user tags by IDs", "error", err)
		return nil, tag.ErrTagInternal
	}
	return userTags, nil
}

// --- Team Tags ---

func (r *TagDatabase) CreateTeamTag(tagModel *tag.TeamTag) (*tag.TeamTag, error) {
	op := "TagDatabase.CreateTeamTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(tagModel.TeamID)), slog.String("tagName", tagModel.Name))

	if err := r.db.Create(tagModel).Error; err != nil {
		log.Error("failed to create team tag in DB", "error", err)
		if strings.Contains(err.Error(), "unique_team_tag_name_per_team") {
			return nil, tag.ErrTeamTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}
	log.Info("team tag created successfully", slog.Uint64("teamTagID", uint64(tagModel.TeamTagID)))
	return tagModel, nil
}

func (r *TagDatabase) GetTeamTagByID(tagID uint, teamID uint) (*tag.TeamTag, error) {
	op := "TagDatabase.GetTeamTagByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("teamID", uint64(teamID)))
	var teamTag tag.TeamTag

	if err := r.db.Where("team_tag_id = ? AND team_id = ?", tagID, teamID).First(&teamTag).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("team tag not found or not part of specified team")
			return nil, tag.ErrTagNotFound
		}
		log.Error("failed to get team tag by ID from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Debug("team tag found by ID")
	return &teamTag, nil
}

func (r *TagDatabase) GetTeamTagsByTeamID(teamID uint) ([]*tag.TeamTag, error) {
	op := "TagDatabase.GetTeamTagsByTeamID"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)))
	var teamTags []*tag.TeamTag

	if err := r.db.Where("team_id = ?", teamID).Order("name ASC").Find(&teamTags).Error; err != nil {
		log.Error("failed to get team tags by team ID from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Info("team tags retrieved for team", slog.Int("count", len(teamTags)))
	return teamTags, nil
}

func (r *TagDatabase) UpdateTeamTag(tagModel *tag.TeamTag) (*tag.TeamTag, error) {
	op := "TagDatabase.UpdateTeamTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamTagID", uint64(tagModel.TeamTagID)))

	// Предполагаем, что UseCase проверил, что тег принадлежит нужной команде.
	result := r.db.Save(tagModel)
	if result.Error != nil {
		log.Error("failed to update team tag in DB", "error", result.Error)
		if strings.Contains(result.Error.Error(), "unique_team_tag_name_per_team") {
			return nil, tag.ErrTeamTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("UpdateTeamTag: no rows affected, tag not found or data unchanged", "teamTagID", tagModel.TeamTagID)
		var checkTag tag.TeamTag
		if errCheck := r.db.First(&checkTag, tagModel.TeamTagID).Error; errors.Is(errCheck, gorm.ErrRecordNotFound) {
			return nil, tag.ErrTagNotFound
		}
	}
	log.Info("team tag updated successfully")
	return tagModel, nil
}

func (r *TagDatabase) DeleteTeamTag(tagID uint, teamID uint) error {
	op := "TagDatabase.DeleteTeamTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("teamID", uint64(teamID)))

	result := r.db.Where("team_tag_id = ? AND team_id = ?", tagID, teamID).Delete(&tag.TeamTag{})
	if result.Error != nil {
		log.Error("failed to delete team tag from DB", "error", result.Error)
		return tag.ErrTagInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("team tag not found for deletion or not part of specified team")
		return tag.ErrTagNotFound
	}
	log.Info("team tag deleted successfully")
	return nil
}

func (r *TagDatabase) FindTeamTagsByIDs(teamID uint, tagIDs []uint) ([]*tag.TeamTag, error) {
	op := "TagDatabase.FindTeamTagsByIDs"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Any("tagIDs", tagIDs))
	var teamTags []*tag.TeamTag

	if len(tagIDs) == 0 {
		return teamTags, nil
	}
	if err := r.db.Where("team_id = ? AND team_tag_id IN ?", teamID, tagIDs).Find(&teamTags).Error; err != nil {
		log.Error("failed to find team tags by IDs", "error", err)
		return nil, tag.ErrTagInternal
	}
	return teamTags, nil
}

// --- TaskTags ---

func (r *TagDatabase) ClearTaskTags(taskID uint) error {
	op := "TagDatabase.ClearTaskTags"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))

	if err := r.db.Where("task_id = ?", taskID).Delete(&tag.TaskTag{}).Error; err != nil {
		log.Error("failed to clear task tags from DB", "error", err)
		return tag.ErrTaskTagUnlinkFailed // Или ErrTagInternal
	}
	log.Info("task tags cleared for task", "taskID", taskID)
	return nil
}

func (r *TagDatabase) AddTaskUserTag(taskID uint, userTagID uint) error {
	op := "TagDatabase.AddTaskUserTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("userTagID", uint64(userTagID)))

	taskTag := tag.TaskTag{TaskID: taskID, UserTagID: &userTagID}
	// Проверка на дубликат (task_id, user_tag_id) и (task_id, team_tag_id) в БД (UNIQUE constraint)
	// Также chk_tag_type. GORM Create вернет ошибку, если constraint нарушен.
	if err := r.db.Create(&taskTag).Error; err != nil {
		log.Error("failed to add user tag to task in DB", "error", err)
		if strings.Contains(err.Error(), "duplicate key value violates unique constraint") ||
			strings.Contains(err.Error(), "chk_tag_type") {
			log.Warn("attempted to add duplicate or conflicting tag to task", "error", err)
			return tag.ErrTaskTagLinkFailed // Более специфичная ошибка
		}
		return tag.ErrTagInternal
	}
	log.Info("user tag added to task", "taskTagID", taskTag.TaskTagID)
	return nil
}

func (r *TagDatabase) AddTaskTeamTag(taskID uint, teamTagID uint) error {
	op := "TagDatabase.AddTaskTeamTag"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)), slog.Uint64("teamTagID", uint64(teamTagID)))

	taskTag := tag.TaskTag{TaskID: taskID, TeamTagID: &teamTagID}
	if err := r.db.Create(&taskTag).Error; err != nil {
		log.Error("failed to add team tag to task in DB", "error", err)
		if strings.Contains(err.Error(), "duplicate key value violates unique constraint") ||
			strings.Contains(err.Error(), "chk_tag_type") {
			log.Warn("attempted to add duplicate or conflicting tag to task", "error", err)
			return tag.ErrTaskTagLinkFailed
		}
		return tag.ErrTagInternal
	}
	log.Info("team tag added to task", "taskTagID", taskTag.TaskTagID)
	return nil
}

// GetTaskTags получает все записи TaskTag для конкретной задачи.
// UseCase затем должен будет по UserTagID/TeamTagID получить сами теги.
func (r *TagDatabase) GetTaskTags(taskID uint) ([]*tag.TaskTag, error) {
	op := "TagDatabase.GetTaskTags"
	log := r.log.With(slog.String("op", op), slog.Uint64("taskID", uint64(taskID)))
	var taskTags []*tag.TaskTag

	if err := r.db.Where("task_id = ?", taskID).Find(&taskTags).Error; err != nil {
		log.Error("failed to get task_tags from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Debug("task_tags retrieved for task", slog.Int("count", len(taskTags)))
	return taskTags, nil
}

func (r *TagDatabase) GetLinksForTaskIDs(taskIDs []uint) ([]*tag.TaskTag, error) {
	op := "TagDatabase.GetLinksForTaskIDs"
	log := r.log.With(slog.String("op", op))
	var taskTags []*tag.TaskTag

	if len(taskIDs) == 0 {
		return taskTags, nil
	}

	if err := r.db.Where("task_id IN ?", taskIDs).Find(&taskTags).Error; err != nil {
		log.Error("failed to get task_tags for multiple tasks from DB", "error", err)
		return nil, tag.ErrTagInternal
	}
	log.Debug("task_tags retrieved for multiple tasks", "count", len(taskTags))
	return taskTags, nil
}
