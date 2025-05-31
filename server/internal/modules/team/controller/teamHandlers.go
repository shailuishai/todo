package controller

import (
	"encoding/json"
	"errors"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"log/slog"
	"mime/multipart"
	"net/http"
	"strconv"

	"server/internal/modules/team" // Для ошибок и DTO ответов
	resp "server/pkg/lib/response"
)

func (c *TeamController) CreateTeam(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.CreateTeam"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	// multipart/form-data ожидается, так как изображение может быть добавлено в будущем через UpdateTeam
	// Но для CreateTeamRequest DTO сейчас не содержит поля для файла.
	// Если CreateTeam всегда БЕЗ файла, то Content-Type должен быть application/json.
	// Если CreateTeam МОЖЕТ иметь файл (даже если сейчас DTO его не описывает),
	// то multipart/form-data и парсинг json_data из поля формы.
	// Судя по вашим DTO, CreateTeamRequest - это JSON.

	var req team.CreateTeamRequest
	// Парсим JSON из тела запроса
	if err := render.DecodeJSON(r.Body, &req); err != nil {
		log.Warn("failed to decode JSON request body for CreateTeam", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload: not a valid JSON")
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for CreateTeamRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	teamResponse, err := c.useCase.CreateTeam(userID, req)
	if err != nil {
		log.Error("usecase CreateTeam failed", "error", err)
		if errors.Is(err, team.ErrTeamNameRequired) {
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to create team")
		}
		return
	}

	log.Info("team created successfully", slog.Uint64("teamID", uint64(teamResponse.TeamID)))
	resp.SendSuccess(w, r, http.StatusCreated, teamResponse)
}

func (c *TeamController) GetTeam(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.GetTeam"
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

	teamDetailResponse, err := c.useCase.GetTeamByID(uint(teamID), userID)
	if err != nil {
		log.Warn("usecase GetTeamByID failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			log.Error("unhandled error in usecase GetTeamByID", "error", err)
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve team")
		}
		return
	}

	log.Info("team retrieved successfully", slog.Uint64("retrievedTeamID", uint64(teamDetailResponse.TeamID)))
	resp.SendSuccess(w, r, http.StatusOK, teamDetailResponse)
}

func (c *TeamController) GetMyTeams(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.GetMyTeams"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		resp.SendError(w, r, http.StatusUnauthorized, "Unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var reqParams team.GetMyTeamsRequest
	if searchStr := r.URL.Query().Get("search"); searchStr != "" {
		reqParams.Search = &searchStr
	}

	if err := c.validate.Struct(reqParams); err != nil {
		log.Warn("validation failed for GetMyTeamsRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	teamsList, err := c.useCase.GetMyTeams(userID, reqParams)
	if err != nil {
		log.Error("usecase GetMyTeams failed", "error", err)
		resp.SendError(w, r, http.StatusInternalServerError, "Failed to retrieve user's teams")
		return
	}

	log.Info("user's teams retrieved successfully", slog.Int("count", len(teamsList)))
	resp.SendSuccess(w, r, http.StatusOK, teamsList)
}

func (c *TeamController) UpdateTeam(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.UpdateTeam"
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
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Team ID")
		return
	}
	log = log.With(slog.Uint64("parsedTeamID", teamID))

	maxUploadSize := c.cfg.S3Config.MaxTeamImageSizeBytes
	if maxUploadSize == 0 {
		maxUploadSize = 5 * 1024 * 1024 // Default 5MB
	}

	// Важно установить MaxBytesReader до ParseMultipartForm
	r.Body = http.MaxBytesReader(w, r.Body, int64(maxUploadSize))
	if err := r.ParseMultipartForm(int64(maxUploadSize)); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) { // Используем errors.As для проверки типа ошибки
			log.Warn("request body (multipart form) too large for team update", "error", err, "limit", maxUploadSize)
			resp.SendError(w, r, http.StatusRequestEntityTooLarge, team.ErrTeamImageInvalidSize.Error())
			return
		}
		log.Error("failed to parse multipart form for team update", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid multipart form")
		return
	}

	var req team.UpdateTeamDetailsRequest
	jsonDataField := r.FormValue("json_data")
	if jsonDataField == "" {
		// Если json_data нет, но есть файл или ResetImage, это может быть нормально.
		// Если нет ни json_data, ни файла, ни ResetImage, то UseCase вернет ErrTeamNoChanges.
		log.Debug("json_data field is empty for team update. This is okay if only image is being updated or reset.")
		// Пустая структура будет передана, и валидатор не должен ругаться, т.к. поля omitempty
	} else {
		if err := json.Unmarshal([]byte(jsonDataField), &req); err != nil {
			log.Error("failed to unmarshal json_data for team update", "error", err, "raw_json", jsonDataField)
			resp.SendError(w, r, http.StatusBadRequest, "Invalid json_data format")
			return
		}
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for team update json_data", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	var imageFileHeader *multipart.FileHeader
	file, header, errFormFile := r.FormFile("image")
	if errFormFile != nil {
		if !errors.Is(errFormFile, http.ErrMissingFile) {
			log.Error("error retrieving team image file from form", "error", errFormFile)
			resp.SendError(w, r, http.StatusBadRequest, "Invalid image file in form")
			return
		}
		log.Debug("No team image file provided in the form for update.")
	} else {
		defer file.Close()
		imageFileHeader = header
		log.Info("Team image file received for update", "filename", header.Filename, "size", header.Size)
	}

	teamResponse, err := c.useCase.UpdateTeamDetails(uint(teamID), userID, req, imageFileHeader)
	if err != nil {
		log.Error("usecase UpdateTeamDetails failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		case errors.Is(err, team.ErrTeamImageInvalidType), errors.Is(err, team.ErrTeamImageInvalidSize), errors.Is(err, team.ErrTeamImageUploadFailed):
			resp.SendError(w, r, http.StatusUnprocessableEntity, err.Error())
		case errors.Is(err, team.ErrTeamIsDeleted):
			resp.SendError(w, r, http.StatusConflict, err.Error())
		case errors.Is(err, team.ErrTeamNoChanges): // Если не было изменений
			resp.SendError(w, r, http.StatusBadRequest, err.Error()) // 400 Bad Request
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to update team")
		}
		return
	}

	log.Info("team updated successfully")
	resp.SendSuccess(w, r, http.StatusOK, teamResponse)
}

func (c *TeamController) DeleteTeam(w http.ResponseWriter, r *http.Request) {
	op := "TeamController.DeleteTeam"
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
		resp.SendError(w, r, http.StatusBadRequest, "Invalid Team ID")
		return
	}
	log = log.With(slog.Uint64("parsedTeamID", teamID))

	err = c.useCase.DeleteTeam(uint(teamID), userID)
	if err != nil {
		log.Error("usecase DeleteTeam failed", "error", err)
		switch {
		case errors.Is(err, team.ErrTeamNotFound):
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		case errors.Is(err, team.ErrTeamAccessDenied):
			resp.SendError(w, r, http.StatusForbidden, err.Error())
		default:
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to delete team")
		}
		return
	}

	log.Info("team deleted successfully")
	resp.SendOK(w, r, http.StatusNoContent)
}
