package usecase

import (
	"errors"
	"log/slog"
	"mime/multipart"
	u "server/internal/modules/user"
	"server/internal/modules/user/profile"
	avatarManager "server/pkg/lib/avatarMenager"
)

type ProfileUseCase struct {
	log *slog.Logger
	rp  profile.Repo
}

func NewProfileUseCase(log *slog.Logger, rp profile.Repo) *ProfileUseCase {
	return &ProfileUseCase{
		log: log,
		rp:  rp,
	}
}

func (uc *ProfileUseCase) UpdateUser(user *profile.UserProfile, avatar *multipart.File) error {
	log := uc.log.With("op", "UpdateUser")

	findUser, err := uc.rp.GetUserById(user.UserId)
	if err != nil {
		if errors.Is(err, u.ErrUserNotFound) {
			return err
		}
		return u.ErrInternal
	}

	if user.Login == nil {
		user.Login = findUser.Login
	}

	if user.ResetAvatar {
		defaultAvatar := "https://useravatar.storage-173.s3hoster.by/default"
		if err := uc.rp.DeleteAvatar(findUser.Login, user.UserId); err != nil {
			log.Error("failed to delete avatar", err)
			return err
		}
		user.AvatarUrl = &defaultAvatar
	} else if avatar != nil {
		smallAvatar, largeAvatar, err := avatarManager.ParsingAvatarImage(avatar)
		if err != nil {
			log.Error("failed to parse avatar image", err)
			switch {
			case errors.Is(err, avatarManager.ErrInvalidTypeAvatar):
				return u.ErrInvalidTypeAvatar
			case errors.Is(err, avatarManager.ErrInvalidResolutionAvatar):
				return u.ErrInvalidResolutionAvatar
			default:
				return u.ErrInternal
			}
		}

		avatarUrl, err := uc.rp.UploadAvatar(smallAvatar, largeAvatar, user.Login, user.UserId)
		if err != nil {
			log.Error("failed to upload avatar", err)
			return err
		}

		user.AvatarUrl = avatarUrl
	}

	if err := uc.rp.UpdateUser(user); err != nil {
		log.Error("failed to update user", err)
		return u.ErrInternal
	}

	return nil
}

func (uc *ProfileUseCase) GetUser(userId uint) (*profile.UserProfile, error) {
	user, err := uc.rp.GetUserById(userId)
	return user, err
}

func (uc *ProfileUseCase) DeleteUser(userId uint) error {
	return uc.rp.DeleteUser(userId)
}
