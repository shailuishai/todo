package controller

import (
	"github.com/go-playground/validator/v10"
	"log/slog"
	"server/internal/modules/user/auth"
)

type AuthController struct {
	log      *slog.Logger
	uc       auth.UseCase
	validate *validator.Validate
}

func NewAuthController(log *slog.Logger, uc auth.UseCase) *AuthController {
	validate := validator.New()
	return &AuthController{
		log:      log,
		uc:       uc,
		validate: validate,
	}
}
