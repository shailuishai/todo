package jwt

import (
	"context"
	"errors"
	"github.com/go-chi/render"
	"log/slog"
	"net/http"
	"server/pkg/lib/jwt"
	resp "server/pkg/lib/response"
)

func NewUserAuth(log *slog.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		log = log.With(
			slog.String("op", "middlewareAuth"),
		)

		log.Info("auth middleware enabled")

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

			// Используем UserID вместо Subject
			uintUserId := claims.UserID
			ctx := context.WithValue(r.Context(), "userId", uintUserId)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

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

			// Проверяем, что пользователь является администратором
			if !claims.IsAdmin {
				log.Info("user is not admin")
				w.WriteHeader(http.StatusForbidden)
				render.JSON(w, r, resp.Error("access forbidden"))
				return
			}

			// Используем UserID вместо Subject
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
