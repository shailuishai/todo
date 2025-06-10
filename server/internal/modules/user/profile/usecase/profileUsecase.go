package usecase

import (
	"context" // Добавлен импорт
	"errors"
	"fmt"
	"github.com/google/uuid"
	"log/slog"
	"mime/multipart"
	gouser "server/internal/modules/user"
	"server/internal/modules/user/profile"
	avatarManager "server/pkg/lib/avatarMenager"
	"strings"
)

type ProfileUseCase struct {
	log                *slog.Logger
	repo               profile.Repo // Интерфейс profile.Repo
	s3UserAvatarBucket string
	s3BaseURL          string
}

func NewProfileUseCase(log *slog.Logger, repo profile.Repo, s3UserAvatarBucket string, s3Endpoint string) profile.UseCase { // Возвращаем интерфейс profile.UseCase
	var s3Base string
	if s3Endpoint != "" && s3UserAvatarBucket != "" {
		cleanEndpoint := strings.TrimPrefix(s3Endpoint, "https://")
		cleanEndpoint = strings.TrimPrefix(cleanEndpoint, "http://")
		// Убедимся, что нет двойных слешей, если s3UserAvatarBucket начинается с /
		s3Base = fmt.Sprintf("https://%s/%s", strings.TrimSuffix(cleanEndpoint, "/"), strings.TrimPrefix(s3UserAvatarBucket, "/"))
	}
	return &ProfileUseCase{
		log:                log,
		repo:               repo,
		s3UserAvatarBucket: s3UserAvatarBucket,
		s3BaseURL:          s3Base,
	}
}

