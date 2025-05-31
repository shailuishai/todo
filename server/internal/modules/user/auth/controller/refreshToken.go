package controller

import (
	"errors"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	gouser "server/internal/modules/user"
	resp "server/pkg/lib/response"
)

func (c *AuthController) RefreshToken(w http.ResponseWriter, r *http.Request) {
	log := c.log.With(slog.String("op", "RefreshTokenHandler"))

	AccessToken, err := c.uc.RefreshToken(r)
	if err != nil {
		switch {
		case errors.Is(err, gouser.ErrNoRefreshToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, gouser.ErrInvalidToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, gouser.ErrExpiredToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, gouser.ErrUserNotFound):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		default:
			log.Error(err.Error())
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error(gouser.ErrInternal.Error()))
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	render.JSON(w, r, resp.AccessToken(AccessToken))
}

// RefreshTokenNative
// @Summary      Refresh Access Token (Native)
// @Tags         auth
// @Description  Refreshes the access token using the provided refresh token in the request body.
// @Description  Optionally returns a new refresh token for rotation.
// @Accept       json
// @Produce      json
// @Param        request body controller.RefreshTokenNativeRequest true "Refresh token payload"
// @Success      200 {object} response.SuccessResponse{data=map[string]string} "Successfully refreshed tokens. Data contains 'access_token' and optionally 'refresh_token'."
// @Failure      400 {object} response.ErrorResponse "Invalid request payload or validation error"
// @Failure      401 {object} response.ErrorResponse "Invalid, missing, or expired refresh token"
// @Failure      500 {object} response.ErrorResponse "Internal server error"
// @Router       /auth/refresh-token-native [post]
func (c *AuthController) RefreshTokenNative(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.RefreshTokenNative"
	log := c.log.With(slog.String("op", op))

	var req RefreshTokenNativeRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body for native refresh", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Failed to decode request")
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for native refresh request", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	newAccessToken, newRefreshToken, err := c.uc.RefreshTokenNative(req.RefreshToken)
	if err != nil {
		// err уже будет типа gouser.ErrNoRefreshToken, ErrInvalidToken, ErrExpiredToken, ErrUserNotFound или ErrInternal
		// из UseCase
		log.Warn("usecase RefreshTokenNative failed", "error", err.Error()) // Используем err.Error() для логирования
		// Определяем статус код на основе типа ошибки
		statusCode := http.StatusInternalServerError
		userFacingError := gouser.ErrInternal.Error() // По умолчанию

		switch {
		case errors.Is(err, gouser.ErrNoRefreshToken), errors.Is(err, gouser.ErrInvalidToken), errors.Is(err, gouser.ErrExpiredToken), errors.Is(err, gouser.ErrUserNotFound):
			statusCode = http.StatusUnauthorized
			userFacingError = err.Error() // Можно вернуть специфичную ошибку клиенту
		}
		resp.SendError(w, r, statusCode, userFacingError)
		return
	}

	responsePayload := map[string]string{
		"access_token": newAccessToken,
	}
	if newRefreshToken != "" { // Если UseCase вернул новый refresh_token, добавляем его
		responsePayload["refresh_token"] = newRefreshToken
	}

	log.Info("tokens refreshed successfully for native client")
	resp.SendSuccess(w, r, http.StatusOK, responsePayload)
}
