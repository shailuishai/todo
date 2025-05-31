package controller

import (
	"github.com/go-playground/validator/v10"
	"log/slog"
	"server/config"
	"server/internal/modules/user/auth"
)

type AuthController struct {
	log      *slog.Logger
	uc       auth.UseCase
	validate *validator.Validate
	oauthCfg config.OAuthConfig
	jwtCfg   config.JWTConfig
}

func NewAuthController(log *slog.Logger, uc auth.UseCase, oauthCfg config.OAuthConfig, jwtCfg config.JWTConfig) *AuthController {
	validate := validator.New()
	return &AuthController{
		log:      log,
		uc:       uc,
		oauthCfg: oauthCfg,
		jwtCfg:   jwtCfg,
		validate: validate,
	}
}
