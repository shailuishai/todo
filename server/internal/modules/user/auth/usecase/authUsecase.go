// internal/modules/user/auth/usecase/authUsecase.go
package usecase

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"golang.org/x/oauth2/yandex"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"os"
	"server/config"
	gouser "server/internal/modules/user"
	"server/internal/modules/user/auth"
	"server/internal/modules/user/profile"
	appjwt "server/pkg/lib/jwt"
	"strings"
	"time"
)

// ... (структуры и NewAuthUseCase без изменений) ...
type OAuthProviderConfig struct {
	Google *oauth2.Config
	Yandex *oauth2.Config
}

type AuthUseCase struct {
	log          *slog.Logger
	repo         auth.Repo
	oauthConfigs OAuthProviderConfig
	profileUC    profile.UseCase
	jwtConfig    config.JWTConfig
}

func NewAuthUseCase(log *slog.Logger, repo auth.Repo, appCfg *config.Config, profileUC profile.UseCase) *AuthUseCase {
	googleKey := os.Getenv("GOOGLE_KEY")
	googleSecret := os.Getenv("GOOGLE_SECRET")
	yandexKey := os.Getenv("YANDEX_KEY")
	yandexSecret := os.Getenv("YANDEX_SECRET")

	if googleKey == "" || googleSecret == "" {
		log.Warn("Google OAuth credentials (GOOGLE_KEY or GOOGLE_SECRET) are not set. Google OAuth will be unavailable.")
	}
	if yandexKey == "" || yandexSecret == "" {
		log.Warn("Yandex OAuth credentials (YANDEX_KEY or YANDEX_SECRET) are not set. Yandex OAuth will be unavailable.")
	}

	googleCfg := &oauth2.Config{
		ClientID:     googleKey,
		ClientSecret: googleSecret,
		RedirectURL:  appCfg.OAuthConfig.GoogleRedirectURL, // Для ВЕБА этот URL теперь указывает на фронтенд.
		Scopes:       []string{"https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"},
		Endpoint:     google.Endpoint,
	}
	yandexCfg := &oauth2.Config{
		ClientID:     yandexKey,
		ClientSecret: yandexSecret,
		RedirectURL:  appCfg.OAuthConfig.YandexRedirectURL, // Для ВЕБА этот URL теперь указывает на фронтенд.
		Scopes:       []string{"login:email", "login:info", "login:avatar"},
		Endpoint:     yandex.Endpoint,
	}

	return &AuthUseCase{
		log:          log,
		repo:         repo,
		oauthConfigs: OAuthProviderConfig{Google: googleCfg, Yandex: yandexCfg},
		profileUC:    profileUC,
		jwtConfig:    appCfg.JWTConfig,
	}
}

// ... (SignUp, SignIn, RefreshToken, RefreshTokenNative без изменений) ...
func (uc *AuthUseCase) SignUp(email string, login string, password string) error {
	op := "AuthUseCase.SignUp"
	log := uc.log.With(slog.String("op", op), slog.String("email", email), slog.String("login", login))

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Error("failed to hash password", "error", err)
		return gouser.ErrInternal
	}
	hashStr := string(hashedPassword)

	userAuthDTO := &auth.UserAuth{
		Email:         email,
		Login:         login,
		PasswordHash:  &hashStr,
		VerifiedEmail: false, // По умолчанию false, должен подтвердить
		IsAdmin:       false,
	}

	_, err = uc.repo.CreateUser(userAuthDTO)
	if err != nil {
		log.Warn("failed to create user in repo", "error", err)
		return err // Возвращаем ошибку из репозитория (ErrEmailExists, ErrLoginExists)
	}
	log.Info("user signed up successfully")
	return nil
}

