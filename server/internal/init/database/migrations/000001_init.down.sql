-- Удаляем триггер и функцию для UserSettings (если они специфичны только для UserSettings)
DROP TRIGGER IF EXISTS trigger_after_user_insert ON Users;
DROP FUNCTION IF EXISTS create_default_user_settings();

-- Удаляем триггеры updated_at
DROP TRIGGER IF EXISTS trigger_chat_messages_updated_at ON ChatMessages;
DROP TRIGGER IF EXISTS trigger_team_tags_updated_at ON TeamTags;
DROP TRIGGER IF EXISTS trigger_user_tags_updated_at ON UserTags;
DROP TRIGGER IF EXISTS trigger_tasks_updated_at ON Tasks;
DROP TRIGGER IF EXISTS trigger_teams_updated_at ON Teams;
DROP TRIGGER IF EXISTS trigger_user_settings_updated_at ON UserSettings;
DROP TRIGGER IF EXISTS trigger_users_updated_at ON Users;

-- Удаляем общую триггерную функцию updated_at
DROP FUNCTION IF EXISTS update_updated_at_column();

-- Удаляем таблицы в обратном порядке их создания (из-за внешних ключей)
DROP TABLE IF EXISTS ChatMessages;
DROP TABLE IF EXISTS TaskTags;
DROP TABLE IF EXISTS TeamTags;
DROP TABLE IF EXISTS UserTags;
DROP TABLE IF EXISTS Tasks;
DROP TABLE IF EXISTS UserTeamMemberships;
DROP TABLE IF EXISTS Teams;
DROP TABLE IF EXISTS UserSettings;
DROP TABLE IF EXISTS Users;

-- Удаляем тип team_member_role
DROP TYPE IF EXISTS team_member_role;