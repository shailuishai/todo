package controller

import (
	"errors"
	"github.com/go-chi/render" // Используется напрямую, а не через resp.Send*
	"github.com/go-playground/validator/v10"
	"log/slog"
	"net/http"
	gouser "server/internal/modules/user" // Импортируем как gouser
	"server/internal/modules/user/email"
	resp "server/pkg/lib/response" // Пакет для стандартизированных ответов
)

type EmailController struct {
	log      *slog.Logger
	uc       email.UseCase
	validate *validator.Validate
}

func NewEmailController(log *slog.Logger, uc email.UseCase) *EmailController {
	validate := validator.New()
	return &EmailController{
		log:      log,
		uc:       uc,
		validate: validate,
	}
}

// SendConfirmedEmailCode
// @Summary Send code for confirmation email
// @Tags email
// @Description Generate code for confirmation email and send this to email. This endpoint has a rate limit of 1 request per minute per IP.
// @Accept json
// @Produce json
// @Param request body SendConfirmedEmailCodeRequest true "User's email for confirmation"
// @Success 202 {object} response.Response "Confirmation code sending process initiated"
// @Failure 400 {object} response.Response "Validation error, email already confirmed, or user not found"
// @Failure 429 {object} response.Response "Too many requests (rate limit exceeded)"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /email/send-code [post]
func (c *EmailController) SendConfirmedEmailCode(w http.ResponseWriter, r *http.Request) {
	op := "EmailController.SendConfirmedEmailCode"
	log := c.log.With(slog.String("op", op))

	var req SendConfirmedEmailCodeRequest

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", "error", err)
		// Используем стандартизированный ответ
		resp.SendError(w, r, http.StatusBadRequest, "failed to decode request")
		return
	}
	log = log.With(slog.String("email", req.Email)) // Логируем email после успешного парсинга

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for request data", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	if err := c.uc.SendEmailForConfirmed(req.Email); err != nil {
		log.Warn("usecase SendEmailForConfirmed failed", "error", err)
		switch {
		case errors.Is(err, gouser.ErrEmailAlreadyConfirmed):
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		case errors.Is(err, gouser.ErrUserNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error()) // 404 для UserNotFound
		default: // Включая gouser.ErrInternal
			resp.SendError(w, r, http.StatusInternalServerError, "failed to initiate email confirmation")
		}
		return
	}

	// Отправка письма - асинхронный процесс. Код сохранен.
	// 202 Accepted - запрос принят к обработке.
	log.Info("email confirmation process initiated successfully")
	resp.SendOK(w, r, http.StatusAccepted) // Используем 202 Accepted
}

// EmailConfirmed
// @Summary Confirm email address
// @Tags email
// @Description Validate confirmation code and if it's correct, update email_verified status.
// @Accept json
// @Produce json
// @Param request body EmailConfirmedRequest true "Data for email confirmation (email and code)"
// @Success 200 {object} response.Response "Email successfully confirmed"
// @Failure 400 {object} response.Response "Invalid request, invalid code, or email already confirmed"
// @Failure 404 {object} response.Response "User not found"
// @Failure 409 {object} response.Response "Email already confirmed (if detected before code check, otherwise 400)"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /email/confirm [put]
func (c *EmailController) EmailConfirmed(w http.ResponseWriter, r *http.Request) {
	op := "EmailController.EmailConfirmed"
	log := c.log.With(slog.String("op", op))

	var req EmailConfirmedRequest

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "failed to decode request")
		return
	}
	log = log.With(slog.String("email", req.Email))

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for request data", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	if err := c.uc.EmailConfirmed(req.Email, req.Code); err != nil {
		log.Warn("usecase EmailConfirmed failed", "error", err)
		switch {
		case errors.Is(err, gouser.ErrUserNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, gouser.ErrEmailAlreadyConfirmed):
			// Если UseCase вернул эту ошибку, значит, email уже был подтвержден.
			// Можно вернуть 400 Bad Request или 409 Conflict. 400 кажется более общим.
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		case errors.Is(err, gouser.ErrInvalidConfirmCode):
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		default: // Включая gouser.ErrInternal
			resp.SendError(w, r, http.StatusInternalServerError, "failed to confirm email")
		}
		return
	}

	log.Info("email confirmed successfully")
	resp.SendOK(w, r, http.StatusOK)
}
