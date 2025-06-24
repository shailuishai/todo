-- 000004_add_indexes.up.sql

-- Индексы для внешних ключей и часто используемых полей

-- Таблица UserTeamMemberships (уже есть PK, но добавим индекс на team_id для быстрого поиска участников команды)
CREATE INDEX IF NOT EXISTS idx_userteammemberships_team_id ON UserTeamMemberships(team_id);

-- Таблица Tasks
CREATE INDEX IF NOT EXISTS idx_tasks_team_id ON Tasks(team_id);
CREATE INDEX IF NOT EXISTS idx_tasks_created_by_user_id ON Tasks(created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to_user_id ON Tasks(assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON Tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_is_deleted_deadline ON Tasks(is_deleted, deadline) WHERE deadline IS NOT NULL; -- Композитный индекс для поиска по дедлайнам

-- Таблица UserTags
CREATE INDEX IF NOT EXISTS idx_usertags_owner_user_id ON UserTags(owner_user_id);

-- Таблица TeamTags
CREATE INDEX IF NOT EXISTS idx_teamtags_team_id ON TeamTags(team_id);

-- Таблица TaskTags (самая важная для JOIN'ов)
CREATE INDEX IF NOT EXISTS idx_tasktags_task_id ON TaskTags(task_id);
CREATE INDEX IF NOT EXISTS idx_tasktags_user_tag_id ON TaskTags(user_tag_id) WHERE user_tag_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasktags_team_tag_id ON TaskTags(team_tag_id) WHERE team_tag_id IS NOT NULL;

-- Таблица ChatMessages
CREATE INDEX IF NOT EXISTS idx_chatmessages_team_id_sent_at ON ChatMessages(team_id, sent_at DESC); -- Для быстрой загрузки истории чата
CREATE INDEX IF NOT EXISTS idx_chatmessages_sender_user_id ON ChatMessages(sender_user_id);

-- Таблица Teams
CREATE INDEX IF NOT EXISTS idx_teams_created_by_user_id ON Teams(created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_teams_name_lower ON Teams (lower(name) text_pattern_ops); -- Для быстрого поиска по имени без учета регистра