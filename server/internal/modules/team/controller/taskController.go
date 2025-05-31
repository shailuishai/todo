package controller

import (
	"github.com/go-playground/validator/v10"
	"log/slog"
	"server/config"
	"server/internal/modules/team" // Для интерфейса team.UseCase и team.Controller
)

// TeamController обрабатывает HTTP-запросы, связанные с командами.
// Методы-хендлеры будут реализованы в отдельных файлах (teamHandlers.go, memberHandlers.go).
type TeamController struct {
	useCase  team.UseCase
	log      *slog.Logger
	validate *validator.Validate
	cfg      *config.Config // Общая конфигурация (например, для MaxUploadSize S3)
}

// NewTeamController создает новый экземпляр TeamController.
func NewTeamController(useCase team.UseCase, log *slog.Logger, cfg *config.Config) team.Controller {
	return &TeamController{
		useCase:  useCase,
		log:      log,
		validate: validator.New(),
		cfg:      cfg,
	}
}
