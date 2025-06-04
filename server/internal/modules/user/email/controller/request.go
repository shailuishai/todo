package controller

type SendConfirmedEmailCodeRequest struct {
	Email string `json:"email" validate:"required,email" example:"jon.doe@gmail.com"`
}

type EmailConfirmedRequest struct {
	Code  string `json:"code" validate:"required" example:"54JK64"`
	Email string `json:"email" validate:"required,email" example:"jon.doe@gmail.com"`
}
