package usecase

import (
	"context"
	"errors"
	"github.com/go-chi/render"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"golang.org/x/oauth2/yandex"
	"log/slog"
	"net/http"
	"os"
	u "server/internal/modules/user"
	"server/internal/modules/user/auth"
	"server/pkg/lib/jwt"
	"strconv"
)

type AuthUseCase struct {
	log *slog.Logger
	rp  auth.Repo
}

func NewAuthUseCase(log *slog.Logger, rp auth.Repo) *AuthUseCase {
	return &AuthUseCase{
		log: log,
		rp:  rp,
	}
}

func (uc *AuthUseCase) SignUp(email string, login string, password string) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return u.ErrInternal
	}
	hashPassword := string(hashedPassword)

	user := &auth.UserAuth{
		Email:          email,
		Login:          login,
		HashedPassword: &hashPassword,
	}

	_, err = uc.rp.CreateUser(user)
	return err
}

func (uc *AuthUseCase) SignIn(email string, login string, password string) (string, string, error) {
	var user *auth.UserAuth
	var err error
	if email != "" {
		user, err = uc.rp.GetUserByEmail(email)
		if err != nil {
			return "", "", err
		}
	} else {
		user, err = uc.rp.GetUserByLogin(login)
		if err != nil {
			return "", "", err
		}
	}

	if user.HashedPassword == nil {
		return "", "", u.ErrUserAuthWithOauth2
	}

	if err := bcrypt.CompareHashAndPassword([]byte(*user.HashedPassword), []byte(password)); err != nil {
		return "", "", u.ErrUserNotFound
	}

	if !user.VerifiedEmail {
		return "", "", u.ErrEmailNotConfirmed
	}

	accessToken, err := jwt.GenerateAccessToken(user.UserId, user.IsAdmin)
	if err != nil {
		return "", "", err
	}

	refreshToken, err := jwt.GenerateRefreshToken(user.UserId, user.IsAdmin)
	if err != nil {
		return "", "", err
	}

	return accessToken, refreshToken, nil
}

func (uc *AuthUseCase) RefreshToken(r *http.Request) (string, error) {
	refreshToken, err := r.Cookie("refresh_token")
	if err != nil {
		return "", u.ErrNoRefreshToken
	}

	claims, err := jwt.ValidateJWT(refreshToken.Value)
	if err != nil {
		return "", err
	}

	userId, err := strconv.ParseUint(claims.Subject, 10, 0)
	if err != nil {
		return "", u.ErrInternal
	}

	user, err := uc.rp.GetUserById(uint(userId))
	if err != nil {
		return "", err
	}

	accessToken, err := jwt.GenerateAccessToken(user.UserId, user.IsAdmin)
	if err != nil {
		return "", err
	}

	return accessToken, nil
}

var oauthConfigs = map[string]*oauth2.Config{
	"google": &oauth2.Config{
		ClientID:     os.Getenv("GOOGLE_KEY"),
		ClientSecret: os.Getenv("GOOGLE_SECRET"),
		RedirectURL:  "https://film-catalog-8re5.onrender.com/v1/auth/google/callback",
		Scopes:       []string{"https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"},
		Endpoint:     google.Endpoint,
	},
	"yandex": &oauth2.Config{
		ClientID:     os.Getenv("YANDEX_KEY"),
		ClientSecret: os.Getenv("YANDEX_SECRET"),
		RedirectURL:  "https://film-catalog-8re5.onrender.com/v1/auth/yandex/callback",
		Endpoint:     yandex.Endpoint,
	},
}

type GoogleUserData struct {
	Email     string  `json:"email"`
	Login     string  `json:"given_name"`
	AvatarUrl *string `json:"picture"`
}

type YandexUserData struct {
	Email string `json:"default_email"`
	Login string `json:"first_name"`
}

func (uc *AuthUseCase) GetAuthURL(provider string) (string, error) {
	config, ok := oauthConfigs[provider]
	if !ok {
		return "", u.ErrUnsupportedProvider
	}

	state := uuid.NewString()
	err := uc.rp.SaveStateCode(state)
	if err != nil {
		return "", err
	}

	return config.AuthCodeURL(state, oauth2.AccessTypeOnline), nil
}

func (uc *AuthUseCase) Callback(provider, state, code string) (bool, string, string, error) {
	config, ok := oauthConfigs[provider]
	if !ok {
		return false, "", "", u.ErrUnsupportedProvider
	}

	isValidState, err := uc.rp.VerifyStateCode(state)
	if err != nil || !isValidState {
		return false, "", "", err
	}

	token, err := config.Exchange(context.Background(), code)
	if err != nil {
		return false, "", "", err
	}

	client := config.Client(context.Background(), token)
	user, err := fetchUserInfo(client, provider)
	if err != nil {
		return false, "", "", err
	}

	existingUser, err := uc.rp.GetUserByEmail(user.Email)
	if errors.Is(err, u.ErrUserNotFound) {
		userId, err := uc.rp.CreateUser(user)
		if err != nil {
			if errors.Is(err, u.ErrLoginExists) {
				user.Login = ""
				userId, err = uc.rp.CreateUser(user)
				if err != nil {
					return false, "", "", err
				}
			} else {
				return false, "", "", err
			}
		}

		accessToken, err := jwt.GenerateAccessToken(userId, user.IsAdmin)
		if err != nil {
			return false, "", "", err
		}

		refreshToken, err := jwt.GenerateRefreshToken(userId, user.IsAdmin)
		if err != nil {
			return false, "", "", err
		}

		return false, accessToken, refreshToken, nil
	} else if err != nil {
		return false, "", "", err
	}

	accessToken, err := jwt.GenerateAccessToken(existingUser.UserId, existingUser.IsAdmin)
	if err != nil {
		return false, "", "", err
	}

	refreshToken, err := jwt.GenerateRefreshToken(existingUser.UserId, existingUser.IsAdmin)
	if err != nil {
		return false, "", "", err
	}
	return true, accessToken, refreshToken, nil
}

func fetchUserInfo(client *http.Client, provider string) (*auth.UserAuth, error) {
	var url string
	switch provider {
	case "google":
		url = "https://www.googleapis.com/oauth2/v3/userinfo"
	case "yandex":
		url = "https://login.yandex.ru/info?format=json"
	default:
		return nil, u.ErrUnsupportedProvider
	}

	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	switch provider {
	case "google":
		var user GoogleUserData
		if err := render.DecodeJSON(resp.Body, &user); err != nil {
			return nil, err
		}
		return GoogleToUser(&user), nil
	case "yandex":
		var user YandexUserData
		if err := render.DecodeJSON(resp.Body, &user); err != nil {
			return nil, err
		}
		return YandexToUser(&user), nil
	default:
		return nil, u.ErrUnsupportedProvider
	}
}

func GoogleToUser(googleData *GoogleUserData) *auth.UserAuth {
	return &auth.UserAuth{
		Email:         googleData.Email,
		Login:         googleData.Login,
		AvatarUrl:     googleData.AvatarUrl,
		VerifiedEmail: true,
	}
}

func YandexToUser(yandexData *YandexUserData) *auth.UserAuth {
	return &auth.UserAuth{
		Email:         yandexData.Email,
		Login:         yandexData.Login,
		VerifiedEmail: true,
	}
}
