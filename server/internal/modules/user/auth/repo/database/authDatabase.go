package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/user"
	"server/internal/modules/user/auth"
	"strings"
)

type AuthDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewAuthDatabase(db *gorm.DB, log *slog.Logger) *AuthDatabase {
	log = log.With("op", "db")
	return &AuthDatabase{
		db:  db,
		log: log,
	}
}

func (db *AuthDatabase) CreateUser(User *auth.UserAuth) (uint, error) {
	userModel := user.FromAuthUser(User)

	if err := db.db.Create(userModel).Error; err != nil {
		db.log.Error(err.Error())
		if strings.Contains(err.Error(), "login") {
			return 0, user.ErrLoginExists
		} else if strings.Contains(err.Error(), "email") {
			return 0, user.ErrEmailExists
		}
		return 0, user.ErrInternal
	}

	return userModel.UserId, nil
}

func (db *AuthDatabase) GetUserByEmail(email string) (*auth.UserAuth, error) {
	var User user.User

	if err := db.db.Where("email = ?", email).First(&User).Error; err != nil {
		db.log.Error(err.Error())
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, user.ErrUserNotFound
		}
		return nil, user.ErrInternal
	}

	return user.ToAuthUser(&User), nil
}

func (db *AuthDatabase) GetUserByLogin(login string) (*auth.UserAuth, error) {
	var User user.User

	if err := db.db.Where("login = ?", login).First(&User).Error; err != nil {
		db.log.Error(err.Error())
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, user.ErrUserNotFound
		}
		return nil, user.ErrInternal
	}

	return user.ToAuthUser(&User), nil
}

func (db *AuthDatabase) GetUserById(id uint) (*auth.UserAuth, error) {
	var User user.User
	if err := db.db.Where("id = ?", id).First(&User).Error; err != nil {
		db.log.Error(err.Error())
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, user.ErrUserNotFound
		}
		return nil, user.ErrInternal
	}

	return user.ToAuthUser(&User), nil
}
