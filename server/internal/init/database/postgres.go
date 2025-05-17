package database

import (
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"os"
	"server/config"

	"github.com/golang-migrate/migrate/v4"
	ps "github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

//go:embed migrations/*
var sqlFiles embed.FS

type Storage struct {
	Db *gorm.DB
}

func NewStorage(cfg config.DbConfig) (*Storage, error) {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s",
		cfg.Host, cfg.Username, os.Getenv("DB_PASSWORD"), cfg.DbName, cfg.Port,
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		return nil, err
	}

	migrator := MustGetNewMigrator(sqlFiles, "migrations")

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	if err := migrator.ApplyMigrations(sqlDB); err != nil {
		fmt.Printf("Failed to apply migrations: %v\n", err)
	} else {
		fmt.Println("Migrations applied successfully!")
	}

	return &Storage{Db: db}, nil
}

type Migrator struct {
	srcDriver source.Driver
}

func MustGetNewMigrator(sqlFiles embed.FS, dirName string) *Migrator {
	srcDriver, err := iofs.New(sqlFiles, dirName)
	if err != nil {
		panic(fmt.Errorf("failed to initialize source driver: %w", err))
	}
	return &Migrator{srcDriver: srcDriver}
}

func (m *Migrator) ApplyMigrations(db *sql.DB) error {
	driver, err := ps.WithInstance(db, &ps.Config{})
	if err != nil {
		return fmt.Errorf("unable to create postgres driver: %w", err)
	}

	migrator, err := migrate.NewWithInstance(
		"iofs", m.srcDriver, "postgres", driver,
	)
	if err != nil {
		return fmt.Errorf("unable to create migrator: %w", err)
	}

	if err := migrator.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("unable to apply migrations: %w", err)
	}

	fmt.Println("Migrations applied successfully!")
	return nil
}
