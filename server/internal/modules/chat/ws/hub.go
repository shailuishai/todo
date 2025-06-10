package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"server/internal/modules/chat"
	"strconv"
	"sync"

	"github.com/go-playground/validator/v10"
)

// Hub управляет активными клиентами и рассылает им сообщения.
type Hub struct {
	teams      map[uint]map[*Client]bool
	mu         sync.RWMutex
	Register   chan *Client
	Unregister chan *Client
	Log        *slog.Logger
	UseCase    chat.UseCase
	validate   *validator.Validate
}

// NewHub создает новый Hub.
func NewHub(log *slog.Logger, uc chat.UseCase) *Hub {
	return &Hub{
		teams:      make(map[uint]map[*Client]bool),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Log:        log.With(slog.String("component", "chat_hub")),
		UseCase:    uc,
		validate:   validator.New(),
	}
}

// Run запускает основной цикл хаба.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			if _, ok := h.teams[client.TeamID]; !ok {
				h.teams[client.TeamID] = make(map[*Client]bool)
			}
			h.teams[client.TeamID][client] = true
			h.mu.Unlock()
			client.Log.Info("Client registered")

		case client := <-h.Unregister:
			h.mu.Lock()
			if teamClients, ok := h.teams[client.TeamID]; ok {
				if _, clientExists := teamClients[client]; clientExists {
					close(client.Send)
					delete(teamClients, client)
					if len(teamClients) == 0 {
						delete(h.teams, client.TeamID)
					}
				}
			}
			h.mu.Unlock()
			client.Log.Info("Client unregistered")
		}
	}
}

