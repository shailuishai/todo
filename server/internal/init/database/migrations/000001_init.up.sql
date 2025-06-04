-- Тип для роли участника команды
CREATE TYPE team_member_role AS ENUM (
    'owner',
    'admin',
    'editor',
    'member'
    );

-- Таблица Пользователей (Users)
CREATE TABLE Users (
                       user_id SERIAL PRIMARY KEY,
                       login VARCHAR(50) UNIQUE NOT NULL,
                       email VARCHAR(100) UNIQUE NOT NULL,
                       password_hash VARCHAR(255),
                       avatar_s3_key VARCHAR(255),
                       is_admin BOOLEAN DEFAULT FALSE NOT NULL,
                       verified_email BOOLEAN DEFAULT FALSE NOT NULL,
                       has_mobile_device_linked BOOLEAN DEFAULT FALSE NOT NULL,
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       last_login_at TIMESTAMP WITH TIME ZONE
);

-- Таблица Настроек Пользователя (UserSettings) - связь один-к-одному с Users
CREATE TABLE UserSettings (
                              user_id INT PRIMARY KEY REFERENCES Users(user_id) ON DELETE CASCADE,
                              theme VARCHAR(20) DEFAULT 'system' NOT NULL,
                              accent_color VARCHAR(7) DEFAULT '#007AFF' NOT NULL,
                              sidebar_collapsed BOOLEAN DEFAULT FALSE NOT NULL,
                              notifications_email_enabled BOOLEAN DEFAULT FALSE NOT NULL,  -- Подписка на рассылку
                              notifications_push_task_assigned BOOLEAN DEFAULT FALSE NOT NULL, -- Push: назначена задача
                              notifications_push_task_deadline BOOLEAN DEFAULT FALSE NOT NULL, -- Push: приближается дедлайн
                              notifications_push_team_mention BOOLEAN DEFAULT FALSE NOT NULL,  -- Push: упоминание в команде/чате
                              updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Таблица Команд (Teams)
CREATE TABLE Teams (
                       team_id SERIAL PRIMARY KEY,
                       name VARCHAR(100) NOT NULL,
                       description TEXT,
                       color VARCHAR(7),
                       image_url_s3_key VARCHAR(255),
                       created_by_user_id INT REFERENCES Users(user_id) ON DELETE SET NULL,
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       is_deleted BOOLEAN DEFAULT FALSE NOT NULL,
                       deleted_at TIMESTAMP WITH TIME ZONE
);

-- Таблица Членства в Командах (UserTeamMemberships)
CREATE TABLE UserTeamMemberships (
                                     user_id INT REFERENCES Users(user_id) ON DELETE CASCADE,
                                     team_id INT REFERENCES Teams(team_id) ON DELETE CASCADE,
                                     role team_member_role NOT NULL DEFAULT 'member',
                                     joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                                     PRIMARY KEY (user_id, team_id)
);

-- Таблица Задач (Tasks)
CREATE TABLE Tasks (
                       task_id SERIAL PRIMARY KEY,
                       title VARCHAR(255) NOT NULL,
                       description TEXT,
                       deadline TIMESTAMP WITH TIME ZONE,
                       status VARCHAR(50) DEFAULT 'todo' NOT NULL,
                       priority INT DEFAULT 1 NOT NULL, -- 1 (low), 2 (medium), 3 (high)
                       created_by_user_id INT REFERENCES Users(user_id) ON DELETE SET NULL,
                       assigned_to_user_id INT REFERENCES Users(user_id) ON DELETE SET NULL,
                       team_id INT REFERENCES Teams(team_id) ON DELETE SET NULL,
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                       completed_at TIMESTAMP WITH TIME ZONE,
                       is_deleted BOOLEAN DEFAULT FALSE NOT NULL,
                       deleted_at TIMESTAMP WITH TIME ZONE,
                       deleted_by_user_id INT REFERENCES Users(user_id) ON DELETE SET NULL
);

-- Таблица Пользовательских Тэгов (UserTags)
CREATE TABLE UserTags (
                          user_tag_id SERIAL PRIMARY KEY,
                          owner_user_id INT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
                          name VARCHAR(50) NOT NULL,
                          color VARCHAR(7),
                          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                          CONSTRAINT unique_user_tag_name_per_owner UNIQUE (owner_user_id, name)
);

-- Таблица Командных Тэгов (TeamTags)
CREATE TABLE TeamTags (
                          team_tag_id SERIAL PRIMARY KEY,
                          team_id INT NOT NULL REFERENCES Teams(team_id) ON DELETE CASCADE,
                          name VARCHAR(50) NOT NULL,
                          color VARCHAR(7),
    -- created_by_user_id INT REFERENCES Users(user_id) ON DELETE SET NULL, -- Кто создал тег в команде (опционально)
                          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                          CONSTRAINT unique_team_tag_name_per_team UNIQUE (team_id, name)
);

-- Таблица Связи Задач и Тэгов (TaskTags)
CREATE TABLE TaskTags (
                          task_tag_id SERIAL PRIMARY KEY, -- Собственный ID для удобства
                          task_id INT NOT NULL REFERENCES Tasks(task_id) ON DELETE CASCADE,
                          user_tag_id INT REFERENCES UserTags(user_tag_id) ON DELETE CASCADE,
                          team_tag_id INT REFERENCES TeamTags(team_tag_id) ON DELETE CASCADE,
    -- Гарантируем, что к задаче применен либо пользовательский, либо командный тег, но не оба одновременно
                          CONSTRAINT chk_tag_type CHECK (
                              (user_tag_id IS NOT NULL AND team_tag_id IS NULL) OR
                              (user_tag_id IS NULL AND team_tag_id IS NOT NULL)
                              ),
    -- Уникальность комбинации задача-тег (независимо от типа тега, но это сложно обеспечить без дублирования task_id)
    -- Проще обеспечить уникальность на уровне приложения или через более сложный constraint,
    -- или просто разрешить дублирование, если это не критично (хотя обычно не нужно).
    -- Для простоты пока оставим так. Если нужно строго, то можно:
    -- 1. TaskUserTags: task_id, user_tag_id (PK)
    -- 2. TaskTeamTags: task_id, team_tag_id (PK)
    -- Но это две таблицы связей.
    -- С текущим chk_tag_type, уникальность будет (task_id, user_tag_id) и (task_id, team_tag_id) если они не NULL.
    -- Чтобы избежать дублирования одного и того же тега (даже если он из разных таблиц, но имеет один ID после JOIN)
    -- лучше сделать так, чтобы ID тегов в UserTags и TeamTags были из разных диапазонов или использовали UUID.
    -- Или, при добавлении, проверять, не применен ли уже "эквивалентный" тег.
    -- Пока что оставим простой вариант. Уникальность (task_id, user_tag_id) и (task_id, team_tag_id) будет работать.
                          UNIQUE (task_id, user_tag_id),
                          UNIQUE (task_id, team_tag_id)
);


-- Таблица Сообщений Чата Команды (ChatMessages)
CREATE TABLE ChatMessages (
                              message_id SERIAL PRIMARY KEY,
                              team_id INT NOT NULL REFERENCES Teams(team_id) ON DELETE CASCADE,
                              user_id INT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE, -- Отправитель
                              content TEXT NOT NULL,
                              sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
                              updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL, -- Для возможности редактирования
                              is_deleted BOOLEAN DEFAULT FALSE NOT NULL -- Для логического удаления
);
-- Можно добавить реакции, вложения и т.д. в будущем.

-- Триггерная функция для автоматического обновления поля updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- Применение триггера к таблицам
CREATE TRIGGER trigger_users_updated_at BEFORE UPDATE ON Users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_user_settings_updated_at BEFORE UPDATE ON UserSettings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_teams_updated_at BEFORE UPDATE ON Teams FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_tasks_updated_at BEFORE UPDATE ON Tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_user_tags_updated_at BEFORE UPDATE ON UserTags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_team_tags_updated_at BEFORE UPDATE ON TeamTags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_chat_messages_updated_at BEFORE UPDATE ON ChatMessages FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Автоматическое создание UserSettings при создании нового пользователя
CREATE OR REPLACE FUNCTION create_default_user_settings()
    RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO UserSettings (user_id) VALUES (NEW.user_id);
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER trigger_after_user_insert
    AFTER INSERT ON Users
    FOR EACH ROW EXECUTE FUNCTION create_default_user_settings();