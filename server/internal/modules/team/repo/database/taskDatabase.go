// file: internal/modules/team/repo/database/team_database.go
package database

import (
	"errors"
	"fmt"
	"gorm.io/gorm"
	"log/slog"
	"server/config"
	"server/internal/modules/task" // Предполагается, что task.Task это GORM модель
	"server/internal/modules/team"
	usermodels "server/internal/modules/user"
	"strings"
	"time"
)

type TeamDatabase struct {
	db    *gorm.DB
	log   *slog.Logger
	s3cfg config.S3Config // Это должно быть config.S3Config из вашего пакета config
}

func NewTeamDatabase(db *gorm.DB, log *slog.Logger, s3cfg config.S3Config) *TeamDatabase {
	return &TeamDatabase{
		db:    db,
		log:   log,
		s3cfg: s3cfg,
	}
}

func (r *TeamDatabase) CreateTeam(teamModel *team.Team) (*team.Team, error) {
	op := "TeamDatabase.CreateTeam"
	log := r.log.With(slog.String("op", op), slog.String("teamName", teamModel.Name))

	// Поле ImageS3Key будет установлено в UseCase перед вызовом этого метода, если изображение было передано
	if err := r.db.Create(teamModel).Error; err != nil {
		log.Error("failed to create team in DB", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Info("team created successfully in DB", slog.Uint64("teamID", uint64(teamModel.TeamID)))
	return teamModel, nil
}

func (r *TeamDatabase) GetTeamByID(teamID uint) (*team.Team, error) {
	op := "TeamDatabase.GetTeamByID"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)))
	var teamModel team.Team

	if err := r.db.Where("is_deleted = ?", false).First(&teamModel, teamID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("team not found by ID or is deleted")
			return nil, team.ErrTeamNotFound
		}
		log.Error("failed to get team by ID from DB", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Debug("team found by ID")
	return &teamModel, nil
}

func (r *TeamDatabase) GetTeamsByUserID(userID uint, searchName *string) ([]*team.Team, error) {
	op := "TeamDatabase.GetTeamsByUserID"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))
	var teams []*team.Team

	query := r.db.Joins("JOIN userteammemberships utm ON utm.team_id = teams.team_id").
		Where("utm.user_id = ? AND teams.is_deleted = ?", userID, false)

	if searchName != nil && *searchName != "" {
		searchVal := "%" + strings.ToLower(*searchName) + "%"
		query = query.Where("LOWER(teams.name) LIKE ?", searchVal)
		log = log.With(slog.String("searchName", *searchName))
	}
	query = query.Order("teams.name ASC")

	if err := query.Find(&teams).Error; err != nil {
		log.Error("failed to get teams by user ID from DB", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Info("teams retrieved for user", slog.Int("count", len(teams)))
	return teams, nil
}

func (r *TeamDatabase) UpdateTeam(teamModel *team.Team) (*team.Team, error) {
	op := "TeamDatabase.UpdateTeam"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamModel.TeamID)))

	// UseCase должен подготовить teamModel.
	// GORM обновит только измененные поля, если teamModel получен из БД и затем изменен.
	// Если teamModel создается заново только с нужными полями для обновления,
	// нужно использовать db.Model(&team.Team{TeamID: teamModel.TeamID}).Updates(teamModel)
	// Но так как мы передаем *team.Team, предполагается, что это полная модель.
	// Важно: ImageS3Key может быть nil (если reset_image=true). GORM должен это обработать.
	// Чтобы GORM корректно обработал nil для указателей, можно использовать Updates с map[string]interface{}
	// или убедиться, что модель, передаваемая в Save, содержит nil, где нужно.
	// Save() обновит все поля, включая нулевые значения для указателей.

	result := r.db.Save(teamModel) // Save обновит все поля, включая ImageS3Key на nil, если так установлено
	if result.Error != nil {
		log.Error("failed to update team in DB", "error", result.Error)
		return nil, team.ErrTeamInternal
	}
	if result.RowsAffected == 0 {
		var checkTeam team.Team
		if errCheck := r.db.Where("is_deleted = ?", false).First(&checkTeam, teamModel.TeamID).Error; errors.Is(errCheck, gorm.ErrRecordNotFound) {
			log.Warn("team not found for update (or already deleted)", "teamID", teamModel.TeamID)
			return nil, team.ErrTeamNotFound
		}
		log.Warn("UpdateTeam: no rows affected, team data might be the same or team not found", "teamID", teamModel.TeamID)
		// Если RowsAffected == 0, но ошибки нет, значит, данные не изменились или запись не найдена.
		// GetTeamByID выше должен был вернуть ErrTeamNotFound, если команда не найдена.
		// Поэтому здесь это, скорее всего, означает, что данные не изменились.
	}
	log.Info("team updated successfully in DB")
	// Возвращаем обновленную модель (GORM должен обновить поля в teamModel)
	return teamModel, nil
}

