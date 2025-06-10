package ws

import (
	"encoding/json"
	"log/slog"
	"reflect"
)

// MarshalPayloadToRawMessage безопасно маршалит payload в json.RawMessage.
// Возвращает nil, если payload is nil, или json.RawMessage с ошибкой, если маршалинг не удался.
func MarshalPayloadToRawMessage(payload interface{}, log *slog.Logger, opName string) json.RawMessage {
	if payload == nil {
		return nil
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		if log != nil {
			log.Error("Failed to marshal payload for WebSocket", "op", opName, "error", err, "payload_type", getType(payload))
		} else {
			// Fallback-логгер, если основной не передан (маловероятно)
			slog.Error("Failed to marshal payload for WebSocket (no logger)", "op", opName, "error", err, "payload_type", getType(payload))
		}
		// В случае ошибки маршалинга внутреннего payload, возвращаем JSON с ошибкой
		// Это важно, чтобы не отправлять некорректный/пустой payload дальше.
		errorMsg := `{"error_message":"internal_payload_marshal_error"}`
		return json.RawMessage(errorMsg)
	}
	return raw
}

// getType вспомогательная функция для получения имени типа (для логирования).
func getType(i interface{}) string {
	if i == nil {
		return "nil"
	}
	if t := reflect.TypeOf(i); t.Kind() == reflect.Ptr {
		return "*" + t.Elem().Name()
	} else {
		return t.Name()
	}
}
