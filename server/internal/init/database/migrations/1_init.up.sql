CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    hashed_password VARCHAR(255),
    is_admin BOOLEAN NOT NULL DEFAULT false,
    login VARCHAR(100) UNIQUE,
    email VARCHAR(100) UNIQUE NOT NULL,
    verified_email  BOOLEAN NOT NULL DEFAULT false,
    avatar_url TEXT DEFAULT 'https://useravatar.storage-173.s3hoster.by/default/',
    create_at DATE DEFAULT current_date
);

CREATE OR REPLACE FUNCTION set_default_login()
    RETURNS TRIGGER AS $$
BEGIN
    IF NEW.login IS NULL OR NEW.login = '' THEN
        UPDATE users
        SET login = 'USER' || NEW.user_id
        WHERE user_id = NEW.user_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_insert_user
    AFTER INSERT ON users
    FOR EACH ROW
EXECUTE FUNCTION set_default_login();

CREATE TABLE films (
    film_id SERIAL PRIMARY KEY,
    title TEXT NOT NULL DEFAULT 'фильмец под чипсики',
    poster_url TEXT DEFAULT 'https://filmposter.storage-173.s3hoster.by/default/',
    synopsis TEXT NOT NULL DEFAULT '-',
    release_date DATE,
    runtime INT,
    producer VARCHAR(255),
    create_at DATE DEFAULT current_date
);

--TODO: сделать жанры как отдельный католог с постерами и описанием крутая фича для пользователей не прошареных за фильмы
CREATE TABLE genres (
    genre_id SERIAL PRIMARY KEY,
    name VARCHAR(200) UNIQUE NOT NULL,
    create_at DATE DEFAULT current_date
);

CREATE TABLE film_genre (
    film_id INT NOT NULL,
    genre_id INT NOT NULL,
    CONSTRAINT fk_film FOREIGN KEY (film_id) REFERENCES films (film_id) ON DELETE CASCADE,
    CONSTRAINT fk_genre FOREIGN KEY (genre_id) REFERENCES genres (genre_id) ON DELETE CASCADE
);

CREATE TABLE actors (
    actor_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    avatar_url TEXT DEFAULT 'https://actoravatar.storage-173.s3hoster.by/default/',
    wiki_url TEXT DEFAULT '',
    create_at DATE DEFAULT current_date
);

CREATE TABLE film_actor (
    film_id INT NOT NULL,
    actor_id INT NOT NULL,
    CONSTRAINT fk_film FOREIGN KEY (film_id) REFERENCES films (film_id) ON DELETE CASCADE,
    CONSTRAINT fk_actor FOREIGN KEY (actor_id) REFERENCES actors (actor_id) ON DELETE CASCADE
);

CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users (user_id) ON DELETE CASCADE,
    film_id INT REFERENCES films (film_id) ON DELETE CASCADE,
    rating INT CHECK (rating >= 0 AND rating <= 100) NOT NULL,
    review_text TEXT NOT NULL,
    create_at DATE DEFAULT current_date,
    UNIQUE (user_id,film_id)
);

CREATE MATERIALIZED VIEW film_stats AS
SELECT
    f.film_id,
    COALESCE(ROUND(AVG(r.rating)), 0) AS avg_rating,
    COALESCE(COUNT(r.rating), 0) AS total_count_reviews,
    COALESCE(COUNT(CASE WHEN r.rating BETWEEN 0 AND 20 THEN 1 END), 0) AS count_0_20,
    COALESCE(COUNT(CASE WHEN r.rating BETWEEN 21 AND 40 THEN 1 END), 0) AS count_21_40,
    COALESCE(COUNT(CASE WHEN r.rating BETWEEN 41 AND 60 THEN 1 END), 0) AS count_41_60,
    COALESCE(COUNT(CASE WHEN r.rating BETWEEN 61 AND 80 THEN 1 END), 0) AS count_61_80,
    COALESCE(COUNT(CASE WHEN r.rating BETWEEN 81 AND 100 THEN 1 END), 0) AS count_81_100
FROM films f
         LEFT JOIN reviews r ON f.film_id = r.film_id
GROUP BY f.film_id;


CREATE OR REPLACE FUNCTION refresh_film_stats()
    RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW film_stats;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_film_stats_after_reviews_change
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH STATEMENT
EXECUTE FUNCTION refresh_film_stats();

CREATE TRIGGER update_film_stats_after_films_change
    AFTER INSERT OR UPDATE OR DELETE ON films
    FOR EACH STATEMENT
EXECUTE FUNCTION refresh_film_stats();


CREATE UNIQUE INDEX idx_film_stats_film_id ON film_stats (film_id);
CREATE INDEX idx_reviews_film_user ON reviews (film_id, user_id);
CREATE INDEX idx_reviews_rating ON reviews (rating);
CREATE INDEX idx_users_is_admin ON users (is_admin);
CREATE INDEX idx_film_runtime ON films (runtime);
CREATE INDEX idx_genres_name ON genres (name);
CREATE INDEX idx_actors_name ON actors (name);
CREATE INDEX idx_film_actor_film_id_actor_id ON film_actor (film_id, actor_id);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_login ON users (login);
CREATE INDEX idx_films_date ON films (release_date);
CREATE INDEx idx_films_producer ON films (producer);
CREATE INDEX idx_review_user_id ON reviews (user_id);