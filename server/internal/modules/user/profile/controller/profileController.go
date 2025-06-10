package controller

import (
	"encoding/json"
	"errors"
	"github.com/go-playground/validator/v10"
	"log/slog"
	"mime/multipart"
	"net/http"
	"server/config"
	gouser "server/internal/modules/user"
	"server/internal/modules/user/profile"
	resp "server/pkg/lib/response"
	"time"
)

type ProfileController struct {
	log      *slog.Logger
	usecase  profile.UseCase // Используем интерфейс profile.UseCase из entity.go
	validate *validator.Validate
	jwtCfg   config.JWTConfig
}

func NewProfileController(log *slog.Logger, uc profile.UseCase, jwtCfg config.JWTConfig) profile.Controller { // Возвращаем интерфейс profile.Controller
	validate := validator.New()
	return &ProfileController{ // ProfileController должен реализовывать profile.Controller
		log:      log,
		usecase:  uc,
		validate: validate,
		jwtCfg:   jwtCfg,
	}
}

func (c *ProfileController) GetUser(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.GetUser"
	log := c.log.With(slog.String("op", op))
	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("cannot get userID from context")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))
	userProfile, err := c.usecase.GetUser(userID)
	if err != nil {
		log.Error("usecase GetUser failed", "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "failed to get profile")
		}
		return
	}
	log.Info("user profile retrieved successfully")
	resp.SendSuccess(w, r, http.StatusOK, userProfile)
}

func (c *ProfileController) parseMultipartFormForProfile(
	w http.ResponseWriter, r *http.Request, jsonRequestData interface{},
) (avatarFileHeader *multipart.FileHeader, ok bool) {
	log := c.log.With(slog.String("op", "ProfileController.parseMultipartForm"))
	const maxUploadSize = 2 * 1024 * 1024
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
	if err := r.ParseMultipartForm(maxUploadSize); err != nil {
		if errors.As(err, new(*http.MaxBytesError)) {
			log.Warn("request body too large", "error", err, "limit", maxUploadSize)
			resp.SendError(w, r, http.StatusRequestEntityTooLarge, gouser.ErrInvalidSizeAvatar.Error())
			return nil, false
		}
		log.Error("failed to parse multipart form", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "invalid multipart form")
		return nil, false
	}
	jsonDataField := r.FormValue("json_data")
	if jsonDataField == "" && r.Method == http.MethodPut {
		log.Warn("missing 'json_data' field in PUT multipart form")
		resp.SendError(w, r, http.StatusBadRequest, "missing 'json_data' form field for PUT request")
		return nil, false
	}
	if jsonDataField != "" {
		if err := json.Unmarshal([]byte(jsonDataField), jsonRequestData); err != nil {
			log.Error("failed to unmarshal json_data", "error", err, "raw_json", jsonDataField)
			resp.SendError(w, r, http.StatusBadRequest, "invalid json_data format")
			return nil, false
		}
		if err := c.validate.Struct(jsonRequestData); err != nil {
			log.Warn("validation failed for json_data", "error", err)
			resp.SendValidationError(w, r, err)
			return nil, false
		}
	} else if r.Method == http.MethodPatch && jsonDataField == "" {
		log.Info("No json_data provided for PATCH, assuming avatar-only update or no field updates.")
	}
	_, hdr, errFormFile := r.FormFile("avatar")
	if errFormFile != nil {
		if !errors.Is(errFormFile, http.ErrMissingFile) {
			log.Error("error retrieving avatar file from form", "error", errFormFile)
			resp.SendError(w, r, http.StatusBadRequest, gouser.ErrInvalidAvatarFile.Error())
			return nil, false
		}
		log.Debug("No avatar file provided in the form.")
	} else {
		log.Info("Avatar file received", "filename", hdr.Filename, "size", hdr.Size)
		avatarFileHeader = hdr
	}
	return avatarFileHeader, true
}

func (c *ProfileController) UpdateUser(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.UpdateUser (PUT)"
	log := c.log.With(slog.String("op", op))
	userID, okCtx := r.Context().Value("userId").(uint)
	if !okCtx {
		log.Error("cannot get userID from context")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))
	var reqJSON profile.UpdateUserProfileRequest
	avatarFileHeader, okParse := c.parseMultipartFormForProfile(w, r, &reqJSON)
	if !okParse {
		return
	}
	updatedUserProfile, err := c.usecase.UpdateUser(userID, &reqJSON, avatarFileHeader)
	if err != nil {
		log.Error("usecase UpdateUser failed", "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		} else if errors.Is(err, gouser.ErrLoginExists) {
			resp.SendError(w, r, http.StatusConflict, err.Error())
		} else if errors.Is(err, gouser.ErrInvalidTypeAvatar) || errors.Is(err, gouser.ErrInvalidResolutionAvatar) || errors.Is(err, gouser.ErrInvalidAvatarFile) || errors.Is(err, gouser.ErrInvalidSizeAvatar) {
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "failed to update profile")
		}
		return
	}
	log.Info("user profile updated successfully via PUT")
	resp.SendSuccess(w, r, http.StatusOK, updatedUserProfile)
}

