// Файл: internal/modules/user/auth/controller/Oauth.go
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

const nativeRedirectURISessionCookie = "native_final_redirect_uri_session" // Имя для временного cookie

// Oauth - ИЗМЕНЕН для поддержки как веб, так и нативного потока
// @Summary      Initiate OAuth flow
// @Description  Redirects the user to the OAuth provider's authorization page.
// @Description  - For WEB clients, provide 'redirect_uri' query param with the frontend's callback URL.
// @Description  - For NATIVE clients, do not provide 'redirect_uri', but provide 'native_final_redirect_uri' for the final redirect.
// @Tags         auth
// @Param        provider path string true "OAuth provider (e.g., google, yandex)"
// @Param        redirect_uri query string false "Callback URL for web clients (e.g., https://myapp.com/oauth/callback/google)"
// @Param        native_final_redirect_uri query string false "Final landing URI for native clients"
// @Success      307 "Temporary Redirect to OAuth provider"
// @Failure      400 "Bad Request"
// @Failure      500 "Internal Server Error"
// @Router       /auth/{provider} [get]
func (c *AuthController) Oauth(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.Oauth"
	provider := chi.URLParam(r, "provider")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	// Для веб-клиента мы ожидаем, что он передаст свой redirect_uri
	// Для нативного клиента он будет пустой, и usecase использует дефолтный.
	clientRedirectURI := r.URL.Query().Get("redirect_uri")

	// Для нативного клиента (когда clientRedirectURI пустой), проверяем native_final_redirect_uri
	nativeFinalRedirectURI := r.URL.Query().Get("native_final_redirect_uri")

	// GetAuthURL теперь принимает clientRedirectURI
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

	// Логика для нативного клиента остается прежней: сохраняем конечный URL в cookie
	if nativeFinalRedirectURI != "" && clientRedirectURI == "" {
		http.SetCookie(w, &http.Cookie{
			Name:     nativeRedirectURISessionCookie,
			Value:    nativeFinalRedirectURI,
			Path:     "/v1/auth/" + provider + "/callback", // Cookie будет доступен только этому callback пути
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

// OAuthExchange - НОВЫЙ ХЕНДЛЕР для веб-потока.
// Принимает code и state от фронтенда и возвращает токены напрямую.
// @Summary      Exchange OAuth data for tokens (Web Flow)
// @Description  Receives authorization code and state from a web client, exchanges them for application tokens, and sets the refresh_token cookie.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body object{code=string,state=string,provider=string} true "OAuth data from frontend"
// @Success      200 {object} response.Response "Returns access_token and sets refresh_token cookie"
// @Failure      400 "Bad Request"
// @Failure      401 "Invalid state or code"
// @Failure      500 "Internal Server Error"
// @Router       /auth/oauth/exchange [post]
func (c *AuthController) OAuthExchange(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OAuthExchange"
	log := c.log.With(slog.String("op", op))

	var req struct {
		Code     string `json:"code"`
		State    string `json:"state"`
		Provider string `json:"provider"`
	}

	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}

	log = log.With("provider", req.Provider, "state", req.State)

	if req.Code == "" || req.State == "" || req.Provider == "" {
		resp.SendError(w, r, http.StatusBadRequest, "Missing code, state, or provider")
		return
	}

	// Вызываем use case, который внутри себя вызовет `Callback`
	accessToken, refreshToken, err := c.uc.OAuthExchange(req.Provider, req.State, req.Code)
	if err != nil {
		log.Error("usecase OAuthExchange failed", "error", err)
		if errors.Is(err, gouser.ErrInvalidState) {
			resp.SendError(w, r, http.StatusUnauthorized, "Invalid state")
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to process OAuth code")
		}
		return
	}

	// Устанавливаем cookie и возвращаем access_token, как в SignIn
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

// OauthCallback - этот хендлер теперь ТОЛЬКО ДЛЯ НАТИВНЫХ КЛИЕНТОВ
// @Summary      OAuth Callback (Native Clients)
// @Description  Handles the callback from the OAuth provider for native clients.
// @Description  Redirects to the native client's final landing URI with tokens in the query string.
// @Tags         auth
// @Param        provider path string true "OAuth provider"
// @Param        code query string true "Authorization code"
// @Param        state query string true "State parameter"
// @Success      307 "Temporary Redirect to native client landing page"
// @Failure      400 "Bad Request"
// @Failure      500 "Internal Server Error"
// @Router       /auth/{provider}/callback [get]
func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthCallback (Native Flow)"
	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	// Пытаемся прочитать native_final_redirect_uri из временного cookie
	nativeRedirectCookie, errCookie := r.Cookie(nativeRedirectURISessionCookie)
	if errCookie != nil || nativeRedirectCookie.Value == "" {
		log.Error("Native callback called without a redirect URI cookie. This endpoint is for native clients only.")
		http.Error(w, "This callback is intended for native clients which provide a final redirect URI.", http.StatusBadRequest)
		return
	}
	nativeFinalRedirectURI := nativeRedirectCookie.Value

	// Удаляем временный cookie
	http.SetCookie(w, &http.Cookie{
		Name:     nativeRedirectURISessionCookie,
		Value:    "",
		Path:     "/v1/auth/" + provider + "/callback",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   c.jwtCfg.SecureCookie,
		SameSite: http.SameSiteLaxMode,
	})

	// Вызываем use case для получения токенов
	_, isNewUser, appAccessToken, appRefreshToken, err := c.uc.Callback(provider, state, code)
	if err != nil {
		log.Error("Usecase Callback processing failed for native client", "error", err)
		// Редиректим на конечный URL с параметрами ошибки
		errorURL, _ := url.Parse(nativeFinalRedirectURI)
		q := errorURL.Query()
		q.Set("error", "oauth_processing_failed")
		q.Set("error_description", err.Error())
		errorURL.RawQuery = q.Encode()
		http.Redirect(w, r, errorURL.String(), http.StatusTemporaryRedirect)
		return
	}

	// Редиректим на конечный URL с токенами в query-параметрах
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