// <<< НАЧАЛО: ГЛАВНОЕ ИСПРАВЛЕНИЕ НА БЭКЕНДЕ >>>
func (h *Hub) ProcessClientMessage(client *Client, wsMsg chat.WebSocketMessage) {
	ctx := context.Background()
	log := client.Log.With("op", "Hub.ProcessClientMessage", "msgType", wsMsg.Type)

	switch wsMsg.Type {
	case chat.MessageTypeNewMessage:
		var payload chat.IncomingNewMessagePayload
		if err := json.Unmarshal(wsMsg.Payload, &payload); err != nil || h.validate.Struct(payload) != nil {
			h.sendErrorToClient(client, "Invalid payload", wsMsg.Type, payload.ClientMessageID)
			return
		}

		// 1. UseCase создает сообщение и базовый DTO
		chatMsgResponse, err := h.UseCase.HandleNewMessage(ctx, client.UserID, client.TeamID, payload)
		if err != nil {
			h.sendErrorToClient(client, err.Error(), wsMsg.Type, payload.ClientMessageID)
			return
		}
		log.Info("New message processed by usecase", "messageID", chatMsgResponse.ID)

		// 2. Рассылаем персонализированные сообщения каждому клиенту
		h.broadcastPersonalizedMessage(client.TeamID, chatMsgResponse)

	case chat.MessageTypeEditMessage:
		var payload chat.EditMessagePayload
		if err := json.Unmarshal(wsMsg.Payload, &payload); err != nil || h.validate.Struct(payload) != nil {
			h.sendErrorToClient(client, "Invalid payload", wsMsg.Type, strconv.Itoa(int(payload.MessageID)))
			return
		}
		editedPayload, err := h.UseCase.HandleEditMessage(ctx, client.UserID, client.TeamID, payload)
		if err != nil {
			h.sendErrorToClient(client, err.Error(), wsMsg.Type, strconv.Itoa(int(payload.MessageID)))
			return
		}
		// Рассылаем всем одинаковое уведомление об изменении
		h.broadcastToTeam(client.TeamID, chat.WebSocketMessage{
			Type:    chat.MessageTypeMessageEdited,
			Payload: MarshalPayloadToRawMessage(editedPayload, log, "MessageEditedPayload"),
		})

	case chat.MessageTypeDeleteMessage:
		var payload chat.DeleteMessagePayload
		if err := json.Unmarshal(wsMsg.Payload, &payload); err != nil || h.validate.Struct(payload) != nil {
			h.sendErrorToClient(client, "Invalid payload", wsMsg.Type, strconv.Itoa(int(payload.MessageID)))
			return
		}
		deletedPayload, err := h.UseCase.HandleDeleteMessage(ctx, client.UserID, client.TeamID, payload.MessageID)
		if err != nil {
			h.sendErrorToClient(client, err.Error(), wsMsg.Type, strconv.Itoa(int(payload.MessageID)))
			return
		}
		// Рассылаем всем одинаковое уведомление об удалении
		h.broadcastToTeam(client.TeamID, chat.WebSocketMessage{
			Type:    chat.MessageTypeMessageDeleted,
			Payload: MarshalPayloadToRawMessage(deletedPayload, log, "MessageDeletedPayload"),
		})

	// Остальные кейсы (MarkAsRead, LoadHistoryRequest) без изменений...
	case chat.MessageTypeMarkAsRead:
		var payload chat.MarkAsReadPayload
		if err := json.Unmarshal(wsMsg.Payload, &payload); err != nil || h.validate.Struct(payload) != nil {
			h.sendErrorToClient(client, "Invalid payload", wsMsg.Type, "")
			return
		}
		senderUpdates, err := h.UseCase.HandleMarkAsRead(ctx, client.UserID, client.TeamID, payload.MessageIDs)
		if err != nil {
			h.sendErrorToClient(client, err.Error(), wsMsg.Type, "")
			return
		}
		for _, update := range senderUpdates {
			h.sendToUserInTeam(update.TeamID, update.TargetUserID, chat.MessageTypeMessageStatusUpdate, update)
		}

	case chat.MessageTypeLoadHistoryRequest:
		var payload chat.HistoryRequestPayload
		if err := json.Unmarshal(wsMsg.Payload, &payload); err != nil || h.validate.Struct(payload) != nil {
			h.sendErrorToClient(client, "Invalid payload", wsMsg.Type, "")
			return
		}
		if payload.Limit == 0 {
			payload.Limit = 50
		}
		historyResp, err := h.UseCase.GetMessagesForHistory(ctx, client.UserID, chat.HTTPGetHistoryParams{
			TeamID:          client.TeamID,
			BeforeMessageID: payload.BeforeMessageID,
			Limit:           payload.Limit,
		})
		if err != nil {
			h.sendErrorToClient(client, err.Error(), wsMsg.Type, "")
			return
		}
		msg := chat.WebSocketMessage{Type: chat.MessageTypeHistoryLoaded, Payload: MarshalPayloadToRawMessage(chat.HistoryLoadedPayload{
			Messages: historyResp.Messages,
			HasMore:  historyResp.HasMore,
			TeamID:   client.TeamID,
		}, log, "HistoryLoadedPayload")}
		h.sendToClient(client, msg)

	default:
		h.sendErrorToClient(client, "Unknown message type", wsMsg.Type, "")
		return
	}
}

// Новый метод для персонализированной рассылки
func (h *Hub) broadcastPersonalizedMessage(teamID uint, baseResponse *chat.ChatMessageResponse) {
	h.mu.RLock()
	clientsInTeam, ok := h.teams[teamID]
	if !ok {
		h.mu.RUnlock()
		return
	}

	// Создаем копии клиентов, чтобы можно было безопасно итерировать и отпустить мьютекс
	clientsToSend := make([]*Client, 0, len(clientsInTeam))
	for c := range clientsInTeam {
		clientsToSend = append(clientsToSend, c)
	}
	h.mu.RUnlock()

	log := h.Log.With("op", "broadcastPersonalizedMessage", "teamID", teamID, "messageID", baseResponse.ID)
	log.Debug("Broadcasting personalized message", "num_clients", len(clientsToSend))

	for _, c := range clientsToSend {
		// Создаем копию ответа для каждого клиента
		personalizedResponse := *baseResponse
		// Устанавливаем флаг в зависимости от того, является ли клиент отправителем
		personalizedResponse.IsCurrentUser = (c.UserID == baseResponse.Sender.UserID)

		// Оборачиваем в WebSocketMessage
		wsMsg := chat.WebSocketMessage{
			Type:    chat.MessageTypeMessageReceived,
			Payload: MarshalPayloadToRawMessage(personalizedResponse, log, "PersonalizedMessageReceived"),
		}

		// Отправляем конкретному клиенту
		h.sendToClient(c, wsMsg)
	}
}

