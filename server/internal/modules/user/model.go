package user

import (
	"server/internal/modules/user/auth"
	"server/internal/modules/user/profile"
	"time"
)

type User struct {
	UserId         uint      `gorm:"primaryKey;column:user_id"`
	HashedPassword *string   `gorm:"size:255;column:hashed_password"`
	IsAdmin        bool      `gorm:"default:false;column:is_admin"`
	Login          string    `gorm:"unique;size:100;not null;column:login"`
	Email          string    `gorm:"unique;size:100;not null;column:email"`
	VerifiedEmail  bool      `gorm:"default:false;column:verified_email"`
	AvatarURL      string    `gorm:"default:'https://useravatar.storage-173.s3hoster.by/default/';column:avatar_url"`
	CreatedAt      time.Time `gorm:"column:create_at"`
}

func ToAuthUser(user *User) *auth.UserAuth {
	return &auth.UserAuth{
		UserId:         user.UserId,
		HashedPassword: user.HashedPassword,
		Login:          user.Login,
		Email:          user.Email,
		IsAdmin:        user.IsAdmin,
		VerifiedEmail:  user.VerifiedEmail,
	}
}

func FromAuthUser(user *auth.UserAuth) *User {
	return &User{
		UserId:         user.UserId,
		HashedPassword: user.HashedPassword,
		IsAdmin:        user.IsAdmin,
		Email:          user.Email,
		Login:          user.Login,
		VerifiedEmail:  user.VerifiedEmail,
	}
}

func ToProfileUser(user *User) *profile.UserProfile {
	return &profile.UserProfile{
		UserId:    user.UserId,
		Email:     &user.Email,
		Login:     &user.Login,
		AvatarUrl: &user.AvatarURL,
	}
}

func FromProfileUser(user *profile.UserProfile) *User {
	return &User{
		UserId:    user.UserId,
		Login:     *user.Login,
		AvatarURL: *user.AvatarUrl,
	}
}
