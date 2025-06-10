package profile

import (
	"context"
	"mime/multipart"
	"net/http"
	gouser "server/internal/modules/user" // GORM модели User и UserSetting
	"strings"
)

// UserProfileResponse - DTO для ответа GetUser
type UserProfileResponse struct {
	UserID                             uint                              `json:"user_id"`
	Login                              string                            `json:"login"`
	Email                              string                            `json:"email"`
	AvatarURL                          *string                           `json:"avatar_url,omitempty"`
	Theme                              string                            `json:"theme"`
	AccentColor                        string                            `json:"accent_color"`
	IsSidebarCollapsed                 bool                              `json:"is_sidebar_collapsed"`
	HasMobileDeviceLinked              bool                              `json:"has_mobile_device_linked"`
	EmailNotificationsLevel            gouser.NotificationLevel          `json:"email_notifications_level"`
	PushNotificationsTasksLevel        gouser.PushTaskNotificationLevel  `json:"push_notifications_tasks_level"`
	PushNotificationsChatMentions      bool                              `json:"push_notifications_chat_mentions"`
	TaskDeadlineRemindersEnabled       bool                              `json:"task_deadline_reminders_enabled"`
	TaskDeadlineReminderTimePreference gouser.DeadlineReminderPreference `json:"task_deadline_reminder_time_preference"`
}

