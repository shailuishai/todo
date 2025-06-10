// Файл: internal/modules/user/auth/controller/Oauth.go
package controller

import (
	"errors"
	"fmt"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"github.com/google/uuid"
	"log/slog"
	"net/http"
	"net/url"
	gouser "server/internal/modules/user"
	resp "server/pkg/lib/response"
	"strings"
	"time"
)

const nativeRedirectURISessionCookie = "native_final_redirect_uri_session"

// Oauth хендлер для редиректа на OAuth провайдера
// @Summary      Initiate OAuth flow
// @Description  Redirects the user to the OAuth provider's authorization page.
// @Description  For native clients, a 'native_final_redirect_uri' query parameter can be provided,
// @Description  which will be used as the final redirect target after successful OAuth with the provider and our backend.
// @Tags         auth
// @Param        provider path string true "OAuth provider (e.g., google, yandex)"
// @Param        native_final_redirect_uri query string false "URI to redirect native clients to after successful authentication by our backend (e.g., http://127.0.0.1:8989/native-oauth-landing)"
// @Success      307 "Temporary Redirect to OAuth provider"
// @Failure      400 "Bad Request - Unsupported provider or provider not configured"
// @Failure      500 "Internal Server Error"
// @Router       /auth/{provider} [get]
func (c *AuthController) Oauth(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.Oauth"
	provider := chi.URLParam(r, "provider")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	nativeFinalRedirectURI := r.URL.Query().Get("native_final_redirect_uri")

	// uc.GetAuthURL должен генерировать state и сохранять его в репозитории (кэше).
	// Этот state будет проверен в OauthCallback.
	authURL, _, err := c.uc.GetAuthURL(provider) // state здесь не используется напрямую контроллером
	if err != nil {
		log.Warn("failed to get auth URL from usecase", "error", err)
		if errors.Is(err, gouser.ErrUnsupportedProvider) || errors.Is(err, gouser.ErrAuthProviderNotConfigured) {
			http.Error(w, err.Error(), http.StatusBadRequest)
		} else {
			http.Error(w, "failed to initiate oauth flow", http.StatusInternalServerError)
		}
		return
	}

	// Если это нативный клиент (есть native_final_redirect_uri),
	// сохраняем его во временный cookie, чтобы OauthCallback мог его использовать.
	if nativeFinalRedirectURI != "" {
		http.SetCookie(w, &http.Cookie{
			Name:     nativeRedirectURISessionCookie,
			Value:    nativeFinalRedirectURI,
			Path:     "/v1/auth/" + provider + "/callback", // Cookie будет доступен только этому callback пути
			Expires:  time.Now().Add(10 * time.Minute),     // Время жизни cookie (например, 10 минут)
			HttpOnly: true,
			Secure:   c.jwtCfg.SecureCookie, // Должно быть true для HTTPS
			SameSite: http.SameSiteLaxMode,  // Lax достаточно для этого временного cookie
		})
		log.Info("Native final redirect URI saved in session cookie for callback", "uri", nativeFinalRedirectURI, "provider", provider)
	}

	log.Info("Redirecting user to OAuth provider authorization page", "provider_auth_url", authURL)
	http.Redirect(w, r, authURL, http.StatusTemporaryRedirect)
}

// OauthCallback теперь НЕ УСТАНАВЛИВАЕТ COOKIE и не редиректит на фронтенд.
// Он генерирует одноразовый код и редиректит на промежуточную страницу /v1/auth/oauth/finalize.
// @Summary      OAuth Callback
// @Description  Handles the callback from the OAuth provider and redirects to an internal finalization page.
// @Tags         auth
// @Param        provider path string true "OAuth provider (e.g., google, yandex)"
// @Param        code query string true "Authorization code from OAuth provider"
// @Param        state query string true "State parameter from OAuth provider"
// @Success      307 "Temporary Redirect to internal finalization page"
// @Failure      400 "Bad Request - Missing code/state, invalid state, or other OAuth processing error"
// @Failure      500 "Internal Server Error"
// @Router       /auth/{provider}/callback [get]
func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthCallback"
	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	// Проверяем наличие state и code
	if state == "" || code == "" {
		log.Warn("Missing state or code in OAuth callback")
		c.redirectToErrorPage(w, r, "missing_oauth_params", "State or code is missing from OAuth provider callback.")
		return
	}

	// Получаем токены нашего приложения из usecase
	_, _, appAccessToken, appRefreshToken, err := c.uc.Callback(provider, state, code)
	if err != nil {
		log.Error("Usecase Callback processing failed", "error", err)
		c.redirectToErrorPage(w, r, "oauth_processing_failed", err.Error())
		return
	}

	// НОВАЯ ЛОГИКА: Вместо установки cookie, сохраняем токены в кэш по одноразовому коду
	finalizeCode := uuid.NewString()
	tokensToCache := fmt.Sprintf("%s:%s", appAccessToken, appRefreshToken) // Простое объединение токенов

	err = c.uc.StoreFinalizeTokens(finalizeCode, tokensToCache)
	if err != nil {
		log.Error("Failed to store finalize tokens in cache", "error", err)
		c.redirectToErrorPage(w, r, "internal_error", "Failed to prepare finalization.")
		return
	}

	// Редиректим на наш же бэкенд, на новую промежуточную страницу
	finalizeURL := fmt.Sprintf("/v1/auth/oauth/finalize?code=%s&frontend_url=%s",
		finalizeCode,
		url.QueryEscape(c.oauthCfg.FrontendRedirectSuccessURL),
	)

	log.Info("Redirecting to internal finalize page", "url", finalizeURL)
	http.Redirect(w, r, finalizeURL, http.StatusTemporaryRedirect)
}

