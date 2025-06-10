package user

import (
	"time"
)

// --- ENUM Типы для Настроек Уведомлений ---
// ... (без изменений, как ты предоставил) ...
type NotificationLevel string

const (
	NotificationLevelAll       NotificationLevel = "all"
	NotificationLevelImportant NotificationLevel = "important"
	NotificationLevelNone      NotificationLevel = "none"
)

type PushTaskNotificationLevel string

const (
	PushTaskNotificationLevelAll     PushTaskNotificationLevel = "all"
	PushTaskNotificationLevelMyTasks PushTaskNotificationLevel = "my_tasks"
	PushTaskNotificationLevelNone    PushTaskNotificationLevel = "none"
)

type DeadlineReminderPreference string

const (
	DeadlineReminderPreferenceOneHour DeadlineReminderPreference = "one_hour"
	DeadlineReminderPreferenceOneDay  DeadlineReminderPreference = "one_day"
	DeadlineReminderPreferenceTwoDays DeadlineReminderPreference = "two_days"
)

// User - основная GORM модель для таблицы 'users'
// ... (без изменений, как ты предоставил) ...
type User struct {
	UserId                uint        `gorm:"primaryKey;column:user_id;autoIncrement"`
	Login                 string      `gorm:"type:varchar(50);uniqueIndex;not null;column:login"`
	Email                 string      `gorm:"type:varchar(100);uniqueIndex;not null;column:email"`
	PasswordHash          *string     `gorm:"type:varchar(255);column:password_hash"`
	AvatarS3Key           *string     `gorm:"type:varchar(255);column:avatar_s3_key"`
	IsAdmin               bool        `gorm:"default:false;not null;column:is_admin"`
	VerifiedEmail         bool        `gorm:"default:false;not null;column:verified_email"`
	HasMobileDeviceLinked bool        `gorm:"default:false;not null;column:has_mobile_device_linked"`
	CreatedAt             time.Time   `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	UpdatedAt             time.Time   `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
	LastLoginAt           *time.Time  `gorm:"column:last_login_at"`
	Settings              UserSetting `gorm:"foreignKey:UserId;references:UserId"`
}

func (User) TableName() string {
	return "users"
}

// UserSetting - GORM модель для таблицы 'usersettings'
// ... (без изменений, как ты предоставил) ...
type UserSetting struct {
	UserId                             uint                       `gorm:"primaryKey;column:user_id"`
	Theme                              string                     `gorm:"type:varchar(20);default:'system';not null;column:theme"`
	AccentColor                        string                     `gorm:"type:varchar(7);default:'#007AFF';not null;column:accent_color"`
	SidebarCollapsed                   bool                       `gorm:"default:false;not null;column:sidebar_collapsed"`
	UpdatedAt                          time.Time                  `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
	EmailNotificationsLevel            NotificationLevel          `gorm:"type:notification_level_enum;default:'important';not null;column:email_notifications_level"`
	PushNotificationsTasksLevel        PushTaskNotificationLevel  `gorm:"type:push_task_notification_level_enum;default:'my_tasks';not null;column:push_notifications_tasks_level"`
	PushNotificationsChatMentions      bool                       `gorm:"default:true;not null;column:push_notifications_chat_mentions"`
	TaskDeadlineRemindersEnabled       bool                       `gorm:"default:true;not null;column:task_deadline_reminders_enabled"`
	TaskDeadlineReminderTimePreference DeadlineReminderPreference `gorm:"type:deadline_reminder_preference_enum;default:'one_day';not null;column:task_deadline_reminder_time_preference"`
}

func (UserSetting) TableName() string {
	return "usersettings"
}

// UserDeviceToken - GORM модель для таблицы 'userdevicetokens'
type UserDeviceToken struct {
	DeviceTokenID uint      `gorm:"primaryKey;column:device_token_id;autoIncrement"`
	UserID        uint      `gorm:"column:user_id;not null"` // Внешний ключ к Users.user_id
	DeviceToken   string    `gorm:"column:device_token;type:text;unique;not null"`
	DeviceType    string    `gorm:"column:device_type;type:varchar(10);not null"` // 'android', 'ios', 'web'
	CreatedAt     time.Time `gorm:"column:created_at;not null;default:CURRENT_TIMESTAMP"`
	LastSeenAt    time.Time `gorm:"column:last_seen_at;not null;default:CURRENT_TIMESTAMP"`

	// User User `gorm:"foreignKey:UserID"` // Связь, если нужна для GORM запросов
}

func (UserDeviceToken) TableName() string {
	return "userdevicetokens"
}
