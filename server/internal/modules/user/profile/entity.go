package profile

import (
	"mime/multipart"
	"net/http"
	gouser "server/internal/modules/user" // GORM модели User и UserSetting
	"strings"
)

// UserProfileResponse - DTO для ответа GetUser
type UserProfileResponse struct {
	UserID                uint    `json:"user_id"`
	Login                 string  `json:"login"` // Убрал omitempty, login всегда должен быть
	Email                 string  `json:"email"` // Убрал omitempty
	AvatarURL             *string `json:"avatar_url,omitempty"`
	Theme                 string  `json:"theme"`
	AccentColor           string  `json:"accent_color"`
	IsSidebarCollapsed    bool    `json:"is_sidebar_collapsed"`
	HasMobileDeviceLinked bool    `json:"has_mobile_device_linked"`
	// Настройки уведомлений
	NotificationsEmailEnabled     bool `json:"notifications_email_enabled"`
	NotificationsPushTaskAssigned bool `json:"notifications_push_task_assigned"`
	NotificationsPushTaskDeadline bool `json:"notifications_push_task_deadline"`
	NotificationsPushTeamMention  bool `json:"notifications_push_team_mention"`
}

// UpdateUserProfileRequest - DTO для PUT запроса на обновление профиля (полное или частичное)
// Для PUT можно ожидать все поля, которые могут быть изменены.
// Клиент должен отправлять все текущие значения для полей, которые не меняет.
// Или мы можем сделать все поля указателями и обрабатывать только не-nil (как для PATCH).
// Для простоты PUT, оставим как есть - клиент шлет все значения.
type UpdateUserProfileRequest struct {
	Login              *string `json:"login,omitempty" validate:"omitempty,min=1,max=50"` // Если не omitempty, то min=1
	Theme              *string `json:"theme,omitempty" validate:"omitempty,oneof=light dark system"`
	AccentColor        *string `json:"accent_color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
	IsSidebarCollapsed *bool   `json:"is_sidebar_collapsed,omitempty"`
	ResetAvatar        *bool   `json:"reset_avatar,omitempty"`
	// Настройки уведомлений для PUT (если хотим их обновлять через этот же эндпоинт)
	NotificationsEmailEnabled     *bool `json:"notifications_email_enabled,omitempty"`
	NotificationsPushTaskAssigned *bool `json:"notifications_push_task_assigned,omitempty"`
	NotificationsPushTaskDeadline *bool `json:"notifications_push_task_deadline,omitempty"`
	NotificationsPushTeamMention  *bool `json:"notifications_push_team_mention,omitempty"`
}

// PatchUserProfileRequest - DTO для PATCH запроса
// Все поля - указатели, чтобы понимать, какие именно поля пришли в запросе.
type PatchUserProfileRequest struct {
	Login                         *string `json:"login,omitempty" validate:"omitempty,min=1,max=50"`
	Theme                         *string `json:"theme,omitempty" validate:"omitempty,oneof=light dark system"`
	AccentColor                   *string `json:"accent_color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
	IsSidebarCollapsed            *bool   `json:"is_sidebar_collapsed,omitempty"`
	ResetAvatar                   *bool   `json:"reset_avatar,omitempty"`             // Для PATCH тоже может быть актуально
	HasMobileDeviceLinked         *bool   `json:"has_mobile_device_linked,omitempty"` // Можно обновлять через PATCH
	NotificationsEmailEnabled     *bool   `json:"notifications_email_enabled,omitempty"`
	NotificationsPushTaskAssigned *bool   `json:"notifications_push_task_assigned,omitempty"`
	NotificationsPushTaskDeadline *bool   `json:"notifications_push_task_deadline,omitempty"`
	NotificationsPushTeamMention  *bool   `json:"notifications_push_team_mention,omitempty"`
}

// --- Конвертеры ---

