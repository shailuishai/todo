-- 002_add_chat_and_notifications_down.sql

-- Удаляем таблицы в обратном порядке их создания
DROP TABLE IF EXISTS UserDeviceTokens;
DROP TABLE IF EXISTS MessageReadReceipts;

-- Возвращаем UserSettings к предыдущему состоянию
-- Это сложнее, так как данные могут быть потеряны или потребуют сложной логики обратного преобразования.
-- Для простоты, мы удалим новые поля и попытаемся вернуть старые (без гарантии сохранения данных).
ALTER TABLE UserSettings
    DROP COLUMN IF EXISTS email_notifications_level,
    DROP COLUMN IF EXISTS push_notifications_tasks_level,
    DROP COLUMN IF EXISTS push_notifications_chat_mentions,
    DROP COLUMN IF EXISTS task_deadline_reminders_enabled,
    DROP COLUMN IF EXISTS task_deadline_reminder_time_preference;

-- Попытка вернуть старые поля UserSettings (значения по умолчанию могут отличаться от исходных)
ALTER TABLE UserSettings
    ADD COLUMN IF NOT EXISTS notifications_email_enabled BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN IF NOT EXISTS notifications_push_task_assigned BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN IF NOT EXISTS notifications_push_task_deadline BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN IF NOT EXISTS notifications_push_team_mention BOOLEAN DEFAULT FALSE NOT NULL;

-- Удаляем ENUM типы
DROP TYPE IF EXISTS deadline_reminder_preference_enum;
DROP TYPE IF EXISTS push_task_notification_level_enum;
DROP TYPE IF EXISTS notification_level_enum;


-- Возвращаем изменения в ChatMessages
ALTER TABLE ChatMessages
    DROP COLUMN IF EXISTS edited_at,
    DROP COLUMN IF EXISTS reply_to_message_id;

ALTER TABLE ChatMessages
    RENAME COLUMN sender_user_id TO user_id;

-- Триггеры и функции, если они были специфичны для этих изменений,
-- но update_updated_at_column и create_default_user_settings являются общими
-- и не должны удаляться здесь, если они используются другими частями схемы,
-- созданными в 001_initial_schema_up.sql.
-- Если бы мы добавили специфический триггер для UserDeviceTokens, мы бы его здесь удалили.
-- Например:
-- DROP TRIGGER IF EXISTS trigger_user_device_tokens_updated_at ON UserDeviceTokens;