// --- Существующие методы GetUser, UpdateUser, PatchUser, DeleteUser ---
// ... (без изменений, как ты предоставил) ...
func (uc *ProfileUseCase) GetUser(userId uint) (*profile.UserProfileResponse, error) {
	op := "ProfileUseCase.GetUser"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userId)))
	user, settings, err := uc.repo.GetUserAndSettings(userId)
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("user not found in repo")
			return nil, gouser.ErrUserNotFound
		}
		log.Error("failed to get user and settings from repo", "error", err)
		return nil, gouser.ErrInternal
	}
	log.Info("user profile retrieved successfully")
	return profile.ToUserProfileResponse(user, settings, uc.s3BaseURL), nil
}
func (uc *ProfileUseCase) handleAvatarUpload(
	userID uint, currentAvatarS3KeyInDB *string, avatarMPFileHeader *multipart.FileHeader, resetAvatarFlag bool,
) (newS3KeyForDB *string, s3KeyToDelete *string, madeChangesToAvatar bool, err error) {
	op := "ProfileUseCase.handleAvatarUpload"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))
	madeChangesToAvatar = false
	if resetAvatarFlag {
		log.Info("Avatar reset requested.")
		if currentAvatarS3KeyInDB != nil {
			s3KeyToDelete = currentAvatarS3KeyInDB
		}
		newS3KeyForDB = nil
		madeChangesToAvatar = true
		return
	}
	if avatarMPFileHeader != nil {
		log.Info("New avatar file provided for upload", "filename", avatarMPFileHeader.Filename, "size", avatarMPFileHeader.Size)
		openedFile, openErr := avatarMPFileHeader.Open()
		if openErr != nil {
			log.Error("Failed to open multipart file from header", "error", openErr)
			err = gouser.ErrInvalidAvatarFile
			return
		}
		defer openedFile.Close()
		_, largeAvatarBytes, errImg := avatarManager.ParsingAvatarImage(openedFile)
		if errImg != nil {
			log.Error("failed to parse avatar image", "error", errImg)
			if errors.Is(errImg, avatarManager.ErrInvalidTypeAvatar) {
				err = gouser.ErrInvalidTypeAvatar
				return
			}
			if errors.Is(errImg, avatarManager.ErrInvalidResolutionAvatar) {
				err = gouser.ErrInvalidResolutionAvatar
				return
			}
			log.Error("internal error during avatar parsing", "original_error", errImg)
			err = gouser.ErrInternal
			return
		}
		generatedS3Key := fmt.Sprintf("user_%d/%s.webp", userID, uuid.New().String())
		contentType := "image/webp"
		errUpload := uc.repo.UploadAvatar(uc.s3UserAvatarBucket, generatedS3Key, largeAvatarBytes, contentType)
		if errUpload != nil {
			log.Error("failed to upload new avatar to S3", "s3_key", generatedS3Key, "error", errUpload)
			err = gouser.ErrInternal
			return
		}
		log.Info("New avatar uploaded to S3", "s3_key", generatedS3Key)
		tempS3Key := generatedS3Key
		newS3KeyForDB = &tempS3Key
		madeChangesToAvatar = true
		if currentAvatarS3KeyInDB != nil && *currentAvatarS3KeyInDB != generatedS3Key {
			s3KeyToDelete = currentAvatarS3KeyInDB
		}
		return
	}
	newS3KeyForDB = currentAvatarS3KeyInDB
	return
}
func (uc *ProfileUseCase) UpdateUser(userID uint, req *profile.UpdateUserProfileRequest, avatarMPFileHeader *multipart.FileHeader) (*profile.UserProfileResponse, error) {
	op := "ProfileUseCase.UpdateUser (PUT)"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))
	userGorm, settingsGorm, err := uc.repo.GetUserAndSettings(userID)
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			return nil, gouser.ErrUserNotFound
		}
		return nil, gouser.ErrInternal
	}
	if settingsGorm == nil {
		log.Error("User settings not found for user, cannot update", "userID", userID)
		return nil, gouser.ErrInternal
	}
	originalLogin := userGorm.Login
	var s3KeyForDBUpdate *string = userGorm.AvatarS3Key
	var s3KeyToDeleteOnSuccess *string
	madeChangesToAvatar := false
	resetAvatarFlag := false
	if req.ResetAvatar != nil && *req.ResetAvatar {
		resetAvatarFlag = true
	}
	s3KeyForDBUpdate, s3KeyToDeleteOnSuccess, madeChangesToAvatar, err = uc.handleAvatarUpload(userID, userGorm.AvatarS3Key, avatarMPFileHeader, resetAvatarFlag)
	if err != nil {
		return nil, err
	}
	userChanged, settingsChanged := profile.ApplyUpdateToUserAndSettings(userGorm, settingsGorm, req, s3KeyForDBUpdate)
	if !userChanged && !settingsChanged && !madeChangesToAvatar {
		log.Info("No changes detected for user profile update.")
		return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
	}
	if req.Login != nil && *req.Login != originalLogin {
		log.Info("User login is being updated", "old_login", originalLogin, "new_login", *req.Login)
	}
	if userChanged {
		if errDb := uc.repo.UpdateUser(userGorm); errDb != nil {
			log.Error("Failed to update user in DB", "error", errDb)
			if madeChangesToAvatar && s3KeyForDBUpdate != nil && (!resetAvatarFlag) {
				log.Warn("DB update for User failed after S3 avatar upload, attempting to delete new S3 avatar", "s3_key", *s3KeyForDBUpdate)
				uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyForDBUpdate)
			}
			if errors.Is(errDb, gouser.ErrLoginExists) {
				return nil, gouser.ErrLoginExists
			}
			return nil, gouser.ErrInternal
		}
	}
	if settingsChanged {
		if errDb := uc.repo.UpdateUserSettings(settingsGorm); errDb != nil {
			log.Error("Failed to update user settings in DB", "error", errDb)
			return nil, gouser.ErrInternal
		}
	}
	if s3KeyToDeleteOnSuccess != nil {
		log.Info("DB update successful, now deleting old S3 avatar", "s3_key", *s3KeyToDeleteOnSuccess)
		if errS3Del := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyToDeleteOnSuccess); errS3Del != nil {
			log.Error("Failed to delete old S3 avatar after successful DB update", "s3_key", *s3KeyToDeleteOnSuccess, "error", errS3Del)
		}
	}
	log.Info("User profile updated successfully.")
	return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
}
func (uc *ProfileUseCase) PatchUser(userID uint, req *profile.PatchUserProfileRequest, avatarMPFileHeader *multipart.FileHeader) (*profile.UserProfileResponse, error) {
	op := "ProfileUseCase.PatchUser"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))
	userGorm, settingsGorm, err := uc.repo.GetUserAndSettings(userID)
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			return nil, gouser.ErrUserNotFound
		}
		return nil, gouser.ErrInternal
	}
	if settingsGorm == nil {
		log.Error("User settings not found for user (PATCH), this should not happen", "userID", userID)
		return nil, gouser.ErrInternal
	}
	originalLogin := userGorm.Login
	var s3KeyForDBUpdate *string = userGorm.AvatarS3Key
	var s3KeyToDeleteOnSuccess *string
	madeChangesToAvatarHandling := false
	resetAvatarFlag := false
	if req.ResetAvatar != nil && *req.ResetAvatar {
		resetAvatarFlag = true
	}
	var tempS3KeyForDB *string
	tempS3KeyForDB, s3KeyToDeleteOnSuccess, madeChangesToAvatarHandling, err = uc.handleAvatarUpload(userID, userGorm.AvatarS3Key, avatarMPFileHeader, resetAvatarFlag)
	if err != nil {
		return nil, err
	}
	if madeChangesToAvatarHandling {
		s3KeyForDBUpdate = tempS3KeyForDB
	}
	userChanged, settingsChanged := profile.ApplyPatchToUserAndSettings(userGorm, settingsGorm, req, s3KeyForDBUpdate)
	if !userChanged && !settingsChanged && !madeChangesToAvatarHandling {
		log.Info("No changes detected for user profile patch.")
		return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
	}
	if req.Login != nil && *req.Login != originalLogin {
		log.Info("User login is being updated via PATCH", "old_login", originalLogin, "new_login", *req.Login)
	}
	if userChanged {
		if errDb := uc.repo.UpdateUser(userGorm); errDb != nil {
			log.Error("Failed to update user in DB (PATCH)", "error", errDb)
			if madeChangesToAvatarHandling && s3KeyForDBUpdate != nil && !resetAvatarFlag {
				log.Warn("DB update for User failed after S3 avatar upload (PATCH), attempting to delete new S3 avatar", "s3_key", *s3KeyForDBUpdate)
				uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyForDBUpdate)
			}
			if errors.Is(errDb, gouser.ErrLoginExists) {
				return nil, gouser.ErrLoginExists
			}
			return nil, gouser.ErrInternal
		}
	}
	if settingsChanged {
		if errDb := uc.repo.UpdateUserSettings(settingsGorm); errDb != nil {
			log.Error("Failed to update user settings in DB (PATCH)", "error", errDb)
			return nil, gouser.ErrInternal
		}
	}
	if s3KeyToDeleteOnSuccess != nil {
		log.Info("DB PATCH successful, now deleting old S3 avatar", "s3_key", *s3KeyToDeleteOnSuccess)
		if errS3Del := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyToDeleteOnSuccess); errS3Del != nil {
			log.Error("Failed to delete old S3 avatar after successful DB PATCH", "s3_key", *s3KeyToDeleteOnSuccess, "error", errS3Del)
		}
	}
	log.Info("User profile patched successfully.")
	return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
}
func (uc *ProfileUseCase) DeleteUser(userId uint) error {
	op := "ProfileUseCase.DeleteUser"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userId)))
	userGorm, _, err := uc.repo.GetUserAndSettings(userId) // settingsGorm здесь не используется, но получаем для полноты
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("user not found for deletion, no action taken")
			return nil
		}
		log.Error("failed to get user GORM model before deletion", "error", err)
		return gouser.ErrInternal
	}
	if userGorm.AvatarS3Key != nil {
		log.Info("deleting user avatar from S3", "s3_key", *userGorm.AvatarS3Key)
		if errS3 := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *userGorm.AvatarS3Key); errS3 != nil {
			log.Error("failed to delete user avatar from S3 during user deletion, proceeding with DB deletion", "s3_key", *userGorm.AvatarS3Key, "error", errS3)
		}
	}
	err = uc.repo.DeleteUser(userId)
	if err != nil {
		log.Error("failed to delete user from DB", "error", err)
		return gouser.ErrInternal
	}
	log.Info("user deleted successfully")
	return nil
}

