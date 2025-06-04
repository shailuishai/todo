package user

import "errors"

var (
	ErrNotFound                  = errors.New("not found")
	ErrInternal                  = errors.New("internal server error")
	ErrInvalidState              = errors.New("invalid state for oauth") // Уточнил
	ErrNoAccessToken             = errors.New("no access token provided")
	ErrNoRefreshToken            = errors.New("no refresh token provided or found in cookies")
	ErrExpiredToken              = errors.New("token has expired")
	ErrInvalidToken              = errors.New("invalid token")
	ErrUnsupportedProvider       = errors.New("unsupported oauth provider")
	ErrEmailExists               = errors.New("user with this email already exists")
	ErrLoginExists               = errors.New("user with this login already exists")
	ErrUserNotFound              = errors.New("user not found")
	ErrEmailNotConfirmed         = errors.New("email not confirmed")
	ErrEmailAlreadyConfirmed     = errors.New("email already confirmed")
	ErrInvalidConfirmCode        = errors.New("invalid confirmation code")
	ErrInvalidSizeAvatar         = errors.New("file size exceeds allowed limit") // Общее для файлов
	ErrInvalidTypeAvatar         = errors.New("invalid avatar file type. Supported: jpg, jpeg, png, webp (non-animated gif)")
	ErrInvalidResolutionAvatar   = errors.New("invalid avatar resolution. Must be 1:1 aspect ratio")
	ErrInvalidAvatarFile         = errors.New("invalid or corrupted avatar file")
	ErrUserAuthWithOauth2        = errors.New("user was registered via OAuth, please sign in with OAuth provider") // Уточнил
	ErrUpdateConflict            = errors.New("update conflict, data may have been changed by another process")    // Общая ошибка для optimistic locking или конфликтов
	ErrBadRequest                = errors.New("bad request")                                                       // Общая ошибка для невалидных запросов
	ErrForbidden                 = errors.New("forbidden")                                                         // Общая ошибка для нехватки прав
	ErrAuthProviderNotConfigured = errors.New("auth provider not configured")
)
