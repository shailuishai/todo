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
	"server/internal/modules/user/profile" // <<< Убедись, что этот импорт корректен
	appjwt "server/pkg/lib/jwt"            // Переименовал jwt в appjwt, чтобы не конфликтовать с github.com/golang-jwt/jwt
	"strings"
	"time"
)

type OAuthProviderConfig struct {
	Google *oauth2.Config
	Yandex *oauth2.Config
}

type AuthUseCase struct {
	log          *slog.Logger
	repo         auth.Repo
	oauthConfigs OAuthProviderConfig
	profileUC    profile.UseCase  // Зависимость от ProfileUseCase
	jwtConfig    config.JWTConfig // <<< Добавим JWTConfig для генерации токенов
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
		RedirectURL:  appCfg.OAuthConfig.GoogleRedirectURL, // Этот redirect_uri для бэкенда
		Scopes:       []string{"https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"},
		Endpoint:     google.Endpoint,
	}
	yandexCfg := &oauth2.Config{
		ClientID:     yandexKey,
		ClientSecret: yandexSecret,
		RedirectURL:  appCfg.OAuthConfig.YandexRedirectURL, // Этот redirect_uri для бэкенда
		Scopes:       []string{"login:email", "login:info", "login:avatar"},
		Endpoint:     yandex.Endpoint,
	}

	return &AuthUseCase{
		log:          log,
		repo:         repo,
		oauthConfigs: OAuthProviderConfig{Google: googleCfg, Yandex: yandexCfg},
		profileUC:    profileUC,
		jwtConfig:    appCfg.JWTConfig, // <<< Сохраняем JWTConfig
	}
}

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

	// Проверяем, не отозван ли токен (если есть такая логика, например, черный список)
	// ...

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
		// ValidateJWT вернет ErrInvalidToken или ErrExpiredToken
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

	// Генерируем новый Access Token
	generatedAccessToken, err := appjwt.GenerateAccessToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate new access token for native", "userID", userID, "error", err)
		return "", "", gouser.ErrInternal
	}

	// Опционально: генерируем новый Refresh Token (для ротации)
	generatedRefreshToken, err := appjwt.GenerateRefreshToken(userAuthDTO.UserId, userAuthDTO.IsAdmin)
	if err != nil {
		log.Error("failed to generate new refresh token for native", "userID", userID, "error", err)
		// Если не удалось сгенерировать новый RT, можно вернуть старый или ошибку.
		// Для простоты вернем ошибку, но можно и вернуть только AT.
		return "", "", gouser.ErrInternal
	}

	log.Info("tokens refreshed successfully for native client", "userID", userID)
	return generatedAccessToken, generatedRefreshToken, nil
}

func (uc *AuthUseCase) GetAuthURL(provider string) (url string, state string, err error) {
	op := "AuthUseCase.GetAuthURL"
	log := uc.log.With(slog.String("op", op), slog.String("provider", provider))

	var oauthCfg *oauth2.Config
	switch provider {
	case "google":
		oauthCfg = uc.oauthConfigs.Google
		if oauthCfg.ClientID == "" {
			log.Error("Google OAuth client ID is not configured.")
			return "", "", gouser.ErrAuthProviderNotConfigured
		}
	case "yandex":
		oauthCfg = uc.oauthConfigs.Yandex
		if oauthCfg.ClientID == "" {
			log.Error("Yandex OAuth client ID is not configured.")
			return "", "", gouser.ErrAuthProviderNotConfigured
		}
	default:
		log.Warn("unsupported oauth provider requested")
		return "", "", gouser.ErrUnsupportedProvider
	}

	stateUUID := uuid.NewString()
	if err := uc.repo.SaveStateCode(stateUUID, provider); err != nil { // Сохраняем provider вместе со state
		log.Error("failed to save oauth state to repo", "error", err)
		return "", "", gouser.ErrInternal
	}

	// Для Yandex иногда нужен параметр `force_confirm=yes`, чтобы всегда показывать страницу подтверждения,
	// если это необходимо для тестов или специфичного UX.
	// opts := []oauth2.AuthCodeOption{}
	// if provider == "yandex" {
	// 	opts = append(opts, oauth2.SetAuthURLParam("force_confirm", "yes"))
	// }
	// authURL := oauthCfg.AuthCodeURL(stateUUID, opts...)
	authURL := oauthCfg.AuthCodeURL(stateUUID, oauth2.AccessTypeOnline) // AccessTypeOnline для Google

	log.Info("OAuth URL generated", "url", authURL, "state", stateUUID)
	return authURL, stateUUID, nil
}

