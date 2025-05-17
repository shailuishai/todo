package controller

import (
	"github.com/go-chi/render"
	"net/http"
	resp "server/pkg/lib/response"
	"time"
)

// Logout logs out the user by invalidating the refresh token cookie.
//
// @Summary      Logout user
// @Description  Logs out the user by clearing the refresh token cookie. If the cookie is not found, returns success without any action.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Success      200  {object}  response.Response    "User successfully logged out or no refresh token found"
// @Failure      204  {object}  response.Response    "No content, token was successfully invalidated"
// @Router       /auth/logout [post]
func (c *AuthController) Logout(w http.ResponseWriter, r *http.Request) {
	_, err := r.Cookie("refresh_token")
	if err != nil {
		w.WriteHeader(http.StatusOK)
		render.JSON(w, r, resp.OK())
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    "",
		Expires:  time.Now().Add(-time.Hour),
		HttpOnly: true,
		Path:     "/",
	})

	w.WriteHeader(http.StatusNoContent)
	render.JSON(w, r, resp.OK())
	return
}