// <<< КОНЕЦ ГЛАВНОГО ИСПРАВЛЕНИЯ >>>

// broadcastToTeam остается для неперсонализированных сообщений (edit, delete)
func (h *Hub) broadcastToTeam(teamID uint, message chat.WebSocketMessage) {
	messageBytes, err := json.Marshal(message)
	if err != nil {
		h.Log.Error("Failed to marshal message for broadcast", "error", err, "teamID", teamID, "msg_type", message.Type)
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	if clientsInTeam, ok := h.teams[teamID]; ok {
		h.Log.Debug("Broadcasting (non-personalized) message", "teamID", teamID, "num_clients", len(clientsInTeam), "msg_type", message.Type)
		for c := range clientsInTeam {
			select {
			case c.Send <- messageBytes:
			default:
				// Канал закрыт, значит клиент отключается. Удаляем его.
				// Эта логика дублируется в Unregister, но здесь она на случай, если Unregister еще не успел сработать.
				// Безопаснее просто пропустить, Unregister сделает свою работу.
				h.Log.Warn("Client send channel full/closed during broadcast, skipping", "userID", c.UserID, "teamID", c.TeamID)
			}
		}
	} else {
		h.Log.Debug("No clients in team to broadcast message", "teamID", teamID, "msg_type", message.Type)
	}
}

// sendToClient, sendToUserInTeam, sendErrorToClient остаются без изменений
func (h *Hub) sendToClient(client *Client, message chat.WebSocketMessage) {
	messageBytes, err := json.Marshal(message)
	if err != nil {
		client.Log.Error("Failed to marshal message for client", "error", err)
		return
	}
	// Добавляем проверку, что канал не закрыт
	if client.Send != nil {
		select {
		case client.Send <- messageBytes:
		default:
			// Канал полон, это может означать, что клиент не успевает обрабатывать сообщения.
			// В этом случае мы его отключаем, чтобы не блокировать хаб.
			h.Log.Warn("Client send channel full or closed for specific message", "userID", client.UserID, "teamID", client.TeamID)
			// Инициируем отключение клиента
			h.Unregister <- client
		}
	}
}

func (h *Hub) sendToUserInTeam(teamID uint, targetUserID uint, msgType string, payloadData interface{}) {
	payloadBytes := MarshalPayloadToRawMessage(payloadData, h.Log, "sendToUserInTeam")
	if payloadBytes == nil {
		return
	}
	msg := chat.WebSocketMessage{Type: msgType, Payload: payloadBytes}
	_, err := json.Marshal(msg)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	if teamClients, ok := h.teams[teamID]; ok {
		for client := range teamClients {
			if client.UserID == targetUserID {
				h.sendToClient(client, msg)
				// Можно было бы `break`, если один юзер = один клиент, но оставим для поддержки нескольких сессий
			}
		}
	}
}

func (h *Hub) sendErrorToClient(client *Client, errorText, originalType, clientMessageID string) {
	errorPayload := chat.ErrorPayload{
		Message:         errorText,
		OriginalType:    originalType,
		ClientMessageID: clientMessageID,
	}
	h.sendToClient(client, chat.WebSocketMessage{
		Type:    chat.MessageTypeError,
		Payload: MarshalPayloadToRawMessage(errorPayload, h.Log, "ErrorPayload"),
	})
}
