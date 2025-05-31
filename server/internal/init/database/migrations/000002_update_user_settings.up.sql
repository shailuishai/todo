-- Добавляем новые столбцы для детализированных настроек уведомлений
ALTER TABLE UserSettings
    ADD COLUMN notifications_email_channel VARCHAR(20) DEFAULT 'important' NOT NULL,
    ADD COLUMN notifications_push_channel_tasks VARCHAR(20) DEFAULT 'my_tasks' NOT NULL,
    ADD COLUMN notifications_push_sound_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN notifications_push_vibration_enabled BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN notifications_push_task_comment BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN notifications_push_task_deadline_reminder_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN notifications_push_task_deadline_reminder_time VARCHAR(20) DEFAULT 'one_day_before' NOT NULL;

-- Миграция данных из старых столбцов в новые (примерная логика)
-- Для notifications_email_channel:
-- Если notifications_email_enabled было TRUE, ставим 'always' (или 'important' по умолчанию)
-- Если было FALSE, ставим 'never'
UPDATE UserSettings
SET notifications_email_channel = CASE
    WHEN notifications_email_enabled = TRUE THEN 'important' -- или 'always', если это более подходящее значение по умолчанию для включенного состояния
    ELSE 'never'
END;

-- Для notifications_push_channel_tasks:
-- Если notifications_push_task_assigned было TRUE, ставим 'my_tasks' (или 'all')
-- Если FALSE, ставим 'none'
UPDATE UserSettings
SET notifications_push_channel_tasks = CASE
    WHEN notifications_push_task_assigned = TRUE THEN 'my_tasks' -- или 'all'
    ELSE 'none'
END;

-- Для notifications_push_task_deadline_reminder_enabled:
-- Если notifications_push_task_deadline было TRUE, ставим TRUE
UPDATE UserSettings
SET notifications_push_task_deadline_reminder_enabled = notifications_push_task_deadline;
-- notifications_push_task_deadline_reminder_time останется со значением по умолчанию 'one_day_before'
-- так как у нас не было информации о конкретном времени ранее.

-- Удаляем старые столбцы, которые были заменены
ALTER TABLE UserSettings
    DROP COLUMN notifications_email_enabled,
    DROP COLUMN notifications_push_task_assigned,
    DROP COLUMN notifications_push_task_deadline;

-- Обновляем триггер для updated_at, если он был удален или изменен при ALTER TABLE
-- (Обычно ALTER TABLE не удаляет триггеры, но на всякий случай, если имя таблицы менялось или что-то подобное)
-- Если триггер уже существует и работает, эта часть не обязательна.
DROP TRIGGER IF EXISTS trigger_user_settings_updated_at ON UserSettings;
CREATE TRIGGER trigger_user_settings_updated_at
    BEFORE UPDATE ON UserSettings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Добавляем комментарии к новым столбцам для ясности (опционально, но полезно)
COMMENT ON COLUMN UserSettings.notifications_email_channel IS 'Email notifications: always, important, never';
COMMENT ON COLUMN UserSettings.notifications_push_channel_tasks IS 'Push notifications for tasks: all, my_tasks, none';
COMMENT ON COLUMN UserSettings.notifications_push_sound_enabled IS 'Enable sound for push notifications';
COMMENT ON COLUMN UserSettings.notifications_push_vibration_enabled IS 'Enable vibration for push notifications';
COMMENT ON COLUMN UserSettings.notifications_push_task_comment IS 'Push for new comments on tasks';
COMMENT ON COLUMN UserSettings.notifications_push_task_deadline_reminder_enabled IS 'Enable push for task deadline reminders';
COMMENT ON COLUMN UserSettings.notifications_push_task_deadline_reminder_time IS 'Time for deadline reminder: e.g., one_hour_before, one_day_before';