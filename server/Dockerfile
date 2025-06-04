# server/Dockerfile

# Этап сборки
FROM golang:1.23.4 AS builder

# Установка зависимостей для сборки, включая libwebp-dev для cgo
# RUN apt-get update && apt-get install -y gcc g++ make libwebp-dev
# Для Alpine (меньший образ) это выглядело бы так:
# RUN apk add --no-cache gcc musl-dev make libwebp-dev
# Но ты используешь golang:1.23.4 (Debian based), так что apt-get корректен.
# Обновление: Если CGO_ENABLED=0, то libwebp-dev может быть не нужен на этапе builder,
# но если CGO_ENABLED=1 (как у тебя), то нужен.
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc g++ make libwebp-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копируем go.mod и go.sum для кэширования зависимостей
COPY go.mod go.sum ./
RUN go mod download
RUN go mod verify # Хорошая практика

# Копируем исходный код проекта
COPY . .
# Копируем конфигурационные файлы и документацию Swagger, которые должны быть частью образа
# Эти пути относительны WORKDIR (/app) на момент выполнения Dockerfile,
# а источник (./config) - относительны контекста сборки (твой server/)
# Но так как docker-compose.yml запускает build с context: . (корень проекта),
# то пути для COPY должны быть server/config, server/docs
COPY ./config /app/server/config
COPY ./docs /app/server/docs
# defaultAvatars копировать не будем, если они нужны только для загрузки в S3 при инициализации
# и эта логика будет выполняться приложением, читающим с хоста через том или изнутри контейнера, если они скопированы
# Если S3 инициализация берет файлы из путей в конфиге, и эти пути - это пути на хосте,
# то они должны быть доступны через том или скопированы в образ.
# Если default_files_to_upload в s3Config предполагают пути ВНУТРИ контейнера,
# тогда их нужно скопировать.

# Копируем defaultAvatars, если они нужны внутри контейнера для инициализации S3
# (если логика инициализации S3 читает файлы из файловой системы контейнера)
# COPY ./server/defaultAvatars /app/server/defaultAvatars


# Собираем приложение
# CGO_ENABLED=1 если есть C зависимости (например, для SQLite или других библиотек)
# Если нет C-зависимостей, можно CGO_ENABLED=0 для статической линковки без внешних библиотек C.
# У тебя libwebp, так что CGO_ENABLED=1.
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o main ./cmd/todo/main.go

# Этап выполнения
FROM debian:bookworm-slim

# Установка ca-certificates для HTTPS запросов и libwebp7 для runtime, если используется
RUN apt-get update && \
    apt-get install -y --no-install-recommends libwebp7 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копируем бинарный файл из этапа сборки
COPY --from=builder /app/main /app/main

# Копируем конфигурационные файлы и документацию Swagger из этапа сборки
# Пути должны соответствовать тому, что приложение ожидает
COPY --from=builder /app/server/config /app/server/config
COPY --from=builder /app/server/docs /app/server/docs

# Копируем defaultAvatars, если они читаются из файловой системы контейнера при инициализации S3
# COPY --from=builder /app/server/defaultAvatars /app/server/defaultAvatars


# Порт, который слушает приложение внутри контейнера (HTTP или HTTPS)
EXPOSE 8080

# Команда для запуска приложения
# Пользователь и группа могут быть добавлены для безопасности (non-root user)
# RUN groupadd -r appgroup && useradd -r -g appgroup appuser
# USER appuser
CMD ["./main"]