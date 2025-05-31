package repo

import (
	gouser "server/internal/modules/user" // GORM модель User
)

// ProfileDb определяет методы для работы с базой данных для профиля пользователя.
type ProfileDb interface {
	GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error)
	UpdateUser(user *gouser.User) error
	UpdateUserSettings(settings *gouser.UserSetting) error
	DeleteUser(userId uint) error
}

// ProfileS3 определяет методы для работы с S3 хранилищем для аватаров.
type ProfileS3 interface {
	UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) error
	DeleteAvatar(bucketName string, s3Key string) error
}

// Repo реализует интерфейс profile.Repo, комбинируя ProfileDb и ProfileS3.
type Repo struct {
	db ProfileDb // Реализация для работы с БД
	s3 ProfileS3 // Реализация для работы с S3
}

func NewRepo(db ProfileDb, s3 ProfileS3) *Repo {
	return &Repo{
		db: db,
		s3: s3,
	}
}

func (r *Repo) GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error) {
	return r.db.GetUserAndSettings(userId)
}

func (r *Repo) UpdateUser(user *gouser.User) error {
	return r.db.UpdateUser(user)
}

func (r *Repo) UpdateUserSettings(settings *gouser.UserSetting) error {
	return r.db.UpdateUserSettings(settings)
}

func (r *Repo) DeleteUser(userId uint) error {
	return r.db.DeleteUser(userId)
}

// UploadAvatar делегирует загрузку аватара в ProfileS3.
func (r *Repo) UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) error {
	return r.s3.UploadAvatar(bucketName, s3Key, avatarBytes, contentType)
}

// DeleteAvatar делегирует удаление аватара из S3 в ProfileS3.
func (r *Repo) DeleteAvatar(bucketName string, s3Key string) error {
	return r.s3.DeleteAvatar(bucketName, s3Key)
}