// Callback теперь возвращает и accessToken, и refreshToken нашего приложения
func (uc *AuthUseCase) Callback(provider, state, code string) (userID uint, isNewUser bool, accessToken string, refreshToken string, err error) {
	op := "AuthUseCase.Callback"
	log := uc.log.With(slog.String("op", op), slog.String("provider", provider), slog.String("state_from_request", state))

	var oauthCfg *oauth2.Config
	var userInfoURL string

	// Проверяем state и извлекаем сохраненный provider
	savedDataProvider, isValidState, err := uc.repo.VerifyStateCode(state)
	if err != nil {
		log.Error("failed to verify oauth state from repo", "state", state, "error", err)
		return 0, false, "", "", gouser.ErrInternal
	}
	if !isValidState || savedDataProvider != provider { // Проверяем, что сохраненный провайдер совпадает
		log.Warn("invalid oauth state or provider mismatch", "state", state, "expected_provider", savedDataProvider, "actual_provider", provider)
		return 0, false, "", "", gouser.ErrInvalidState
	}
	log.Info("OAuth state verified successfully")

	switch provider {
	case "google":
		oauthCfg = uc.oauthConfigs.Google
		if oauthCfg.ClientID == "" {
			log.Error("Google OAuth client ID is not configured.")
			return 0, false, "", "", gouser.ErrAuthProviderNotConfigured
		}
		userInfoURL = "https://www.googleapis.com/oauth2/v3/userinfo"
	case "yandex":
		oauthCfg = uc.oauthConfigs.Yandex
		if oauthCfg.ClientID == "" {
			log.Error("Yandex OAuth client ID is not configured.")
			return 0, false, "", "", gouser.ErrAuthProviderNotConfigured
		}
		userInfoURL = "https://login.yandex.ru/info?format=json"
	default: // Эта проверка уже была, но на всякий случай
		log.Warn("unsupported oauth provider in callback after state verification")
		return 0, false, "", "", gouser.ErrUnsupportedProvider
	}

	oauthToken, err := oauthCfg.Exchange(context.Background(), code)
	if err != nil {
		log.Error("failed to exchange oauth code for token", "provider", provider, "error", err)
		return 0, false, "", "", fmt.Errorf("oauth exchange failed: %w", err)
	}
	log.Info("OAuth code exchanged for token successfully", slog.Bool("refresh_token_exists_from_provider", oauthToken.RefreshToken != ""))

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
		// Здесь можно обновить LastLoginAt или аватар (если он из OAuth и отличается)
		// Например, обновить аватар, если он есть в oauthUserDTO и отличается от existingUser.AvatarS3Key
		// Это потребует логики загрузки аватара в S3 здесь. Пока пропустим.
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
	return parseOAuthUserInfo(provider, resp.Body, log) // Передаем логгер
}

// parseOAuthUserInfo теперь принимает логгер
func parseOAuthUserInfo(provider string, body io.Reader, log *slog.Logger) (*auth.UserAuth, error) {
	user := &auth.UserAuth{}
	decoder := json.NewDecoder(body)
	log = log.With(slog.String("op", "parseOAuthUserInfo"), slog.String("provider", provider))

	switch provider {
	case "google":
		var googleData struct {
			Sub           string `json:"sub"` // Google User ID
			Email         string `json:"email"`
			GivenName     string `json:"given_name"`
			FamilyName    string `json:"family_name"`
			Picture       string `json:"picture"`
			EmailVerified bool   `json:"email_verified"`
			Name          string `json:"name"` // Полное имя
		}
		if err := decoder.Decode(&googleData); err != nil {
			log.Error("failed to decode google user info", "error", err)
			return nil, fmt.Errorf("decode google user info: %w", err)
		}
		user.Email = googleData.Email
		user.Login = googleData.GivenName // Используем GivenName как логин
		if user.Login == "" {             // Фоллбэк, если GivenName пустой
			if googleData.Name != "" {
				user.Login = strings.Fields(googleData.Name)[0] // Первое слово из полного имени
			} else {
				user.Login = strings.Split(googleData.Email, "@")[0] // Часть email до @
			}
		}
		// Убираем недопустимые символы из логина, если они есть
		user.Login = strings.Map(func(r rune) rune {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
				return r
			}
			return -1 // Удаляем символ
		}, user.Login)
		if len(user.Login) > 50 {
			user.Login = user.Login[:50]
		} // Обрезаем, если слишком длинный
		if user.Login == "" {
			user.Login = "guser_" + googleData.Sub[:8]
		} // Крайний случай

		user.VerifiedEmail = googleData.EmailVerified
		log.Info("Parsed Google user info", "email", user.Email, "login", user.Login, "verified", user.VerifiedEmail)
	case "yandex":
		var yandexData struct {
			DefaultEmail    string `json:"default_email"`
			Login           string `json:"login"`
			FirstName       string `json:"first_name"`
			DefaultAvatarID string `json:"default_avatar_id"`
			ID              string `json:"id"` // ID пользователя Яндекса
		}
		if err := decoder.Decode(&yandexData); err != nil {
			log.Error("failed to decode yandex user info", "error", err)
			return nil, fmt.Errorf("decode yandex user info: %w", err)
		}
		user.Email = yandexData.DefaultEmail
		user.Login = yandexData.Login
		if user.Login == "" { // Фоллбэк, если Login пустой
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

		user.VerifiedEmail = true // Яндекс email считается подтвержденным
		log.Info("Parsed Yandex user info", "email", user.Email, "login", user.Login)
	default:
		return nil, gouser.ErrUnsupportedProvider
	}
	return user, nil
}

// GetUserProfileAfterOAuth - реализация метода интерфейса
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

func (uc *AuthUseCase) StoreFinalizeTokens(code, tokens string) error {
	// Делегируем в репозиторий (который использует кеш)
	// Этот метод нужно добавить в ваш интерфейс auth.Repo
	return uc.repo.StoreFinalizeTokens(code, tokens)
}

// RetrieveFinalizeTokens извлекает и удаляет токены по одноразовому коду
func (uc *AuthUseCase) RetrieveFinalizeTokens(code string) (string, error) {
	// Делегируем в репозиторий
	// Этот метод нужно добавить в ваш интерфейс auth.Repo
	return uc.repo.RetrieveFinalizeTokens(code)
}