func (uc *AuthUseCase) SignIn(email string, login string, password string) (string, string, error) {
	op := "AuthUseCase.SignIn"
	log := uc.log.With(slog.String("op", op))

	var userAuthDTO *auth.UserAuth
	var err error

	if email != "" {
		log = log.With(slog.String("email", email))
		userAuthDTO, err = uc.repo.GetUserByEmail(email)
	} else if login != "" {
		log = log.With(slog.String("login", login))
		userAuthDTO, err = uc.repo.GetUserByLogin(login)
	} else {
		log.Warn("neither email nor login provided for sign in")
		return "", "", gouser.ErrBadRequest
	}

	if err != nil {
		log.Warn("failed to get user from repo", "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			return "", "", gouser.ErrUserNotFound // Используем общую ошибку "неверные данные"
		}
		return "", "", err // Другие ошибки репозитория
	}

	if userAuthDTO.PasswordHash == nil {
		log.Warn("user attempted to sign in with password but was registered via OAuth", "userID", userAuthDTO.UserId)
		return "", "", gouser.ErrUserAuthWithOauth2
	}

	if err := bcrypt.CompareHashAndPassword([]byte(*userAuthDTO.PasswordHash), []byte(password)); err != nil {
		log.Warn("password mismatch for user", "userID", userAuthDTO.UserId)
		return "", "", gouser.ErrUserNotFound // Используем общую ошибку "неверные данные"
	}

	if !userAuthDTO.VerifiedEmail {
		log.Warn("user email not verified", "userID", userAuthDTO.UserId)
		return "", "", gouser.ErrEmailNotConfirmed
	}

	accessToken, err := appjwt.GenerateAccessToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate access token", "userID", userAuthDTO.UserId, "error", err)
		return "", "", gouser.ErrInternal
	}

	refreshToken, err := appjwt.GenerateRefreshToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate refresh token", "userID", userAuthDTO.UserId, "error", err)
		return "", "", gouser.ErrInternal
	}

	log.Info("user signed in successfully", "userID", userAuthDTO.UserId)
	return accessToken, refreshToken, nil
}

// RefreshToken для веба (использует cookie)
func (uc *AuthUseCase) RefreshToken(r *http.Request) (string, error) {
	op := "AuthUseCase.RefreshToken (Web)"
	log := uc.log.With(slog.String("op", op))

	cookie, err := r.Cookie("refresh_token")
	if err != nil {
		log.Warn("refresh token cookie not found")
		return "", gouser.ErrNoRefreshToken
	}
	refreshTokenValue := cookie.Value

	claims, err := appjwt.ValidateJWT(refreshTokenValue)
	if err != nil {
		log.Warn("invalid or expired refresh token from cookie", "error", err)
		return "", err // ValidateJWT возвращает ErrInvalidToken или ErrExpiredToken
	}

	userID := claims.UserID
	if userID == 0 {
		log.Error("UserID is zero in refresh token claims from cookie")
		return "", gouser.ErrInvalidToken
	}

	userAuthDTO, err := uc.repo.GetUserById(userID)
	if err != nil {
		log.Warn("user not found for refresh token", "userID", userID, "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			return "", gouser.ErrUserNotFound
		}
		return "", gouser.ErrInternal
	}

	newAccessToken, err := appjwt.GenerateAccessToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate new access token", "userID", userID, "error", err)
		return "", gouser.ErrInternal
	}

	log.Info("access token refreshed successfully via cookie", "userID", userID)
	return newAccessToken, nil
}

// RefreshTokenNative для нативных клиентов (использует токен из тела запроса)
func (uc *AuthUseCase) RefreshTokenNative(tokenString string) (newAccessToken string, newRefreshToken string, err error) {
	op := "AuthUseCase.RefreshTokenNative"
	log := uc.log.With(slog.String("op", op))

	if tokenString == "" {
		log.Warn("empty refresh token string provided for native refresh")
		return "", "", gouser.ErrNoRefreshToken
	}

	claims, err := appjwt.ValidateJWT(tokenString)
	if err != nil {
		log.Warn("invalid or expired refresh token from request body", "error", err)
		return "", "", err
	}

	userID := claims.UserID
	if userID == 0 {
		log.Error("UserID is zero in native refresh token claims")
		return "", "", gouser.ErrInvalidToken
	}

	userAuthDTO, err := uc.repo.GetUserById(userID)
	if err != nil {
		log.Warn("user not found for native refresh token", "userID", userID, "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			return "", "", gouser.ErrUserNotFound
		}
		return "", "", gouser.ErrInternal
	}

	generatedAccessToken, err := appjwt.GenerateAccessToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate new access token for native", "userID", userID, "error", err)
		return "", "", gouser.ErrInternal
	}

	generatedRefreshToken, err := appjwt.GenerateRefreshToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate new refresh token for native", "userID", userID, "error", err)
		return "", "", gouser.ErrInternal
	}

	log.Info("tokens refreshed successfully for native client", "userID", userID)
	return generatedAccessToken, generatedRefreshToken, nil
}

