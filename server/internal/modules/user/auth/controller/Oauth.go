// Файл: internal/modules/user/auth/controller/Oauth.go
package controller

import (
	"fmt"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"github.com/google/uuid"
	"log/slog"
	"net/http"
	"net/url"
	resp "server/pkg/lib/response"
	"strings"
	"time"
)

// Oauth ... (без изменений)
func (c *AuthController) Oauth(w http.ResponseWriter, r *http.Request) {
	// ... ваш текущий код без изменений ...
}

// OauthCallback теперь НЕ УСТАНАВЛИВАЕТ COOKIE и не редиректит на фронтенд.
// Он генерирует одноразовый код и редиректит на промежуточную страницу /oauth/finalize.
func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthCallback"
	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	// ... (вся ваша логика проверки state и code остается) ...

	_, _, appAccessToken, appRefreshToken, err := c.uc.Callback(provider, state, code)
	if err != nil {
		log.Error("Usecase Callback processing failed", "error", err)
		// Редиректим на страницу ошибки фронтенда
		errorRedirectURL, _ := url.Parse(c.oauthCfg.FrontendRedirectErrorURL)
		q := errorRedirectURL.Query()
		q.Set("error", "oauth_processing_failed")
		q.Set("error_description", err.Error())
		errorRedirectURL.RawQuery = q.Encode()
		http.Redirect(w, r, errorRedirectURL.String(), http.StatusTemporaryRedirect)
		return
	}

	// НОВАЯ ЛОГИКА: Вместо установки cookie, сохраняем токены в кэш по одноразовому коду
	finalizeCode := uuid.New().String()
	tokensToCache := fmt.Sprintf("%s:%s", appAccessToken, appRefreshToken) // Простое объединение

	// Используем тот же кеш, что и для state, но с другим префиксом и коротким временем жизни
	// Предполагаем, что у вас есть метод для этого в usecase/repo.
	// Для простоты, давайте представим, что мы можем вызвать метод репозитория напрямую.
	// Это не очень чисто, но для демонстрации подхода пойдет.
	// В идеале, это должен делать usecase.
	// Давайте добавим в usecase новый метод:
	err = c.uc.StoreFinalizeTokens(finalizeCode, tokensToCache)
	if err != nil {
		log.Error("Failed to store finalize tokens in cache", "error", err)
		// Обработка ошибки...
		http.Error(w, "Internal server error", http.StatusInternalServerError)
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
func (c *AuthController) OauthFinalizePage(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	frontendURL := r.URL.Query().Get("frontend_url")

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
		<script>
			async function finalize() {
				try {
					const response = await fetch('/v1/auth/oauth/exchange-code', {
						method: 'POST',
						headers: {
							'Content-Type': 'application/json'
						},
						body: JSON.stringify({ code: '` + code + `' })
					});

					if (!response.ok) {
						throw new Error('Failed to exchange code for tokens. Status: ' + response.status);
					}
					
					// Если все успешно, сервер установил cookie, и мы можем редиректить
					window.location.href = '` + frontendURL + `';

				} catch (error) {
					console.error('Finalization error:', error);
					// Редиректим на страницу ошибки, если что-то пошло не так
					window.location.href = '/error-page?message=' + encodeURIComponent(error.message);
				}
			}
			window.onload = finalize;
		</script>
	</head>
	<body>
		<p>Please wait, finalizing authentication...</p>
	</body>
	</html>
	`
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(html))
}

// OauthExchangeCode - это новый API-эндпоинт, который вызывается скриптом.
// Он работает как SignIn - в прямом ответе.
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
