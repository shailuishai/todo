package main

import (
	"context"
	"errors"
	"fmt"
	httpSwagger "github.com/swaggo/http-swagger/v2"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"
	"github.com/robfig/cron/v3"
	"server/config"
	"server/docs"

	"server/internal/init/cache"
	"server/internal/init/database"
	s3init "server/internal/init/s3"

	// User submodules
	authC "server/internal/modules/user/auth/controller"
	authRp "server/internal/modules/user/auth/repo"
	authCache "server/internal/modules/user/auth/repo/cache"
	authDb "server/internal/modules/user/auth/repo/database"
	authUC "server/internal/modules/user/auth/usecase"

	emailC "server/internal/modules/user/email/controller"
	emailRp "server/internal/modules/user/email/repo"
	emailCache "server/internal/modules/user/email/repo/cache"
	emailDb "server/internal/modules/user/email/repo/database"
	emailUC "server/internal/modules/user/email/usecase"

	profileC "server/internal/modules/user/profile/controller"
	profileRp "server/internal/modules/user/profile/repo"
	profileDb "server/internal/modules/user/profile/repo/database"
	profileS3 "server/internal/modules/user/profile/repo/s3"
	profileUC "server/internal/modules/user/profile/usecase"

	// Task module
	taskC "server/internal/modules/task/controller"
	taskRp "server/internal/modules/task/repo"
	taskCacheRepo "server/internal/modules/task/repo/cache"
	taskDbRepo "server/internal/modules/task/repo/database"
	taskUC "server/internal/modules/task/usecase"

	// Team module
	teamC "server/internal/modules/team/controller"
	teamRp "server/internal/modules/team/repo"
	teamCacheRepo "server/internal/modules/team/repo/cache"
	teamDbRepo "server/internal/modules/team/repo/database"
	teamS3Repo "server/internal/modules/team/repo/s3"
	teamUC "server/internal/modules/team/usecase"

	// Tag module
	tagC "server/internal/modules/tag/controller"         // <<< НОВЫЙ ИМПОРТ
	tagRp "server/internal/modules/tag/repo"              // <<< НОВЫЙ ИМПОРТ
	tagCacheRepo "server/internal/modules/tag/repo/cache" // <<< НОВЫЙ ИМПОРТ
	tagDbRepo "server/internal/modules/tag/repo/database" // <<< НОВЫЙ ИМПОРТ
	tagUC "server/internal/modules/tag/usecase"           // <<< НОВЫЙ ИМПОРТ

	"server/pkg/lib/TaskService"
	"server/pkg/lib/emailsender"
	appMiddleware "server/pkg/middleware/jwt"
	"server/pkg/middleware/logger"
)

// App struct and NewApp, Start methods ... (без изменений) ...
type App struct {
	Storage     *database.Storage
	Cache       *cache.Cache
	S3          *s3init.S3Storage
	EmailSender *emailsender.EmailSender
	Router      chi.Router
	Log         *slog.Logger
	Cfg         *config.Config
	Cron        *cron.Cron
	TS          *TaskService.TaskService
}

func NewApp(cfg *config.Config, log *slog.Logger) (*App, error) {
	storage, err := database.NewStorage(cfg.DbConfig)
	if err != nil {
		return nil, fmt.Errorf("db init failed: %w", err)
	}

	appCache, err := cache.NewCache(cfg.CacheConfig)
	if err != nil {
		return nil, fmt.Errorf("cache init failed: %w", err)
	}

	s3s, err := s3init.NewS3Storage(cfg.S3Config)
	if err != nil {
		return nil, fmt.Errorf("s3 init failed: %w", err)
	}

	eSender, err := emailsender.New(cfg.SMTPConfig)
	if err != nil {
		return nil, fmt.Errorf("email sender init failed: %w", err)
	}

	router := chi.NewRouter()
	bgTaskService := TaskService.NewTaskService(storage.Db, log)
	cronScheduler := cron.New()
	_, err = cronScheduler.AddFunc("0 0 * * *", func() {
		bgTaskService.CleanUnverifiedUsers()
	})
	if err != nil {
		return nil, fmt.Errorf("cron init failed: %w", err)
	}
	cronScheduler.Start()

	return &App{
		Storage:     storage,
		Cache:       appCache,
		S3:          s3s,
		EmailSender: eSender,
		Router:      router,
		Log:         log,
		Cfg:         cfg,
		Cron:        cronScheduler,
		TS:          bgTaskService,
	}, nil
}