// GetAuthURL - без изменений, он уже принимает redirectURI
func (uc *AuthUseCase) GetAuthURL(provider, clientRedirectURI string) (url string, state string, err error) {
	op := "AuthUseCase.GetAuthURL"
	log := uc.log.With(slog.String("op", op), slog.String("provider", provider))

	var oauthCfg *oauth2.Config
	switch provider {
	case "google":
		oauthCfg = uc.oauthConfigs.Google
		if oauthCfg.ClientID == "" {
			return "", "", gouser.ErrAuthProviderNotConfigured
		}
	case "yandex":
		oauthCfg = uc.oauthConfigs.Yandex
		if oauthCfg.ClientID == "" {
			return "", "", gouser.ErrAuthProviderNotConfigured
		}
	default:
		return "", "", gouser.ErrUnsupportedProvider
	}

	cfgCopy := *oauthCfg

	if clientRedirectURI != "" {
		cfgCopy.RedirectURL = clientRedirectURI
		log.Info("Using client-provided redirect URI for web flow", "uri", clientRedirectURI)
	} else {
		log.Info("Using default redirect URI from config for native flow", "uri", cfgCopy.RedirectURL)
	}

	stateUUID := uuid.NewString()
	if err := uc.repo.SaveStateCode(stateUUID, provider); err != nil {
		log.Error("failed to save oauth state to repo", "error", err)
		return "", "", gouser.ErrInternal
	}

	authURL := cfgCopy.AuthCodeURL(stateUUID, oauth2.AccessTypeOnline)
	log.Info("OAuth URL generated", "url", authURL, "state", stateUUID, "redirect_uri", cfgCopy.RedirectURL)
	return authURL, stateUUID, nil
}

// <<< ИЗМЕНЕНИЕ: OAuthExchange теперь принимает redirectURI и передает его дальше >>>
func (uc *AuthUseCase) OAuthExchange(provider, state, code, redirectURI string) (accessToken string, refreshToken string, err error) {
	op := "AuthUseCase.OAuthExchange"
	log := uc.log.With(slog.String("op", op), slog.String("provider", provider))

	// Передаем redirectURI в Callback
	_, _, appAccessToken, appRefreshToken, err := uc.Callback(provider, state, code, redirectURI)
	if err != nil {
		log.Error("underlying callback logic failed during exchange", "error", err)
		return "", "", err
	}

	log.Info("OAuth exchange successful")
	return appAccessToken, appRefreshToken, nil
}

