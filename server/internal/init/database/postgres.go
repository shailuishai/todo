// internal/init/database/postgres.go
package database

import (
	"embed"
	"errors"
	"fmt"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"log"
	"os"
	"server/config"
	"time"

	"github.com/golang-migrate/migrate/v4"
	ps "github.com/golang-migrate/migrate/v4/database/postgres"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

//go:embed migrations/*.sql
var sqlFiles embed.FS

type Storage struct {
	Db *gorm.DB
}

func NewStorage(cfg config.DbConfig) (*Storage, error) {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=%s TimeZone=UTC",
		cfg.Host, cfg.Username, os.Getenv("DB_PASSWORD"), cfg.DbName, cfg.Port, cfg.SSLMode,
	)

	gormLogger := logger.New(
		log.New(os.Stdout, "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logger.Info,
			IgnoreRecordNotFoundError: true,
			Colorful:                  true,
		},
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: gormLogger,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get generic database object from GORM: %w", err)
	}

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}
	fmt.Println("Successfully connected to the database!")

	srcDriver, err := iofs.New(sqlFiles, "migrations")
	if err != nil {
		return nil, fmt.Errorf("failed to create source driver for migrations: %w", err)
	}

	pgDriver, err := ps.WithInstance(sqlDB, &ps.Config{})
	if err != nil {
		return nil, fmt.Errorf("failed to create postgres driver instance for migrations: %w", err)
	}

	migrator, err := migrate.NewWithInstance("iofs", srcDriver, "postgres", pgDriver)
	if err != nil {
		return nil, fmt.Errorf("failed to create migrator instance: %w", err)
	}

	err = migrator.Up()
	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return nil, fmt.Errorf("failed to apply migrations: %w", err)
	}

	if errors.Is(err, migrate.ErrNoChange) {
		fmt.Println("No new migrations to apply.")
	} else {
		fmt.Println("Migrations applied successfully!")
	}

	return &Storage{Db: db}, nil
}
