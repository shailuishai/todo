package repo

import "server/internal/modules/user/profile"

type ProfileDb interface {
	GetUserById(userId uint) (*profile.UserProfile, error)
	UpdateUser(user *profile.UserProfile) error
	DeleteUser(userId uint) error
}

type ProfileS3 interface {
	UploadAvatar(avatarSmall []byte, avatarLarge []byte, login string, userId uint) (*string, error)
	DeleteAvatar(login string, userId uint) error
}

type Repo struct {
	db ProfileDb
	s3 ProfileS3
}

func NewProfileRepo(db ProfileDb, s3 ProfileS3) *Repo {
	return &Repo{
		db: db,
		s3: s3,
	}
}

func (r *Repo) GetUserById(userId uint) (*profile.UserProfile, error) {
	return r.db.GetUserById(userId)
}

func (r *Repo) UpdateUser(user *profile.UserProfile) error {
	return r.db.UpdateUser(user)
}

func (r *Repo) DeleteUser(userId uint) error {
	return r.db.DeleteUser(userId)
}

func (r *Repo) UploadAvatar(avatarSmall []byte, avatarLarge []byte, login *string, userId uint) (*string, error) {
	return r.s3.UploadAvatar(avatarSmall, avatarLarge, *login, userId)
}

func (r *Repo) DeleteAvatar(login *string, userId uint) error {
	return r.s3.DeleteAvatar(*login, userId)
}