// <<< ИЗМЕНЕНИЕ: Callback теперь принимает redirectURI для правильной работы Exchange >>>
func (uc *AuthUseCase) Callback(provider, state, code, redirectURI string) (userID uint, isNewUser bool, accessToken string, refreshToken string, err error) {
	op := "AuthUseCase.Callback"
	log := uc.log.With(slog.String("op", op), slog.String("provider", provider), slog.String("state_from_request", state))

	var oauthCfg *oauth2.Config
	var userInfoURL string

	savedDataProvider, isValidState, err := uc.repo.VerifyStateCode(state)
	if err != nil {
		log.Error("failed to verify oauth state from repo", "state", state, "error", err)
		return 0, false, "", "", gouser.ErrInternal
	}
	if !isValidState || savedDataProvider != provider {
		log.Warn("invalid oauth state or provider mismatch", "state", state, "expected_provider", savedDataProvider, "actual_provider", provider)
		return 0, false, "", "", gouser.ErrInvalidState
	}
	log.Info("OAuth state verified successfully")

	switch provider {
	case "google":
		oauthCfg = uc.oauthConfigs.Google
		if oauthCfg.ClientID == "" {
			return 0, false, "", "", gouser.ErrAuthProviderNotConfigured
		}
		userInfoURL = "https://www.googleapis.com/oauth2/v3/userinfo"
	case "yandex":
		oauthCfg = uc.oauthConfigs.Yandex
		if oauthCfg.ClientID == "" {
			return 0, false, "", "", gouser.ErrAuthProviderNotConfigured
		}
		userInfoURL = "https://login.yandex.ru/info?format=json"
	default:
		return 0, false, "", "", gouser.ErrUnsupportedProvider
	}

	// <<< КЛЮЧЕВОЕ ИЗМЕНЕНИЕ >>>
	// Создаем копию конфига, чтобы установить правильный RedirectURL для этого конкретного вызова
	cfgCopy := *oauthCfg
	if redirectURI != "" {
		// Если URI передан (веб-поток), используем его
		cfgCopy.RedirectURL = redirectURI
	}
	// Если URI не передан (нативный поток), используется cfgCopy.RedirectURL изначального конфига,
	// который должен указывать на бэкенд.

	oauthToken, err := cfgCopy.Exchange(context.Background(), code)
	if err != nil {
		log.Error("failed to exchange oauth code for token", "provider", provider, "redirect_uri_used", cfgCopy.RedirectURL, "error", err)
		return 0, false, "", "", fmt.Errorf("oauth exchange failed: %w", err)
	}
	log.Info("OAuth code exchanged for token successfully", slog.Bool("refresh_token_exists_from_provider", oauthToken.RefreshToken != ""))

	// ... (остальной код метода Callback без изменений) ...
	if oauthToken.AccessToken == "" {
		log.Error("exchanged oauth token but AccessToken from provider is empty", "provider", provider)
		return 0, false, "", "", errors.New("oauth provider returned empty access token")
	}

	oauthUserDTO, err := uc.fetchOAuthUserInfo(provider, userInfoURL, oauthToken)
	if err != nil {
		return 0, false, "", "", err
	}
	oauthUserDTO.VerifiedEmail = true

	existingUser, err := uc.repo.GetUserByEmail(oauthUserDTO.Email)
	wasNewUser := false

	if errors.Is(err, gouser.ErrUserNotFound) {
		log.Info("user not found by email, creating new user from oauth data", "email", oauthUserDTO.Email)
		wasNewUser = true
		newUserID, createErr := uc.repo.CreateUser(oauthUserDTO)
		if createErr != nil {
			if errors.Is(createErr, gouser.ErrLoginExists) {
				originalLoginAttempt := oauthUserDTO.Login
				oauthUserDTO.Login = fmt.Sprintf("%s_%s", strings.Split(oauthUserDTO.Email, "@")[0], uuid.NewString()[:4])
				log.Warn("login from oauth provider already exists, attempting to create user with generated login", "original_login", originalLoginAttempt, "new_login_attempt", oauthUserDTO.Login)
				newUserID, createErr = uc.repo.CreateUser(oauthUserDTO)
			}
			if createErr != nil {
				log.Error("failed to create new user from oauth data after attempting to resolve conflict", "error", createErr)
				return 0, false, "", "", createErr
			}
		}
		oauthUserDTO.UserId = newUserID
	} else if err != nil {
		log.Error("error checking for existing user by email", "email", oauthUserDTO.Email, "error", err)
		return 0, false, "", "", err
	} else {
		log.Info("existing user found by email from oauth data", "userID", existingUser.UserId)
		oauthUserDTO = existingUser
	}

	appAccessToken, err := appjwt.GenerateAccessToken(oauthUserDTO.UserId, oauthUserDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate app access token for oauth user", "userID", oauthUserDTO.UserId, "error", err)
		return 0, false, "", "", gouser.ErrInternal
	}
	appRefreshToken, err := appjwt.GenerateRefreshToken(oauthUserDTO.UserId, oauthUserDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate app refresh token for oauth user", "userID", oauthUserDTO.UserId, "error", err)
		return 0, false, "", "", gouser.ErrInternal
	}

	log.Info("oauth callback processed successfully, app tokens generated", "userID", oauthUserDTO.UserId, "isNewUser", wasNewUser)
	return oauthUserDTO.UserId, wasNewUser, appAccessToken, appRefreshToken, nil
}

