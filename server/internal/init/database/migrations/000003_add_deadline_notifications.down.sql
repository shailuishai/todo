-- Новая миграция
ALTER TABLE Tasks
    ADD COLUMN deadline_notification_sent_at TIMESTAMP WITH TIME ZONE;