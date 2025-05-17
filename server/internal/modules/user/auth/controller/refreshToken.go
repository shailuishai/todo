package controller

import (
	"errors"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	u "server/internal/modules/user"
	resp "server/pkg/lib/response"
)

// RefreshToken
// @Summary Refresh Access Token
// @Tags auth
// @Description Refreshes the access token using the provided refresh token from cookies.
// @Accept json
// @Produce json
// @Success 200 {object} response.Response "Successfully refreshed access token"
// @Failure 401 {object} response.Response "Invalid, missing or expired refresh token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /auth/refresh-token [post]
func (c *AuthController) RefreshToken(w http.ResponseWriter, r *http.Request) {
	log := c.log.With(slog.String("op", "RefreshTokenHandler"))

	AccessToken, err := c.uc.RefreshToken(r)
	if err != nil {
		switch {
		case errors.Is(err, u.ErrNoRefreshToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, u.ErrInvalidToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, u.ErrExpiredToken):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		case errors.Is(err, u.ErrUserNotFound):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error(err.Error()))
		default:
			log.Error(err.Error())
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error(u.ErrInternal.Error()))
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	render.JSON(w, r, resp.AccessToken(AccessToken))
}
