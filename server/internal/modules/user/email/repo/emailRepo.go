package repo

type EmailCache interface {
	SaveEmailConfirmedCode(email string, code string) error
	GetEmailConfirmedCode(email string) (string, error)
}

type EmailDb interface {
	ConfirmEmail(email string) error
	IsEmailConfirmed(email string) (bool, error)
}

type Repo struct {
	db EmailDb
	ch EmailCache
}

func NewEmailRepo(db EmailDb, cache EmailCache) *Repo {
	return &Repo{
		db: db,
		ch: cache,
	}
}

func (r *Repo) ConfirmEmail(email string) error {
	return r.db.ConfirmEmail(email)
}

func (r *Repo) IsEmailConfirmed(email string) (bool, error) {
	return r.db.IsEmailConfirmed(email)
}

func (r *Repo) GetEmailConfirmedCode(email string) (string, error) {
	return r.ch.GetEmailConfirmedCode(email)
}

func (r *Repo) SaveEmailConfirmedCode(email string, code string) error {
	return r.ch.SaveEmailConfirmedCode(email, code)
}