type UpdateUserProfileRequest struct {
	Login                              *string                            `json:"login,omitempty" validate:"omitempty,min=1,max=50"`
	Theme                              *string                            `json:"theme,omitempty" validate:"omitempty,oneof=light dark system"`
	AccentColor                        *string                            `json:"accent_color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
	IsSidebarCollapsed                 *bool                              `json:"is_sidebar_collapsed,omitempty"`
	ResetAvatar                        *bool                              `json:"reset_avatar,omitempty"`
	EmailNotificationsLevel            *gouser.NotificationLevel          `json:"email_notifications_level,omitempty" validate:"omitempty,oneof=all important none"`
	PushNotificationsTasksLevel        *gouser.PushTaskNotificationLevel  `json:"push_notifications_tasks_level,omitempty" validate:"omitempty,oneof=all my_tasks none"`
	PushNotificationsChatMentions      *bool                              `json:"push_notifications_chat_mentions,omitempty"`
	TaskDeadlineRemindersEnabled       *bool                              `json:"task_deadline_reminders_enabled,omitempty"`
	TaskDeadlineReminderTimePreference *gouser.DeadlineReminderPreference `json:"task_deadline_reminder_time_preference,omitempty" validate:"omitempty,oneof=one_hour one_day two_days"`
}

type PatchUserProfileRequest struct {
	Login                              *string                            `json:"login,omitempty" validate:"omitempty,min=1,max=50"`
	Theme                              *string                            `json:"theme,omitempty" validate:"omitempty,oneof=light dark system"`
	AccentColor                        *string                            `json:"accent_color,omitempty" validate:"omitempty,hexcolor|rgb|rgba"`
	IsSidebarCollapsed                 *bool                              `json:"is_sidebar_collapsed,omitempty"`
	ResetAvatar                        *bool                              `json:"reset_avatar,omitempty"`
	HasMobileDeviceLinked              *bool                              `json:"has_mobile_device_linked,omitempty"`
	EmailNotificationsLevel            *gouser.NotificationLevel          `json:"email_notifications_level,omitempty" validate:"omitempty,oneof=all important none"`
	PushNotificationsTasksLevel        *gouser.PushTaskNotificationLevel  `json:"push_notifications_tasks_level,omitempty" validate:"omitempty,oneof=all my_tasks none"`
	PushNotificationsChatMentions      *bool                              `json:"push_notifications_chat_mentions,omitempty"`
	TaskDeadlineRemindersEnabled       *bool                              `json:"task_deadline_reminders_enabled,omitempty"`
	TaskDeadlineReminderTimePreference *gouser.DeadlineReminderPreference `json:"task_deadline_reminder_time_preference,omitempty" validate:"omitempty,oneof=one_hour one_day two_days"`
}

type RegisterDeviceTokenRequest struct {
	DeviceToken string `json:"device_token" validate:"required"`
	DeviceType  string `json:"device_type" validate:"required,oneof=android ios web"`
}

// UnregisterDeviceTokenRequest - DTO для удаления токена устройства.
type UnregisterDeviceTokenRequest struct {
	DeviceToken string `json:"device_token" validate:"required"`
}

// --- Конвертеры ---

// ToUserProfileResponse конвертирует GORM модели gouser.User и gouser.UserSetting в DTO UserProfileResponse.
func ToUserProfileResponse(user *gouser.User, settings *gouser.UserSetting, s3BaseURLForAvatars string) *UserProfileResponse {
	if user == nil {
		return nil
	}
	var avatarFinalURL *string
	if user.AvatarS3Key != nil && *user.AvatarS3Key != "" && s3BaseURLForAvatars != "" {
		cleanBaseURL := strings.TrimSuffix(s3BaseURLForAvatars, "/")
		cleanKey := strings.TrimPrefix(*user.AvatarS3Key, "/")
		urlValue := cleanBaseURL + "/" + cleanKey
		avatarFinalURL = &urlValue
	}
	theme := "system"
	accentColor := "#007AFF"
	sidebarCollapsed := false
	emailLevel := gouser.NotificationLevelImportant
	pushTasksLevel := gouser.PushTaskNotificationLevelMyTasks
	pushChatMentions := true
	deadlineRemindersEnabled := true
	deadlinePref := gouser.DeadlineReminderPreferenceOneDay

	if settings != nil {
		theme = settings.Theme
		accentColor = settings.AccentColor
		sidebarCollapsed = settings.SidebarCollapsed
		emailLevel = settings.EmailNotificationsLevel
		pushTasksLevel = settings.PushNotificationsTasksLevel
		pushChatMentions = settings.PushNotificationsChatMentions
		deadlineRemindersEnabled = settings.TaskDeadlineRemindersEnabled
		deadlinePref = settings.TaskDeadlineReminderTimePreference
	}
	return &UserProfileResponse{
		UserID: user.UserId, Login: user.Login, Email: user.Email,
		AvatarURL: avatarFinalURL, Theme: theme, AccentColor: accentColor,
		IsSidebarCollapsed: sidebarCollapsed, HasMobileDeviceLinked: user.HasMobileDeviceLinked,
		EmailNotificationsLevel: emailLevel, PushNotificationsTasksLevel: pushTasksLevel,
		PushNotificationsChatMentions: pushChatMentions, TaskDeadlineRemindersEnabled: deadlineRemindersEnabled,
		TaskDeadlineReminderTimePreference: deadlinePref,
	}
}

func ApplyUpdateToUserAndSettings(
	existingUser *gouser.User, existingSettings *gouser.UserSetting,
	req *UpdateUserProfileRequest, s3KeyForAvatar *string,
) (userChanged bool, settingsChanged bool) {
	if existingUser == nil || existingSettings == nil {
		return false, false
	}
	uChanged, sChanged := false, false
	if req.Login != nil && *req.Login != existingUser.Login {
		existingUser.Login = *req.Login
		uChanged = true
	}
	if s3KeyForAvatar != existingUser.AvatarS3Key {
		if (s3KeyForAvatar == nil && existingUser.AvatarS3Key != nil) ||
			(s3KeyForAvatar != nil && existingUser.AvatarS3Key == nil) ||
			(s3KeyForAvatar != nil && existingUser.AvatarS3Key != nil && *s3KeyForAvatar != *existingUser.AvatarS3Key) {
			existingUser.AvatarS3Key = s3KeyForAvatar
			uChanged = true
		}
	}
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
	if req.EmailNotificationsLevel != nil && *req.EmailNotificationsLevel != existingSettings.EmailNotificationsLevel {
		existingSettings.EmailNotificationsLevel = *req.EmailNotificationsLevel
		sChanged = true
	}
	if req.PushNotificationsTasksLevel != nil && *req.PushNotificationsTasksLevel != existingSettings.PushNotificationsTasksLevel {
		existingSettings.PushNotificationsTasksLevel = *req.PushNotificationsTasksLevel
		sChanged = true
	}
	if req.PushNotificationsChatMentions != nil && *req.PushNotificationsChatMentions != existingSettings.PushNotificationsChatMentions {
		existingSettings.PushNotificationsChatMentions = *req.PushNotificationsChatMentions
		sChanged = true
	}
	if req.TaskDeadlineRemindersEnabled != nil && *req.TaskDeadlineRemindersEnabled != existingSettings.TaskDeadlineRemindersEnabled {
		existingSettings.TaskDeadlineRemindersEnabled = *req.TaskDeadlineRemindersEnabled
		sChanged = true
	}
	if req.TaskDeadlineReminderTimePreference != nil && *req.TaskDeadlineReminderTimePreference != existingSettings.TaskDeadlineReminderTimePreference {
		existingSettings.TaskDeadlineReminderTimePreference = *req.TaskDeadlineReminderTimePreference
		sChanged = true
	}
	return uChanged, sChanged
}

func ApplyPatchToUserAndSettings(
	existingUser *gouser.User, existingSettings *gouser.UserSetting,
	req *PatchUserProfileRequest, s3KeyForAvatar *string,
) (userChanged bool, settingsChanged bool) {
	if existingUser == nil || existingSettings == nil || req == nil {
		return false, false
	}
	uChanged, sChanged := false, false
	if req.Login != nil {
		if *req.Login != existingUser.Login {
			existingUser.Login = *req.Login
			uChanged = true
		}
	}
	if req.ResetAvatar != nil && *req.ResetAvatar {
		if existingUser.AvatarS3Key != nil {
			existingUser.AvatarS3Key = nil
			uChanged = true
		}
	} else if s3KeyForAvatar != nil {
		if existingUser.AvatarS3Key == nil || *s3KeyForAvatar != *existingUser.AvatarS3Key {
			existingUser.AvatarS3Key = s3KeyForAvatar
			uChanged = true
		}
	}
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
	if req.HasMobileDeviceLinked != nil {
		if *req.HasMobileDeviceLinked != existingUser.HasMobileDeviceLinked {
			existingUser.HasMobileDeviceLinked = *req.HasMobileDeviceLinked
			uChanged = true
		}
	}
	if req.EmailNotificationsLevel != nil {
		if *req.EmailNotificationsLevel != existingSettings.EmailNotificationsLevel {
			existingSettings.EmailNotificationsLevel = *req.EmailNotificationsLevel
			sChanged = true
		}
	}
	if req.PushNotificationsTasksLevel != nil {
		if *req.PushNotificationsTasksLevel != existingSettings.PushNotificationsTasksLevel {
			existingSettings.PushNotificationsTasksLevel = *req.PushNotificationsTasksLevel
			sChanged = true
		}
	}
	if req.PushNotificationsChatMentions != nil {
		if *req.PushNotificationsChatMentions != existingSettings.PushNotificationsChatMentions {
			existingSettings.PushNotificationsChatMentions = *req.PushNotificationsChatMentions
			sChanged = true
		}
	}
	if req.TaskDeadlineRemindersEnabled != nil {
		if *req.TaskDeadlineRemindersEnabled != existingSettings.TaskDeadlineRemindersEnabled {
			existingSettings.TaskDeadlineRemindersEnabled = *req.TaskDeadlineRemindersEnabled
			sChanged = true
		}
	}
	if req.TaskDeadlineReminderTimePreference != nil {
		if *req.TaskDeadlineReminderTimePreference != existingSettings.TaskDeadlineReminderTimePreference {
			existingSettings.TaskDeadlineReminderTimePreference = *req.TaskDeadlineReminderTimePreference
			sChanged = true
		}
	}
	return uChanged, sChanged
}

// --- Интерфейсы для модуля profile ---
// (Остаются без изменений, т.к. сигнатуры методов контроллера, usecase, repo не меняются из-за этой правки)

type DeviceTokenRepo interface {
	AddDeviceToken(ctx context.Context, token *gouser.UserDeviceToken) error
	RemoveDeviceToken(ctx context.Context, userID uint, deviceTokenValue string) error
	GetDeviceTokensByUserID(ctx context.Context, userID uint) ([]gouser.UserDeviceToken, error)
	UpdateDeviceTokenLastSeen(ctx context.Context, deviceTokenValue string) error
	// GetUserDeviceTokens (для UserSettingsProvider) - это GetDeviceTokensByUserID
}

// Controller (расширяем существующий)
type Controller interface {
	GetUser(w http.ResponseWriter, r *http.Request)
	UpdateUser(w http.ResponseWriter, r *http.Request)
	PatchUser(w http.ResponseWriter, r *http.Request)
	DeleteUser(w http.ResponseWriter, r *http.Request)

	// Новые методы для токенов
	RegisterDeviceToken(w http.ResponseWriter, r *http.Request)
	UnregisterDeviceToken(w http.ResponseWriter, r *http.Request)
}

// UseCase (расширяем существующий)
type UseCase interface {
	GetUser(userId uint) (*UserProfileResponse, error)
	UpdateUser(userID uint, req *UpdateUserProfileRequest, avatarFile *multipart.FileHeader) (*UserProfileResponse, error)
	PatchUser(userID uint, req *PatchUserProfileRequest, avatarFile *multipart.FileHeader) (*UserProfileResponse, error)
	DeleteUser(userId uint) error

	// Новые методы для токенов
	RegisterDeviceToken(ctx context.Context, userID uint, tokenValue string, deviceType string) error
	UnregisterDeviceToken(ctx context.Context, userID uint, tokenValue string) error

	// Методы для UserSettingsProvider (уже часть ProfileUseCase)
	GetUserNotificationSettings(userID uint) (*gouser.UserSetting, error) // Будет частью GetUser, но можно сделать отдельным
	GetUserDeviceTokens(userID uint) ([]gouser.UserDeviceToken, error)
	GetUserEmail(userID uint) (email string, isVerified bool, err error)
}

// Repo (расширяем существующий)
type Repo interface {
	// Методы для User и UserSettings
	GetUserAndSettings(userId uint) (*gouser.User, *gouser.UserSetting, error)
	UpdateUser(user *gouser.User) error
	UpdateUserSettings(settings *gouser.UserSetting) error
	DeleteUser(userId uint) error
	GetUserEmail(userID uint) (email string, isVerified bool, err error) // Для UserInfoProvider

	// Методы для S3
	UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) (err error)
	DeleteAvatar(bucketName string, s3Key string) error

	// Методы для Device Tokens (реализуются через DeviceTokenRepo)
	AddDeviceToken(ctx context.Context, token *gouser.UserDeviceToken) error
	RemoveDeviceToken(ctx context.Context, userID uint, deviceTokenValue string) error
	GetDeviceTokensByUserID(ctx context.Context, userID uint) ([]gouser.UserDeviceToken, error)
	UpdateDeviceTokenLastSeen(ctx context.Context, deviceTokenValue string) error
}
