FROM golang:1.23.4 AS builder

RUN apt-get update && apt-get install -y gcc g++ make libwebp-dev

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

COPY ./config /app/server/config
COPY ./docs /app/server/docs
COPY ./defaultAvatars /app/server/defaultAvatars

RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o main ./cmd/todo/main.go

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y libwebp7 ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/main /app/main
COPY --from=builder /app/server/config /app/server/config
COPY --from=builder /app/server/docs /app/server/docs
COPY --from=builder /app/server/defaultAvatars /app/server/defaultAvatars

EXPOSE 8080
CMD ["./main"]
