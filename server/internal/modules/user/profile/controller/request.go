package controller

type UpdateUserRequest struct {
	Login *string `json:"login,omitempty" validate:"omitempty,min=3,max=50"`
}
