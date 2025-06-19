package main

import (
	"context"
	"errors"
	firebase "firebase.google.com/go/v4"
	"fmt"
	"google.golang.org/api/option"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"server/internal/modules/notification"
	"server/internal/modules/notification/dispatcher"
	"server/pkg/lib/pushsender"
	"server/pkg/lib/pushsender/fcm"
	"strings"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"
	"github.com/go-playground/validator/v10" // Добавлен импорт
	"github.com/robfig/cron/v3"
	httpSwagger "github.com/swaggo/http-swagger/v2"

	"server/config"
	"server/docs"
	"server/internal/init/cache"
	"server/internal/init/database"
	s3init "server/internal/init/s3"

	// Chat Module
	chatEntity "server/internal/modules/chat" // Для интерфейсов и DTO
	chatCtrl "server/internal/modules/chat/controller"
	chatDB "server/internal/modules/chat/repo/database"
	chatUC "server/internal/modules/chat/usecase"
	"server/internal/modules/chat/ws"

	// User submodules
	authC "server/internal/modules/user/auth/controller"
	authRepo "server/internal/modules/user/auth/repo" // Изменено имя импорта для authRp
	authCache "server/internal/modules/user/auth/repo/cache"
	authDb "server/internal/modules/user/auth/repo/database"
	authUC "server/internal/modules/user/auth/usecase"

	emailC "server/internal/modules/user/email/controller"
	emailRepo "server/internal/modules/user/email/repo" // Изменено имя импорта для emailRp
	emailCache "server/internal/modules/user/email/repo/cache"
	emailDb "server/internal/modules/user/email/repo/database"
	emailUC "server/internal/modules/user/email/usecase"

	profileC "server/internal/modules/user/profile/controller"
	profileRepo "server/internal/modules/user/profile/repo" // Изменено имя импорта для profileRp
	profileDb "server/internal/modules/user/profile/repo/database"
	profileS3 "server/internal/modules/user/profile/repo/s3"
	profileUC "server/internal/modules/user/profile/usecase"

	// Task module
	taskC "server/internal/modules/task/controller"
	taskRepo "server/internal/modules/task/repo" // Изменено имя импорта для taskRp
	taskCacheRepo "server/internal/modules/task/repo/cache"
	taskDbRepo "server/internal/modules/task/repo/database"
	taskUC "server/internal/modules/task/usecase"

	// Team module
	teamC "server/internal/modules/team/controller"
	teamRepo "server/internal/modules/team/repo" // Изменено имя импорта для teamRp
	teamCacheRepo "server/internal/modules/team/repo/cache"
	teamDbRepo "server/internal/modules/team/repo/database"
	teamS3Repo "server/internal/modules/team/repo/s3"
	teamUC "server/internal/modules/team/usecase"

	// Tag module
	tagC "server/internal/modules/tag/controller"
	tagRepo "server/internal/modules/tag/repo" // Изменено имя импорта для tagRp
	tagCacheRepo "server/internal/modules/tag/repo/cache"
	tagDbRepo "server/internal/modules/tag/repo/database"
	tagUC "server/internal/modules/tag/usecase"

	"server/pkg/lib/TaskService"
	"server/pkg/lib/emailsender"
	appMiddleware "server/pkg/middleware/jwt"
	"server/pkg/middleware/logger"
)

type App struct {
	Storage                *database.Storage
	Cache                  *cache.Cache
	S3                     *s3init.S3Storage
	EmailSender            *emailsender.EmailSender
	Router                 chi.Router
	Log                    *slog.Logger
	Cfg                    *config.Config
	Cron                   *cron.Cron
	TS                     *TaskService.TaskService
	ChatHub                *ws.Hub
	PushNotificationSender *pushsender.Sender
}

