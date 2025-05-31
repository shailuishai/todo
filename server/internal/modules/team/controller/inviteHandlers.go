package controller

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"log/slog"

	"server/internal/modules/team"
	resp "server/pkg/lib/response"
)

func (c *TeamController) GenerateInviteToken(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.GenerateInviteToken"
	log := c.log.With(slog.String("op", op))

	currentUserID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("currentUserID", uint64(currentUserID)))

	teamIDStr := chi.URLParam(r, "teamID")
	teamID, err := strconv.ParseUint(teamIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Team ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTeamID", teamID))

	var req team.GenerateInviteTokenRequest
	if r.ContentLength > 0 {
		if err := render.DecodeJSON(r.Body, &req); err != nil && !errors.Is(err, io.EOF) {
			log.Warn("failed to decode request body for GenerateInviteToken", "error", err)
			resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
			return
		}
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for GenerateInviteTokenRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	if req.ExpiresInHours != nil {
		log = log.With("expires_in_hours", *req.ExpiresInHours)
	}
	if req.RoleToAssign != nil {
		log = log.With("role_to_assign", *req.RoleToAssign)
	}

	inviteResponse, err := c.useCase.GenerateInviteToken(uint(teamID), currentUserID, req)
	if err != nil {
		log.Error("usecase GenerateInviteToken failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied), errors.Is(err, team.ErrRoleChangeNotAllowed):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, team.ErrTeamIsDeleted):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to generate invite token")
		}
		return
	}
	log.Info("invite token generated successfully")
	resp.SendSuccess(w, r, http.StatusCreated, inviteResponse)
}

func (c *TeamController) JoinTeamByToken(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.JoinTeamByToken"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var req team.JoinTeamByTokenRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body for JoinTeamByToken", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for JoinTeamByTokenRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	log = log.With(slog.String("token_value_hash", hashTokenForLog(req.InviteToken)))

	teamResponse, err := c.useCase.JoinTeamByToken(req.InviteToken, userID)
	if err != nil {
		log.Error("usecase JoinTeamByToken failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamInviteTokenInvalid):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, team.ErrUserAlreadyMember):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to join team by token")
		}
		return
	}
	log.Info("user successfully joined team by token")
	resp.SendSuccess(w, r, http.StatusOK, teamResponse)
}

func hashTokenForLog(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:8])
}
