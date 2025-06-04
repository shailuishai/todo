package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	gouser "server/internal/modules/user" // GORM модели User и UserSetting
	"strings"
)

type ProfileDatabase struct {
	db                 *gorm.DB
	log                *slog.Logger
	s3Endpoint         string
	s3UserAvatarBucket string
}

func NewProfileDatabase(db *gorm.DB, log *slog.Logger, s3Endpoint string, s3UserAvatarBucket string) *ProfileDatabase {
	return &ProfileDatabase{
		db:                 db,
		log:                log,
		s3Endpoint:         s3Endpoint,
		s3UserAvatarBucket: s3UserAvatarBucket,
	}
}

// GetUserAndSettings получает User и UserSetting. UserSetting может быть nil, если не найден.
func (r *ProfileDatabase) GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error) {
	log := r.log.With(slog.String("op", "ProfileDatabase.GetUserAndSettings"), slog.Uint64("userID", uint64(userId)))
	var user gouser.User

	// Используем Preload для загрузки связанных настроек
	if err := r.db.Preload("Settings").First(&user, userId).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Warn("user not found by ID")
			return nil, nil, gouser.ErrUserNotFound
		}
		log.Error("failed to get user and settings by ID from DB", "error", err)
		return nil, nil, gouser.ErrInternal
	}

	// user.Settings будет заполнена GORM, если есть связь и запись в UserSettings.
	// Если записи в UserSettings нет (маловероятно из-за триггера), то user.Settings будет пустой структурой UserSetting (с UserId=0).
	// Мы должны вернуть &user.Settings, если она действительно была загружена.
	// GORM при First с Preload, если связанная запись не найдена, не вернет ошибку,
	// а просто оставит поле структуры (user.Settings) в его zero-value.
	// Проверим, что user.Settings.UserId > 0, чтобы убедиться, что она была загружена.
	var settingsPtr *gouser.UserSetting
	if user.Settings.UserId > 0 { // UserSetting.UserId это PK и FK
		settingsPtr = &user.Settings
	} else {
		log.Warn("UserSettings not found or not preloaded for user", "userID", userId)
		// Это может случиться, если триггер не сработал или связь настроена неверно.
		// В этом случае вернем nil для settings, UseCase должен это обработать.
	}

	log.Debug("user and settings retrieved", "userLogin", user.Login)
	return &user, settingsPtr, nil
}

func (r *ProfileDatabase) UpdateUser(user *gouser.User) error {
	log := r.log.With(slog.String("op", "ProfileDatabase.UpdateUser"), slog.Uint64("userID", uint64(user.UserId)))
	result := r.db.Save(user) // Save обновит все поля или создаст, если не существует (но мы знаем, что существует)
	if result.Error != nil {
		log.Error("failed to update user in DB", "error", result.Error)
		if strings.Contains(result.Error.Error(), "duplicate key value violates unique constraint") &&
			strings.Contains(result.Error.Error(), "users_login_key") {
			return gouser.ErrLoginExists
		}
		return gouser.ErrInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("UpdateUser: no rows affected, user data might be the same or user not found", "userID", user.UserId)
		// Можно вернуть ошибку, если считаем, что обновление всегда должно затрагивать строки,
		// но Save может вернуть 0, если данные не изменились.
	}
	log.Info("user data updated successfully in DB", slog.Int64("rows_affected", result.RowsAffected))
	return nil
}

func (r *ProfileDatabase) UpdateUserSettings(settings *gouser.UserSetting) error {
	log := r.log.With(slog.String("op", "ProfileDatabase.UpdateUserSettings"), slog.Uint64("userID", uint64(settings.UserId)))
	// Используем Save, так как запись UserSettings должна уже существовать (создается триггером).
	// Save обновит все поля.
	result := r.db.Save(settings)
	if result.Error != nil {
		log.Error("failed to update user settings in DB", "error", result.Error)
		return gouser.ErrInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("UpdateUserSettings: no rows affected, settings data might be the same", "userID", settings.UserId)
	}
	log.Info("user settings updated successfully in DB", slog.Int64("rows_affected", result.RowsAffected))
	return nil
}

func (r *ProfileDatabase) DeleteUser(userId uint) error {
	log := r.log.With(slog.String("op", "ProfileDatabase.DeleteUser"), slog.Uint64("userID", uint64(userId)))
	// ON DELETE CASCADE в UserSettings должен удалить настройки автоматически.
	// ON DELETE SET NULL/CASCADE для внешних ключей в других таблицах (Tasks, Teams etc.) тоже отработают.
	result := r.db.Delete(&gouser.User{}, userId)
	if result.Error != nil {
		log.Error("failed to delete user from DB", "error", result.Error)
		return gouser.ErrInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("user not found for deletion (or already deleted)", "userID", userId)
		return gouser.ErrUserNotFound // Возвращаем ошибку, если пользователь не найден для удаления
	}
	log.Info("user deleted successfully from DB")
	return nil
}
