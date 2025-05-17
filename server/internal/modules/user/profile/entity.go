package profile

import (
	"mime/multipart"
	"net/http"
)

type UserProfile struct {
	UserId      uint
	AvatarUrl   *string
	Login       *string
	Email       *string
	ResetAvatar bool
}

type Controller interface {
	UpdateUser(w http.ResponseWriter, r *http.Request)
	GetUser(w http.ResponseWriter, r *http.Request)
	DeleteUser(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	UpdateUser(profile *UserProfile, avatar *multipart.File) error
	GetUser(userId uint) (*UserProfile, error)
	DeleteUser(userId uint) error
}

type Repo interface {
	GetUserById(userId uint) (*UserProfile, error)
	UpdateUser(user *UserProfile) error
	UploadAvatar(avatarSmall []byte, avatarLarge []byte, login *string, userId uint) (*string, error)
	DeleteUser(userId uint) error
	DeleteAvatar(login *string, userId uint) error
}
