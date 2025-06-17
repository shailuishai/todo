// internal/modules/team/controller/memberHandlers.go
package controller

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"log/slog"

	"server/internal/modules/team"
	usermodels "server/internal/modules/user"
	resp "server/pkg/lib/response"
)

// ... (GetTeamMembers и AddTeamMember остаются без изменений) ...

func (c *TeamController) GetTeamMembers(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.GetTeamMembers"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	teamIDStr := chi.URLParam(r, "teamID")
	teamID, err := strconv.ParseUint(teamIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Team ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTeamID", teamID))

	members, err := c.useCase.GetTeamMembers(uint(teamID), userID)
	if err != nil {
		log.Warn("usecase GetTeamMembers failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			log.Error("unhandled error in usecase GetTeamMembers", "error", err)
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve team members")
		}
		return
	}

	log.Info("team members retrieved successfully", slog.Int("count", len(members)))
	resp.SendSuccess(w, r, http.StatusOK, members)
}

func (c *TeamController) AddTeamMember(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.AddTeamMember"
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

	var req team.AddTeamMemberRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body for AddTeamMember", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for AddTeamMemberRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}
	log = log.With(slog.Uint64("targetUserID", uint64(req.UserID)))
	if req.Role != nil {
		log = log.With("targetRole", string(*req.Role))
	}

	memberResponse, err := c.useCase.AddTeamMember(uint(teamID), currentUserID, req)
	if err != nil {
		log.Error("usecase AddTeamMember failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound), errors.Is(err, usermodels.ErrUserNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied), errors.Is(err, team.ErrRoleChangeNotAllowed):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, team.ErrUserAlreadyMember):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to add team member")
		}
		return
	}

	log.Info("team member added successfully")
	resp.SendSuccess(w, r, http.StatusCreated, memberResponse)
}

func (c *TeamController) UpdateTeamMemberRole(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.UpdateTeamMemberRole"
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

	targetUserIDStr := chi.URLParam(r, "userID")
	targetUserID, err := strconv.ParseUint(targetUserIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid target User ID format")
		return
	}
	log = log.With(slog.Uint64("targetUserID", targetUserID))

	var req team.UpdateTeamMemberRoleRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body for UpdateTeamMemberRole", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for UpdateTeamMemberRoleRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}
	log = log.With("newRole", string(req.Role))

	// <<< ИСПРАВЛЕНИЕ: Передаем правильные ID (currentUserID и targetUserID) >>>
	memberResponse, err := c.useCase.UpdateTeamMemberRole(uint(teamID), currentUserID, uint(targetUserID), req)
	if err != nil {
		log.Error("usecase UpdateTeamMemberRole failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrUserNotMember):
			resp.SendError(w, r, http.StatusNotFound, "Target user is not a member of this team")
		case errors.Is(err, team.ErrTeamAccessDenied), errors.Is(err, team.ErrCannotChangeOwnerRole), errors.Is(err, team.ErrCannotPerformActionOnSelf), errors.Is(err, team.ErrRoleChangeNotAllowed):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to update team member role")
		}
		return
	}

	log.Info("team member role updated successfully")
	resp.SendSuccess(w, r, http.StatusOK, memberResponse)
}

func (c *TeamController) RemoveTeamMember(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.RemoveTeamMember"
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

	targetUserIDStr := chi.URLParam(r, "userID")
	targetUserID, err := strconv.ParseUint(targetUserIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid target User ID format")
		return
	}
	log = log.With(slog.Uint64("targetUserID", targetUserID))

	err = c.useCase.RemoveTeamMember(uint(teamID), currentUserID, uint(targetUserID))
	if err != nil {
		log.Error("usecase RemoveTeamMember failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrUserNotMember):
			resp.SendError(w, r, http.StatusNotFound, "Target user is not a member of this team")
		case errors.Is(err, team.ErrTeamAccessDenied), errors.Is(err, team.ErrCannotRemoveLastOwner), errors.Is(err, team.ErrCannotPerformActionOnSelf):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to remove team member")
		}
		return
	}

	log.Info("team member removed successfully")
	resp.SendOK(w, r, http.StatusNoContent)
}

func (c *TeamController) LeaveTeam(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.LeaveTeam"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	teamIDStr := chi.URLParam(r, "teamID")
	teamID, err := strconv.ParseUint(teamIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Team ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTeamID", teamID))

	err = c.useCase.LeaveTeam(uint(teamID), userID)
	if err != nil {
		log.Error("usecase LeaveTeam failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrUserNotMember):
			resp.SendError(w, r, http.StatusNotFound, "You are not a member of this team")
		case errors.Is(err, team.ErrTeamAccessDenied), errors.Is(err, team.ErrCannotRemoveLastOwner):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to leave team")
		}
		return
	}

	log.Info("user successfully left team")
	resp.SendOK(w, r, http.StatusNoContent)
}