func (c *ProfileController) PatchUser(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.PatchUser"
	log := c.log.With(slog.String("op", op))
	userID, okCtx := r.Context().Value("userId").(uint)
	if !okCtx {
		log.Error("cannot get userID from context for PATCH")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))
	var reqJSON profile.PatchUserProfileRequest
	avatarFileHeader, okParse := c.parseMultipartFormForProfile(w, r, &reqJSON)
	if !okParse {
		return
	}
	if r.FormValue("json_data") == "" && avatarFileHeader == nil {
		log.Warn("PATCH request with no data to update (neither json_data nor avatar).")
	}
	updatedUserProfile, err := c.usecase.PatchUser(userID, &reqJSON, avatarFileHeader)
	if err != nil {
		log.Error("usecase PatchUser failed", "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		} else if errors.Is(err, gouser.ErrLoginExists) {
			resp.SendError(w, r, http.StatusConflict, err.Error())
		} else if errors.Is(err, gouser.ErrInvalidTypeAvatar) || errors.Is(err, gouser.ErrInvalidResolutionAvatar) || errors.Is(err, gouser.ErrInvalidAvatarFile) || errors.Is(err, gouser.ErrInvalidSizeAvatar) {
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "failed to patch profile")
		}
		return
	}
	log.Info("user profile patched successfully")
	resp.SendSuccess(w, r, http.StatusOK, updatedUserProfile)
}

func (c *ProfileController) DeleteUser(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.DeleteUser"
	log := c.log.With(slog.String("op", op))
	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("cannot get userID from context")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))
	err := c.usecase.DeleteUser(userID)
	if err != nil {
		log.Error("usecase DeleteUser failed", "error", err)
		if errors.Is(err, gouser.ErrUserNotFound) {
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "failed to delete profile")
		}
		return
	}
	log.Info("user profile deleted successfully, clearing refresh token cookie")
	http.SetCookie(w, &http.Cookie{
		Name: "refresh_token", Value: "", Expires: time.Unix(0, 0),
		HttpOnly: true, Path: "/", Secure: c.jwtCfg.SecureCookie,
		SameSite: http.SameSiteNoneMode, Domain: c.jwtCfg.CookieDomain,
	})
	w.WriteHeader(http.StatusNoContent)
}

// RegisterDeviceToken
// @Summary Register a new device token for push notifications
// @Tags Profile Management
// @Description Registers a device token for the authenticated user.
// @Accept json
// @Produce json
// @Param token_data body profile.RegisterDeviceTokenRequest true "Device token and type"
// @Success 204 "Device token registered successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload or validation error"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /profile/device-tokens [post]
// @Security ApiKeyAuth
func (c *ProfileController) RegisterDeviceToken(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.RegisterDeviceToken"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("cannot get userID from context")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var req profile.RegisterDeviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}

	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for RegisterDeviceTokenRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	err := c.usecase.RegisterDeviceToken(r.Context(), userID, req.DeviceToken, req.DeviceType)
	if err != nil {
		log.Error("usecase RegisterDeviceToken failed", "error", err)
		if errors.Is(err, gouser.ErrBadRequest) { // Если UseCase вернул ошибку валидации типа устройства
			resp.SendError(w, r, http.StatusBadRequest, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "Failed to register device token")
		}
		return
	}

	log.Info("Device token registered successfully")
	resp.SendOK(w, r, http.StatusNoContent)
}

// UnregisterDeviceToken
// @Summary Unregister a device token
// @Tags Profile Management
// @Description Unregisters (deletes) a specific device token for the authenticated user.
// @Accept json
// @Produce json
// @Param token_data body profile.UnregisterDeviceTokenRequest true "Device token to unregister"
// @Success 204 "Device token unregistered successfully"
// @Failure 400 {object} response.ErrorResponse "Invalid request payload or validation error"
// @Failure 401 {object} response.ErrorResponse "Unauthorized"
// @Failure 500 {object} response.ErrorResponse "Internal server error"
// @Router /profile/device-tokens [delete]
// @Security ApiKeyAuth
func (c *ProfileController) UnregisterDeviceToken(w http.ResponseWriter, r *http.Request) {
	op := "ProfileController.UnregisterDeviceToken"
	log := c.log.With(slog.String("op", op))

	userID, ok := r.Context().Value("userId").(uint)
	if !ok {
		log.Error("cannot get userID from context")
		resp.SendError(w, r, http.StatusUnauthorized, "unauthorized")
		return
	}
	log = log.With(slog.Uint64("userID", uint64(userID)))

	var req profile.UnregisterDeviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Warn("failed to decode request body", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "Invalid request payload")
		return
	}
	if err := c.validate.Struct(req); err != nil {
		log.Warn("validation failed for UnregisterDeviceTokenRequest", "error", err)
		resp.SendValidationError(w, r, err)
		return
	}

	err := c.usecase.UnregisterDeviceToken(r.Context(), userID, req.DeviceToken)
	if err != nil {
		log.Error("usecase UnregisterDeviceToken failed", "error", err)
		resp.SendError(w, r, http.StatusInternalServerError, "Failed to unregister device token")
		return
	}

	log.Info("Device token unregistered successfully")
	resp.SendOK(w, r, http.StatusNoContent)
}
