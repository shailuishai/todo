package response

import (
	"errors"
	"fmt"
	"github.com/go-chi/render"
	"github.com/go-playground/validator/v10"
	"net/http"
	"server/internal/modules/user/profile" // Для UserProfileData
	"strings"
)

// Response представляет общую структуру ответа API
type Response struct {
	Status string      `json:"status" example:"success/error"` // "success" or "error"
	Error  string      `json:"error,omitempty" example:"Error message if status is 'error'"`
	Data   interface{} `json:"data,omitempty"` // Payload for success responses
}

// SuccessResponse используется для Swagger, чтобы показать структуру успешного ответа с data
type SuccessResponse struct {
	Status string      `json:"status" example:"success"`
	Data   interface{} `json:"data"`
}

// ErrorResponse используется для Swagger, чтобы показать структуру ответа с ошибкой
type ErrorResponse struct {
	Status string `json:"status" example:"error"`
	Error  string `json:"error" example:"Error message"`
}

const (
	StatusOK    = "success"
	StatusError = "error"
)

// --- Функции для формирования стандартных ответов ---

func OK() Response {
	return Response{
		Status: StatusOK,
	}
}

func Success(data interface{}) Response {
	return Response{
		Status: StatusOK,
		Data:   data,
	}
}

func Error(message string) Response {
	return Response{
		Status: StatusError,
		Error:  message,
	}
}

// --- Функции для отправки ответов ---

func SendSuccess(w http.ResponseWriter, r *http.Request, statusCode int, data interface{}) {
	render.Status(r, statusCode)
	render.JSON(w, r, Success(data))
}

func SendOK(w http.ResponseWriter, r *http.Request, statusCode int) {
	render.Status(r, statusCode)
	render.JSON(w, r, OK())
}

func SendError(w http.ResponseWriter, r *http.Request, statusCode int, errorMessage string) {
	render.Status(r, statusCode)
	render.JSON(w, r, Error(errorMessage))
}

func SendValidationError(w http.ResponseWriter, r *http.Request, err error) {
	var errMsgs []string
	var validationErrs validator.ValidationErrors

	if errors.As(err, &validationErrs) {
		for _, fe := range validationErrs {
			// Формируем сообщение на основе тега валидации и поля
			// Можно сделать более кастомные сообщения
			errMsgs = append(errMsgs, fmt.Sprintf("field '%s' failed on a '%s' validation", strings.ToLower(fe.Field()), fe.Tag()))
		}
	} else {
		// Если это не ошибка валидатора, просто используем текст ошибки
		errMsgs = append(errMsgs, err.Error())
	}

	render.Status(r, http.StatusBadRequest) // Ошибки валидации обычно 400
	render.JSON(w, r, Error(strings.Join(errMsgs, "; ")))
}

// --- Специфичные структуры данных для ответов (если нужны) ---

type AccessTokenData struct {
	AccessToken string `json:"access_token"`
}

// UserProfileResponseData используется для Swagger и может быть кастомизирован для ответа GetUser
// Используем непосредственно profile.UserProfile для data в SendSuccess
// Эта структура UserProfileData из твоего предыдущего кода была для примера, но мы можем
// просто передавать *profile.UserProfile в `Success(data)`.
// Если нужно кастомизировать JSON поля, то можно использовать отдельную структуру.
// type UserProfileResponseData struct {
// 	UserID             uint    `json:"user_id"`
// 	Login              *string `json:"login,omitempty"`
// 	Email              *string `json:"email,omitempty"`
// 	AvatarUrl          *string `json:"avatar_url,omitempty"`
// 	Theme              *string `json:"theme,omitempty"`
// 	AccentColor        *string `json:"accent_color,omitempty"`
// 	IsSidebarCollapsed *bool   `json:"is_sidebar_collapsed,omitempty"`
// }
//
// func ForUserProfile(user *profile.UserProfile) Response {
// 	if user == nil {
// 		return Error("user data is nil") // Или другая обработка
// 	}
// 	data := UserProfileResponseData{
// 		UserID:            user.UserId,
// 		Login:             user.Login,
// 		Email:             user.Email,
// 		AvatarUrl:         user.AvatarUrl,
// 		Theme:             user.Theme,
// 		AccentColor:       user.AccentColor,
// 		IsSidebarCollapsed: user.IsSidebarCollapsed,
// 	}
// 	return Success(data)
// }

// --- Старые функции из твоего примера, адаптированные ---
// Они создают Response структуру, а не отправляют ее.
// Функции Send* выше предпочтительнее для контроллеров.

func AccessToken(token string) Response { // Эта функция создает Response, а не отправляет
	return Response{
		Status: StatusOK,
		Data: AccessTokenData{
			AccessToken: token,
		},
	}
}

// UserProfile - создает Response для профиля пользователя.
// Переименовал, чтобы не конфликтовать с profile.UserProfile.
// Рекомендую использовать SendSuccess(w, r, http.StatusOK, userProfileDTO) напрямую в контроллере.
func UserProfileResponse(user *profile.UserProfileResponse) Response {
	return Response{
		Status: StatusOK,
		Data:   user, // Передаем DTO как есть
	}
}
