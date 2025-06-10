-- 002_add_chat_and_notifications_up.sql

-- Обновление таблицы ChatMessages для поддержки ответов и редактирования
-- (В твоем скрипте уже есть updated_at и is_deleted, добавим reply_to_message_id)
-- (Также меняем user_id на sender_user_id для ясности)
ALTER TABLE ChatMessages
    RENAME COLUMN user_id TO sender_user_id;

ALTER TABLE ChatMessages
    ADD COLUMN reply_to_message_id INT REFERENCES ChatMessages(message_id) ON DELETE SET NULL, -- Ссылка на сообщение, на которое отвечают
-- sent_at уже есть
-- updated_at уже есть
-- is_deleted уже есть
-- content уже есть
-- team_id уже есть
    ADD COLUMN edited_at TIMESTAMP WITH TIME ZONE; -- Время последнего редактирования

-- Применяем триггер updated_at, если он был удален или изменен (или создаем, если еще нет для этой таблицы)
-- (Твоя предыдущая миграция уже создавала триггер 'trigger_chat_messages_updated_at',
-- но поле updated_at будет обновляться автоматически при редактировании.
-- Поле edited_at нужно будет выставлять явно при операции редактирования сообщения)

-- Таблица для отслеживания прочтения сообщений пользователями
CREATE TABLE MessageReadReceipts (
                                     message_id INT NOT NULL REFERENCES ChatMessages(message_id) ON DELETE CASCADE,
                                     user_id INT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE, -- Пользователь, который прочитал сообщение
                                     read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                                     PRIMARY KEY (message_id, user_id)
);

-- Обновление таблицы UserSettings для детализированных настроек уведомлений
-- (notifications_email_enabled -> email_notifications_level)
-- (notifications_push_task_assigned -> push_notifications_tasks_level и т.д.)

-- Сначала создадим необходимые ENUM типы для настроек
CREATE TYPE notification_level_enum AS ENUM ('all', 'important', 'none');
CREATE TYPE push_task_notification_level_enum AS ENUM ('all', 'my_tasks', 'none');
CREATE TYPE deadline_reminder_preference_enum AS ENUM ('one_hour', 'one_day', 'two_days'); -- 'За час', 'За день', 'За 2 дня'

-- Удаляем старые булевы поля, если они есть, и добавляем новые с ENUM
-- Важно: При реальной миграции нужно будет перенести данные из старых полей в новые, если это возможно.
-- Здесь для простоты просто удаляем и добавляем.
ALTER TABLE UserSettings
    DROP COLUMN IF EXISTS notifications_email_enabled,
    DROP COLUMN IF EXISTS notifications_push_task_assigned,
    DROP COLUMN IF EXISTS notifications_push_task_deadline,
    DROP COLUMN IF EXISTS notifications_push_team_mention;

ALTER TABLE UserSettings
    ADD COLUMN email_notifications_level notification_level_enum DEFAULT 'important' NOT NULL,
    ADD COLUMN push_notifications_tasks_level push_task_notification_level_enum DEFAULT 'my_tasks' NOT NULL,
    ADD COLUMN push_notifications_chat_mentions BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN task_deadline_reminders_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN task_deadline_reminder_time_preference deadline_reminder_preference_enum DEFAULT 'one_day' NOT NULL;

-- Таблица для хранения Push-токенов устройств пользователей
CREATE TABLE UserDeviceTokens (
                                  device_token_id SERIAL PRIMARY KEY,
                                  user_id INT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
                                  device_token TEXT UNIQUE NOT NULL, -- Токен, полученный от FCM/APNS
                                  device_type VARCHAR(10) NOT NULL, -- 'android', 'ios', 'web'
                                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                                  last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL -- Обновляется при каждом использовании/проверке токена
);

-- Индекс для быстрого поиска токенов по user_id
CREATE INDEX idx_user_device_tokens_user_id ON UserDeviceTokens(user_id);


-- Обновление общей триггерной функции, если она была удалена (на всякий случай)
CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- Применение триггера к новым таблицам или если он был удален
-- Для UserSettings он уже был, проверим
DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_user_settings_updated_at') THEN
            CREATE TRIGGER trigger_user_settings_updated_at BEFORE UPDATE ON UserSettings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
        END IF;
    END
$$;

-- Для ChatMessages триггер уже должен быть из прошлой миграции.
-- Для UserDeviceTokens добавим updated_at и триггер, если он нужен.
-- В данном случае last_seen_at более специфичен. Если нужен общий updated_at:
-- ALTER TABLE UserDeviceTokens ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL;
-- CREATE TRIGGER trigger_user_device_tokens_updated_at BEFORE UPDATE ON UserDeviceTokens FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Функция для автоматического создания UserSettings, если она была удалена (на всякий случай)
CREATE OR REPLACE FUNCTION create_default_user_settings()
    RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO UserSettings (user_id) VALUES (NEW.user_id);
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- Применение триггера, если он был удален
DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_after_user_insert') THEN
            CREATE TRIGGER trigger_after_user_insert
                AFTER INSERT ON Users
                FOR EACH ROW EXECUTE FUNCTION create_default_user_settings();
        END IF;
    END
$$;