// ... (остальные методы без изменений) ...
func (uc *AuthUseCase) fetchOAuthUserInfo(provider, userInfoURL string, token *oauth2.Token) (*auth.UserAuth, error) {
	log := uc.log.With(slog.String("op", "AuthUseCase.fetchOAuthUserInfo"), slog.String("provider", provider))

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", userInfoURL, nil)
	if err != nil {
		log.Error("failed to create request for user info", "error", err)
		return nil, fmt.Errorf("create user info request failed: %w", err)
	}

	if provider == "yandex" {
		req.Header.Set("Authorization", "OAuth "+token.AccessToken)
	} else { // Google и другие обычно Bearer
		req.Header.Set("Authorization", "Bearer "+token.AccessToken)
	}
	req.Header.Set("User-Agent", "ToDoAppServer/1.0")

	dumpReq, _ := httputil.DumpRequestOut(req, true)
	log.Debug("Sending OAuth UserInfo Request", slog.String("request_dump", string(dumpReq)))

	resp, err := client.Do(req)
	if err != nil {
		log.Error("failed to execute request to oauth provider user info endpoint", "error", err)
		return nil, fmt.Errorf("fetch user info http client Do failed: %w", err)
	}
	defer resp.Body.Close()

	dumpResp, _ := httputil.DumpResponse(resp, true)
	log.Debug("Received OAuth UserInfo Response", slog.String("response_dump", string(dumpResp)))

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		log.Error("oauth provider returned non-200 status for user info", "status", resp.Status, "body", string(bodyBytes))
		return nil, fmt.Errorf("oauth provider user info error: %s, body: %s", resp.Status, string(bodyBytes))
	}
	return parseOAuthUserInfo(provider, resp.Body, log)
}

func parseOAuthUserInfo(provider string, body io.Reader, log *slog.Logger) (*auth.UserAuth, error) {
	user := &auth.UserAuth{}
	decoder := json.NewDecoder(body)
	log = log.With(slog.String("op", "parseOAuthUserInfo"), slog.String("provider", provider))

	switch provider {
	case "google":
		var googleData struct {
			Sub           string `json:"sub"`
			Email         string `json:"email"`
			GivenName     string `json:"given_name"`
			FamilyName    string `json:"family_name"`
			Picture       string `json:"picture"`
			EmailVerified bool   `json:"email_verified"`
			Name          string `json:"name"`
		}
		if err := decoder.Decode(&googleData); err != nil {
			log.Error("failed to decode google user info", "error", err)
			return nil, fmt.Errorf("decode google user info: %w", err)
		}
		user.Email = googleData.Email
		user.Login = googleData.GivenName
		if user.Login == "" {
			if googleData.Name != "" {
				user.Login = strings.Fields(googleData.Name)[0]
			} else {
				user.Login = strings.Split(googleData.Email, "@")[0]
			}
		}
		user.Login = strings.Map(func(r rune) rune {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
				return r
			}
			return -1
		}, user.Login)
		if len(user.Login) > 50 {
			user.Login = user.Login[:50]
		}
		if user.Login == "" {
			user.Login = "guser_" + googleData.Sub[:8]
		}

		user.VerifiedEmail = googleData.EmailVerified
		log.Info("Parsed Google user info", "email", user.Email, "login", user.Login, "verified", user.VerifiedEmail)
	case "yandex":
		var yandexData struct {
			DefaultEmail    string `json:"default_email"`
			Login           string `json:"login"`
			FirstName       string `json:"first_name"`
			DefaultAvatarID string `json:"default_avatar_id"`
			ID              string `json:"id"`
		}
		if err := decoder.Decode(&yandexData); err != nil {
			log.Error("failed to decode yandex user info", "error", err)
			return nil, fmt.Errorf("decode yandex user info: %w", err)
		}
		user.Email = yandexData.DefaultEmail
		user.Login = yandexData.Login
		if user.Login == "" {
			if yandexData.FirstName != "" {
				user.Login = yandexData.FirstName
			} else {
				user.Login = strings.Split(yandexData.DefaultEmail, "@")[0]
			}
		}
		user.Login = strings.Map(func(r rune) rune {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
				return r
			}
			return -1
		}, user.Login)
		if len(user.Login) > 50 {
			user.Login = user.Login[:50]
		}
		if user.Login == "" {
			user.Login = "yauser_" + yandexData.ID[:8]
		}

		user.VerifiedEmail = true
		log.Info("Parsed Yandex user info", "email", user.Email, "login", user.Login)
	default:
		return nil, gouser.ErrUnsupportedProvider
	}
	return user, nil
}

func (uc *AuthUseCase) GetUserProfileAfterOAuth(userID uint) (*profile.UserProfileResponse, error) {
	op := "AuthUseCase.GetUserProfileAfterOAuth"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	if uc.profileUC == nil {
		log.Error("ProfileUseCase is not initialized in AuthUseCase")
		return nil, errors.New("profile service unavailable in auth usecase")
	}

	userProfile, err := uc.profileUC.GetUser(userID)
	if err != nil {
		log.Error("Failed to get user profile via ProfileUseCase after OAuth", "error", err)
		return nil, err
	}
	return userProfile, nil
}
