package controller

import (
	"errors"
	"net/http"
	"server/internal/modules/team"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"github.com/go-playground/validator/v10"
	"log/slog"

	"server/internal/modules/tag" // Для DTO запросов, ответов, ошибок и интерфейса UseCase
	// usermodels "server/internal/modules/user" // Для общих ошибок, если понадобятся (например, ErrForbidden)
	resp "server/pkg/lib/response"
)

// TagController обрабатывает HTTP-запросы для тегов.
type TagController struct {
	useCase  tag.UseCase
	log      *slog.Logger
	validate *validator.Validate
}

// NewTagController создает новый экземпляр TagController.
func NewTagController(useCase tag.UseCase, log *slog.Logger) tag.Controller {
	return &TagController{
		useCase:  useCase,
		log:      log,
		validate: validator.New(),
	}
}

// --- User Tag Handlers ---

// CreateUserTag
// @Summary Create a new user tag
// @Tags user-tags
// @Description Creates a new personal tag for the authenticated user.
// @Accept json
// @Produce json
// @Param tag_data body tag.CreateUserTagRequest true "User tag data"
// @Success 201 {object} response.SuccessResponse{data=tag.TagResponse} "User tag created successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload or validation error"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 409 {object} response.ErrorResponse "Tag with this name already exists for the user"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /user-tags [post]
// @Security ApiKeyAuth
func (c *TagController) CreateUserTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.CreateUserTag"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var req tag.CreateUserTagRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for CreateUserTagRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	tagResponse, err := c.useCase.CreateUserTag(userID, req)
	if err != nil {
		log.Error("usecase CreateUserTag failed", "error", err)
		if errors.Is(err, tag.ErrUserTagNameConflict) {
			resp.SendError(w, r, http.StatusConflict, err.Error())
		} else if errors.Is(err, tag.ErrTagNameRequired) || errors.Is(err, tag.ErrTagColorInvalid) {
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to create user tag")
		}
		return
	}
	log.Info("user tag created", "tagID", tagResponse.ID)
	resp.SendSuccess(w, r, http.StatusCreated, tagResponse)
}

// GetUserTags
// @Summary Get all tags for the authenticated user
// @Tags user-tags
// @Description Retrieves a list of all personal tags for the authenticated user.
// @Produce json
// @Success 200 {object} response.SuccessResponse{data=[]tag.TagResponse} "User tags retrieved successfully"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /user-tags [get]
// @Security ApiKeyAuth
func (c *TagController) GetUserTags(w http.ResponseWriter, r *http.Request) {
	op := "TagController.GetUserTags"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	tagsResponse, err := c.useCase.GetUserTags(userID)
	if err != nil {
		log.Error("usecase GetUserTags failed", "error", err)
		resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve user tags")
		return
	}
	log.Info("user tags retrieved", slog.Int("count", len(tagsResponse)))
	resp.SendSuccess(w, r, http.StatusOK, tagsResponse)
}

// UpdateUserTag
// @Summary Update an existing user tag
// @Tags user-tags
// @Description Updates a specific personal tag for the authenticated user.
// @Accept json
// @Produce json
// @Param tagID path int true "User Tag ID"
// @Param tag_data body tag.UpdateUserTagRequest true "Data to update user tag"
// @Success 200 {object} response.SuccessResponse{data=tag.TagResponse} "User tag updated successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload, validation error, or invalid Tag ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (not owner of the tag)"
// @Failure 404 {object} response.ErrorResponse "User tag not found"
// @Failure 409 {object} response.ErrorResponse "Tag with this name already exists for the user"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /user-tags/{tagID} [put]
// @Security ApiKeyAuth
func (c *TagController) UpdateUserTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.UpdateUserTag"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	tagIDStr := chi.URLParam(r, "tagID")
	tagID, err := strconv.ParseUint(tagIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Tag ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTagID", tagID))

	var req tag.UpdateUserTagRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for UpdateUserTagRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	tagResponse, err := c.useCase.UpdateUserTag(uint(tagID), userID, req)
	if err != nil {
		log.Error("usecase UpdateUserTag failed", "error", err)
		switch {
		case errors.Is(err, tag.ErrTagNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, tag.ErrTagAccessDenied): // UseCase должен вернуть это, если GetUserTagByID не нашел по userID
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, tag.ErrUserTagNameConflict):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, tag.ErrTagNameRequired) || errors.Is(err, tag.ErrTagColorInvalid):
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to update user tag")
		}
		return
	}
	log.Info("user tag updated", "tagID", tagResponse.ID)
	resp.SendSuccess(w, r, http.StatusOK, tagResponse)
}

