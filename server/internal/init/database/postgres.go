package database

import (
	"embed"
	"errors"
	"fmt"
	"os"
	"server/config"

	"github.com/golang-migrate/migrate/v4"
	ps "github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger" // Добавлено для настройки логгера GORM
	"log"                 // Стандартный логгер для вывода GORM
	"time"                // Для настройки логгера GORM
)

//go:embed migrations/*.sql
var sqlFiles embed.FS // Убедись, что .sql файлы здесь

type Storage struct {
	Db *gorm.DB
}

func NewStorage(cfg config.DbConfig) (*Storage, error) {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=%s TimeZone=UTC", // Добавлен sslmode и TimeZone
		cfg.Host, cfg.Username, os.Getenv("DB_PASSWORD"), cfg.DbName, cfg.Port, cfg.SSLMode,
	)

	// Настройка логгера GORM
	gormLogger := logger.New(
		log.New(os.Stdout, "\r\n", log.LstdFlags), // io writer
		logger.Config{
			SlowThreshold:             time.Second, // Медленный SQL запрос порог
			LogLevel:                  logger.Info, // Уровень логирования (Silent, Error, Warn, Info)
			IgnoreRecordNotFoundError: true,        // Игнорировать ErrRecordNotFound ошибки
			Colorful:                  true,        // Включить цветной вывод
		},
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: gormLogger, // Подключаем настроенный логгер
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get generic database object from GORM: %w", err)
	}

	// Проверка соединения
	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}
	fmt.Println("Successfully connected to the database!")

	// Миграции
	// Убедись, что 'migrations' - это правильный путь внутри embed.FS
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

	// Закомментировал старый код мигратора, т.к. выше более подробная инициализация
	// migrator := MustGetNewMigrator(sqlFiles, "migrations")
	// if err := migrator.ApplyMigrations(sqlDB); err != nil {
	// 	fmt.Printf("Failed to apply migrations: %v\n", err) // Лучше вернуть ошибку
	//  return nil, fmt.Errorf("failed to apply migrations: %w", err)
	// } else {
	// 	fmt.Println("Migrations applied successfully!")
	// }

	return &Storage{Db: db}, nil
}

// Старый код мигратора, можно удалить или оставить если используется где-то еще.
// Для NewStorage он больше не нужен в таком виде.
/*
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

	if errors.Is(err, migrate.ErrNoChange) {
		fmt.Println("No new migrations to apply.")
	} else {
		fmt.Println("Migrations applied successfully!")
	}
	return nil
}
*/
