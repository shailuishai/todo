package usecase

import (
	"crypto/rand"
	"errors"
	"log/slog"
	"math/big"
	u "server/internal/modules/user"
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

func (uc *EmailUseCase) SendEmailForConfirmed(email string) error {
	ok, err := uc.rp.IsEmailConfirmed(email)
	if err != nil {
		if errors.Is(err, u.ErrUserNotFound) {
			return u.ErrUserNotFound
		}
		return err
	}
	if ok {
		return u.ErrEmailAlreadyConfirmed
	}

	code, err := GenerateEmailCode()
	if err != nil {
		return err
	}

	if err := uc.rp.SaveEmailConfirmedCode(email, code); err != nil {
		return err
	}

	go func() {
		err := uc.ess.SendConfirmEmail(code, email)
		if err != nil {
			uc.log.Error("send email confirm code failed", slog.String("email", email), slog.String("error", err.Error()))
		}
	}()

	return nil
}

func (uc *EmailUseCase) EmailConfirmed(email string, code string) error {
	ok, err := uc.rp.IsEmailConfirmed(email)
	if err != nil {
		if errors.Is(err, u.ErrUserNotFound) {
			return u.ErrUserNotFound
		}
		return err
	}
	if ok {
		return u.ErrEmailAlreadyConfirmed
	}

	realCode, err := uc.rp.GetEmailConfirmedCode(email)
	if err != nil {
		return err
	}

	if realCode != code {
		return u.ErrInvalidConfirmCode
	}

	if err := uc.rp.ConfirmEmail(email); err != nil {
		return err
	}

	return nil
}

func GenerateEmailCode() (string, error) {
	const CharSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	code := make([]byte, 6)
	for i := range code {
		index, err := rand.Int(rand.Reader, big.NewInt(int64(len(CharSet))))
		if err != nil {
			return "", err
		}
		code[i] = CharSet[index.Int64()]
	}
	return string(code), nil
}
