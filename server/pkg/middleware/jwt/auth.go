package jwt

import (
	"context"
	"errors"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	"server/pkg/lib/jwt"
	resp "server/pkg/lib/response"
	"strings" // Добавляем импорт strings
)

func NewUserAuth(log *slog.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		log = log.With(
			slog.String("op", "middlewareAuth"),
		)

		log.Info("auth middleware enabled")

		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var tokenStr string
			var err error

			// 1. Попытка получить токен из заголовка Authorization (стандартный способ)
			tokenStr, err = jwt.ExtractJWTFromHeader(r)

			// 2. Если токен не найден в заголовке, и это WebSocket запрос, ищем в query-параметрах
			isWebSocketUpgrade := r.Header.Get("Upgrade") == "websocket" && strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade")
			if errors.Is(err, jwt.ErrNoAccessToken) && isWebSocketUpgrade {
				log.Debug("No Authorization header found, checking query params for WebSocket upgrade request")
				tokenStr = r.URL.Query().Get("token")
				if tokenStr != "" {
					err = nil // Сбрасываем ошибку ErrNoAccessToken, так как токен найден
				}
			}

			// 3. Если после всех проверок токен пуст или была другая ошибка, выходим
			if err != nil || tokenStr == "" {
				if err == nil {
					err = jwt.ErrNoAccessToken // Устанавливаем ошибку, если токен просто пустой
				}
				handleAuthError(w, r, log, err)
				return
			}

			// 4. Валидация токена
			claims, err := jwt.ValidateJWT(tokenStr)
			if err != nil {
				handleAuthError(w, r, log, err)
				return
			}

			// 5. Успешно! Добавляем userID в контекст и передаем дальше.
			uintUserId := claims.UserID
			ctx := context.WithValue(r.Context(), "userId", uintUserId)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// NewAdminAuth и handleAuthError остаются без изменений
func NewAdminAuth(log *slog.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		log = log.With(
			slog.String("op", "middlewareAdminAuth"),
		)

		log.Info("admin auth middleware enabled")

		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tokenStr, err := jwt.ExtractJWTFromHeader(r)
			if err != nil {
				handleAuthError(w, r, log, err)
				return
			}

			claims, err := jwt.ValidateJWT(tokenStr)
			if err != nil {
				handleAuthError(w, r, log, err)
				return
			}

			if !claims.IsAdmin {
				log.Info("user is not admin")
				w.WriteHeader(http.StatusForbidden)
				render.JSON(w, r, resp.Error("access forbidden"))
				return
			}

			uintUserId := claims.UserID
			ctx := context.WithValue(r.Context(), "userId", uintUserId)
			ctx = context.WithValue(ctx, "isAdmin", true)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func handleAuthError(w http.ResponseWriter, r *http.Request, log *slog.Logger, err error) {
	log.Error("auth error", slog.String("error", err.Error()))
	if errors.Is(err, jwt.ErrNoAccessToken) {
		w.WriteHeader(http.StatusUnauthorized)
		render.JSON(w, r, resp.Error(err.Error()))
	} else {
		w.WriteHeader(http.StatusUnauthorized)
		render.JSON(w, r, resp.Error(err.Error()))
	}
}