// OauthFinalizePage - это новый хендлер, который отдает HTML-страницу со скриптом.
// @Summary      OAuth Finalization Page
// @Description  Serves an HTML page with JavaScript to finalize the OAuth flow by exchanging a one-time-code for tokens.
// @Tags         auth
// @Param        code query string true "One-time code for finalization"
// @Param        frontend_url query string true "The final frontend URL to redirect to"
// @Success      200 {string} string "HTML page"
// @Failure      400 "Bad Request - Missing code or frontend_url"
// @Router       /auth/oauth/finalize [get]
func (c *AuthController) OauthFinalizePage(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	frontendURL := r.URL.Query().Get("frontend_url")
	errorRedirectURL := c.oauthCfg.FrontendRedirectErrorURL

	if code == "" || frontendURL == "" {
		http.Error(w, "Missing code or frontend_url", http.StatusBadRequest)
		return
	}

	// Отдаем простую HTML-страницу
	html := `
	<!DOCTYPE html>
	<html>
	<head>
		<title>Finalizing Authentication...</title>
		<style>body { font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background-color: #f0f2f5; color: #333; }</style>
		<script>
			async function finalize() {
				try {
					const response = await fetch('/v1/auth/oauth/exchange-code', {
						method: 'POST',
						headers: { 'Content-Type': 'application/json' },
						body: JSON.stringify({ code: '` + code + `' })
					});
					if (!response.ok) {
						const errorBody = await response.json().catch(() => ({ error: 'Unknown error' }));
						throw new Error(errorBody.error || 'Failed to exchange code. Status: ' + response.status);
					}
					window.location.href = '` + frontendURL + `';
				} catch (error) {
					console.error('Finalization error:', error);
					const errorUrl = new URL('` + errorRedirectURL + `');
					errorUrl.searchParams.set('error', 'finalization_failed');
					errorUrl.searchParams.set('error_description', error.message);
					window.location.href = errorUrl.toString();
				}
			}
			window.onload = finalize;
		</script>
	</head>
	<body><p>Please wait, finalizing authentication...</p></body>
	</html>
	`
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(html))
}

// OauthExchangeCode - это новый API-эндпоинт, который вызывается скриптом.
// Он работает как SignIn - в прямом ответе.
// @Summary      Exchange OAuth Code
// @Description  Exchanges a one-time-code for application tokens and sets the refresh_token cookie.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body object{code=string} true "One-time code"
// @Success      200 {object} response.Response "Returns access_token"
// @Failure      400 "Bad Request"
// @Failure      401 "Invalid or expired code"
// @Failure      500 "Internal Server Error"
// @Router       /auth/oauth/exchange-code [post]
func (c *AuthController) OauthExchangeCode(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthExchangeCode"
	log := c.log.With(slog.String("op", op))

	var req struct {
		Code string `json:"code"`
	}
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Error("Failed to decode request", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request")
		return
	}

	tokens, err := c.uc.RetrieveFinalizeTokens(req.Code)
	if err != nil {
		log.Warn("Failed to retrieve finalize tokens", "error", err, "code", req.Code)
		resp.SendError(w, r, http.StatusUnauthorized, "Invalid or expired code")
		return
	}

	parts := strings.Split(tokens, ":")
	if len(parts) != 2 {
		log.Error("Invalid token format in cache", "code", req.Code)
		resp.SendError(w, r, http.StatusInternalServerError, "Internal error")
		return
	}
	accessToken := parts[0]
	refreshToken := parts[1]

	// ТЕПЕРЬ МЫ УСТАНАВЛИВАЕМ COOKIE В ПРЯМОМ ОТВЕТЕ НА FETCH-ЗАПРОС
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
	log.Info("HttpOnly refresh_token cookie set successfully in exchange-code flow")

	// И возвращаем access_token в теле, как делает SignIn
	render.JSON(w, r, resp.AccessToken(accessToken))
}

// redirectToErrorPage - вспомогательная функция для редиректа на страницу ошибки.
func (c *AuthController) redirectToErrorPage(w http.ResponseWriter, r *http.Request, errCode, errDesc string) {
	errorRedirectURL, _ := url.Parse(c.oauthCfg.FrontendRedirectErrorURL)
	q := errorRedirectURL.Query()
	q.Set("error", errCode)
	q.Set("error_description", errDesc)
	errorRedirectURL.RawQuery = q.Encode()
	http.Redirect(w, r, errorRedirectURL.String(), http.StatusTemporaryRedirect)
}
