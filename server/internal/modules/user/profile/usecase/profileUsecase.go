package usecase

import (
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
	repo               profile.Repo // Интерфейс ProfileRepo
	s3UserAvatarBucket string
	s3BaseURL          string // Базовый URL для S3 (https://endpoint/bucket)
}

func NewProfileUseCase(log *slog.Logger, repo profile.Repo, s3UserAvatarBucket string, s3Endpoint string) *ProfileUseCase {
	var s3Base string
	if s3Endpoint != "" && s3UserAvatarBucket != "" {
		cleanEndpoint := strings.TrimPrefix(s3Endpoint, "https://")
		cleanEndpoint = strings.TrimPrefix(cleanEndpoint, "http://")
		s3Base = fmt.Sprintf("https://%s/%s", cleanEndpoint, s3UserAvatarBucket)
	}
	return &ProfileUseCase{
		log:                log,
		repo:               repo,
		s3UserAvatarBucket: s3UserAvatarBucket,
		s3BaseURL:          s3Base,
	}
}

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
	if settings == nil { // Этого не должно быть из-за триггера, но для безопасности
		log.Error("UserSettings are nil for user, this should not happen.", "userID", userId)
		// Можно создать дефолтные настройки на лету или вернуть ошибку
		// return nil, gouser.ErrInternal
		// Либо использовать дефолтные значения в ToUserProfileResponse
	}

	log.Info("user profile retrieved successfully")
	return profile.ToUserProfileResponse(user, settings, uc.s3BaseURL), nil
}

func (uc *ProfileUseCase) handleAvatarUpload(
	userID uint,
	currentAvatarS3KeyInDB *string,
	avatarMPFileHeader *multipart.FileHeader,
	resetAvatarFlag bool,
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
		return // err = nil
	}

	if avatarMPFileHeader != nil {
		log.Info("New avatar file provided for upload", "filename", avatarMPFileHeader.Filename, "size", avatarMPFileHeader.Size)

		openedFile, openErr := avatarMPFileHeader.Open() // openedFile имеет тип multipart.File
		if openErr != nil {
			log.Error("Failed to open multipart file from header", "error", openErr)
			err = gouser.ErrInvalidAvatarFile
			return
		}
		defer openedFile.Close() // Важно закрыть файл

		// Теперь передаем openedFile (который реализует io.Reader) в ParsingAvatarImage
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
			// Если ошибка из avatarManager не одна из этих, считаем ее внутренней
			log.Error("internal error during avatar parsing", "original_error", errImg)
			err = gouser.ErrInternal
			return
		}

		generatedS3Key := fmt.Sprintf("user_%d/%s.webp", userID, uuid.New().String())
		contentType := "image/webp" // Мы всегда конвертируем в webp

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
		return // err = nil
	}

	// Если не было resetAvatar и не было нового файла
	newS3KeyForDB = currentAvatarS3KeyInDB
	// madeChangesToAvatar остается false (уже инициализировано)
	return // err = nil
}

