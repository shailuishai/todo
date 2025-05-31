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
	"time" // Для SetCookie в DeleteUser
)

type ProfileController struct {
	log      *slog.Logger
	usecase  profile.UseCase
	validate *validator.Validate
	jwtCfg   config.JWTConfig
}

func NewProfileController(log *slog.Logger, uc profile.UseCase, jwtCfg config.JWTConfig) *ProfileController {
	validate := validator.New()
	return &ProfileController{
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

// parseMultipartFormForProfile является общей функцией для PUT и PATCH
func (c *ProfileController) parseMultipartFormForProfile(
	w http.ResponseWriter, r *http.Request,
	jsonRequestData interface{}, // Указатель на структуру для JSON (UpdateUserProfileRequest или PatchUserProfileRequest)
) (avatarFileHeader *multipart.FileHeader, ok bool) {

	log := c.log.With(slog.String("op", "ProfileController.parseMultipartForm"))

	const maxUploadSize = 2 * 1024 * 1024 // 2 MB
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
	if err := r.ParseMultipartForm(maxUploadSize); err != nil {
		if errors.As(err, new(*http.MaxBytesError)) {
			log.Warn("request body (multipart form) too large", "error", err, "limit", maxUploadSize)
			resp.SendError(w, r, http.StatusRequestEntityTooLarge, gouser.ErrInvalidSizeAvatar.Error())
			return nil, false
		}
		log.Error("failed to parse multipart form", "error", err)
		resp.SendError(w, r, http.StatusBadRequest, "invalid multipart form")
		return nil, false
	}

	jsonDataField := r.FormValue("json_data")
	// Для PATCH json_data может отсутствовать, если меняется только аватар
	// Для PUT он обязателен (или должен быть пустым JSON объектом {})
	if jsonDataField == "" && r.Method == http.MethodPut { // Для PUT json_data обязателен
		log.Warn("missing 'json_data' field in PUT multipart form")
		resp.SendError(w, r, http.StatusBadRequest, "missing 'json_data' form field for PUT request")
		return nil, false
	}

	if jsonDataField != "" { // Парсим json_data, если он есть
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
		// Если это PATCH и json_data нет, это нормально, если пришел файл аватара
		log.Info("No json_data provided for PATCH, assuming avatar-only update or no field updates.")
	}

	_, hdr, errFormFile := r.FormFile("avatar")
	if errFormFile != nil {
		if !errors.Is(errFormFile, http.ErrMissingFile) {
			log.Error("error retrieving avatar file from form", "error", errFormFile)
			resp.SendError(w, r, http.StatusBadRequest, gouser.ErrInvalidAvatarFile.Error())
			return nil, false
		}
		// Если файл отсутствует, это нормально, avatarFileHeader останется nil
		log.Debug("No avatar file provided in the form.")
	} else {
		log.Info("Avatar file received", "filename", hdr.Filename, "size", hdr.Size)
		avatarFileHeader = hdr // Возвращаем FileHeader
	}
	return avatarFileHeader, true
}

// UpdateUser (PUT)
// (Swagger аннотации остаются как в твоем предыдущем файле)
// @Summary      Update user profile (PUT)
// @Description  Fully updates the profile information. All mutable fields should be provided.
// @Tags         Profile Management
// @Accept       multipart/form-data
// @Produce      json
// @Param        json_data formData string true "JSON string with ALL profile data fields."
// @Param        avatar    formData file   false "New avatar image file."
// @Success      200 {object} response.SuccessResponse{data=profile.UserProfileResponse} "Profile updated."
// @Router       /profile [put]
// @Security     ApiKeyAuth
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
		return // Ошибка уже отправлена parseMultipartFormForProfile
	}
	// Для PUT, если reqJSON пустая (например, json_data был "{}"), это может быть валидно, если мы ожидаем,
	// что PUT всегда сбрасывает поля на дефолты или требует все поля.
	// Текущая валидация в DTO (omitempty) позволяет частичные данные, что ближе к PATCH.
	// Для строгого PUT, валидатор должен требовать все поля или UseCase должен их обрабатывать соответственно.
	// Пока оставляем как есть, UseCase.UpdateUser применит то, что есть в reqJSON.

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

// PatchUser (PATCH)
// @Summary      Partially update user profile (PATCH)
// @Description  Partially updates profile fields. Only provided fields in json_data will be updated.
// @Description  Avatar can also be updated or reset.
// @Tags         Profile Management
// @Accept       multipart/form-data
// @Produce      json
// @Param        json_data formData string false "JSON string with profile fields to update (all optional)." example({"login":"new_username_partial","theme":"dark"})
// @Param        avatar    formData file   false "New avatar image file."
// @Success      200 {object} response.SuccessResponse{data=profile.UserProfileResponse} "Profile partially updated."
// @Router       /profile [patch]
// @Security     ApiKeyAuth
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

	var reqJSON profile.PatchUserProfileRequest // Используем DTO для PATCH
	avatarFileHeader, okParse := c.parseMultipartFormForProfile(w, r, &reqJSON)
	if !okParse {
		return
	}
	// Проверяем, что хотя бы что-то пришло для PATCH (json_data или avatar)
	// jsonDataField был r.FormValue("json_data")
	if r.FormValue("json_data") == "" && avatarFileHeader == nil {
		log.Warn("PATCH request with no data to update (neither json_data nor avatar).")
		// Можно вернуть 200 с текущим профилем или 400, если это считается ошибкой.
		// Пока что, если UseCase вернет "no changes", то вернется 200 с текущим профилем.
		// Но лучше, если UseCase вернет ошибку типа "ErrNoChangesProvided".
		// Или здесь отправить 400:
		// resp.SendError(w, r, http.StatusBadRequest, "No data provided for PATCH update.")
		// return
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

// DeleteUser (без изменений)
// @Summary      Delete current user's account
// @Router       /profile [delete]
// @Security     ApiKeyAuth
// ... (остальные Swagger аннотации как были)
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
		if errors.Is(err, gouser.ErrUserNotFound) { // Если UseCase вернул ErrUserNotFound
			resp.SendError(w, r, http.StatusNotFound, err.Error())
		} else {
			resp.SendError(w, r, http.StatusInternalServerError, "failed to delete profile")
		}
		return
	}

	log.Info("user profile deleted successfully, clearing refresh token cookie")
	http.SetCookie(w, &http.Cookie{
		Name: "refresh_token", Value: "", Expires: time.Unix(0, 0), // Прошлое время для удаления
		HttpOnly: true, Path: "/", Secure: c.jwtCfg.SecureCookie, // Зависит от конфигурации
		SameSite: http.SameSiteNoneMode, Domain: c.jwtCfg.CookieDomain, // Зависит от конфигурации
	})
	w.WriteHeader(http.StatusNoContent)
}
