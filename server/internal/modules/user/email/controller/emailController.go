package controller

import (
	"errors"
	"github.com/go-chi/render"
	"github.com/go-playground/validator/v10"
	"log/slog"
	"net/http"
	u "server/internal/modules/user"
	"server/internal/modules/user/email"
	resp "server/pkg/lib/response"
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
// @Description Generate code for confirmation email and send this to email. This endpoint have rate 1 req in 1 min
// @Accept json
// @Produce json
// @Param request body SendConfirmedEmailCodeRequest true "Email пользователя для подтверждения"
// @Success 201 {object} response.Response "Код подтверждения успешно отправлен"
// @Failure 400 {object} response.Response "Ошибка валидации или неверный запрос"
// @Failure 500 {object} response.Response "Внутренняя ошибка сервера"
// @Router /email/send-code [post]
func (c *EmailController) SendConfirmedEmailCode(w http.ResponseWriter, r *http.Request) {
	log := c.log.With("op", "SendConfirmedEmailCode")

	var req SendConfirmedEmailCodeRequest

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", err)
		w.WriteHeader(http.StatusBadRequest)
		render.JSON(w, r, resp.Error("failed to decode request"))
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Info("failed to validate request data", err)
		w.WriteHeader(http.StatusBadRequest)
		render.JSON(w, r, resp.ValidationError(err))
		return
	}

	if err := c.uc.SendEmailForConfirmed(req.Email); err != nil {

		switch {
		case errors.Is(err, u.ErrEmailAlreadyConfirmed):
			w.WriteHeader(http.StatusBadRequest)
			render.JSON(w, r, resp.Error(u.ErrEmailAlreadyConfirmed.Error()))
		case errors.Is(err, u.ErrUserNotFound):
			w.WriteHeader(http.StatusBadRequest)
			render.JSON(w, r, resp.Error(u.ErrUserNotFound.Error()))
		default:
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error("internal server error"))
		}

		return
	}

	w.WriteHeader(http.StatusCreated)
	render.JSON(w, r, resp.OK())
	return
}

// EmailConfirmed godoc
// @Summary Confirmation email address
// @Tags email
// @Description Validate confirmed code and is it confirmed update email_status
// @Accept json
// @Produce json
// @Param request body EmailConfirmedRequest true "data for confirmed email"
// @Success 200 {object} response.Response "Success email confirmation"
// @Failure 400 {object} response.Response "Error email confirmation"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /email/confirm	 [put]
func (c *EmailController) EmailConfirmed(w http.ResponseWriter, r *http.Request) {
	log := c.log.With("op", "EmailConfirmedHandler")

	var req EmailConfirmedRequest

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", err)
		w.WriteHeader(http.StatusBadRequest)
		render.JSON(w, r, resp.Error("failed to decode request"))
		return
	}

	if err := c.validate.Struct(req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		render.JSON(w, r, resp.ValidationError(err))
		return
	}

	if err := c.uc.EmailConfirmed(req.Email, req.Code); err != nil {
		switch {
		case errors.Is(err, u.ErrUserNotFound):
			w.WriteHeader(http.StatusNotFound)
			render.JSON(w, r, resp.Error(u.ErrUserNotFound.Error()))
		case errors.Is(err, u.ErrEmailAlreadyConfirmed):
			w.WriteHeader(http.StatusConflict)
			render.JSON(w, r, resp.Error(u.ErrEmailAlreadyConfirmed.Error()))
		case errors.Is(err, u.ErrInvalidConfirmCode):
			w.WriteHeader(http.StatusBadRequest)
			render.JSON(w, r, resp.Error(u.ErrEmailNotConfirmed.Error()))
		default:
			log.Error("failed to confirm email", err)
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error("internal server error"))
		}
		return
	}

	w.WriteHeader(http.StatusOK)
	render.JSON(w, r, resp.OK())
}