func (app *App) Start() error {
	srv := &http.Server{
		Addr:         app.Cfg.HttpServerConfig.Address,
		Handler:      app.Router,
		ReadTimeout:  app.Cfg.HttpServerConfig.Timeout,
		WriteTimeout: app.Cfg.HttpServerConfig.Timeout,
		IdleTimeout:  app.Cfg.HttpServerConfig.IdleTimeout,
	}

	protocol := "https" // По умолчанию http
	if app.Cfg.HttpServerConfig.TLS.Enabled {
		protocol = "https"
	}
	swaggerHost := app.Cfg.HttpServerConfig.Address
	if strings.HasPrefix(swaggerHost, "0.0.0.0:") {
		swaggerHost = "localhost" + swaggerHost[len("0.0.0.0"):]
	} else if strings.HasPrefix(swaggerHost, ":") {
		swaggerHost = "localhost" + swaggerHost
	}

	docs.SwaggerInfo.Host = swaggerHost
	docs.SwaggerInfo.Schemes = []string{protocol}

	var swaggerSchemeForLog string
	if len(docs.SwaggerInfo.Schemes) > 0 {
		swaggerSchemeForLog = docs.SwaggerInfo.Schemes[0]
	} else {
		swaggerSchemeForLog = "http"
		app.Log.Warn("docs.SwaggerInfo.Schemes is empty, defaulting to http for logging Swagger URL")
	}

	serverShutdown := make(chan error, 1)
	go func() {
		var err error
		serverType := "HTTP"
		addr := app.Cfg.HttpServerConfig.Address
		app.Log.Info("Attempting to start server", slog.String("address", addr), slog.Bool("tls_enabled", app.Cfg.HttpServerConfig.TLS.Enabled))

		if app.Cfg.HttpServerConfig.TLS.Enabled {
			serverType = "HTTPS"
			certFile := app.Cfg.HttpServerConfig.TLS.CertFile
			keyFile := app.Cfg.HttpServerConfig.TLS.KeyFile
			app.Log.Info(fmt.Sprintf("TLS is enabled. %s server starting", serverType),
				slog.String("address", addr), slog.String("certFile", certFile), slog.String("keyFile", keyFile))
			if _, errStat := os.Stat(certFile); os.IsNotExist(errStat) {
				errMsg := fmt.Sprintf("TLS cert_file not found: %s", certFile)
				app.Log.Error(errMsg)
				serverShutdown <- errors.New(errMsg)
				return
			}
			if _, errStat := os.Stat(keyFile); os.IsNotExist(errStat) {
				errMsg := fmt.Sprintf("TLS key_file not found: %s", keyFile)
				app.Log.Error(errMsg)
				serverShutdown <- errors.New(errMsg)
				return
			}
			err = srv.ListenAndServeTLS(certFile, keyFile)
		} else {
			app.Log.Info(fmt.Sprintf("%s server starting", serverType), slog.String("address", addr))
			err = srv.ListenAndServe()
		}

		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			app.Log.Error(fmt.Sprintf("%s server run failed", serverType), slog.String("error", err.Error()))
			serverShutdown <- err
		} else if err == http.ErrServerClosed {
			app.Log.Info(fmt.Sprintf("%s server closed", serverType))
			serverShutdown <- nil
		}
	}()

	app.Log.Info("Server started", slog.String("Address", swaggerHost), slog.String("Protocol", protocol))
	app.Log.Info(fmt.Sprintf("Swagger docs available at %s://%s%s/swagger/index.html",
		swaggerSchemeForLog, docs.SwaggerInfo.Host, docs.SwaggerInfo.BasePath))

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serverShutdown:
		if err != nil {
			app.Log.Error("Server failed to start or encountered a fatal error", slog.String("error", err.Error()))
			if app.Cron != nil {
				app.Cron.Stop()
			}
			return fmt.Errorf("server runtime error: %w", err)
		}
		app.Log.Info("Server shutdown initiated by server itself.")
	case sig := <-quit:
		app.Log.Info("Received OS signal, initiating graceful shutdown...", slog.String("signal", sig.String()))
	}

	if app.Cron != nil {
		app.Log.Info("Stopping cron scheduler...")
		cronCtx := app.Cron.Stop()
		select {
		case <-cronCtx.Done():
			app.Log.Info("Cron scheduler stopped.")
		case <-time.After(3 * time.Second):
			app.Log.Warn("Cron scheduler stop timed out.")
		}
	}

	app.Log.Info("Shutting down HTTP/HTTPS server...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		app.Log.Error("Server graceful shutdown failed", slog.String("error", err.Error()))
		return fmt.Errorf("server shutdown failed: %w", err)
	}
	app.Log.Info("Server stopped gracefully")
	return nil
}

