package controller

import (
	"errors"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	u "server/internal/modules/user"
	resp "server/pkg/lib/response"
	"time"
)

// Oauth
// @Summary User SignWithOauth
// @Tags auth
// @Description Redirects the user to the OAuth provider for authentication.
// @Accept json
// @Produce json
// @Param provider path string true "OAuth provider DON'T WORK IN SWAGGER!!!" example("google" or "yandex")
// @Success 307 "Redirecting to provider"
// @Failure 400 {object} response.Response "Provider not supported"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /auth/{provider} [get]
func (c *AuthController) Oauth(w http.ResponseWriter, r *http.Request) {
	log := c.log.With(slog.String("op", "OauthHandler"))

	provider := chi.URLParam(r, "provider")
	url, err := c.uc.GetAuthURL(provider)
	if err != nil {
		switch {
		case errors.Is(err, u.ErrUnsupportedProvider):
			log.Info("unsupported provider", slog.String("provider", provider))
			w.WriteHeader(http.StatusBadRequest)
			render.JSON(w, r, resp.Error("unsupported provider"))
		default:
			log.Error("internal", slog.String("error", err.Error()))
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error("internal server error"))
		}
		return
	}
	http.Redirect(w, r, url, http.StatusTemporaryRedirect)
	return
}

// OauthCallback
// @Summary OAuth2 Callback Handler
// @Tags auth
// @Description Handles the callback from the OAuth provider after the user has authorized the app. THIS ENDPOINT IS CALLED BY THE OAUTH PROVIDER, NOT THE FRONTEND!!!
// @Accept json
// @Produce json
// @Param provider path string true "OAuth provider" example("google" or "yandex")
// @Param state query string true "State parameter sent during OAuth authorization" example("randomstate123")
// @Param code query string true "Authorization code returned by OAuth provider" example("authorizationcode123")
// @Success 200 {object} response.Response "User already exists, successfully authenticated"
// @Success 201 {object} response.Response "New user created and successfully authenticated"
// @Failure 400 {object} response.Response "Provider not supported or invalid state"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /auth/{provider}/callback [get]
func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	log := c.log.With(slog.String("op", "OauthCallbackHandler"))

	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")

	ExistedUser, AccessToken, RefreshToken, err := c.uc.Callback(provider, state, code)
	if err != nil {
		switch {
		case errors.Is(err, u.ErrUnsupportedProvider):
			log.Info("unsupported provider", slog.String("provider", provider))
			w.WriteHeader(http.StatusBadRequest)
			render.JSON(w, r, resp.Error("unsupported provider"))
		default:
			log.Error("internal", slog.String("error", err.Error()))
			w.WriteHeader(http.StatusInternalServerError)
			render.JSON(w, r, resp.Error("internal server error"))
		}
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    RefreshToken,
		Expires:  time.Now().Add(15 * 24 * time.Hour),
		HttpOnly: true,
		Path:     "/",
	})

	w.Header().Set("Content-Type", "application/json")
	if ExistedUser {
		w.WriteHeader(http.StatusOK)
	} else {
		w.WriteHeader(http.StatusCreated)
	}
	render.JSON(w, r, resp.AccessToken(AccessToken))
	return
}
