package database

import (
	"errors"
	"gorm.io/gorm"
	"log/slog"
	"server/internal/modules/user" // GORM модель User и ошибки
)

type EmailDatabase struct {
	db  *gorm.DB
	log *slog.Logger
}

func NewEmailDatabase(db *gorm.DB, log *slog.Logger) *EmailDatabase {
	return &EmailDatabase{
		db:  db,
		log: log, // Используем переданный логгер
	}
}

// ConfirmEmail обновляет статус verified_email пользователя на true.
func (r *EmailDatabase) ConfirmEmail(email string) error {
	log := r.log.With(slog.String("op", "EmailDatabase.ConfirmEmail"), slog.String("email", email))

	// Обновляем только поле verified_email для пользователя с указанным email.
	// Важно: убедись, что user.User имеет gorm теги для всех полей,
	// чтобы GORM знал, как обновлять.
	result := r.db.Model(&user.User{}).Where("email = ?", email).Update("verified_email", true)

	if result.Error != nil {
		log.Error("failed to update verified_email status in DB", "error", result.Error)
		return user.ErrInternal
	}

	if result.RowsAffected == 0 {
		log.Warn("no user found with this email to confirm")
		return user.ErrUserNotFound // Пользователь не найден
	}

	log.Info("email confirmed successfully in DB")
	return nil
}

// IsEmailConfirmed проверяет, подтвержден ли email пользователя.
func (r *EmailDatabase) IsEmailConfirmed(email string) (bool, error) {
	log := r.log.With(slog.String("op", "EmailDatabase.IsEmailConfirmed"), slog.String("email", email))
	var userGormModel user.User

	// Ищем пользователя по email, чтобы получить его статус verified_email.
	// Select("verified_email") может оптимизировать запрос, если другие поля не нужны.
	err := r.db.Select("verified_email").Where("email = ?", email).First(&userGormModel).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Debug("user not found by email for checking confirmation status")
			// Если пользователь не найден, его email точно не подтвержден с точки зрения системы.
			// Возвращаем (false, user.ErrUserNotFound), чтобы UseCase мог это обработать.
			return false, user.ErrUserNotFound
		}
		log.Error("failed to get user by email for checking confirmation status from DB", "error", err)
		// В предыдущей версии было `return true, user.ErrUserNotFound` - это некорректно.
		// Если произошла ошибка, отличная от RecordNotFound, это внутренняя ошибка.
		return false, user.ErrInternal
	}

	log.Debug("retrieved email confirmation status", "is_confirmed", userGormModel.VerifiedEmail)
	return userGormModel.VerifiedEmail, nil
}