// ToUserProfileResponse конвертирует GORM модели gouser.User и gouser.UserSetting в DTO UserProfileResponse.
// s3BaseURLForAvatars это https://{ENDPOINT}/{BUCKET_NAME}
func ToUserProfileResponse(user *gouser.User, settings *gouser.UserSetting, s3BaseURLForAvatars string) *UserProfileResponse {
	if user == nil { // Если нет пользователя, то и настроек быть не должно
		return nil
	}

	var avatarFinalURL *string
	if user.AvatarS3Key != nil && *user.AvatarS3Key != "" && s3BaseURLForAvatars != "" {
		cleanBaseURL := strings.TrimSuffix(s3BaseURLForAvatars, "/")
		cleanKey := strings.TrimPrefix(*user.AvatarS3Key, "/")
		urlValue := cleanBaseURL + "/" + cleanKey
		avatarFinalURL = &urlValue
	}

	// Если settings nil (на случай, если триггер не сработал или данные неполные), используем дефолты
	theme := "system"
	accentColor := "#007AFF"
	sidebarCollapsed := false
	notificationsEmailEnabled := false // По дефолту false
	notificationsPushTaskAssigned := false
	notificationsPushTaskDeadline := false
	notificationsPushTeamMention := false

	if settings != nil {
		theme = settings.Theme
		accentColor = settings.AccentColor
		sidebarCollapsed = settings.SidebarCollapsed
		notificationsEmailEnabled = settings.NotificationsEmailEnabled
		notificationsPushTaskAssigned = settings.NotificationsPushTaskAssigned
		notificationsPushTaskDeadline = settings.NotificationsPushTaskDeadline
		notificationsPushTeamMention = settings.NotificationsPushTeamMention
	}

	return &UserProfileResponse{
		UserID:                        user.UserId,
		Login:                         user.Login,
		Email:                         user.Email,
		AvatarURL:                     avatarFinalURL,
		Theme:                         theme,
		AccentColor:                   accentColor,
		IsSidebarCollapsed:            sidebarCollapsed,
		HasMobileDeviceLinked:         user.HasMobileDeviceLinked,
		NotificationsEmailEnabled:     notificationsEmailEnabled,
		NotificationsPushTaskAssigned: notificationsPushTaskAssigned,
		NotificationsPushTaskDeadline: notificationsPushTaskDeadline,
		NotificationsPushTeamMention:  notificationsPushTeamMention,
	}
}

// ApplyUpdateToUserAndSettings применяет изменения из UpdateUserProfileRequest
// к GORM моделям User и UserSetting.
// s3KeyForAvatar: ключ нового аватара, или nil для сброса/отсутствия изменений в аватаре.
func ApplyUpdateToUserAndSettings(
	existingUser *gouser.User,
	existingSettings *gouser.UserSetting,
	req *UpdateUserProfileRequest,
	s3KeyForAvatar *string,
) (userChanged bool, settingsChanged bool) {
	if existingUser == nil || existingSettings == nil {
		return false, false
	}

	uChanged := false
	sChanged := false

	if req.Login != nil && *req.Login != existingUser.Login {
		existingUser.Login = *req.Login
		uChanged = true
	}
	// Обработка аватара
	if s3KeyForAvatar != existingUser.AvatarS3Key { // Сравниваем указатели и значения
		if (s3KeyForAvatar == nil && existingUser.AvatarS3Key != nil) ||
			(s3KeyForAvatar != nil && existingUser.AvatarS3Key == nil) ||
			(s3KeyForAvatar != nil && existingUser.AvatarS3Key != nil && *s3KeyForAvatar != *existingUser.AvatarS3Key) {
			existingUser.AvatarS3Key = s3KeyForAvatar
			uChanged = true
		}
	}

	// Обновление UserSettings
	if req.Theme != nil && *req.Theme != existingSettings.Theme {
		existingSettings.Theme = *req.Theme
		sChanged = true
	}
	if req.AccentColor != nil && *req.AccentColor != existingSettings.AccentColor {
		existingSettings.AccentColor = *req.AccentColor
		sChanged = true
	}
	if req.IsSidebarCollapsed != nil && *req.IsSidebarCollapsed != existingSettings.SidebarCollapsed {
		existingSettings.SidebarCollapsed = *req.IsSidebarCollapsed
		sChanged = true
	}
	if req.NotificationsEmailEnabled != nil && *req.NotificationsEmailEnabled != existingSettings.NotificationsEmailEnabled {
		existingSettings.NotificationsEmailEnabled = *req.NotificationsEmailEnabled
		sChanged = true
	}
	if req.NotificationsPushTaskAssigned != nil && *req.NotificationsPushTaskAssigned != existingSettings.NotificationsPushTaskAssigned {
		existingSettings.NotificationsPushTaskAssigned = *req.NotificationsPushTaskAssigned
		sChanged = true
	}
	if req.NotificationsPushTaskDeadline != nil && *req.NotificationsPushTaskDeadline != existingSettings.NotificationsPushTaskDeadline {
		existingSettings.NotificationsPushTaskDeadline = *req.NotificationsPushTaskDeadline
		sChanged = true
	}
	if req.NotificationsPushTeamMention != nil && *req.NotificationsPushTeamMention != existingSettings.NotificationsPushTeamMention {
		existingSettings.NotificationsPushTeamMention = *req.NotificationsPushTeamMention
		sChanged = true
	}
	// Поле HasMobileDeviceLinked не обновляется через этот DTO для PUT, оно для PATCH или спец. эндпоинта

	return uChanged, sChanged
}

