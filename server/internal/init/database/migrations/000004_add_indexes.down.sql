-- 000004_add_indexes.down.sql

DROP INDEX IF EXISTS idx_userteammemberships_team_id;
DROP INDEX IF EXISTS idx_tasks_team_id;
DROP INDEX IF EXISTS idx_tasks_created_by_user_id;
DROP INDEX IF EXISTS idx_tasks_assigned_to_user_id;
DROP INDEX IF EXISTS idx_tasks_status;
DROP INDEX IF EXISTS idx_tasks_is_deleted_deadline;
DROP INDEX IF EXISTS idx_usertags_owner_user_id;
DROP INDEX IF EXISTS idx_teamtags_team_id;
DROP INDEX IF EXISTS idx_tasktags_task_id;
DROP INDEX IF EXISTS idx_tasktags_user_tag_id;
DROP INDEX IF EXISTS idx_tasktags_team_tag_id;
DROP INDEX IF EXISTS idx_chatmessages_team_id_sent_at;
DROP INDEX IF EXISTS idx_chatmessages_sender_user_id;
DROP INDEX IF EXISTS idx_teams_created_by_user_id;
DROP INDEX IF EXISTS idx_teams_name_lower;