// DeleteUserTag
// @Summary Delete a user tag
// @Tags user-tags
// @Description Deletes a specific personal tag for the authenticated user.
// @Produce json
// @Param tagID path int true "User Tag ID"
// @Success 204 "User tag deleted successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Tag ID format"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (not owner of the tag)"
// @Failure 404 {object} response.ErrorResponse "User tag not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /user-tags/{tagID} [delete]
// @Security ApiKeyAuth
func (c *TagController) DeleteUserTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.DeleteUserTag"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	tagIDStr := chi.URLParam(r, "tagID")
	tagID, err := strconv.ParseUint(tagIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Tag ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTagID", tagID))

	err = c.useCase.DeleteUserTag(uint(tagID), userID)
	if err != nil {
		log.Error("usecase DeleteUserTag failed", "error", err)
		switch {
		case errors.Is(err, tag.ErrTagNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, tag.ErrTagAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to delete user tag")
		}
		return
	}
	log.Info("user tag deleted", "tagID", tagID)
	resp.SendOK(w, r, http.StatusNoContent)
}

// --- Team Tag Handlers ---

// CreateTeamTag
// @Summary Create a new team tag
// @Tags team-tags
// @Description Creates a new tag for a specific team. Requires 'owner', 'admin', or 'editor' role in the team.
// @Accept json
// @Produce json
// @Param teamID path int true "Team ID"
// @Param tag_data body tag.CreateTeamTagRequest true "Team tag data"
// @Success 201 {object} response.SuccessResponse{data=tag.TagResponse} "Team tag created successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload, validation error, or invalid Team ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (insufficient role in team)"
// @Failure 404 {object} response.ErrorResponse "Team not found"
// @Failure 409 {object} response.ErrorResponse "Tag with this name already exists for the team"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /teams/{teamID}/tags [post]
// @Security ApiKeyAuth
func (c *TagController) CreateTeamTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.CreateTeamTag"
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

	var req tag.CreateTeamTagRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for CreateTeamTagRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	tagResponse, err := c.useCase.CreateTeamTag(uint(teamID), userID, req)
	if err != nil {
		log.Error("usecase CreateTeamTag failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound): // Ошибка от TeamService, если команда не найдена
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied): // Если пользователь не участник или нет прав
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, tag.ErrTeamTagNameConflict):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, tag.ErrTagNameRequired) || errors.Is(err, tag.ErrTagColorInvalid):
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to create team tag")
		}
		return
	}
	log.Info("team tag created", "tagID", tagResponse.ID, "teamID", teamID)
	resp.SendSuccess(w, r, http.StatusCreated, tagResponse)
}

// GetTeamTags
// @Summary Get all tags for a specific team
// @Tags team-tags
// @Description Retrieves a list of all tags for a specific team. Requester must be a member of the team.
// @Produce json
// @Param teamID path int true "Team ID"
// @Success 200 {object} response.SuccessResponse{data=[]tag.TagResponse} "Team tags retrieved successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Team ID format"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (not a team member)"
// @Failure 404 {object} response.ErrorResponse "Team not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /teams/{teamID}/tags [get]
// @Security ApiKeyAuth
func (c *TagController) GetTeamTags(w http.ResponseWriter, r *http.Request) {
	op := "TagController.GetTeamTags"
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

	tagsResponse, err := c.useCase.GetTeamTags(uint(teamID), userID)
	if err != nil {
		log.Error("usecase GetTeamTags failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve team tags")
		}
		return
	}
	log.Info("team tags retrieved", "teamID", teamID, "count", len(tagsResponse))
	resp.SendSuccess(w, r, http.StatusOK, tagsResponse)
}

// UpdateTeamTag
// @Summary Update an existing team tag
// @Tags team-tags
// @Description Updates a specific tag for a team. Requires 'owner', 'admin', or 'editor' role in the team.
// @Accept json
// @Produce json
// @Param teamID path int true "Team ID"
// @Param tagID path int true "Team Tag ID"
// @Param tag_data body tag.UpdateTeamTagRequest true "Data to update team tag"
// @Success 200 {object} response.SuccessResponse{data=tag.TagResponse} "Team tag updated successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload, validation error, or invalid Team/Tag ID"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (insufficient role or tag not in team)"
// @Failure 404 {object} response.ErrorResponse "Team or Tag not found"
// @Failure 409 {object} response.ErrorResponse "Tag with this name already exists for the team"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /teams/{teamID}/tags/{tagID} [put]
// @Security ApiKeyAuth
func (c *TagController) UpdateTeamTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.UpdateTeamTag"
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

	tagIDStr := chi.URLParam(r, "tagID")
	tagID, err := strconv.ParseUint(tagIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Tag ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTagID", tagID))

	var req tag.UpdateTeamTagRequest
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for UpdateTeamTagRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	tagResponse, err := c.useCase.UpdateTeamTag(uint(tagID), uint(teamID), userID, req)
	if err != nil {
		log.Error("usecase UpdateTeamTag failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound), errors.Is(err, tag.ErrTagNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, tag.ErrTeamTagNameConflict):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, tag.ErrTagNameRequired) || errors.Is(err, tag.ErrTagColorInvalid):
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to update team tag")
		}
		return
	}
	log.Info("team tag updated", "tagID", tagResponse.ID, "teamID", teamID)
	resp.SendSuccess(w, r, http.StatusOK, tagResponse)
}

// DeleteTeamTag
// @Summary Delete a team tag
// @Tags team-tags
// @Description Deletes a specific tag for a team. Requires 'owner', 'admin', or 'editor' role in the team.
// @Produce json
// @Param teamID path int true "Team ID"
// @Param tagID path int true "Team Tag ID"
// @Success 204 "Team tag deleted successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid Team/Tag ID format"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 403 {object} response.ErrorResponse "Access denied (insufficient role or tag not in team)"
// @Failure 404 {object} response.ErrorResponse "Team or Tag not found"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /teams/{teamID}/tags/{tagID} [delete]
// @Security ApiKeyAuth
func (c *TagController) DeleteTeamTag(w http.ResponseWriter, r *http.Request) {
	op := "TagController.DeleteTeamTag"
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

	tagIDStr := chi.URLParam(r, "tagID")
	tagID, err := strconv.ParseUint(tagIDStr, 10, 32)
	if err != nil {
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Tag ID format")
		return
	}
	log = log.With(slog.Uint64("parsedTagID", tagID))

	err = c.useCase.DeleteTeamTag(uint(tagID), uint(teamID), userID)
	if err != nil {
		log.Error("usecase DeleteTeamTag failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound), errors.Is(err, tag.ErrTagNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to delete team tag")
		}
		return
	}
	log.Info("team tag deleted", "tagID", tagID, "teamID", teamID)
	resp.SendOK(w, r, http.StatusNoContent)
}