func (app *App) SetupRoutes() {
	app.Router.Use(
		middleware.Recoverer,
		middleware.RequestID,
		logger.New(app.Log),
		cors.Handler(cors.Options{
			AllowedOrigins:   app.Cfg.HttpServerConfig.AllowedOrigins,
			AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
			AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token", "Cookie"},
			ExposedHeaders:   []string{"Link", "Set-Cookie"},
			AllowCredentials: true,
			MaxAge:           300,
		}),
	)

	// Используем динамический URL для Swagger JSON, если ты исправил docs.SwaggerInfo.Host и docs.SwaggerInfo.Schemes в app.Start()
	// Либо оставляем фиксированный, если swagger.json генерируется с ним
	var swaggerJSONURL string
	if len(docs.SwaggerInfo.Schemes) > 0 && docs.SwaggerInfo.Host != "" && docs.SwaggerInfo.BasePath != "" {
		swaggerJSONURL = fmt.Sprintf("%s://%s%s/swagger/doc.json", docs.SwaggerInfo.Schemes[0], docs.SwaggerInfo.Host, docs.SwaggerInfo.BasePath)
	} else {
		// Фоллбэк на случай, если SwaggerInfo не полностью инициализирован
		// Ты указал https://localhost:8080/swagger/doc.json, так что можно использовать его
		swaggerJSONURL = "https://localhost:8080/swagger/doc.json" // или http, если TLS выключен
		if !app.Cfg.HttpServerConfig.TLS.Enabled {
			swaggerJSONURL = "http://localhost:8080/swagger/doc.json"
			if strings.HasPrefix(app.Cfg.HttpServerConfig.Address, "0.0.0.0:") {
				swaggerJSONURL = "http://localhost" + app.Cfg.HttpServerConfig.Address[len("0.0.0.0"):] + "/swagger/doc.json"
			} else if strings.HasPrefix(app.Cfg.HttpServerConfig.Address, ":") {
				swaggerJSONURL = "http://localhost" + app.Cfg.HttpServerConfig.Address + "/swagger/doc.json"
			} else {
				swaggerJSONURL = "http://" + app.Cfg.HttpServerConfig.Address + "/swagger/doc.json"
			}
		}
		app.Log.Warn("Using fallback Swagger JSON URL", "url", swaggerJSONURL)
	}
	app.Router.Get("/swagger/*", httpSwagger.Handler(httpSwagger.URL(swaggerJSONURL)))

	apiVersion := "/v1"
	AuthUserMiddleware := appMiddleware.NewUserAuth(app.Log)

	// --- Email Module ---
	emailDBImpl := emailDb.NewEmailDatabase(app.Storage.Db, app.Log)
	emailCacheImpl := emailCache.NewEmailCache(app.Cache)
	emailRepoImpl := emailRp.NewEmailRepo(emailDBImpl, emailCacheImpl)
	emailUseCaseImpl := emailUC.NewEmailUseCase(app.Log, emailRepoImpl, app.EmailSender)
	emailCtrl := emailC.NewEmailController(app.Log, emailUseCaseImpl)

	app.Router.Route(apiVersion+"/email", func(r chi.Router) {
		r.Group(func(r chi.Router) {
			r.Use(httprate.Limit(1, 1*time.Minute, httprate.WithKeyFuncs(httprate.KeyByIP)))
			r.Post("/send-code", emailCtrl.SendConfirmedEmailCode)
		})
		r.Put("/confirm", emailCtrl.EmailConfirmed)
	})

	// --- Profile Module ---
	profileDBImpl := profileDb.NewProfileDatabase(app.Storage.Db, app.Log, app.Cfg.S3Config.Endpoint, app.Cfg.S3Config.BucketUserAvatars)
	profileS3Impl := profileS3.NewProfileS3(app.Log, app.S3)
	profileRepoImpl := profileRp.NewRepo(profileDBImpl, profileS3Impl)
	profileUseCaseImpl := profileUC.NewProfileUseCase(app.Log, profileRepoImpl, app.Cfg.S3Config.BucketUserAvatars, app.Cfg.S3Config.Endpoint)
	profileCtrl := profileC.NewProfileController(app.Log, profileUseCaseImpl, app.Cfg.JWTConfig)

	app.Router.Route(apiVersion+"/profile", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Get("/", profileCtrl.GetUser)
		r.Put("/", profileCtrl.UpdateUser)
		r.Patch("/", profileCtrl.PatchUser)
		r.Delete("/", profileCtrl.DeleteUser)
	})

	// --- Auth Module ---
	authDBImpl := authDb.NewAuthDatabase(app.Storage.Db, app.Log)
	authCacheImpl := authCache.NewAuthCache(app.Cache)
	authRepoImpl := authRp.NewRepo(authDBImpl, authCacheImpl)
	authUseCaseImpl := authUC.NewAuthUseCase(app.Log, authRepoImpl, app.Cfg, profileUseCaseImpl)
	authCtrl := authC.NewAuthController(app.Log, authUseCaseImpl, app.Cfg.OAuthConfig, app.Cfg.JWTConfig)

	app.Router.Route(apiVersion+"/auth", func(r chi.Router) {
		r.Post("/sign-up", authCtrl.SignUp)
		r.Post("/sign-in", authCtrl.SignIn)
		r.Post("/refresh-token", authCtrl.RefreshToken)
		r.Post("/refresh-token-native", authCtrl.RefreshTokenNative)
		r.Get("/{provider}", authCtrl.Oauth)
		r.Get("/{provider}/callback", authCtrl.OauthCallback)
		r.With(AuthUserMiddleware).Post("/logout", authCtrl.Logout)
	})

	// --- UserRepoForTeamModule (реализация для TeamUseCase) ---
	// s3UserAvatarBaseURL формируется из PublicURL (который должен быть https://endpoint) и бакета аватаров
	// s3UserAvatarBaseURL := fmt.Sprintf("%s%s/%s", "https://", strings.TrimSuffix(app.Cfg.S3Config.Endpoint, "/"), strings.TrimPrefix(app.Cfg.S3Config.BucketUserAvatars, "/"))
	// --- Team Module ---
	teamDBImpl := teamDbRepo.NewTeamDatabase(app.Storage.Db, app.Log, app.Cfg.S3Config)
	teamCacheImpl := teamCacheRepo.NewTeamCache(app.Cache, app.Log, app.Cfg.CacheConfig)
	// s3BaseURLForTeamImages - это полный URL до бакета изображений команд
	s3BaseURLForTeamImages := fmt.Sprintf("%s%s/%s", "https://", strings.TrimSuffix(app.Cfg.S3Config.Endpoint, "/"), strings.TrimPrefix(app.Cfg.S3Config.BucketTeamImages, "/"))
	teamS3Impl := teamS3Repo.NewTeamS3(app.Log, app.S3, app.Cfg.S3Config) // Endpoint здесь - это хост S3
	teamRepoImpl := teamRp.NewRepo(teamDBImpl, teamCacheImpl, teamS3Impl, app.Log, app.Cfg.S3Config.BucketTeamImages, s3BaseURLForTeamImages)

	teamUseCaseImpl := teamUC.NewTeamUseCase(
		teamRepoImpl,
		app.Log,
		*app.Cfg,
	)
	teamCtrl := teamC.NewTeamController(teamUseCaseImpl, app.Log, app.Cfg)

	app.Router.Route(apiVersion+"/teams", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", teamCtrl.CreateTeam)
		r.Get("/my", teamCtrl.GetMyTeams)
		r.Route("/{teamID}", func(r chi.Router) {
			r.Get("/", teamCtrl.GetTeam)
			r.Put("/", teamCtrl.UpdateTeam)    // Обновление деталей команды
			r.Delete("/", teamCtrl.DeleteTeam) // Удаление команды

			// Участники
			r.Get("/members", teamCtrl.GetTeamMembers)
			r.Post("/members", teamCtrl.AddTeamMember)
			r.Route("/members/{userID}", func(r chi.Router) { // userID здесь - это targetUserID
				r.Put("/role", teamCtrl.UpdateTeamMemberRole)
				r.Delete("/", teamCtrl.RemoveTeamMember)
			})
			r.Post("/leave", teamCtrl.LeaveTeam) // Пользователь покидает команду

			// Приглашения
			r.Post("/invites", teamCtrl.GenerateInviteToken)

			// Командные теги
			r.Route("/tags", func(r chi.Router) { // <<< НАЧАЛО МАРШРУТОВ ДЛЯ TEAM TAGS
				// tagCtrl будет инициализирован ниже
				// r.Post("/", tagCtrl.CreateTeamTag)
				// r.Get("/", tagCtrl.GetTeamTags)
				// r.Put("/{tagID}", tagCtrl.UpdateTeamTag)
				// r.Delete("/{tagID}", tagCtrl.DeleteTeamTag)
			}) // <<< КОНЕЦ МАРШРУТОВ ДЛЯ TEAM TAGS
		})
	})
	app.Router.With(AuthUserMiddleware).Post(apiVersion+"/teams/join", teamCtrl.JoinTeamByToken)

	// --- Tag Module ---
	tagDBImpl := tagDbRepo.NewTagDatabase(app.Storage.Db, app.Log)
	tagCacheImpl := tagCacheRepo.NewTagCache(app.Cache, app.Log, app.Cfg.CacheConfig.DefaultTeamListCacheTtl) // TTL для списков тегов
	tagRepoImpl := tagRp.NewRepo(tagDBImpl, tagCacheImpl, app.Log)

	// TeamServiceForTag для TagUseCase (используем teamUseCaseImpl)
	var teamServiceProviderForTag tagUC.TeamServiceForTag = teamUseCaseImpl

	tagUseCaseImpl := tagUC.NewTagUseCase(tagRepoImpl, teamServiceProviderForTag, app.Log)
	tagCtrl := tagC.NewTagController(tagUseCaseImpl, app.Log)

	// Пользовательские теги
	app.Router.Route(apiVersion+"/user-tags", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", tagCtrl.CreateUserTag)
		r.Get("/", tagCtrl.GetUserTags)
		r.Put("/{tagID}", tagCtrl.UpdateUserTag)
		r.Delete("/{tagID}", tagCtrl.DeleteUserTag)
	})

	// Командные теги (уже вложены в /teams/{teamID}/tags)
	// Обновляем существующую группу маршрутов для команд
	app.Router.Route(apiVersion+"/teams/{teamID}/tags", func(r chi.Router) {
		r.Use(AuthUserMiddleware) // Middleware уже должен быть применен к /teams/{teamID}
		r.Post("/", tagCtrl.CreateTeamTag)
		r.Get("/", tagCtrl.GetTeamTags)
		r.Put("/{tagID}", tagCtrl.UpdateTeamTag)
		r.Delete("/{tagID}", tagCtrl.DeleteTeamTag)
	})

	// --- Task Module ---
	taskDBImpl := taskDbRepo.NewTaskDatabase(app.Storage.Db, app.Log)
	taskCacheImpl := taskCacheRepo.NewTaskCache(app.Cache, app.Log, app.Cfg.CacheConfig)
	taskRepoImpl := taskRp.NewRepo(taskDBImpl, taskCacheImpl)

	var teamServiceProviderForTask taskUC.TeamService = teamUseCaseImpl

	taskUseCaseImpl := taskUC.NewTaskUseCase(taskRepoImpl, tagUseCaseImpl, tagRepoImpl, teamServiceProviderForTask, app.Log, app.Cfg.CacheConfig.DefaultTaskCacheTtl)
	taskCtrl := taskC.NewTaskController(taskUseCaseImpl, app.Log)

	app.Router.Route(apiVersion+"/tasks", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", taskCtrl.CreateTask)
		r.Get("/", taskCtrl.GetTasks)
		r.Get("/{taskID}", taskCtrl.GetTask)
		r.Put("/{taskID}", taskCtrl.UpdateTask)
		r.Patch("/{taskID}", taskCtrl.PatchTask)
		r.Delete("/{taskID}", taskCtrl.DeleteTask)
	})
}

