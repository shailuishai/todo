package auth

import (
	"net/http"
)

type UserAuth struct {
	UserId         uint    `json:"user_id"`
	HashedPassword *string `json:"hashed_password"`
	Login          string  `json:"login"`
	Email          string  `json:"email"`
	IsAdmin        bool    `json:"is_admin"`
	VerifiedEmail  bool    `json:"version"`
	AvatarUrl      *string `json:"avatar_url"`
}

type Controller interface {
	SignUp(w http.ResponseWriter, r *http.Request)
	SignIn(w http.ResponseWriter, r *http.Request)
	Oauth(w http.ResponseWriter, r *http.Request)
	OauthCallback(w http.ResponseWriter, r *http.Request)
	RefreshToken(w http.ResponseWriter, r *http.Request)
	Logout(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	SignUp(email string, login string, password string) error
	SignIn(email string, login string, password string) (string, string, error)
	GetAuthURL(provider string) (string, error)
	Callback(provider, state, code string) (bool, string, string, error)
	RefreshToken(r *http.Request) (string, error)
}

type Repo interface {
	CreateUser(user *UserAuth) (uint, error)
	GetUserByEmail(email string) (*UserAuth, error)
	GetUserByLogin(login string) (*UserAuth, error)
	GetUserById(id uint) (*UserAuth, error)
	SaveStateCode(state string) error
	VerifyStateCode(state string) (bool, error)
}
