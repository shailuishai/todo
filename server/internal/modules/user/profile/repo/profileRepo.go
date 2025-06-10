package repo

import (
	"context" // Добавлен импорт
	gouser "server/internal/modules/user"
	// profileEntity "server/internal/modules/user/profile" // Не нужен, т.к. интерфейс Repo уже в profile.entity.go
)

// ProfileDb определяет методы для работы с базой данных для профиля пользователя.
// Этот интерфейс используется реализацией Repo для делегирования DB-операций.
type ProfileDb interface {
	GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error)
	UpdateUser(user *gouser.User) error
	UpdateUserSettings(settings *gouser.UserSetting) error
	DeleteUser(userId uint) error
	GetUserEmail(userID uint) (email string, isVerified bool, err error) // Добавлен

	// Методы для Device Tokens
	AddDeviceToken(ctx context.Context, token *gouser.UserDeviceToken) error
	RemoveDeviceToken(ctx context.Context, userID uint, deviceTokenValue string) error
	GetDeviceTokensByUserID(ctx context.Context, userID uint) ([]gouser.UserDeviceToken, error)
	UpdateDeviceTokenLastSeen(ctx context.Context, deviceTokenValue string) error
}

// ProfileS3 определяет методы для работы с S3 хранилищем для аватаров.
// ... (без изменений) ...
type ProfileS3 interface {
	UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) error
	DeleteAvatar(bucketName string, s3Key string) error
}

// Repo реализует интерфейс profile.Repo, комбинируя ProfileDb и ProfileS3.
type Repo struct {
	db ProfileDb // Реализация для работы с БД, теперь включает методы для DeviceToken
	s3 ProfileS3 // Реализация для работы с S3
}

func NewRepo(db ProfileDb, s3 ProfileS3) *Repo { // Возвращает *Repo, который должен реализовывать profile.Repo
	return &Repo{
		db: db,
		s3: s3,
	}
}

// --- Методы User & UserSettings ---
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
func (r *Repo) GetUserEmail(userID uint) (email string, isVerified bool, err error) {
	return r.db.GetUserEmail(userID)
}

// --- Методы S3 ---
func (r *Repo) UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) error {
	return r.s3.UploadAvatar(bucketName, s3Key, avatarBytes, contentType)
}
func (r *Repo) DeleteAvatar(bucketName string, s3Key string) error {
	return r.s3.DeleteAvatar(bucketName, s3Key)
}

// --- Методы Device Tokens (делегирование в ProfileDb) ---
func (r *Repo) AddDeviceToken(ctx context.Context, token *gouser.UserDeviceToken) error {
	return r.db.AddDeviceToken(ctx, token)
}
func (r *Repo) RemoveDeviceToken(ctx context.Context, userID uint, deviceTokenValue string) error {
	return r.db.RemoveDeviceToken(ctx, userID, deviceTokenValue)
}
func (r *Repo) GetDeviceTokensByUserID(ctx context.Context, userID uint) ([]gouser.UserDeviceToken, error) {
	return r.db.GetDeviceTokensByUserID(ctx, userID)
}
func (r *Repo) UpdateDeviceTokenLastSeen(ctx context.Context, deviceTokenValue string) error {
	return r.db.UpdateDeviceTokenLastSeen(ctx, deviceTokenValue)
}
