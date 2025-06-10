package config

import (
	"github.com/ilyakaznacheev/cleanenv"
	"log"
	"os"
	"time"
)

type Config struct {
	Env              string           `yaml:"env" env-Default:"development"`
	DbConfig         DbConfig         `yaml:"db" env-required:"true"`
	HttpServerConfig HttpServerConfig `yaml:"http_server"  env-required:"true"`
	CacheConfig      CacheConfig      `yaml:"cache" env-required:"true"`
	SMTPConfig       SMTPConfig       `yaml:"smtp" env-required:"true"`
	JWTConfig        JWTConfig        `yaml:"jwt" env-required:"true"`
	S3Config         S3Config         `yaml:"s3" env-required:"true"`
	OAuthConfig      OAuthConfig      `yaml:"oauth" env-required:"true"`
	FCMConfig        FCMConfig        `yaml:"fcm_config"`
}

type CacheConfig struct {
	Address                      string        `yaml:"address" env-required:"true"`
	Db                           int           `yaml:"db"`
	StateExpiration              time.Duration `yaml:"state_expiration" env-required:"true"`
	EmailConfirmedCodeExpiration time.Duration `yaml:"email_confirmed_code_expiration" env-required:"true"`
	DefaultTaskCacheTtl          time.Duration `yaml:"default_task_cache_ttl" env-required:"true"`
	DefaultTeamCacheTtl          time.Duration `yaml:"default_team_cache_ttl" env-required:"true"`
	DefaultTeamListCacheTtl      time.Duration `yaml:"default_team_list_cache_ttl" env-required:"true"`
}

type TLSConfig struct {
	Enabled  bool   `yaml:"enabled" env-default:"false"`
	CertFile string `yaml:"cert_file"`
	KeyFile  string `yaml:"key_file"`
}

type HttpServerConfig struct {
	Address        string        `yaml:"address" env-required:"true"`
	Timeout        time.Duration `yaml:"timeout" env-required:"true"`
	IdleTimeout    time.Duration `yaml:"idle_timeout" env-required:"true"`
	AllowedOrigins []string      `yaml:"allowed_origins"`
	TLS            TLSConfig     `yaml:"tls"`
}

type FCMConfig struct {
	ProjectID                 string `yaml:"project_id"`                    // Project ID из Firebase Console
	ServiceAccountKeyJSONPath string `yaml:"service_account_key_json_path"` // Путь к файлу JSON или сам JSON как строка
}

type DbConfig struct {
	Username string `yaml:"username"`
	Host     string `yaml:"host"`
	Port     string `yaml:"port"`
	DbName   string `yaml:"dbname"`
	SSLMode  string `yaml:"ssl_mode"`
}

type SMTPConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
}

var JwtConfig JWTConfig

type JWTConfig struct {
	AccessExpire  time.Duration `yaml:"access_expire" env-required:"true"`
	RefreshExpire time.Duration `yaml:"refresh_expire" env-required:"true"`
	CookieDomain  string        `yaml:"cookie_domain" env-required:"true"`
	SecureCookie  bool          `yaml:"secure_cookie" default:"true"`
}

type S3Config struct {
	Endpoint              string `yaml:"endpoint"`
	Region                string `yaml:"region"`
	BucketUserAvatars     string `yaml:"bucket_user_avatars"`
	BucketTeamImages      string `yaml:"bucket_team_images"` // Добавлено
	MaxTeamImageSizeBytes int    `yaml:"max_team_image_size_bytes" default:"0"`
}

type OAuthConfig struct {
	GoogleRedirectURL          string `yaml:"google_redirect_url" env-required:"true"`
	YandexRedirectURL          string `yaml:"yandex_redirect_url" env-required:"true"`
	FrontendRedirectSuccessURL string `yaml:"frontend_redirect_success_url" env-required:"true"` // Добавлено
	FrontendRedirectErrorURL   string `yaml:"frontend_redirect_error_url" env-required:"true"`   // Добавлено
}

func MustLoad() *Config {
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		// Если переменная не установлена, по умолчанию ищем local.yaml.
		// Render будет использовать prod.yaml через переменную, а локально будет работать dev.yaml
		configPath = "config/dev.yaml"
	}

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		log.Fatalf("config file does not exist: %s", configPath)
	}

	var cfg Config
	if err := cleanenv.ReadConfig(configPath, &cfg); err != nil {
		log.Fatalf("error reading config file: %s. Error: %v", configPath, err)
	}

	JwtConfig = cfg.JWTConfig

	return &cfg
}
