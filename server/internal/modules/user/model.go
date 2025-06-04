package user

import (
	"time"
)

// User - основная GORM модель для таблицы 'users'
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

// TableName явно указывает GORM имя таблицы
func (User) TableName() string {
	return "users"
}

// UserSetting - GORM модель для таблицы 'user_settings'
type UserSetting struct {
	UserId                        uint      `gorm:"primaryKey;column:user_id"`
	Theme                         string    `gorm:"type:varchar(20);default:'system';not null;column:theme"`
	AccentColor                   string    `gorm:"type:varchar(7);default:'#007AFF';not null;column:accent_color"`
	SidebarCollapsed              bool      `gorm:"default:false;not null;column:sidebar_collapsed"`
	NotificationsEmailEnabled     bool      `gorm:"default:false;not null;column:notifications_email_enabled"`
	NotificationsPushTaskAssigned bool      `gorm:"default:false;not null;column:notifications_push_task_assigned"`
	NotificationsPushTaskDeadline bool      `gorm:"default:false;not null;column:notifications_push_task_deadline"`
	NotificationsPushTeamMention  bool      `gorm:"default:false;not null;column:notifications_push_team_mention"`
	UpdatedAt                     time.Time `gorm:"column:updated_at;not null;default:CURRENT_TIMESTAMP"`
}

// TableName явно указывает GORM имя таблицы
func (UserSetting) TableName() string {
	return "usersettings"
}
