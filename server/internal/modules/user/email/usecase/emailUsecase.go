package usecase

import (
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	gouser "server/internal/modules/user" // Импортируем как gouser, чтобы не конфликтовать с пакетом email
	"server/internal/modules/user/email"
)

type EmailSenderService interface {
	SendConfirmEmail(code string, email string) error
}

type EmailUseCase struct {
	log *slog.Logger
	rp  email.Repo
	ess EmailSenderService
}

func NewEmailUseCase(log *slog.Logger, rp email.Repo, ess EmailSenderService) *EmailUseCase {
	return &EmailUseCase{
		log: log,
		rp:  rp,
		ess: ess,
	}
}

func (uc *EmailUseCase) SendEmailForConfirmed(emailAddr string) error { // Переименовал email в emailAddr для ясности
	op := "EmailUseCase.SendEmailForConfirmed"
	log := uc.log.With(slog.String("op", op), slog.String("email", emailAddr))

	isConfirmed, err := uc.rp.IsEmailConfirmed(emailAddr)
	if err != nil {
		// ErrUserNotFound от IsEmailConfirmed означает, что пользователя нет,
		// и мы не должны отправлять код подтверждения.
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("user not found, cannot send confirmation email")
			return gouser.ErrUserNotFound
		}
		log.Error("failed to check if email is confirmed", "error", err)
		return gouser.ErrInternal // Используем ошибку из пакета user
	}
	if isConfirmed {
		log.Info("email is already confirmed")
		return gouser.ErrEmailAlreadyConfirmed
	}

	code, err := GenerateEmailCode()
	if err != nil {
		log.Error("failed to generate email code", "error", err)
		return gouser.ErrInternal
	}

	if err := uc.rp.SaveEmailConfirmedCode(emailAddr, code); err != nil {
		log.Error("failed to save email confirmation code to repo", "error", err)
		return gouser.ErrInternal
	}

	go func(currentEmail, currentCode string) { // Передаем email и code в горутину как параметры
		sendErr := uc.ess.SendConfirmEmail(currentCode, currentEmail)
		if sendErr != nil {
			// Логируем ошибку отправки, но не возвращаем ее синхронно,
			// так как код уже сохранен и пользователь может его ввести.
			// Возможно, стоит добавить механизм повторной отправки или уведомления администратора.
			uc.log.Error("async send email confirmation code failed", slog.String("email", currentEmail), slog.String("error", sendErr.Error()))
		} else {
			uc.log.Info("async email confirmation code sent successfully", slog.String("email", currentEmail))
		}
	}(emailAddr, code) // Передаем актуальные значения

	log.Info("email confirmation process initiated, code saved")
	return nil
}

func (uc *EmailUseCase) EmailConfirmed(emailAddr string, code string) error {
	op := "EmailUseCase.EmailConfirmed"
	log := uc.log.With(slog.String("op", op), slog.String("email", emailAddr))

	isAlreadyConfirmed, err := uc.rp.IsEmailConfirmed(emailAddr)
	if err != nil {
		// Опять же, ErrUserNotFound здесь означает, что нет такого пользователя.
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("user not found, cannot confirm email")
			return gouser.ErrUserNotFound
		}
		log.Error("failed to check if email is already confirmed", "error", err)
		return gouser.ErrInternal
	}
	if isAlreadyConfirmed {
		log.Info("email is already confirmed by the time of code submission")
		return gouser.ErrEmailAlreadyConfirmed
	}

	realCode, err := uc.rp.GetEmailConfirmedCode(emailAddr)
	if err != nil {
		// Если GetEmailConfirmedCode вернул ErrInvalidConfirmCode (например, код не найден в кэше)
		if errors.Is(err, gouser.ErrInvalidConfirmCode) {
			log.Warn("invalid or expired confirmation code from repo")
			return gouser.ErrInvalidConfirmCode
		}
		log.Error("failed to get email confirmation code from repo", "error", err)
		return gouser.ErrInternal
	}

	if realCode != code {
		log.Warn("provided confirmation code does not match stored code")
		return gouser.ErrInvalidConfirmCode
	}

	// Если код верный, подтверждаем email в БД
	if err := uc.rp.ConfirmEmail(emailAddr); err != nil {
		log.Error("failed to confirm email in DB", "error", err)
		// Если ConfirmEmail вернул ErrUserNotFound, это странно, так как мы должны были его найти раньше.
		// Но на всякий случай обрабатываем.
		if errors.Is(err, gouser.ErrUserNotFound) {
			return gouser.ErrUserNotFound
		}
		return gouser.ErrInternal
	}

	// После успешного подтверждения удаляем код из кэша
	errDel := uc.rp.DeleteEmailConfirmedCode(emailAddr)
	if errDel != nil {
		// Логируем ошибку удаления из кэша, но не считаем это ошибкой для пользователя,
		// так как email уже подтвержден. Код просто истечет в Redis.
		log.Error("failed to delete used confirmation code from cache, but email confirmed", "error", errDel)
	}

	log.Info("email confirmed successfully")
	return nil
}

func GenerateEmailCode() (string, error) {
	const CharSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	const codeLength = 6
	code := make([]byte, codeLength)
	for i := range code {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(CharSet))))
		if err != nil {
			// slog.Error("failed to generate random number for email code", "error", err) // Логирование здесь излишне, вернем ошибку наверх
			return "", fmt.Errorf("failed to generate random part of email code: %w", err) // Оборачиваем ошибку
		}
		code[i] = CharSet[num.Int64()]
	}
	return string(code), nil
}