// ApplyPatchToUserAndSettings применяет изменения из PatchUserProfileRequest
// к GORM моделям User и UserSetting.
func ApplyPatchToUserAndSettings(
	existingUser *gouser.User,
	existingSettings *gouser.UserSetting,
	req *PatchUserProfileRequest, // Для PATCH запроса
	s3KeyForAvatar *string, // nil если аватар не меняется или сбрасывается (если req.ResetAvatar=true)
) (userChanged bool, settingsChanged bool) {
	if existingUser == nil || existingSettings == nil || req == nil {
		return false, false
	}

	uChanged := false
	sChanged := false

	if req.Login != nil {
		if *req.Login != existingUser.Login {
			existingUser.Login = *req.Login
			uChanged = true
		}
	}

	// Обработка аватара для PATCH:
	// Если req.ResetAvatar == true, s3KeyForAvatar должен быть nil (устанавливается в UseCase)
	// Если s3KeyForAvatar не nil, значит загружен новый файл.
	if req.ResetAvatar != nil && *req.ResetAvatar { // Если пришел флаг сброса
		if existingUser.AvatarS3Key != nil {
			existingUser.AvatarS3Key = nil
			uChanged = true
		}
	} else if s3KeyForAvatar != nil { // Если есть новый ключ (т.е. был загружен файл)
		if existingUser.AvatarS3Key == nil || *s3KeyForAvatar != *existingUser.AvatarS3Key {
			existingUser.AvatarS3Key = s3KeyForAvatar
			uChanged = true
		}
	}
	// Если req.ResetAvatar не пришел и s3KeyForAvatar тоже nil, значит аватар не менялся.

	// Обновление UserSettings
	if req.Theme != nil {
		if *req.Theme != existingSettings.Theme {
			existingSettings.Theme = *req.Theme
			sChanged = true
		}
	}
	if req.AccentColor != nil {
		if *req.AccentColor != existingSettings.AccentColor {
			existingSettings.AccentColor = *req.AccentColor
			sChanged = true
		}
	}
	if req.IsSidebarCollapsed != nil {
		if *req.IsSidebarCollapsed != existingSettings.SidebarCollapsed {
			existingSettings.SidebarCollapsed = *req.IsSidebarCollapsed
			sChanged = true
		}
	}
	if req.HasMobileDeviceLinked != nil { // Обновление HasMobileDeviceLinked
		if *req.HasMobileDeviceLinked != existingUser.HasMobileDeviceLinked {
			existingUser.HasMobileDeviceLinked = *req.HasMobileDeviceLinked
			uChanged = true
		}
	}
	if req.NotificationsEmailEnabled != nil {
		if *req.NotificationsEmailEnabled != existingSettings.NotificationsEmailEnabled {
			existingSettings.NotificationsEmailEnabled = *req.NotificationsEmailEnabled
			sChanged = true
		}
	}
	if req.NotificationsPushTaskAssigned != nil {
		if *req.NotificationsPushTaskAssigned != existingSettings.NotificationsPushTaskAssigned {
			existingSettings.NotificationsPushTaskAssigned = *req.NotificationsPushTaskAssigned
			sChanged = true
		}
	}
	if req.NotificationsPushTaskDeadline != nil {
		if *req.NotificationsPushTaskDeadline != existingSettings.NotificationsPushTaskDeadline {
			existingSettings.NotificationsPushTaskDeadline = *req.NotificationsPushTaskDeadline
			sChanged = true
		}
	}
	if req.NotificationsPushTeamMention != nil {
		if *req.NotificationsPushTeamMention != existingSettings.NotificationsPushTeamMention {
			existingSettings.NotificationsPushTeamMention = *req.NotificationsPushTeamMention
			sChanged = true
		}
	}

	return uChanged, sChanged
}

// --- Интерфейсы для модуля profile ---

type Controller interface {
	GetUser(w http.ResponseWriter, r *http.Request)
	UpdateUser(w http.ResponseWriter, r *http.Request) // Будет PUT
	PatchUser(w http.ResponseWriter, r *http.Request)  // <<< НОВЫЙ PATCH
	DeleteUser(w http.ResponseWriter, r *http.Request)
}

type UseCase interface {
	GetUser(userId uint) (*UserProfileResponse, error)
	UpdateUser(userID uint, req *UpdateUserProfileRequest, avatarFile *multipart.FileHeader) (*UserProfileResponse, error) // Изменил avatarFile на FileHeader
	PatchUser(userID uint, req *PatchUserProfileRequest, avatarFile *multipart.FileHeader) (*UserProfileResponse, error)   // <<< НОВЫЙ PATCH
	DeleteUser(userId uint) error
	// SetMobileDeviceLinked(userID uint, linked bool) error // Может понадобиться отдельный метод
}

type Repo interface {
	//db
	GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error)
	UpdateUser(user *gouser.User) error
	UpdateUserSettings(settings *gouser.UserSetting) error
	DeleteUser(userId uint) error
	//s3
	UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) (err error)
	DeleteAvatar(bucketName string, s3Key string) error
}