func (r *TeamDatabase) CreateMembership(membership *team.UserTeamMembership) error {
	op := "TeamDatabase.CreateMembership"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(membership.UserID)), slog.Uint64("teamID", uint64(membership.TeamID)))

	if err := r.db.Create(membership).Error; err != nil {
		log.Error("failed to create team membership in DB", "error", err)
		if strings.Contains(err.Error(), "duplicate key value violates unique constraint") &&
			strings.Contains(err.Error(), "userteammemberships_pkey") {
			return team.ErrUserAlreadyMember
		}
		return team.ErrTeamInternal
	}
	log.Info("team membership created successfully")
	return nil
}

func (r *TeamDatabase) GetMembership(userID, teamID uint) (*team.UserTeamMembership, error) {
	op := "TeamDatabase.GetMembership"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("teamID", uint64(teamID)))
	var membership team.UserTeamMembership

	if err := r.db.Where("user_id = ? AND team_id = ?", userID, teamID).First(&membership).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Debug("team membership not found")
			return nil, team.ErrUserNotMember
		}
		log.Error("failed to get team membership from DB", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Debug("team membership found")
	return &membership, nil
}

func (r *TeamDatabase) GetTeamMemberships(teamID uint) ([]*team.UserTeamMembership, error) {
	op := "TeamDatabase.GetTeamMemberships"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)))
	var memberships []*team.UserTeamMembership

	var t team.Team
	if err := r.db.Select("team_id").Where("is_deleted = ?", false).First(&t, teamID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("team not found or deleted when getting memberships", "teamID", teamID)
			return nil, team.ErrTeamNotFound
		}
		return nil, team.ErrTeamInternal
	}

	if err := r.db.Where("team_id = ?", teamID).Order("joined_at ASC").Find(&memberships).Error; err != nil {
		log.Error("failed to get team memberships from DB", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Info("team memberships retrieved", slog.Int("count", len(memberships)))
	return memberships, nil
}

// <<< РЕАЛИЗАЦИЯ GetTeamMembershipsCount >>>
func (r *TeamDatabase) GetTeamMembershipsCount(teamID uint) (int, error) {
	op := "TeamDatabase.GetTeamMembershipsCount"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)))
	var count int64

	// Сначала проверяем, существует ли команда и не удалена ли она
	var t team.Team
	if err := r.db.Select("team_id").Where("is_deleted = ?", false).First(&t, teamID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("team not found or deleted when getting memberships count", "teamID", teamID)
			return 0, team.ErrTeamNotFound // Важно вернуть ошибку, если команда не найдена
		}
		log.Error("failed to check team existence for GetTeamMembershipsCount", "error", err)
		return 0, team.ErrTeamInternal
	}

	if err := r.db.Model(&team.UserTeamMembership{}).Where("team_id = ?", teamID).Count(&count).Error; err != nil {
		log.Error("failed to count team memberships from DB", "error", err)
		return 0, team.ErrTeamInternal
	}
	log.Debug("team memberships count retrieved", slog.Int64("count", count))
	return int(count), nil
}

func (r *TeamDatabase) UpdateTeamMemberRole(userID, teamID uint, newRole team.TeamMemberRole) (*team.UserTeamMembership, error) {
	op := "TeamDatabase.UpdateTeamMemberRole"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("teamID", uint64(teamID)), slog.String("newRole", string(newRole)))

	var membership team.UserTeamMembership
	result := r.db.Model(&membership).
		Where("user_id = ? AND team_id = ?", userID, teamID).
		Update("role", newRole)

	if result.Error != nil {
		log.Error("failed to update team member role in DB", "error", result.Error)
		return nil, team.ErrTeamInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("team membership not found for role update, or role is already the same")
		errCheck := r.db.Where("user_id = ? AND team_id = ?", userID, teamID).First(&team.UserTeamMembership{}).Error
		if errors.Is(errCheck, gorm.ErrRecordNotFound) {
			return nil, team.ErrUserNotMember
		}
	}
	if err := r.db.Where("user_id = ? AND team_id = ?", userID, teamID).First(&membership).Error; err != nil {
		log.Error("failed to fetch updated membership after role update", "error", err)
		return nil, team.ErrTeamInternal
	}
	log.Info("team member role updated successfully")
	return &membership, nil
}

func (r *TeamDatabase) RemoveTeamMember(userID, teamID uint) error {
	op := "TeamDatabase.RemoveTeamMember"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.Uint64("teamID", uint64(teamID)))

	result := r.db.Where("user_id = ? AND team_id = ?", userID, teamID).Delete(&team.UserTeamMembership{})
	if result.Error != nil {
		log.Error("failed to remove team member from DB", "error", result.Error)
		return team.ErrTeamInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("team member not found for removal")
		return team.ErrUserNotMember
	}
	log.Info("team member removed successfully")
	return nil
}

