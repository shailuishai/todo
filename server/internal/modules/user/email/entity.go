package email

import (
	"net/http"
)

type UserEmail struct {
	UserId        int64  `json:"user_id"`
	Email         string `json:"email"`
	VerifiedEmail bool   `json:"verified_email"`
}

type Controller interface {
	SendConfirmedEmailCode(w http.ResponseWriter, r *http.Request)
	EmailConfirmed(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	SendEmailForConfirmed(email string) error
	EmailConfirmed(email string, code string) error
}

type Repo interface {
	ConfirmEmail(email string) error
	IsEmailConfirmed(email string) (bool, error)
	SaveEmailConfirmedCode(email string, code string) error
	GetEmailConfirmedCode(email string) (string, error)
}
