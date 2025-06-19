-- Новая миграция
ALTER TABLE Tasks
    DROP COLUMN IF EXISTS deadline_notification_sent_at;