func (r *TeamDatabase) IsTeamMember(userID, teamID uint) (bool, error) {
	op := "TeamDatabase.IsTeamMember"
	log := r.log.With(slog.String("op", op))
	var count int64
	err := r.db.Model(&team.UserTeamMembership{}).
		Where("user_id = ? AND team_id = ?", userID, teamID).
		Count(&count).Error
	if err != nil {
		log.Error("failed to check team membership", "error", err, "userID", userID, "teamID", teamID)
		return false, team.ErrTeamInternal
	}
	return count > 0, nil
}

func (r *TeamDatabase) LogicallyDeleteTasksByTeamID(teamID uint, deletedByUserID uint) error {
	op := "TeamDatabase.LogicallyDeleteTasksByTeamID"
	log := r.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("deletedByUserID", uint64(deletedByUserID)))
	updates := map[string]interface{}{
		"is_deleted":         true,
		"deleted_at":         time.Now(),
		"deleted_by_user_id": deletedByUserID,
	}
	result := r.db.Model(&task.Task{}).
		Where("team_id = ? AND is_deleted = ?", teamID, false).
		Updates(updates)
	if result.Error != nil {
		log.Error("failed to logically delete tasks by team ID", "error", result.Error)
		return team.ErrTeamInternal
	}
	log.Info("tasks logically deleted for team", slog.Int64("rows_affected", result.RowsAffected))
	return nil
}

// GetUserLiteByID из предыдущего шага, предполагается, что он уже корректен
func (r *TeamDatabase) GetUserLiteByID(userID uint) (*team.UserLiteResponse, error) {
	op := "TeamDatabase.GetUserLiteByID" // Изменил имя репозитория для лога для ясности
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	type scannedUserLiteData struct {
		UserID      uint    `gorm:"column:user_id"`
		Login       string  `gorm:"column:login"`
		AvatarS3Key *string `gorm:"column:avatar_s3_key"`
		AccentColor *string `gorm:"column:accent_color"`
	}
	var scanResult scannedUserLiteData

	err := r.db.Table("users").
		Select("users.user_id, users.login, users.avatar_s3_key, us.accent_color").
		Joins("LEFT JOIN usersettings us ON users.user_id = us.user_id").
		Where("users.user_id = ?", userID).
		First(&scanResult).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("user not found for lite response")
			return nil, usermodels.ErrUserNotFound
		}
		log.Error("failed to get user and settings from DB", "error", err)
		return nil, usermodels.ErrInternal
	}

	log.Debug("Data scanned from DB for GetUserLiteByID",
		"userID", scanResult.UserID,
		"login", scanResult.Login,
		"avatarS3Key", scanResult.AvatarS3Key,
		"accentColor", scanResult.AccentColor)

	var avatarURL *string
	if scanResult.AvatarS3Key != nil && *scanResult.AvatarS3Key != "" {
		if r.s3cfg.Endpoint != "" && r.s3cfg.BucketUserAvatars != "" {
			cleanBase := strings.TrimSuffix(r.s3cfg.Endpoint, "/")
			cleanBucket := strings.TrimSuffix(r.s3cfg.BucketUserAvatars, "/") // Это должно быть r.s3cfg.BucketUserAvatars
			cleanKey := strings.TrimPrefix(*scanResult.AvatarS3Key, "/")

			s3ObjectUrl := fmt.Sprintf("%s/%s/%s", cleanBase, cleanBucket, cleanKey)
			if !strings.HasPrefix(s3ObjectUrl, "http://") && !strings.HasPrefix(s3ObjectUrl, "https://") {
				s3ObjectUrl = "https://" + s3ObjectUrl
			}
			avatarURL = &s3ObjectUrl
		} else {
			log.Warn("S3 endpoint or bucket (user avatars) not configured, cannot form avatar URL", "userID", userID)
		}
	}

	finalResponse := &team.UserLiteResponse{
		UserID:    scanResult.UserID,
		Login:     scanResult.Login,
		AvatarURL: avatarURL,
	}

	if avatarURL == nil {
		finalResponse.AccentColor = scanResult.AccentColor
	}
	return finalResponse, nil
}

func (r *TeamDatabase) GetUserByLoginOrEmail(identifier string) (*usermodels.User, error) {
	op := "TeamDatabase.GetUserByLoginOrEmail"
	log := r.log.With(slog.String("op", op), slog.String("identifier", identifier))
	var user usermodels.User
	query := r.db.Model(&usermodels.User{})
	if strings.Contains(identifier, "@") {
		query = query.Where("email = ?", identifier)
	} else {
		query = query.Where("login = ?", identifier)
	}
	if err := query.First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Info("user not found by login or email", "identifier", identifier)
			return nil, usermodels.ErrUserNotFound
		}
		log.Error("failed to get user by login or email from DB", "error", err)
		return nil, usermodels.ErrInternal
	}
	log.Info("user found by login or email", "userID", user.UserId, "login", user.Login)
	return &user, nil
}
