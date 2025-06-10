package repo

import "server/internal/modules/user/auth" // Интерфейсы и DTO UserAuth

// AuthCache определяет методы для работы с кэшем аутентификации (OAuth state).
type AuthCache interface {
	SaveStateCode(state string, providerData string) error
	VerifyStateCode(state string) (providerData string, isValid bool, err error)
	StoreFinalizeTokens(code, tokens string) error
	RetrieveFinalizeTokens(code string) (string, error)
}

// AuthDb определяет методы для работы с базой данных пользователей для аутентификации.
type AuthDb interface {
	CreateUser(user *auth.UserAuth) (userID uint, err error)
	GetUserByEmail(email string) (*auth.UserAuth, error)
	GetUserByLogin(login string) (*auth.UserAuth, error)
	GetUserById(id uint) (*auth.UserAuth, error)
}

// Repo реализует интерфейс auth.Repo, комбинируя AuthDb и AuthCache.
type Repo struct {
	db AuthDb    // Реализация для работы с БД
	ch AuthCache // Реализация для работы с кэшем
}

func NewRepo(db AuthDb, ch AuthCache) *Repo {
	return &Repo{
		db: db,
		ch: ch,
	}
}

// CreateUser делегирует создание пользователя в AuthDb.
func (r *Repo) CreateUser(user *auth.UserAuth) (uint, error) {
	return r.db.CreateUser(user)
}

// GetUserByEmail делегирует получение пользователя по email в AuthDb.
func (r *Repo) GetUserByEmail(email string) (*auth.UserAuth, error) {
	return r.db.GetUserByEmail(email)
}

// GetUserByLogin делегирует получение пользователя по логину в AuthDb.
func (r *Repo) GetUserByLogin(login string) (*auth.UserAuth, error) {
	return r.db.GetUserByLogin(login)
}

// GetUserById делегирует получение пользователя по ID в AuthDb.
func (r *Repo) GetUserById(id uint) (*auth.UserAuth, error) {
	return r.db.GetUserById(id)
}

// SaveStateCode делегирует сохранение OAuth state в AuthCache.
func (r *Repo) SaveStateCode(state string, providerData string) error {
	return r.ch.SaveStateCode(state, providerData)
}

// VerifyStateCode делегирует верификацию OAuth state в AuthCache.
func (r *Repo) VerifyStateCode(state string) (string, bool, error) {
	return r.ch.VerifyStateCode(state)
}

func (r *Repo) StoreFinalizeTokens(code, tokens string) error {
	// Предполагается, что у AuthCache есть подходящий метод
	return r.ch.StoreFinalizeTokens(code, tokens)
}

// Добавьте этот метод в ваш Repo
func (r *Repo) RetrieveFinalizeTokens(code string) (string, error) {
	return r.ch.RetrieveFinalizeTokens(code)
}
