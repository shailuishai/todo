package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	gouser "server/internal/modules/user" // GORM модель User и UserSetting, также ошибки
	"server/internal/modules/user/auth"   // DTO UserAuth
	"strings"
)

type AuthDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewAuthDatabase(db *gorm.DB, log *slog.Logger) *AuthDatabase {
	return &AuthDatabase{
		db:  db,
		log: log,
	}
}

// CreateUser создает нового пользователя в БД.
// Принимает UserAuth DTO, конвертирует его в GORM модель User.
// GORM модель User не должна содержать инициализированное поле Settings,
// чтобы триггер в БД мог создать связанную запись в user_settings.
func (r *AuthDatabase) CreateUser(authUserDTO *auth.UserAuth) (uint, error) {
	log := r.log.With(slog.String("op", "AuthDatabase.CreateUser"), slog.String("email", authUserDTO.Email), slog.String("login", authUserDTO.Login))

	// Конвертируем DTO в GORM модель User.
	// FromAuthUser НЕ должен инициализировать userGormModel.Settings
	userGormModel := auth.FromAuthUser(authUserDTO)

	// При создании пользователя, запись в UserSettings будет создана автоматически триггером.
	// GORM не будет пытаться вставить userGormModel.Settings, если оно zero value.
	if err := r.db.Create(userGormModel).Error; err != nil {
		log.Error("failed to create user in DB", "error", err)
		if strings.Contains(err.Error(), "duplicate key value violates unique constraint") {
			if strings.Contains(err.Error(), "users_login_key") || strings.Contains(err.Error(), "idx_users_login") {
				return 0, gouser.ErrLoginExists
			}
			if strings.Contains(err.Error(), "users_email_key") || strings.Contains(err.Error(), "idx_users_email") {
				return 0, gouser.ErrEmailExists
			}
		}
		return 0, gouser.ErrInternal
	}

	log.Info("user created successfully in DB", slog.Uint64("userID", uint64(userGormModel.UserId)))
	return userGormModel.UserId, nil
}

// fetchUser получает пользователя из БД без явной загрузки Settings.
// Это внутренняя функция, чтобы избежать дублирования кода.
func (r *AuthDatabase) fetchUser(query string, args ...interface{}) (*auth.UserAuth, error) {
	var userGormModel gouser.User // GORM модель
	// Мы не используем Preload("Settings"), так как UserAuth DTO не содержит полей настроек.
	// GORM загрузит только поля из таблицы 'users'.
	if err := r.db.Where(query, args...).First(&userGormModel).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, gouser.ErrUserNotFound
		}
		return nil, gouser.ErrInternal
	}
	return auth.ToAuthUser(&userGormModel), nil // Конвертируем GORM модель в UserAuth DTO
}

func (r *AuthDatabase) GetUserByEmail(email string) (*auth.UserAuth, error) {
	log := r.log.With(slog.String("op", "AuthDatabase.GetUserByEmail"), slog.String("email", email))
	userAuth, err := r.fetchUser("email = ?", email)
	if err != nil {
		if !errors.Is(err, gouser.ErrUserNotFound) { // Логируем только если не ErrUserNotFound
			log.Error("failed to get user by email from DB", "error", err)
		} else {
			log.Debug("user not found by email")
		}
		return nil, err
	}
	log.Debug("user found by email")
	return userAuth, nil
}

func (r *AuthDatabase) GetUserByLogin(login string) (*auth.UserAuth, error) {
	log := r.log.With(slog.String("op", "AuthDatabase.GetUserByLogin"), slog.String("login", login))
	userAuth, err := r.fetchUser("login = ?", login)
	if err != nil {
		if !errors.Is(err, gouser.ErrUserNotFound) {
			log.Error("failed to get user by login from DB", "error", err)
		} else {
			log.Debug("user not found by login")
		}
		return nil, err
	}
	log.Debug("user found by login")
	return userAuth, nil
}

func (r *AuthDatabase) GetUserById(id uint) (*auth.UserAuth, error) {
	log := r.log.With(slog.String("op", "AuthDatabase.GetUserById"), slog.Uint64("userID", uint64(id)))
	// GORM First по primary key (id) также не будет загружать Settings без Preload.
	userAuth, err := r.fetchUser("user_id = ?", id)
	if err != nil {
		if !errors.Is(err, gouser.ErrUserNotFound) {
			log.Error("failed to get user by ID from DB", "error", err)
		} else {
			log.Debug("user not found by ID")
		}
		return nil, err
	}
	log.Debug("user found by ID")
	return userAuth, nil
}