// --- Новые методы для Device Tokens ---

func (uc *ProfileUseCase) RegisterDeviceToken(ctx context.Context, userID uint, tokenValue string, deviceType string) error {
	op := "ProfileUseCase.RegisterDeviceToken"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.String("deviceType", deviceType))

	// Валидация deviceType (хотя это уже делает валидатор в контроллере)
	switch strings.ToLower(deviceType) {
	case "android", "ios", "web":
		// OK
	default:
		log.Warn("Invalid device type provided", "deviceType", deviceType)
		return gouser.ErrBadRequest // Или более специфичная ошибка
	}

	tokenModel := &gouser.UserDeviceToken{
		UserID:      userID,
		DeviceToken: tokenValue,
		DeviceType:  deviceType,
		// CreatedAt и LastSeenAt будут установлены в репозитории или БД
	}

	if err := uc.repo.AddDeviceToken(ctx, tokenModel); err != nil {
		log.Error("Failed to add device token via repo", "error", err)
		return err // Репозиторий должен вернуть gouser.ErrInternal или более специфичную
	}
	log.Info("Device token registered successfully")
	return nil
}

func (uc *ProfileUseCase) UnregisterDeviceToken(ctx context.Context, userID uint, tokenValue string) error {
	op := "ProfileUseCase.UnregisterDeviceToken"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	if err := uc.repo.RemoveDeviceToken(ctx, userID, tokenValue); err != nil {
		log.Error("Failed to remove device token via repo", "error", err)
		return err
	}
	log.Info("Device token unregistered successfully (if it existed for user)")
	return nil
}

