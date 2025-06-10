package controller

import (
	"errors"
	"log/slog"
	"net/http"
	"server/internal/modules/chat"
	"server/internal/modules/chat/ws"
	"server/pkg/lib/response"
	// "server/pkg/middleware/jwt" // Этот импорт может быть не нужен, если ключ "userId" - строка
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/go-playground/validator/v10"
)

type httpChatController struct {
	useCase  chat.UseCase
	log      *slog.Logger
	validate *validator.Validate
}

type wsChatController struct {
	hub         *ws.Hub
	teamService chat.TeamChecker
	log         *slog.Logger
}

type controllerImpl struct {
	httpCtrl *httpChatController
	wsCtrl   *wsChatController
}

func NewController(
	log *slog.Logger,
	uc chat.UseCase,
	hub *ws.Hub,
	teamService chat.TeamChecker,
	validate *validator.Validate,
) chat.Controller {
	if validate == nil {
		validate = validator.New()
	}
	return &controllerImpl{
		httpCtrl: &httpChatController{
			useCase:  uc,
			log:      log.With(slog.String("controller_sub_type", "http_chat")),
			validate: validate,
		},
		wsCtrl: &wsChatController{
			hub:         hub,
			teamService: teamService,
			log:         log.With(slog.String("controller_sub_type", "ws_chat")),
		},
	}
}

func (c *controllerImpl) ServeWs(w http.ResponseWriter, r *http.Request) {
	c.wsCtrl.ServeWs(w, r)
}

func (c *controllerImpl) GetChatHistory(w http.ResponseWriter, r *http.Request) {
	c.httpCtrl.GetChatHistory(w, r)
}

func (wc *wsChatController) ServeWs(w http.ResponseWriter, r *http.Request) {
	op := "wsChatController.ServeWs"

	// Используем тот же ключ и тип, что и в ProfileController
	userID, ok := r.Context().Value("userId").(uint)
	if !ok || userID == 0 {
		wc.log.Warn("Unauthorized WS: userID not found in context or is zero", slog.String("op", op))
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	log := wc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	teamIDStr := chi.URLParam(r, "teamID")
	teamIDUint64, err := strconv.ParseUint(teamIDStr, 10, 32)
	if err != nil {
		log.Warn("Invalid teamID in URL", "teamIDStr", teamIDStr, "error", err)
		http.Error(w, "Invalid team ID", http.StatusBadRequest)
		return
	}
	teamID := uint(teamIDUint64)
	log = log.With(slog.Uint64("teamID", uint64(teamID)))

	isMember, err := wc.teamService.IsUserMember(userID, teamID)
	if err != nil {
		log.Error("Failed to check team membership for WS", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	if !isMember {
		log.Warn("User not member of team for WS", "userID", userID, "teamID", teamID)
		http.Error(w, "Forbidden: Not a team member", http.StatusForbidden)
		return
	}

	conn, err := ws.Upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Error("Failed to upgrade connection to WebSocket", "error", err)
		return
	}
	log.Info("WebSocket connection upgraded", "remoteAddr", conn.RemoteAddr())

	client := &ws.Client{
		Hub:    wc.hub,
		Conn:   conn,
		Send:   make(chan []byte, 256),
		UserID: userID,
		TeamID: teamID,
		Log:    log.With(slog.String("component", "ws_client")),
	}
	wc.hub.Register <- client

	go client.WritePump()
	go client.ReadPump()
}

func (hc *httpChatController) GetChatHistory(w http.ResponseWriter, r *http.Request) {
	op := "httpChatController.GetChatHistory"

	userID, ok := r.Context().Value("userId").(uint)
	if !ok || userID == 0 {
		hc.log.Warn("Unauthorized HTTP: userID not found in context or is zero", slog.String("op", op))
		response.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log := hc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	teamIDStr := chi.URLParam(r, "teamID")
	teamIDUint64, err := strconv.ParseUint(teamIDStr, 10, 32)
	if err != nil {
		log.Warn("Invalid teamID in URL", "teamIDStr", teamIDStr, "error", err)
		response.SendError(w, r, http.StatusBadRequest, "Invalid team ID")
		return
	}
	teamID := uint(teamIDUint64)
	log = log.With(slog.Uint64("teamID", uint64(teamID)))

	var beforeMessageID *uint
	if beforeStr := r.URL.Query().Get("before_message_id"); beforeStr != "" {
		beforeID, errParse := strconv.ParseUint(beforeStr, 10, 32)
		if errParse == nil && beforeID > 0 {
			uid := uint(beforeID)
			beforeMessageID = &uid
		} else {
			log.Warn("Invalid 'before_message_id' query param", "value", beforeStr)
		}
	}

	limit := 50
	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		limitInt, errParse := strconv.Atoi(limitStr)
		if errParse == nil && limitInt > 0 && limitInt <= 100 {
			limit = limitInt
		} else {
			log.Warn("Invalid 'limit' query param, using default", "value", limitStr)
		}
	}

	params := chat.HTTPGetHistoryParams{
		TeamID:          teamID,
		BeforeMessageID: beforeMessageID,
		Limit:           limit,
	}

	historyResponse, err := hc.useCase.GetMessagesForHistory(r.Context(), userID, params)
	if err != nil {
		log.Error("UseCase GetMessagesForHistory failed", "error", err)
		if errors.Is(err, chat.ErrUserNotInTeamChat) || errors.Is(err, chat.ErrUserNotInTeam) {
			response.SendError(w, r, http.StatusForbidden, err.Error())
		} else if errors.Is(err, chat.ErrChatAccessDenied) {
			response.SendError(w, r, http.StatusForbidden, err.Error())
		} else {
			response.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve chat history")
		}
		return
	}

	log.Info("Chat history retrieved via HTTP", "count", len(historyResponse.Messages), "hasMore", historyResponse.HasMore)
	response.SendSuccess(w, r, http.StatusOK, historyResponse)
}
