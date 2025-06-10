# server/Dockerfile

# Этап сборки
FROM golang:1.24 AS builder

# Установка зависимостей для сборки, включая libwebp-dev для cgo
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc g++ make libwebp-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# <<< ИСПРАВЛЕНИЕ: Удален префикс 'server/' >>>
# Копируем go.mod и go.sum для кэширования зависимостей
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# <<< ИСПРАВЛЕНИЕ: Удален префикс 'server/' >>>
# Копируем весь исходный код проекта
COPY . .

# Собираем приложение. Путь к main.go теперь относительный.
# CGO_ENABLED=1 нужен для libwebp
RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-w -s" -o main ./cmd/todo

# Этап выполнения
FROM debian:bookworm-slim

# Установка ca-certificates для HTTPS запросов и libwebp7 для runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends libwebp7 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копируем бинарный файл из этапа сборки
COPY --from=builder /app/main .

# Копируем статические ассеты, которые нужны приложению для работы
COPY --from=builder /app/config ./config
COPY --from=builder /app/docs ./docs
COPY --from=builder /app/todo-80b1b-firebase-adminsdk-fbsvc-6f38d4c04c.json .

# Порт, который слушает приложение внутри контейнера
EXPOSE 8080

# Команда для запуска приложения
CMD ["/app/main"]