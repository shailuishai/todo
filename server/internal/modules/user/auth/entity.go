package auth

import (
	"net/http"
	gouser "server/internal/modules/user"  // GORM модель User и UserSetting
	"server/internal/modules/user/profile" // Для UserProfileResponse в UseCase
)

// UserAuth - DTO для данных аутентификации.
// Содержит только поля, необходимые для процесса аутентификации и идентификации,
// которые находятся в таблице 'users'. Настройки (theme, accent_color и т.д.) сюда не входят.
type UserAuth struct {
	UserId                uint    `json:"user_id"`
	PasswordHash          *string `json:"-"` // Не для JSON ответа, используется внутри
	Login                 string  `json:"login"`
	Email                 string  `json:"email"`
	IsAdmin               bool    `json:"is_admin"`
	VerifiedEmail         bool    `json:"verified_email"`
	AvatarS3Key           *string `json:"-"`                        // Не для JSON ответа, может использоваться для OAuth flow
	HasMobileDeviceLinked bool    `json:"has_mobile_device_linked"` // Добавим сюда, т.к. это свойство User
}

// --- Конвертеры ---

// ToAuthUser конвертирует GORM модель gouser.User в DTO UserAuth.
// НЕ включает поля из gouser.User.Settings.
func ToAuthUser(user *gouser.User) *UserAuth {
	if user == nil {
		return nil
	}
	return &UserAuth{
		UserId:                user.UserId,
		PasswordHash:          user.PasswordHash,
		Login:                 user.Login,
		Email:                 user.Email,
		IsAdmin:               user.IsAdmin,
		VerifiedEmail:         user.VerifiedEmail,
		AvatarS3Key:           user.AvatarS3Key,
		HasMobileDeviceLinked: user.HasMobileDeviceLinked, // Добавлено
	}
}

// FromAuthUser конвертирует DTO UserAuth в GORM модель gouser.User.
// Поле gouser.User.Settings НЕ инициализируется здесь, так как UserSettings
// создаются триггером в БД при создании новой записи User.
// При обновлении существующего User, его Settings не должны затрагиваться этим конвертером.
func FromAuthUser(authUser *UserAuth) *gouser.User {
	if authUser == nil {
		return nil
	}
	// Создаем gouser.User только с полями, которые есть в UserAuth DTO
	// и относятся к таблице 'users'.
	return &gouser.User{
		UserId:                authUser.UserId, // Важно для обновления существующего User по ID
		Login:                 authUser.Login,
		Email:                 authUser.Email,
		PasswordHash:          authUser.PasswordHash,
		AvatarS3Key:           authUser.AvatarS3Key,
		IsAdmin:               authUser.IsAdmin,
		VerifiedEmail:         authUser.VerifiedEmail,
		HasMobileDeviceLinked: authUser.HasMobileDeviceLinked, // Добавлено
		// Settings здесь НЕ инициализируем, GORM не будет пытаться создать/обновить UserSettings
		// если это поле не заполнено или если мы явно не укажем ассоциацию для обновления.
		// При Create(&User) - триггер создаст UserSettings.
		// При Update(&User) - UserSettings не трогаются, если не было явного Preload и изменения поля Settings.
	}
}

// --- Интерфейсы для модуля auth ---

type Controller interface {
	SignUp(w http.ResponseWriter, r *http.Request)
	SignIn(w http.ResponseWriter, r *http.Request)
	Oauth(w http.ResponseWriter, r *http.Request)
	OauthCallback(w http.ResponseWriter, r *http.Request)
	RefreshToken(w http.ResponseWriter, r *http.Request)
	RefreshTokenNative(w http.ResponseWriter, r *http.Request)
	Logout(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	SignUp(email string, login string, password string) error
	SignIn(email string, login string, password string) (accessToken string, refreshToken string, err error)
	GetAuthURL(provider string) (url string, state string, err error)
	Callback(provider, state, code string) (userID uint, isNewUser bool, accessToken string, refreshToken string, err error)
	RefreshToken(r *http.Request) (accessToken string, err error)
	RefreshTokenNative(tokenString string) (newAccessToken string, newRefreshToken string, err error)
	// GetUserProfileAfterOAuth теперь возвращает UserProfileResponse, который включает настройки
	GetUserProfileAfterOAuth(userID uint) (*profile.UserProfileResponse, error)
}

// Repo определяет интерфейсы для взаимодействия с хранилищем данных (БД и кэш).
type Repo interface {
	// DB methods
	CreateUser(user *UserAuth) (userID uint, err error) // Принимает UserAuth DTO
	GetUserByEmail(email string) (*UserAuth, error)     // Возвращает UserAuth DTO
	GetUserByLogin(login string) (*UserAuth, error)     // Возвращает UserAuth DTO
	GetUserById(id uint) (*UserAuth, error)             // Возвращает UserAuth DTO
	// Cache methods
	SaveStateCode(state string, providerData string) error
	VerifyStateCode(state string) (providerData string, isValid bool, err error)
}
