package user

import "errors"

var (
	ErrInternal                = errors.New("internal server error")
	ErrInvalidState            = errors.New("invalid state")
	ErrNoAccessToken           = errors.New("no access token")
	ErrNoRefreshToken          = errors.New("no refresh token")
	ErrExpiredToken            = errors.New("token expired")
	ErrInvalidToken            = errors.New("invalid token")
	ErrUnsupportedProvider     = errors.New("unsupported provider")
	ErrEmailExists             = errors.New("user with this email already exists")
	ErrLoginExists             = errors.New("user with this login already exists")
	ErrUserNotFound            = errors.New("user not found")
	ErrEmailNotConfirmed       = errors.New("email not confirmed")
	ErrEmailAlreadyConfirmed   = errors.New("email already confirmed")
	ErrInvalidConfirmCode      = errors.New("invalid confirm code")
	ErrInvalidSizeAvatar       = errors.New("file size exceeds 1 MB limit")
	ErrInvalidTypeAvatar       = errors.New("invalid type avatar, supported avatar formats are jpg, jpeg, png, webp, or no animated gif")
	ErrInvalidResolutionAvatar = errors.New("invalid resolution avatar, supported avatar resolution 1x1")
	ErrInvalidAvatarFile       = errors.New("invalid avatar file")
	ErrUserAuthWithOauth2      = errors.New("pls auth with oauth2")
)