// main and SetupLogger ... (без изменений) ...
// @title ToDoApp API
// @version 1.0.0
// @description API for ToDoApp

// @contact.name Evdokimov Igor
// @contact.url https://t.me/epelptic

// @host localhost:8080 // Динамически обновляется
// @BasePath /v1
// @Schemes http https   // Динамически обновляется (остается одна схема)

// @securityDefinitions.apikey ApiKeyAuth
// @in header
// @name Authorization
func main() {
	cfg := config.MustLoad()
	log := SetupLogger(cfg.Env)
	slog.SetDefault(log)

	app, err := NewApp(cfg, log)
	if err != nil {
		log.Error("app init failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	app.SetupRoutes()

	if err := app.Start(); err != nil {
		log.Error("application terminated with error", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func SetupLogger(env string) *slog.Logger {
	var log *slog.Logger
	level := slog.LevelInfo
	switch strings.ToLower(env) {
	case "local", "dev", "development":
		level = slog.LevelDebug
		log = slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level, AddSource: true}))
	case "prod", "production":
		log = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level, AddSource: true}))
	default:
		level = slog.LevelDebug
		log = slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level, AddSource: true}))
		slog.Warn("Unknown environment in SetupLogger, defaulting to 'local' text debug logger", slog.String("env", env))
	}
	return log
}
