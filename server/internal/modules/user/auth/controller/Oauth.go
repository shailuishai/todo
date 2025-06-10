package controller

import (
	"errors"
	"github.com/go-chi/chi/v5"
	"log/slog"
	"net/http"
	"net/url"
	gouser "server/internal/modules/user"
	"time"
)

const nativeRedirectURISessionCookie = "native_final_redirect_uri_session" // Имя для временного cookie

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

// OauthCallback хендлер для коллбэка от OAuth провайдера
// @Summary      OAuth Callback
// @Description  Handles the callback from the OAuth provider after user authentication.
// @Description  Exchanges the authorization code for tokens, authenticates/creates a user in our system.
// @Description  For web clients, sets an httpOnly refresh_token cookie and redirects to FrontendRedirectSuccessURL.
// @Description  For native clients (if 'native_final_redirect_uri' was provided earlier),
// @Description  redirects to that URI with app's access_token and refresh_token in query parameters.
// @Tags         auth
// @Param        provider path string true "OAuth provider (e.g., google, yandex)"
// @Param        code query string true "Authorization code from OAuth provider"
// @Param        state query string true "State parameter from OAuth provider"
// @Success      307 "Temporary Redirect to frontend or native client landing page"
// @Failure      400 "Bad Request - Missing code/state, invalid state, or other OAuth processing error"
// @Failure      500 "Internal Server Error"
// @Router       /auth/{provider}/callback [get]
func (c *AuthController) OauthCallback(w http.ResponseWriter, r *http.Request) {
	op := "AuthController.OauthCallback"
	provider := chi.URLParam(r, "provider")
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	log := c.log.With(slog.String("op", op), slog.String("provider", provider))

	// Пытаемся прочитать native_final_redirect_uri из временного cookie
	var nativeFinalRedirectURI string
	nativeRedirectCookie, errCookie := r.Cookie(nativeRedirectURISessionCookie)
	if errCookie == nil && nativeRedirectCookie.Value != "" {
		nativeFinalRedirectURI = nativeRedirectCookie.Value
		// Удаляем временный cookie, так как он больше не нужен
		http.SetCookie(w, &http.Cookie{
			Name:     nativeRedirectURISessionCookie,
			Value:    "",
			Path:     "/v1/auth/" + provider + "/callback",
			MaxAge:   -1, // Удалить cookie
			HttpOnly: true,
			Secure:   c.jwtCfg.SecureCookie,
			SameSite: http.SameSiteLaxMode,
		})
		log.Info("Read and cleared native final redirect URI from session cookie", "uri", nativeFinalRedirectURI)
	}

	// Определяем URL для ошибки в зависимости от типа клиента
	errorRedirectTarget := c.oauthCfg.FrontendRedirectErrorURL
	if nativeFinalRedirectURI != "" {
		// Для нативного клиента ошибка тоже должна идти на его landing page с параметрами ошибки
		// Или можно иметь отдельный FrontendRedirectErrorURLNative. Пока упростим.
		// Если мы редиректим на nativeFinalRedirectURI, то параметры ошибки будут добавлены к нему.
		// Если произойдет ошибка *до* того, как мы решим, куда редиректить,
		// то используем общий errorRedirectTarget, а потом уже специфичный.
	}

	if state == "" || code == "" {
		log.Warn("Missing state or code in OAuth callback")
		parsedErrorURL, _ := url.Parse(errorRedirectTarget) // Используем общий errorRedirectTarget
		q := parsedErrorURL.Query()
		q.Set("error", "missing_oauth_params")
		q.Set("error_description", "State or code is missing from OAuth provider callback.")
		q.Set("provider", provider)
		parsedErrorURL.RawQuery = q.Encode()
		http.Redirect(w, r, parsedErrorURL.String(), http.StatusTemporaryRedirect)
		return
	}

	// uc.Callback должен обменять код на токены OAuth провайдера, получить инфо о пользователе,
	// создать/найти пользователя в нашей БД, сгенерировать JWT access и refresh токены нашего приложения.
	// Возвращает: userID, isNewUser, appAccessToken, appRefreshToken, error
	_, isNewUser, appAccessToken, appRefreshToken, err := c.uc.Callback(provider, state, code)
	if err != nil {
		log.Error("Usecase Callback processing failed", "error", err)
		errorMsgTechnical := err.Error()                  // Техническое описание ошибки
		errorMsgUserFriendly := "oauth_processing_failed" // Общее сообщение для пользователя

		if errors.Is(err, gouser.ErrUnsupportedProvider) || errors.Is(err, gouser.ErrInvalidState) {
			errorMsgUserFriendly = "invalid_oauth_request"
		} else if errors.Is(err, gouser.ErrLoginExists) || errors.Is(err, gouser.ErrEmailExists) {
			errorMsgUserFriendly = "user_conflict_oauth"
		}

		// Определяем, куда редиректить ошибку
		finalErrorRedirectURL := errorRedirectTarget // По умолчанию веб-ошибка
		if nativeFinalRedirectURI != "" {
			// Если это нативный, формируем URL на основе его nativeFinalRedirectURI
			parsedNativeErrorURL, parseErr := url.Parse(nativeFinalRedirectURI)
			if parseErr == nil {
				finalErrorRedirectURL = parsedNativeErrorURL.String() // Берем базовый URL
			} else {
				log.Error("Failed to parse nativeFinalRedirectURI for error redirect", "uri", nativeFinalRedirectURI, "error", parseErr)
				// Если не можем распарсить, редиректим на стандартную веб-страницу ошибки
			}
		}

		parsedFinalErrorURL, _ := url.Parse(finalErrorRedirectURL)
		q := parsedFinalErrorURL.Query()
		q.Set("error", errorMsgUserFriendly)
		q.Set("error_description", errorMsgTechnical)
		q.Set("provider", provider)
		parsedFinalErrorURL.RawQuery = q.Encode()
		http.Redirect(w, r, parsedFinalErrorURL.String(), http.StatusTemporaryRedirect)
		return
	}

	// Успешная обработка коллбэка, теперь решаем, как вернуть токены
	if nativeFinalRedirectURI != "" {
		// Это нативный клиент: передаем токены нашего приложения в query-параметрах
		log.Info("OAuth successful for NATIVE client, preparing redirect with tokens in URL", "redirect_to", nativeFinalRedirectURI)

		targetURL, parseErr := url.Parse(nativeFinalRedirectURI)
		if parseErr != nil {
			log.Error("Failed to parse native_final_redirect_uri for success redirect", "uri", nativeFinalRedirectURI, "error", parseErr)
			// Если не можем распарсить, редиректим на стандартную веб-страницу ошибки (хотя это странный сценарий)
			http.Redirect(w, r, errorRedirectTarget+"?error=internal_redirect_parse_error", http.StatusTemporaryRedirect)
			return
		}

		q := targetURL.Query()
		q.Set("access_token", appAccessToken)
		q.Set("refresh_token", appRefreshToken) // Передаем refresh_token нашего приложения
		q.Set("provider", provider)
		if isNewUser {
			q.Set("new_user", "true")
		}
		targetURL.RawQuery = q.Encode()

		log.Info("Redirecting to NATIVE client's landing page with tokens in URL", "final_url", targetURL.String())
		http.Redirect(w, r, targetURL.String(), http.StatusTemporaryRedirect)
	} else {
		// Это веб-клиент: устанавливаем httpOnly refresh_token cookie и редиректим на FrontendRedirectSuccessURL
		log.Info("OAuth successful for WEB client, setting httpOnly refresh_token cookie and redirecting to frontend.")
		cookieDomain := "todo-vd2m.onrender.com" // ХАРДКОД
		isSecure := true                         // ХАРДКОД

		cookie := http.Cookie{
			Name:     "refresh_token",
			Value:    appRefreshToken,
			Expires:  time.Now().Add(30 * 24 * time.Hour), // 30 дней
			HttpOnly: true,
			Path:     "/",
			Domain:   cookieDomain,
			Secure:   isSecure,
			SameSite: http.SameSiteNoneMode,
		}

		// ЛОГИРУЕМ ВСЁ, ЧТО МОЖНО
		log.Info("DEBUG: Preparing to set cookie with HARDCODED values",
			slog.String("cookie_name", cookie.Name),
			slog.String("cookie_value_prefix", appRefreshToken[:10]+"..."), // Не логируем весь токен
			slog.String("cookie_domain", cookie.Domain),
			slog.Bool("cookie_secure", cookie.Secure),
			slog.String("cookie_samesite", "None"),
			slog.String("cookie_path", cookie.Path),
			slog.String("cookie_expires", cookie.Expires.String()),
		)

		http.SetCookie(w, &cookie)
		log.Info("DEBUG: SetCookie header has been written to the response writer.")
		// ==========================================================

		successRedirectURL, _ := url.Parse(c.oauthCfg.FrontendRedirectSuccessURL)
		q := successRedirectURL.Query()
		q.Set("provider", provider)
		q.Set("debug_ts", time.Now().Format(time.RFC3339Nano)) // Добавим метку времени для отладки
		successRedirectURL.RawQuery = q.Encode()

		log.Info("Redirecting to WEB client's success page", "final_url", successRedirectURL.String())

		// ВАЖНО: Убедимся, что ничего больше не пишется в writer после редиректа.
		http.Redirect(w, r, successRedirectURL.String(), http.StatusTemporaryRedirect)
	}
}