func NewApp(cfg *config.Config, log *slog.Logger) (*App, error) {
	opt := option.WithCredentialsFile(cfg.FCMConfig.ServiceAccountKeyJSONPath)
	_, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		return nil, fmt.Errorf("error initializing app: %v", err)
	}

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

	eSender, err := emailsender.New(cfg.SMTPConfig, log)
	if err != nil {
		return nil, fmt.Errorf("email sender init failed: %w", err)
	}

	var pushNotificationSvc pushsender.Sender
	if cfg.FCMConfig.ProjectID != "" { // Инициализируем FCM только если есть ProjectID
		var fcmServiceAccountJSON []byte
		var errFcmKey error

		// ServiceAccountKeyJSONPath теперь указывает на путь внутри контейнера
		if cfg.FCMConfig.ServiceAccountKeyJSONPath != "" {
			log.Info("Loading FCM service account key from path specified in config", "path", cfg.FCMConfig.ServiceAccountKeyJSONPath)
			fcmServiceAccountJSON, errFcmKey = os.ReadFile(cfg.FCMConfig.ServiceAccountKeyJSONPath)
			if errFcmKey != nil {
				log.Error("Failed to read FCM service account key JSON file", "path", cfg.FCMConfig.ServiceAccountKeyJSONPath, "error", errFcmKey)
				// Можно решить, является ли это фатальной ошибкой. Если Push критичны, то да.
				// return nil, fmt.Errorf("read FCM key file %s: %w", cfg.FCMConfig.ServiceAccountKeyJSONPath, errFcmKey)
			}
		} else {
			log.Info("FCM service account key path not provided in config; if ProjectID is set, FCM will attempt to use Application Default Credentials.")
		}

		if errFcmKey == nil { // Продолжаем инициализацию, только если ключ успешно прочитан (или не указан путь, и мы полагаемся на ADC)
			fcmSender, errFCM := fcm.NewFCMSender(context.Background(), fcmServiceAccountJSON, cfg.FCMConfig.ProjectID, log)
			if errFCM != nil {
				log.Error("Failed to initialize FCMSender", "error", errFCM)
				// Опять же, решить, фатально ли это.
			} else {
				pushNotificationSvc = fcmSender
				log.Info("FCMSender initialized.")
				// Опциональный пинг при старте
				if errPing := pushNotificationSvc.Ping(context.Background()); errPing != nil {
					log.Error("FCMSender Ping failed on startup", "error", errPing)
				} else {
					log.Info("FCMSender Ping successful on startup.")
				}
			}
		}
	} else {
		log.Warn("FCMConfig.ProjectID is not set. Push notifications via FCM will be disabled.")
	}

	router := chi.NewRouter()
	// ИЗМЕНЕНИЕ: Настройка Cron задач
	profileDBImpl := profileDb.NewProfileDatabase(storage.Db, log, cfg.S3Config.Endpoint, cfg.S3Config.BucketUserAvatars)
	profileS3Impl := profileS3.NewProfileS3(log, s3s)
	profileRepoImpl := profileRepo.NewRepo(profileDBImpl, profileS3Impl)
	profileUseCaseImpl := profileUC.NewProfileUseCase(log, profileRepoImpl, cfg.S3Config.BucketUserAvatars, cfg.S3Config.Endpoint)

	var notificationDispatcher notification.Dispatcher
	if pushNotificationSvc != nil {
		notificationDispatcher = dispatcher.New(pushNotificationSvc, profileUseCaseImpl, log)
		log.Info("NotificationDispatcher initialized.")
	} else {
		log.Warn("PushNotificationSender is nil, NotificationDispatcher will not be initialized.")
	}

	teamDBImpl := teamDbRepo.NewTeamDatabase(storage.Db, log, cfg.S3Config)
	teamCacheImpl := teamCacheRepo.NewTeamCache(appCache, log, cfg.CacheConfig)
	s3BaseURLForTeamImages := fmt.Sprintf("https://%s/%s", strings.TrimSuffix(cfg.S3Config.Endpoint, "/"), strings.TrimPrefix(cfg.S3Config.BucketTeamImages, "/"))
	teamS3Impl := teamS3Repo.NewTeamS3(log, s3s, cfg.S3Config)
	teamRepoImpl := teamRepo.NewRepo(teamDBImpl, teamCacheImpl, teamS3Impl, log, cfg.S3Config.BucketTeamImages, s3BaseURLForTeamImages)
	teamUseCaseImpl := teamUC.NewTeamUseCase(teamRepoImpl, log, *cfg)

	tagDBImpl := tagDbRepo.NewTagDatabase(storage.Db, log)
	tagCacheImpl := tagCacheRepo.NewTagCache(appCache, log, cfg.CacheConfig.DefaultTeamListCacheTtl)
	tagRepoImpl := tagRepo.NewRepo(tagDBImpl, tagCacheImpl, log)
	var teamServiceProviderForTag tagUC.TeamServiceForTag = teamUseCaseImpl
	tagUseCaseImpl := tagUC.NewTagUseCase(tagRepoImpl, teamServiceProviderForTag, log)

	taskDBImpl := taskDbRepo.NewTaskDatabase(storage.Db, log)
	taskCacheImpl := taskCacheRepo.NewTaskCache(appCache, log, cfg.CacheConfig)
	taskRepoImpl := taskRepo.NewRepo(taskDBImpl, taskCacheImpl)
	var teamServiceProviderForTask taskUC.TeamService = teamUseCaseImpl
	taskUseCaseImpl := taskUC.NewTaskUseCase(taskRepoImpl, tagUseCaseImpl, tagRepoImpl, teamServiceProviderForTask, log, cfg.CacheConfig.DefaultTaskCacheTtl, profileUseCaseImpl, notificationDispatcher)

	bgTaskService := TaskService.NewTaskService(storage.Db, log)
	cronScheduler := cron.New()

	// Задача очистки пользователей (раз в сутки)
	_, err = cronScheduler.AddFunc("0 0 * * *", func() {
		log.Info("Cron: Running CleanUnverifiedUsers task")
		bgTaskService.CleanUnverifiedUsers()
	})
	if err != nil {
		return nil, fmt.Errorf("cron CleanUnverifiedUsers init failed: %w", err)
	}

	// Задача проверки дедлайнов (каждые 5 минут)
	_, err = cronScheduler.AddFunc("@every 5m", func() {
		log.Info("Cron: Running ProcessDeadlineChecks task")
		if err := taskUseCaseImpl.ProcessDeadlineChecks(context.Background()); err != nil {
			log.Error("Cron: failed to process deadline checks", "error", err)
		}
	})
	if err != nil {
		return nil, fmt.Errorf("cron ProcessDeadlineChecks init failed: %w", err)
	}

	cronScheduler.Start()

	return &App{
		Storage:                storage,
		Cache:                  appCache,
		S3:                     s3s,
		EmailSender:            eSender,
		Router:                 router,
		Log:                    log,
		Cfg:                    cfg,
		Cron:                   cronScheduler,
		TS:                     bgTaskService,
		PushNotificationSender: &pushNotificationSvc,
	}, nil
}