func (uc *ProfileUseCase) UpdateUser(userID uint, req *profile.UpdateUserProfileRequest, avatarMPFileHeader *multipart.FileHeader) (*profile.UserProfileResponse, error) {
	op := "ProfileUseCase.UpdateUser (PUT)"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	userGorm, settingsGorm, err := uc.repo.GetUserAndSettings(userID)
	if err != nil {
		// ... (обработка ErrUserNotFound и ErrInternal)
		if errors.Is(err, gouser.ErrUserNotFound) {
			return nil, gouser.ErrUserNotFound
		}
		return nil, gouser.ErrInternal
	}
	if settingsGorm == nil { // Должен быть создан триггером
		log.Error("User settings not found for user, cannot update", "userID", userID)
		return nil, gouser.ErrInternal // Или создать настройки по умолчанию здесь?
	}

	originalLogin := userGorm.Login
	var s3KeyForDBUpdate *string = userGorm.AvatarS3Key // По умолчанию ключ не меняется
	var s3KeyToDeleteOnSuccess *string                  // Старый ключ, который нужно будет удалить из S3 *после* успеха в БД
	madeChangesToAvatar := false

	resetAvatarFlag := false
	if req.ResetAvatar != nil && *req.ResetAvatar {
		resetAvatarFlag = true
	}

	// Обработка аватара
	s3KeyForDBUpdate, s3KeyToDeleteOnSuccess, madeChangesToAvatar, err = uc.handleAvatarUpload(userID, userGorm.AvatarS3Key, avatarMPFileHeader, resetAvatarFlag)
	if err != nil {
		// handleAvatarUpload уже залогировал, здесь просто возвращаем ошибку
		return nil, err
	}

	// Применяем изменения к моделям User и UserSettings
	userChanged, settingsChanged := profile.ApplyUpdateToUserAndSettings(userGorm, settingsGorm, req, s3KeyForDBUpdate)

	if !userChanged && !settingsChanged && !madeChangesToAvatar { // Если ничего не изменилось (включая аватар)
		log.Info("No changes detected for user profile update.")
		return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
	}

	// Если логин изменился, проверяем на уникальность (если не полагаемся только на БД constraint)
	if req.Login != nil && *req.Login != originalLogin {
		// Здесь можно добавить проверку на уникальность логина через репозиторий Auth, если необходимо
		// _, errCheckLogin := uc.authRepo.GetUserByLogin(*req.Login) // Пример
		// if errCheckLogin == nil { return nil, gouser.ErrLoginExists }
		// if !errors.Is(errCheckLogin, gouser.ErrUserNotFound) { return nil, gouser.ErrInternal }
		log.Info("User login is being updated", "old_login", originalLogin, "new_login", *req.Login)
	}

	// Сохраняем изменения в БД
	// Можно использовать транзакцию, если обновляются обе таблицы
	// tx := uc.repo.BeginTx() (если repo поддерживает транзакции)
	if userChanged {
		if errDb := uc.repo.UpdateUser(userGorm); errDb != nil {
			log.Error("Failed to update user in DB", "error", errDb)
			// Если мы загрузили новый аватар, но БД не обновилась, нужно откатить S3
			if madeChangesToAvatar && s3KeyForDBUpdate != nil && (resetAvatarFlag == false) {
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
			// Здесь сложнее с откатом S3, т.к. user мог обновиться успешно.
			// Нужна полноценная транзакция или более сложная логика отката.
			return nil, gouser.ErrInternal
		}
	}
	// uc.repo.CommitTx(tx) или RollbackTx(tx, err)

	// Если все успешно и был старый аватар, который заменили/сбросили, удаляем его из S3
	if s3KeyToDeleteOnSuccess != nil {
		log.Info("DB update successful, now deleting old S3 avatar", "s3_key", *s3KeyToDeleteOnSuccess)
		if errS3Del := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyToDeleteOnSuccess); errS3Del != nil {
			log.Error("Failed to delete old S3 avatar after successful DB update, but operation considered success", "s3_key", *s3KeyToDeleteOnSuccess, "error", errS3Del)
			// Не возвращаем ошибку клиенту, т.к. основные данные обновлены
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
	madeChangesToAvatarHandling := false // Флаг, что мы вообще трогали логику аватара (загрузка/сброс)

	resetAvatarFlag := false
	if req.ResetAvatar != nil && *req.ResetAvatar {
		resetAvatarFlag = true
	}

	// Обработка аватара для PATCH
	// s3KeyForDBUpdate будет nil если reset, или ключ нового файла, или старый ключ если не менялся
	var tempS3KeyForDB *string
	tempS3KeyForDB, s3KeyToDeleteOnSuccess, madeChangesToAvatarHandling, err = uc.handleAvatarUpload(userID, userGorm.AvatarS3Key, avatarMPFileHeader, resetAvatarFlag)
	if err != nil {
		return nil, err
	}
	// Если handleAvatarUpload вернул madeChangesToAvatar=true, значит s3KeyForDBUpdate нужно обновить
	// Если madeChangesToAvatar=false, то s3KeyForDBUpdate остается userGorm.AvatarS3Key
	if madeChangesToAvatarHandling {
		s3KeyForDBUpdate = tempS3KeyForDB
	}

	// Применяем частичные изменения к моделям
	userChanged, settingsChanged := profile.ApplyPatchToUserAndSettings(userGorm, settingsGorm, req, s3KeyForDBUpdate)

	if !userChanged && !settingsChanged && !madeChangesToAvatarHandling { // Если вообще ничего не изменилось
		log.Info("No changes detected for user profile patch.")
		return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
	}

	if req.Login != nil && *req.Login != originalLogin {
		log.Info("User login is being updated via PATCH", "old_login", originalLogin, "new_login", *req.Login)
		// Проверка уникальности (опционально здесь, обязательно в БД)
	}

	if userChanged {
		if errDb := uc.repo.UpdateUser(userGorm); errDb != nil {
			log.Error("Failed to update user in DB (PATCH)", "error", errDb)
			if madeChangesToAvatarHandling && s3KeyForDBUpdate != nil && !resetAvatarFlag { // Откатываем новый аватар
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

	if s3KeyToDeleteOnSuccess != nil { // Если был старый аватар, который заменили/сбросили
		log.Info("DB PATCH successful, now deleting old S3 avatar", "s3_key", *s3KeyToDeleteOnSuccess)
		if errS3Del := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *s3KeyToDeleteOnSuccess); errS3Del != nil {
			log.Error("Failed to delete old S3 avatar after successful DB PATCH", "s3_key", *s3KeyToDeleteOnSuccess, "error", errS3Del)
		}
	}

	log.Info("User profile patched successfully.")
	return profile.ToUserProfileResponse(userGorm, settingsGorm, uc.s3BaseURL), nil
}

func (uc *ProfileUseCase) DeleteUser(userId uint) error {
	// ... (логика DeleteUser остается без изменений, но она должна удалять и UserSettings через ON DELETE CASCADE)
	op := "ProfileUseCase.DeleteUser"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userId)))

	userGorm, settingsGorm, err := uc.repo.GetUserAndSettings(userId)
	if err != nil {
		if errors.Is(err, gouser.ErrUserNotFound) {
			log.Warn("user not found for deletion, no action taken")
			return nil
		}
		log.Error("failed to get user GORM model before deletion", "error", err)
		return gouser.ErrInternal
	}
	_ = settingsGorm // Используем, чтобы компилятор не ругался, если settingsGorm не нужен явно

	if userGorm.AvatarS3Key != nil {
		log.Info("deleting user avatar from S3", "s3_key", *userGorm.AvatarS3Key)
		errS3 := uc.repo.DeleteAvatar(uc.s3UserAvatarBucket, *userGorm.AvatarS3Key)
		if errS3 != nil {
			log.Error("failed to delete user avatar from S3 during user deletion, proceeding with DB deletion", "s3_key", *userGorm.AvatarS3Key, "error", errS3)
		}
	}

	// repo.DeleteUser должен вызывать метод репозитория User, который удалит пользователя.
	// Если у тебя нет такого общего репозитория User, то ProfileRepo должен иметь метод DeleteUser.
	// Предположим, что ProfileRepo может удалить User и связанные UserSettings (через ON DELETE CASCADE)
	err = uc.repo.DeleteUser(userId) // <<< НУЖЕН МЕТОД DeleteUser В ИНТЕРФЕЙСЕ И РЕАЛИЗАЦИИ profile.Repo
	if err != nil {
		log.Error("failed to delete user from DB", "error", err)
		return gouser.ErrInternal
	}

	log.Info("user deleted successfully")
	return nil
}
