package controller

type UserSignUpRequest struct {
	Login    string `json:"login,omitempty" validate:"omitempty,min=1,max=50" example:"user1"`
	Email    string `json:"email" validate:"required,email" example:"jon.doe@gmail.com"`
	Password string `json:"password" validate:"required" example:"SuperPassword123"`
}

type UserSignInRequest struct {
	Login    string `json:"login,omitempty" validate:"omitempty,min=1,max=50" example:"user1"`
	Email    string `json:"email,omitempty" validate:"omitempty,email" example:"jon.doe@gmail.com"`
	Password string `json:"password" validate:"required" example:"SuperPassword123"`
}

type RefreshTokenNativeRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}
