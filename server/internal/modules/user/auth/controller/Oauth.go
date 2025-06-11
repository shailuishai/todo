// internal/modules/user/auth/controller/Oauth.go
package controller

import (
	"errors"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	"net/url"
	gouser "server/internal/modules/user"
	resp "server/pkg/lib/response"
	"time"
)

const nativeRedirectURISessionCookie = "native_final_redirect_uri_session"

func (c *AuthController) Oauth(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.Oauth"
	provider := chi.URLParam(r, "provider")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	clientRedirectURI := r.URL.Query().Get("redirect_uri")
	nativeFinalRedirectURI := r.URL.Query().Get("native_final_redirect_uri")

	// Usecase сам выберет нужный конфиг на основе clientRedirectURI
	authURL, _, err := c.uc.GetAuthURL(provider, clientRedirectURI)
	if err != nil {
		log.Warn("failed to get auth URL from usecase", "error", err)
		if errors.Is(err, gouser.ErrUnsupportedProvider) || errors.Is(err, gouser.ErrAuthProviderNotConfigured) {
			http.Error(w, err.Error(), http.StatusBadRequest)
		} else {
			http.Error(w, "failed to initiate oauth flow", http.StatusInternalServerError)
		}
		return
	}

	if nativeFinalRedirectURI != "" && clientRedirectURI == "" {
		http.SetCookie(w, &http.Cookie{
			Name:     nativeRedirectURISessionCookie,
			Value:    nativeFinalRedirectURI,
			Path:     "/v1/auth/" + provider + "/callback",
			Expires:  time.Now().Add(10 * time.Minute),
			HttpOnly: true,
			Secure:   c.jwtCfg.SecureCookie,
			SameSite: http.SameSiteLaxMode,
		})
		log.Info("Native final redirect URI saved in session cookie for callback", "uri", nativeFinalRedirectURI, "provider", provider)
	}

	log.Info("Redirecting user to OAuth provider authorization page", "provider_auth_url", authURL)
	http.Redirect(w, r, authURL, http.StatusTemporaryRedirect)
}

func (c *AuthController) OAuthExchange(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OAuthExchange"
	log := c.log.With(slog.String("op", op))

	var req struct {
		Code        string `json:"code"`
		State       string `json:"state"`
		Provider    string `json:"provider"`
		RedirectURI string `json:"redirect_uri"`
	}

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}

	log = log.With("provider", req.Provider, "state", req.State)

	if req.Code == "" || req.State == "" || req.Provider == "" || req.RedirectURI == "" {
		resp.SendError(w, r, http.StatusBadRequest, "Missing required fields")
		return
	}

	accessToken, refreshToken, err := c.uc.OAuthExchange(req.Provider, req.State, req.Code, req.RedirectURI)
	if err != nil {
		log.Error("usecase OAuthExchange failed", "error", err)
		if errors.Is(err, gouser.ErrInvalidState) {
			resp.SendError(w, r, http.StatusUnauthorized, "Invalid state")
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to process OAuth code")
		}
		return
	}

	cookie := http.Cookie{
		Name:     "refresh_token",
		Value:    refreshToken,
		Expires:  time.Now().Add(c.jwtCfg.RefreshExpire),
		HttpOnly: true,
		Path:     "/",
		Domain:   c.jwtCfg.CookieDomain,
		Secure:   true,
		SameSite: http.SameSiteNoneMode,
	}
	http.SetCookie(w, &cookie)

	log.Info("OAuthExchange successful, tokens issued and cookie set.")
	render.JSON(w, r, resp.AccessToken(accessToken))
}

func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthCallback (Native Flow)"
	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	nativeRedirectCookie, errCookie := r.Cookie(nativeRedirectURISessionCookie)
	if errCookie != nil || nativeRedirectCookie.Value == "" {
		log.Error("Native callback called without a redirect URI cookie. This endpoint is for native clients only.")
		http.Error(w, "This callback is intended for native clients which provide a final redirect URI.", http.StatusBadRequest)
		return
	}
	nativeFinalRedirectURI := nativeRedirectCookie.Value

	http.SetCookie(w, &http.Cookie{
		Name:     nativeRedirectURISessionCookie,
		Value:    "",
		Path:     "/v1/auth/" + provider + "/callback",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   c.jwtCfg.SecureCookie,
		SameSite: http.SameSiteLaxMode,
	})

	// Передаем пустой redirectURI, чтобы usecase использовал дефолтный (нативный)
	_, isNewUser, appAccessToken, appRefreshToken, err := c.uc.Callback(provider, state, code, "")
	if err != nil {
		log.Error("Usecase Callback processing failed for native client", "error", err)
		errorURL, _ := url.Parse(nativeFinalRedirectURI)
		q := errorURL.Query()
		q.Set("error", "oauth_processing_failed")
		q.Set("error_description", err.Error())
		errorURL.RawQuery = q.Encode()
		http.Redirect(w, r, errorURL.String(), http.StatusTemporaryRedirect)
		return
	}

	targetURL, _ := url.Parse(nativeFinalRedirectURI)
	q := targetURL.Query()
	q.Set("access_token", appAccessToken)
	q.Set("refresh_token", appRefreshToken)
	q.Set("provider", provider)
	if isNewUser {
		q.Set("new_user", "true")
	}
	targetURL.RawQuery = q.Encode()

	log.Info("Redirecting to NATIVE client's landing page with tokens in URL", "final_url", targetURL.String())
	http.Redirect(w, r, targetURL.String(), http.StatusTemporaryRedirect)
}
