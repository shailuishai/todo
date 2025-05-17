package repo

import "server/internal/modules/user/auth"

type AuthCache interface {
	SaveStateCode(state string) error
	VerifyStateCode(state string) (bool, error)
}

type AuthDb interface {
	CreateUser(user *auth.UserAuth) (uint, error)
	GetUserByEmail(email string) (*auth.UserAuth, error)
	GetUserByLogin(login string) (*auth.UserAuth, error)
	GetUserById(id uint) (*auth.UserAuth, error)
}

type Repo struct {
	ch AuthCache
	db AuthDb
}

func NewRepo(db AuthDb, ch AuthCache) *Repo {
	return &Repo{
		ch: ch,
		db: db,
	}
}

func (r *Repo) CreateUser(user *auth.UserAuth) (uint, error) {
	return r.db.CreateUser(user)
}

func (r *Repo) GetUserByEmail(email string) (*auth.UserAuth, error) {
	return r.db.GetUserByEmail(email)
}

func (r *Repo) GetUserByLogin(login string) (*auth.UserAuth, error) {
	return r.db.GetUserByLogin(login)
}

func (r *Repo) GetUserById(id uint) (*auth.UserAuth, error) {
	return r.db.GetUserById(id)
}

func (r *Repo) SaveStateCode(state string) error {
	return r.ch.SaveStateCode(state)
}

func (r *Repo) VerifyStateCode(state string) (bool, error) {
	return r.ch.VerifyStateCode(state)
}
