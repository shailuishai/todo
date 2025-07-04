package controller

import (
	"errors"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	u "server/internal/modules/user"
	resp "server/pkg/lib/response"
	"time"
)

// SignIn
// @Summary User SignIn
// @Tags auth
// @Description Create access and refresh token and return them to the user
// @Accept json
// @Produce json
// @Param user body controller.UserSignInRequest true "User login details"
// @Success 200 {object} response.Response "User successfully signed in"
// @Failure 400 {object} response.Response "Invalid request payload or validation error"
// @Failure 401 {object} response.Response "Invalid Password or Email"
// @Failure 403 {object} response.Response "User email is not confirmed"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /auth/sign-in [post]
func (c *AuthController) SignIn(w http.ResponseWriter, r *http.Request) {
	log := c.log.With(slog.String("op", "SignInHandler"))

	var req UserSignInRequest

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", err)
		w.WriteHeader(http.StatusBadRequest)
		render.JSON(w, r, resp.Error("failed to decode request"))
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Error("failed to validate request", err)
		w.WriteHeader(http.StatusBadRequest)
		resp.SendValidationError(w, r, err)
		return
	}

	AccessToken, RefreshToken, err := c.uc.SignIn(req.Email, req.Login, req.Password)
	if err != nil {
		switch {
		case errors.Is(err, u.ErrUserNotFound):
			w.WriteHeader(http.StatusUnauthorized)
			render.JSON(w, r, resp.Error("failed email or login or password"))
		case errors.Is(err, u.ErrEmailNotConfirmed):
			w.WriteHeader(http.StatusForbidden)
			render.JSON(w, r, resp.Error("email not confirmed"))
		default:
			log.Error("failed to sign in", err)
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error("internal server error"))
		}
		return
	}

	cookie := http.Cookie{
		Name:     "refresh_token",
		Value:    RefreshToken,
		Expires:  time.Now().Add(c.jwtCfg.RefreshExpire),
		HttpOnly: true,
		Path:     "/",
		Domain:   c.jwtCfg.CookieDomain, // "localhost" из вашего config.yml
		Secure:   c.jwtCfg.SecureCookie, // false из вашего config.yml для http
	}

	if !cookie.Secure {
		cookie.SameSite = http.SameSiteNoneMode
	} else {
		// Для HTTPS можно использовать SameSite=Lax или SameSite=None (если нужна кросс-сайтовая отправка cookie)
		// В данном OAuth сценарии с редиректами Lax более чем достаточен и безопасен.
		cookie.SameSite = http.SameSiteNoneMode
	} // Устанавливаем refresh_token в cookie

	http.SetCookie(w, &cookie)
	log.Info("refresh_token cookie set",
		slog.String("name", cookie.Name),
		slog.String("domain", cookie.Domain),
		slog.Bool("secure", cookie.Secure))

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	render.JSON(w, r, resp.AccessToken(AccessToken))
}