// --- Реализация методов для UserSettingsProvider ---

// GetUserNotificationSettings извлекает только настройки уведомлений.
// Может быть полезно, если не нужен весь UserProfileResponse.
func (uc *ProfileUseCase) GetUserNotificationSettings(userID uint) (*gouser.UserSetting, error) {
	op := "ProfileUseCase.GetUserNotificationSettings"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	_, settings, err := uc.repo.GetUserAndSettings(userID)
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("User not found for GetUserNotificationSettings")
			// Возвращаем nil, nil, т.к. если нет юзера, нет и настроек. Ошибка ErrUserNotFound уже это сигнализирует.
			return nil, gouser.ErrUserNotFound
		}
		log.Error("Failed to get user settings from repo", "error", err)
		return nil, gouser.ErrInternal
	}
	if settings == nil {
		// Этого не должно произойти, если пользователь существует (из-за триггера),
		// но если все же произошло, это внутренняя проблема.
		log.Error("User found, but settings are nil. This indicates a data integrity issue.", "userID", userID)
		return nil, gouser.ErrInternal
	}
	return settings, nil
}

// GetUserDeviceTokens извлекает все активные токены устройств для пользователя.
func (uc *ProfileUseCase) GetUserDeviceTokens(userID uint) ([]gouser.UserDeviceToken, error) {
	op := "ProfileUseCase.GetUserDeviceTokens"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	tokens, err := uc.repo.GetDeviceTokensByUserID(context.Background(), userID) // Используем background context
	if err != nil {
		log.Error("Failed to get device tokens from repo", "error", err)
		return nil, err // Репозиторий вернет gouser.ErrInternal
	}
	// Здесь можно добавить логику фильтрации "мертвых" токенов, если FCM/APNS вернули ошибку о недействительности
	// или если LastSeenAt слишком старый. Пока просто возвращаем все.
	return tokens, nil
}

// GetUserEmail извлекает email пользователя и статус его верификации.
func (uc *ProfileUseCase) GetUserEmail(userID uint) (email string, isVerified bool, err error) {
	op := "ProfileUseCase.GetUserEmail"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	email, isVerified, err = uc.repo.GetUserEmail(userID)
	if err != nil {
		log.Error("Failed to get user email from repo", "error", err)
		return "", false, err // Репозиторий вернет ErrUserNotFound или ErrInternal
	}
	return email, isVerified, nil
}