func (app *App) Start() error {
	// ... (код Start без изменений, как в предыдущем ответе) ...
	srv := &http.Server{
		Addr:         app.Cfg.HttpServerConfig.Address,
		Handler:      app.Router,
		ReadTimeout:  app.Cfg.HttpServerConfig.Timeout,
		WriteTimeout: app.Cfg.HttpServerConfig.Timeout,
		IdleTimeout:  app.Cfg.HttpServerConfig.IdleTimeout,
	}

	protocol := "http" // По умолчанию http
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
	docs.SwaggerInfo.Schemes = []string{protocol} // Обновляем схемы

	var swaggerSchemeForLog string
	if len(docs.SwaggerInfo.Schemes) > 0 {
		swaggerSchemeForLog = docs.SwaggerInfo.Schemes[0]
	} else {
		swaggerSchemeForLog = "http" // Фоллбэк, если схемы не установились
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
			serverShutdown <- nil // Сигнализируем об успешном закрытии
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
			if app.Cron != nil { // Убедимся, что Cron не nil перед вызовом Stop
				app.Cron.Stop()
			}
			return fmt.Errorf("server runtime error: %w", err)
		}
		// Если err == nil, сервер закрылся штатно (например, из-за http.ErrServerClosed)
		app.Log.Info("Server shutdown initiated by server itself.")
	case sig := <-quit:
		app.Log.Info("Received OS signal, initiating graceful shutdown...", slog.String("signal", sig.String()))
	}

	if app.Cron != nil {
		app.Log.Info("Stopping cron scheduler...")
		cronCtx := app.Cron.Stop() // Stop возвращает контекст, который завершается, когда все задачи остановлены
		select {
		case <-cronCtx.Done():
			app.Log.Info("Cron scheduler stopped.")
		case <-time.After(3 * time.Second): // Таймаут на остановку cron
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

	var swaggerJSONURL string
	if len(docs.SwaggerInfo.Schemes) > 0 && docs.SwaggerInfo.Host != "" && docs.SwaggerInfo.BasePath != "" {
		swaggerJSONURL = fmt.Sprintf("%s://%s%s/swagger/doc.json", docs.SwaggerInfo.Schemes[0], docs.SwaggerInfo.Host, docs.SwaggerInfo.BasePath)
	} else {
		swaggerJSONURL = "http://localhost:8080/swagger/doc.json"
		if app.Cfg.HttpServerConfig.TLS.Enabled {
			swaggerJSONURL = "https://localhost:8080/swagger/doc.json"
		}
		// Более точное формирование URL для Swagger JSON
		var hostPort string
		if strings.HasPrefix(app.Cfg.HttpServerConfig.Address, ":") { // e.g. ":8080"
			hostPort = "localhost" + app.Cfg.HttpServerConfig.Address
		} else if strings.HasPrefix(app.Cfg.HttpServerConfig.Address, "0.0.0.0:") { // e.g. "0.0.0.0:8080"
			hostPort = "localhost" + app.Cfg.HttpServerConfig.Address[len("0.0.0.0"):]
		} else { // e.g. "localhost:8080" or "someservice:8080"
			hostPort = app.Cfg.HttpServerConfig.Address
		}
		scheme := "http"
		if app.Cfg.HttpServerConfig.TLS.Enabled {
			scheme = "https"
		}
		swaggerJSONURL = fmt.Sprintf("%s://%s/swagger/doc.json", scheme, hostPort)
		app.Log.Warn("Using fallback Swagger JSON URL generation", "url", swaggerJSONURL)
	}
	app.Router.Get("/swagger/*", httpSwagger.Handler(httpSwagger.URL(swaggerJSONURL)))

	apiVersion := "/v1"
	AuthUserMiddleware := appMiddleware.NewUserAuth(app.Log)
	validate := validator.New() // Глобальный валидатор для контроллеров

	// --- Email Module ---
	emailDBImpl := emailDb.NewEmailDatabase(app.Storage.Db, app.Log)
	emailCacheImpl := emailCache.NewEmailCache(app.Cache)
	emailRepoImpl := emailRepo.NewEmailRepo(emailDBImpl, emailCacheImpl)
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
	profileRepoImpl := profileRepo.NewRepo(profileDBImpl, profileS3Impl)
	profileUseCaseImpl := profileUC.NewProfileUseCase(app.Log, profileRepoImpl, app.Cfg.S3Config.BucketUserAvatars, app.Cfg.S3Config.Endpoint) // Тип *profileUC.ProfileUseCase
	profileCtrl := profileC.NewProfileController(app.Log, profileUseCaseImpl, app.Cfg.JWTConfig)
	app.Router.Route(apiVersion+"/profile", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Get("/", profileCtrl.GetUser)
		r.Put("/", profileCtrl.UpdateUser)
		r.Patch("/", profileCtrl.PatchUser)
		r.Delete("/", profileCtrl.DeleteUser)
		r.Post("/device-tokens", profileCtrl.RegisterDeviceToken)
		r.Delete("/device-tokens", profileCtrl.UnregisterDeviceToken)
	})

	// --- Auth Module ---
	authDBImpl := authDb.NewAuthDatabase(app.Storage.Db, app.Log)
	authCacheImpl := authCache.NewAuthCache(app.Cache)
	authRepoImpl := authRepo.NewRepo(authDBImpl, authCacheImpl)
	authUseCaseImpl := authUC.NewAuthUseCase(app.Log, authRepoImpl, app.Cfg, profileUseCaseImpl) // profileUseCaseImpl здесь типа profileEntity.UseCase
	authCtrl := authC.NewAuthController(app.Log, authUseCaseImpl, app.Cfg.OAuthConfig, app.Cfg.JWTConfig)
	app.Router.Route(apiVersion+"/auth", func(r chi.Router) {
		r.Post("/sign-up", authCtrl.SignUp)
		r.Post("/sign-in", authCtrl.SignIn)
		r.Post("/refresh-token", authCtrl.RefreshToken)
		r.Post("/refresh-token-native", authCtrl.RefreshTokenNative)
		r.Get("/{provider}", authCtrl.Oauth)
		r.Get("/{provider}/callback", authCtrl.OauthCallback) // Для нативных клиентов
		r.Post("/oauth/exchange", authCtrl.OAuthExchange)
		r.With(AuthUserMiddleware).Post("/logout", authCtrl.Logout)
	})

	// --- Notifications Module ---
	notificationDispatcher := dispatcher.New(*app.PushNotificationSender, profileUseCaseImpl, app.Log)

	// --- Team Module ---
	teamDBImpl := teamDbRepo.NewTeamDatabase(app.Storage.Db, app.Log, app.Cfg.S3Config)
	teamCacheImpl := teamCacheRepo.NewTeamCache(app.Cache, app.Log, app.Cfg.CacheConfig)
	s3BaseURLForTeamImages := fmt.Sprintf("https://%s/%s", strings.TrimSuffix(app.Cfg.S3Config.Endpoint, "/"), strings.TrimPrefix(app.Cfg.S3Config.BucketTeamImages, "/"))
	teamS3Impl := teamS3Repo.NewTeamS3(app.Log, app.S3, app.Cfg.S3Config)
	teamRepoImpl := teamRepo.NewRepo(teamDBImpl, teamCacheImpl, teamS3Impl, app.Log, app.Cfg.S3Config.BucketTeamImages, s3BaseURLForTeamImages)
	teamUseCaseImpl := teamUC.NewTeamUseCase(teamRepoImpl, app.Log, *app.Cfg) // Тип *teamUC.TeamUseCase
	teamCtrl := teamC.NewTeamController(teamUseCaseImpl, app.Log, app.Cfg)
	app.Router.Route(apiVersion+"/teams", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", teamCtrl.CreateTeam)
		r.Get("/my", teamCtrl.GetMyTeams)
		r.Route("/{teamID}", func(r chi.Router) {
			r.Get("/", teamCtrl.GetTeam)
			r.Put("/", teamCtrl.UpdateTeam)
			r.Delete("/", teamCtrl.DeleteTeam)
			r.Get("/members", teamCtrl.GetTeamMembers)
			r.Post("/members", teamCtrl.AddTeamMember)
			r.Route("/members/{userID}", func(r chi.Router) {
				r.Put("/role", teamCtrl.UpdateTeamMemberRole)
				r.Delete("/", teamCtrl.RemoveTeamMember)
			})
			r.Post("/leave", teamCtrl.LeaveTeam)
			r.Post("/invites", teamCtrl.GenerateInviteToken)
			// Маршруты для командных тегов будут ниже, после инициализации TagController
		})
	})
	app.Router.With(AuthUserMiddleware).Post(apiVersion+"/teams/join", teamCtrl.JoinTeamByToken)

	// --- Tag Module ---
	tagDBImpl := tagDbRepo.NewTagDatabase(app.Storage.Db, app.Log)
	tagCacheImpl := tagCacheRepo.NewTagCache(app.Cache, app.Log, app.Cfg.CacheConfig.DefaultTeamListCacheTtl)
	tagRepoImpl := tagRepo.NewRepo(tagDBImpl, tagCacheImpl, app.Log)
	var teamServiceProviderForTag tagUC.TeamServiceForTag = teamUseCaseImpl // Приведение типа
	tagUseCaseImpl := tagUC.NewTagUseCase(tagRepoImpl, teamServiceProviderForTag, app.Log)
	tagCtrl := tagC.NewTagController(tagUseCaseImpl, app.Log)
	app.Router.Route(apiVersion+"/user-tags", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", tagCtrl.CreateUserTag)
		r.Get("/", tagCtrl.GetUserTags)
		r.Put("/{tagID}", tagCtrl.UpdateUserTag)
		r.Delete("/{tagID}", tagCtrl.DeleteUserTag)
	})
	app.Router.Route(apiVersion+"/teams/{teamID}/tags", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", tagCtrl.CreateTeamTag)
		r.Get("/", tagCtrl.GetTeamTags)
		r.Put("/{tagID}", tagCtrl.UpdateTeamTag)
		r.Delete("/{tagID}", tagCtrl.DeleteTeamTag)
	})

	// --- Task Module ---
	taskDBImpl := taskDbRepo.NewTaskDatabase(app.Storage.Db, app.Log)
	taskCacheImpl := taskCacheRepo.NewTaskCache(app.Cache, app.Log, app.Cfg.CacheConfig)
	taskRepoImpl := taskRepo.NewRepo(taskDBImpl, taskCacheImpl)
	var teamServiceProviderForTask taskUC.TeamService = teamUseCaseImpl // Приведение типа
	taskUseCaseImpl := taskUC.NewTaskUseCase(taskRepoImpl, tagUseCaseImpl, tagRepoImpl, teamServiceProviderForTask, app.Log, app.Cfg.CacheConfig.DefaultTaskCacheTtl, profileUseCaseImpl, notificationDispatcher)
	taskCtrl := taskC.NewTaskController(taskUseCaseImpl, app.Log)
	app.Router.Route(apiVersion+"/tasks", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		r.Post("/", taskCtrl.CreateTask)
		r.Get("/", taskCtrl.GetTasks)
		r.Get("/{taskID}", taskCtrl.GetTask)
		r.Put("/{taskID}", taskCtrl.UpdateTask)
		r.Patch("/{taskID}", taskCtrl.PatchTask)
		r.Delete("/{taskID}", taskCtrl.DeleteTask)
		r.Post("/{taskID}/restore", taskCtrl.RestoreTask)
		r.Delete("/{taskID}/permanent", taskCtrl.DeleteTaskPermanently)
	})

	// --- Chat Module ---
	chatLog := app.Log.With(slog.String("module", "chat"))
	chatDatabaseRepo := chatDB.NewDBRepo(app.Storage.Db, chatLog.With(slog.String("layer", "db_repo")))

	// Убедимся, что teamUseCaseImpl и profileUseCaseImpl реализуют нужные интерфейсы
	var teamCheckerForChat chatEntity.TeamServiceProvider = teamUseCaseImpl
	var userInfoProviderForChat chatEntity.UserInfoProvider = profileUseCaseImpl

	chatUseCaseInstance := chatUC.NewUseCase(
		chatLog.With(slog.String("layer", "usecase")),
		chatDatabaseRepo,
		teamCheckerForChat,
		userInfoProviderForChat,
		notificationDispatcher,
	)
	chatHubInstance := ws.NewHub(chatLog.With(slog.String("component", "hub")), chatUseCaseInstance)
	app.ChatHub = chatHubInstance // Сохраняем хаб в App

	chatControllerInstance := chatCtrl.NewController(
		chatLog.With(slog.String("layer", "controller")),
		chatUseCaseInstance,
		app.ChatHub,
		teamCheckerForChat, // Передаем teamUseCaseImpl, который реализует chatEntity.TeamChecker
		validate,           // Передаем глобальный валидатор
	)

	app.Router.Route(apiVersion+"/chat", func(r chi.Router) {
		r.Use(AuthUserMiddleware)
		// WebSocket эндпоинт для команды
		r.Get("/ws/teams/{teamID}", chatControllerInstance.ServeWs)
		// HTTP эндпоинт для получения истории сообщений команды
		r.Get("/teams/{teamID}/messages", chatControllerInstance.GetChatHistory)
	})
}

