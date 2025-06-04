package repo

// EmailCache определяет методы для работы с кэшем кодов подтверждения email.
type EmailCache interface {
	SaveEmailConfirmedCode(email string, code string) error
	GetEmailConfirmedCode(email string) (string, error)
	DeleteEmailConfirmedCode(email string) error // Добавлен метод
}

// EmailDb определяет методы для работы с базой данных для подтверждения email.
type EmailDb interface {
	ConfirmEmail(email string) error
	IsEmailConfirmed(email string) (bool, error)
}

// Repo реализует интерфейс email.Repo, комбинируя EmailDb и EmailCache.
type Repo struct {
	db EmailDb    // Реализация для работы с БД
	ch EmailCache // Реализация для работы с кэшем
}

func NewEmailRepo(db EmailDb, ch EmailCache) *Repo {
	return &Repo{
		db: db,
		ch: ch,
	}
}

// --- Методы для работы с БД ---

func (r *Repo) ConfirmEmail(email string) error {
	return r.db.ConfirmEmail(email)
}

func (r *Repo) IsEmailConfirmed(email string) (bool, error) {
	return r.db.IsEmailConfirmed(email)
}

// --- Методы для работы с кэшем ---

func (r *Repo) SaveEmailConfirmedCode(email string, code string) error {
	return r.ch.SaveEmailConfirmedCode(email, code)
}

func (r *Repo) GetEmailConfirmedCode(email string) (string, error) {
	return r.ch.GetEmailConfirmedCode(email)
}

func (r *Repo) DeleteEmailConfirmedCode(email string) error { // Реализация нового метода
	return r.ch.DeleteEmailConfirmedCode(email)
}
