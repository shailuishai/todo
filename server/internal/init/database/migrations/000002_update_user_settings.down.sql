-- Возвращаем старые столбцы
ALTER TABLE UserSettings
    ADD COLUMN notifications_email_enabled BOOLEAN,
    ADD COLUMN notifications_push_task_assigned BOOLEAN,
    ADD COLUMN notifications_push_task_deadline BOOLEAN;

-- Пытаемся восстановить данные для старых столбцов из новых
UPDATE UserSettings
SET notifications_email_enabled = CASE
    WHEN notifications_email_channel = 'never' THEN FALSE
    ELSE TRUE -- 'always' и 'important' считаем как включенные
END;

UPDATE UserSettings
SET notifications_push_task_assigned = CASE
    WHEN notifications_push_channel_tasks = 'none' THEN FALSE
    ELSE TRUE -- 'all' и 'my_tasks' считаем как включенные
END;

UPDATE UserSettings
SET notifications_push_task_deadline = notifications_push_task_deadline_reminder_enabled;
-- Данные о notifications_push_task_deadline_reminder_time будут утеряны при откате

-- Устанавливаем значения по умолчанию для NOT NULL столбцов, чтобы избежать ошибок при удалении новых
-- Это необходимо, если в новой схеме эти поля были NOT NULL, а в старой они могли быть NULL
-- или если мы хотим установить какие-то осмысленные значения по умолчанию перед удалением новых полей.
-- Однако, если старые поля могли быть NULL, то значения по умолчанию не так критичны.
-- Для простоты, если старые поля были BOOLEAN DEFAULT FALSE, то ничего дополнительно делать не нужно.
-- Если они были просто BOOLEAN (nullable), то после восстановления данных из новых полей
-- те записи, для которых не нашлось соответствия, останутся NULL.
-- Для примера, установим дефолты, как в изначальной таблице:
UPDATE UserSettings SET notifications_email_enabled = COALESCE(notifications_email_enabled, FALSE);
UPDATE UserSettings SET notifications_push_task_assigned = COALESCE(notifications_push_task_assigned, FALSE);
UPDATE UserSettings SET notifications_push_task_deadline = COALESCE(notifications_push_task_deadline, FALSE);

-- Делаем старые столбцы NOT NULL с DEFAULT, как было в оригинальной схеме
ALTER TABLE UserSettings
    ALTER COLUMN notifications_email_enabled SET DEFAULT FALSE,
    ALTER COLUMN notifications_email_enabled SET NOT NULL,
    ALTER COLUMN notifications_push_task_assigned SET DEFAULT FALSE,
    ALTER COLUMN notifications_push_task_assigned SET NOT NULL,
    ALTER COLUMN notifications_push_task_deadline SET DEFAULT FALSE,
    ALTER COLUMN notifications_push_task_deadline SET NOT NULL;


-- Удаляем новые столбцы
ALTER TABLE UserSettings
    DROP COLUMN notifications_email_channel,
    DROP COLUMN notifications_push_channel_tasks,
    DROP COLUMN notifications_push_sound_enabled,
    DROP COLUMN notifications_push_vibration_enabled,
    DROP COLUMN notifications_push_task_comment,
    DROP COLUMN notifications_push_task_deadline_reminder_enabled,
    DROP COLUMN notifications_push_task_deadline_reminder_time;

-- Обновляем триггер для updated_at (если он был изменен)
DROP TRIGGER IF EXISTS trigger_user_settings_updated_at ON UserSettings;
CREATE TRIGGER trigger_user_settings_updated_at
    BEFORE UPDATE ON UserSettings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();