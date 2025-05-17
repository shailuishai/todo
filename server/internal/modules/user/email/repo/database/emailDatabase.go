package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/user"
)

type EmailDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewEmailDatabase(db *gorm.DB, log *slog.Logger) *EmailDatabase {
	log = log.With("op", "db")
	return &EmailDatabase{
		db:  db,
		log: log,
	}
}

func (db *EmailDatabase) ConfirmEmail(email string) error {
	result := db.db.Model(&user.User{}).Where("email = ?", email).Update("verified_email", true)
	if result.Error != nil {
		return user.ErrInternal
	}

	if result.RowsAffected == 0 {
		return user.ErrUserNotFound
	}

	return nil
}

func (db *EmailDatabase) IsEmailConfirmed(email string) (bool, error) {
	var User user.User

	if err := db.db.Where("email = ?", email).First(&User).Error; err != nil {
		db.log.Error(err.Error())
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, user.ErrUserNotFound
		}
		return true, user.ErrUserNotFound
	}

	return User.VerifiedEmail, nil
}
