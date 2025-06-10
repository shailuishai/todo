package database

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"log/slog"
	gouser "server/internal/modules/user" // GORM модели User и UserSetting
	"strings"
	"time"
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

func (r *ProfileDatabase) GetUserEmail(userID uint) (email string, isVerified bool, err error) {
	log := r.log.With(slog.String("op", "ProfileDatabase.GetUserEmail"), slog.Uint64("userID", uint64(userID)))
	var user struct {
		Email         string
		VerifiedEmail bool
	}
	if dbErr := r.db.Model(&gouser.User{}).Where("user_id = ?", userID).First(&user).Error; dbErr != nil {
		if errors.Is(dbErr, gorm.ErrRecordNotFound) {
			log.Warn("user not found for GetUserEmail")
			return "", false, gouser.ErrUserNotFound
		}
		log.Error("failed to get user email from DB", "error", dbErr)
		return "", false, gouser.ErrInternal
	}
	return user.Email, user.VerifiedEmail, nil
}

// --- Методы для UserDeviceToken (реализация DeviceTokenRepo) ---

func (r *ProfileDatabase) AddDeviceToken(ctx context.Context, token *gouser.UserDeviceToken) error {
	op := "ProfileDatabase.AddDeviceToken"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(token.UserID)), slog.String("deviceType", token.DeviceType))

	// Устанавливаем время, если не установлено
	now := time.Now().UTC()
	if token.CreatedAt.IsZero() {
		token.CreatedAt = now
	}
	token.LastSeenAt = now // Всегда обновляем LastSeenAt

	// Используем OnConflict для обновления LastSeenAt и DeviceType, если токен уже существует
	// Это покрывает случай, когда пользователь переустанавливает приложение или меняет тип устройства для того же токена (маловероятно, но возможно).
	err := r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "device_token"}},                                      // Конфликт по уникальному device_token
		DoUpdates: clause.AssignmentColumns([]string{"user_id", "device_type", "last_seen_at"}), // Обновляем эти поля при конфликте
	}).Create(token).Error

	if err != nil {
		log.Error("failed to add or update device token", "error", err)
		// Здесь можно добавить более специфичную обработку ошибок БД, если нужно
		return gouser.ErrInternal
	}
	log.Info("Device token added or updated successfully", "deviceTokenID", token.DeviceTokenID)
	return nil
}

func (r *ProfileDatabase) RemoveDeviceToken(ctx context.Context, userID uint, deviceTokenValue string) error {
	op := "ProfileDatabase.RemoveDeviceToken"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	result := r.db.WithContext(ctx).Where("user_id = ? AND device_token = ?", userID, deviceTokenValue).Delete(&gouser.UserDeviceToken{})
	if result.Error != nil {
		log.Error("failed to remove device token", "error", result.Error)
		return gouser.ErrInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("device token not found for removal or does not belong to user")
		// Не возвращаем ошибку, так как цель - токен удален, если его и так не было, то все ок.
	}
	log.Info("Device token removed (if existed)", "rows_affected", result.RowsAffected)
	return nil
}

func (r *ProfileDatabase) GetDeviceTokensByUserID(ctx context.Context, userID uint) ([]gouser.UserDeviceToken, error) {
	op := "ProfileDatabase.GetDeviceTokensByUserID"
	log := r.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))
	var tokens []gouser.UserDeviceToken

	// Можно добавить условие для обновления LastSeenAt, если токен "старый", но это лучше делать при фактической отправке Push.
	// Например, удалить токены, которые не использовались > X месяцев.
	if err := r.db.WithContext(ctx).Where("user_id = ?", userID).Find(&tokens).Error; err != nil {
		log.Error("failed to get device tokens by user ID", "error", err)
		return nil, gouser.ErrInternal
	}
	log.Debug("Device tokens retrieved for user", slog.Int("count", len(tokens)))
	return tokens, nil
}

func (r *ProfileDatabase) UpdateDeviceTokenLastSeen(ctx context.Context, deviceTokenValue string) error {
	op := "ProfileDatabase.UpdateDeviceTokenLastSeen"
	log := r.log.With(slog.String("op", op))

	result := r.db.WithContext(ctx).Model(&gouser.UserDeviceToken{}).
		Where("device_token = ?", deviceTokenValue).
		Update("last_seen_at", time.Now().UTC())

	if result.Error != nil {
		log.Error("failed to update device token last_seen_at", "error", result.Error)
		return gouser.ErrInternal
	}
	if result.RowsAffected == 0 {
		log.Warn("device token not found for updating last_seen_at")
		// Не ошибка, если токен был удален параллельно
	}
	return nil
}