// @title ToDoApp API
// @version 1.0.0
// @description API for ToDoApp

// @contact.name Evdokimov Igor
// @contact.url https://t.me/epelptic

// @host localhost:8080
// @BasePath /v1
// @schemes http https

// @securityDefinitions.apikey ApiKeyAuth
// @in header
// @name Authorization
func main() {
	cfg := config.MustLoad()
	log := SetupLogger(cfg.Env)
	slog.SetDefault(log) // Устанавливаем глобальный логгер

	currentApp, err := NewApp(cfg, log)
	if err != nil {
		log.Error("app init failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	currentApp.SetupRoutes() // Инициализация ChatHub теперь происходит здесь

	// Запуск Chat Hub в отдельной горутине, если он был инициализирован
	if currentApp.ChatHub != nil {
		go currentApp.ChatHub.Run()
		log.Info("Chat Hub worker started")
	} else {
		// Этого не должно произойти, если SetupRoutes вызывается после NewApp
		log.Error("Chat Hub is nil after SetupRoutes, cannot start worker. Check initialization logic.")
		// os.Exit(1) // Возможно, стоит завершить приложение, если ChatHub критичен
	}

	if err := currentApp.Start(); err != nil {
		log.Error("application terminated with error", slog.String("error", err.Error()))
		os.Exit(1) // Явно выходим, если Start вернул ошибку
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
	default: // По умолчанию, если env не распознан
		level = slog.LevelDebug // Безопасный дефолт
		log = slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level, AddSource: true}))
		// Используем стандартный slog для предупреждения, т.к. наш 'log' еще не инициализирован полностью
		slog.Warn("Unknown environment in SetupLogger, defaulting to 'local' text debug logger", slog.String("env", env))
	}
	return log
}
