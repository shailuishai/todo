package ws

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"server/internal/modules/chat"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 4096
)

var (
	newline = []byte{'\n'}
	space   = []byte{' '}
)

var Upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// TODO: Заменить на проверку реальных Origins в production
		return true // Временно для разработки
	},
}

type Client struct {
	Hub    *Hub
	Conn   *websocket.Conn
	Send   chan []byte
	UserID uint
	TeamID uint
	Log    *slog.Logger
}

func (c *Client) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c
		if err := c.Conn.Close(); err != nil {
			// Избегаем логирования ошибки "use of closed network connection", если Conn уже закрыт из WritePump или Unregister
			if !strings.Contains(err.Error(), "use of closed network connection") {
				c.Log.Warn("Error closing connection in ReadPump defer", "error", err)
			}
		}
		c.Log.Info("Client ReadPump: unregistered and connection closed")
	}()
	c.Conn.SetReadLimit(maxMessageSize)
	_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error { _ = c.Conn.SetReadDeadline(time.Now().Add(pongWait)); return nil })

	for {
		_, messageBytes, err := c.Conn.ReadMessage()
		if err != nil {
			// Логируем только если это не ожидаемое закрытие
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure, websocket.CloseNoStatusReceived) {
				c.Log.Warn("ReadPump: unexpected close error", "error", err)
			} else if !errors.Is(err, websocket.ErrCloseSent) && !strings.Contains(err.Error(), "use of closed network connection") {
				// Это может быть нормальное закрытие со стороны клиента или хаба
				c.Log.Info("ReadPump: websocket connection closed or known error", "error", err)
			}
			break // Выходим из цикла при любой ошибке чтения
		}
		messageBytes = bytes.TrimSpace(bytes.Replace(messageBytes, newline, space, -1))

		var wsMsg chat.WebSocketMessage
		if err := json.Unmarshal(messageBytes, &wsMsg); err != nil {
			c.Log.Warn("ReadPump: failed to unmarshal websocket message", "error", err, "raw_message", string(messageBytes))
			errorPayload := chat.ErrorPayload{Message: "Invalid message format"}
			// Используем ws.MarshalPayloadToRawMessage из utils.go
			rawErrPayload := MarshalPayloadToRawMessage(errorPayload, c.Log, "ClientUnmarshalError")
			errMsgBytes, _ := json.Marshal(chat.WebSocketMessage{Type: chat.MessageTypeError, Payload: rawErrPayload})
			select {
			case c.Send <- errMsgBytes:
			default:
				c.Log.Warn("ReadPump: Send channel closed or full for unmarshal error")
			}
			continue
		}
		c.Log.Debug("ReadPump: received message from client", "type", wsMsg.Type)
		c.Hub.ProcessClientMessage(c, wsMsg)
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		// Закрываем соединение здесь, чтобы ReadPump тоже завершился, если он еще работает
		if err := c.Conn.Close(); err != nil {
			if !strings.Contains(err.Error(), "use of closed network connection") {
				c.Log.Warn("Error closing connection in WritePump defer", "error", err)
			}
		}
		c.Log.Info("Client WritePump: stopped and connection closed")
	}()
	for {
		select {
		case message, ok := <-c.Send:
			if !ok { // Канал c.Send был закрыт (вероятно, из Hub при отписке)
				_ = c.Conn.WriteMessage(websocket.CloseMessage, []byte{}) // Отправляем CloseMessage клиенту
				c.Log.Info("WritePump: Send channel closed by Hub")
				return // Завершаем горутину
			}
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				c.Log.Error("WritePump: failed to get next writer", "error", err)
				return
			}
			if _, errWrite := w.Write(message); errWrite != nil {
				c.Log.Error("WritePump: failed to write message via writer", "error", errWrite)
				_ = w.Close() // Всегда закрываем writer
				return
			}
			if errClose := w.Close(); errClose != nil {
				c.Log.Error("WritePump: failed to close writer", "error", errClose)
				return
			}
		case <-ticker.C:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				c.Log.Error("WritePump: failed to write ping message", "error", err)
				return // Ошибка записи пинга означает проблемы с соединением
			}
		}
	}
}
