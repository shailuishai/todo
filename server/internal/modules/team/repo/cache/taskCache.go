package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"server/config"
	"server/internal/init/cache" // Ваш пакет инициализации кэша
	"server/internal/modules/team"
	usermodels "server/internal/modules/user" // Для общих ошибок
	"time"

	"github.com/go-redis/redis/v8"
)

// TeamCache реализует интерфейс repo.TeamCache
type TeamCache struct {
	rdb    *redis.Client
	log    *slog.Logger
	ttlCfg config.CacheConfig
}

// NewTeamCache создает новый экземпляр TeamCache.
func NewTeamCache(appCache *cache.Cache, log *slog.Logger, ttlCfg config.CacheConfig) *TeamCache {
	return &TeamCache{
		rdb:    appCache.Client,
		log:    log,
		ttlCfg: ttlCfg,
	}
}

// --- Ключи кэша ---
func teamKey(teamID uint) string {
	return fmt.Sprintf("team:%d", teamID)
}

func teamMembersKey(teamID uint) string {
	return fmt.Sprintf("team:%d:members", teamID)
}

func userTeamsKey(userID uint) string {
	return fmt.Sprintf("user:%d:teams", userID)
}

func inviteTokenKey(token string) string { return fmt.Sprintf("invite_token:%s", token) }

type InviteTokenData struct {
	TeamID       uint                `json:"team_id"`
	RoleToAssign team.TeamMemberRole `json:"role_to_assign"`
	// ExpiresAt не хранится здесь, т.к. TTL Redis управляет истечением
}

func (c *TeamCache) SaveInviteToken(token string, teamID uint, roleToAssign team.TeamMemberRole, expiresAt time.Time) error {
	op := "TeamCache.SaveInviteToken"
	key := inviteTokenKey(token)
	log := c.log.With(slog.String("op", op), slog.String("key", key), slog.Uint64("teamID", uint64(teamID)))

	ttl := time.Until(expiresAt)
	if ttl <= 0 {
		log.Warn("invite token already expired or invalid expiration time", "expiresAt", expiresAt)
		return team.ErrTeamInviteTokenInvalid // Или другая ошибка "срок истек"
	}

	data := InviteTokenData{
		TeamID:       teamID,
		RoleToAssign: roleToAssign,
	}
	val, err := json.Marshal(data)
	if err != nil {
		log.Error("failed to marshal invite token data for cache", "error", err)
		return team.ErrTeamInternal
	}

	if err := c.rdb.Set(context.Background(), key, val, ttl).Err(); err != nil {
		log.Error("failed to save invite token to cache", "error", err)
		return team.ErrTeamInternal
	}
	log.Info("invite token saved to cache", "ttl", ttl.String())
	return nil
}

func (c *TeamCache) GetInviteTokenData(token string) (teamID uint, roleToAssign team.TeamMemberRole, isValid bool, err error) {
	op := "TeamCache.GetInviteTokenData"
	key := inviteTokenKey(token)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, redisErr := c.rdb.Get(context.Background(), key).Bytes()
	if redisErr != nil {
		if errors.Is(redisErr, redis.Nil) {
			log.Info("invite token not found in cache or expired")
			return 0, "", false, nil // Не ошибка, просто токен невалиден/не найден
		}
		log.Error("failed to get invite token from cache", "error", redisErr)
		return 0, "", false, team.ErrTeamInternal
	}

	var data InviteTokenData
	if errUnmarshal := json.Unmarshal(val, &data); errUnmarshal != nil {
		log.Error("failed to unmarshal invite token data from cache", "error", errUnmarshal)
		// Если данные повреждены, удаляем ключ
		_ = c.rdb.Del(context.Background(), key)
		return 0, "", false, team.ErrTeamInternal
	}

	log.Info("invite token data retrieved from cache")
	return data.TeamID, data.RoleToAssign, true, nil
}

func (c *TeamCache) DeleteInviteToken(token string) error {
	op := "TeamCache.DeleteInviteToken"
	key := inviteTokenKey(token)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		// Если токена уже нет, это не ошибка для этой операции
		if !errors.Is(err, redis.Nil) {
			log.Error("failed to delete invite token from cache", "error", err)
			// Можно не возвращать ошибку, если удаление некритично
		}
	} else {
		log.Info("invite token deleted from cache")
	}
	return nil
}

// --- Team Cache ---

func (c *TeamCache) GetTeam(teamID uint) (*team.Team, error) {
	op := "TeamCache.GetTeam"
	key := teamKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("team not found in cache")
			return nil, usermodels.ErrNotFound
		}
		log.Error("failed to get team from cache", "error", err)
		return nil, usermodels.ErrInternal
	}

	var teamModel team.Team
	if err := json.Unmarshal(val, &teamModel); err != nil {
		log.Error("failed to unmarshal team from cache", "error", err)
		_ = c.rdb.Del(context.Background(), key)
		return nil, usermodels.ErrInternal
	}
	log.Debug("team retrieved from cache")
	return &teamModel, nil
}

func (c *TeamCache) SaveTeam(teamModel *team.Team) error {
	op := "TeamCache.SaveTeam"
	key := teamKey(teamModel.TeamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := json.Marshal(teamModel)
	if err != nil {
		log.Error("failed to marshal team for cache", "error", err)
		return usermodels.ErrInternal
	}

	if err := c.rdb.Set(context.Background(), key, val, c.ttlCfg.DefaultTeamCacheTtl).Err(); err != nil {
		log.Error("failed to save team to cache", "error", err)
		return usermodels.ErrInternal
	}
	log.Debug("team saved to cache")
	return nil
}

func (c *TeamCache) DeleteTeam(teamID uint) error {
	op := "TeamCache.DeleteTeam"
	key := teamKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		log.Error("failed to delete team from cache", "error", err)
		// Не возвращаем ошибку, чтобы не прерывать основной поток
	} else {
		log.Debug("team deleted from cache")
	}
	return nil
}

// --- Team Members Cache ---

func (c *TeamCache) GetTeamMembers(teamID uint) ([]*team.UserTeamMembership, error) {
	op := "TeamCache.GetTeamMembers"
	key := teamMembersKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("team members not found in cache")
			return nil, usermodels.ErrNotFound
		}
		log.Error("failed to get team members from cache", "error", err)
		return nil, usermodels.ErrInternal
	}

	var memberships []*team.UserTeamMembership
	if err := json.Unmarshal(val, &memberships); err != nil {
		log.Error("failed to unmarshal team members from cache", "error", err)
		_ = c.rdb.Del(context.Background(), key)
		return nil, usermodels.ErrInternal
	}
	log.Debug("team members retrieved from cache", slog.Int("count", len(memberships)))
	return memberships, nil
}

func (c *TeamCache) SaveTeamMembers(teamID uint, members []*team.UserTeamMembership) error {
	op := "TeamCache.SaveTeamMembers"
	key := teamMembersKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := json.Marshal(members)
	if err != nil {
		log.Error("failed to marshal team members for cache", "error", err)
		return usermodels.ErrInternal
	}
	if err := c.rdb.Set(context.Background(), key, val, c.ttlCfg.DefaultTeamListCacheTtl).Err(); err != nil {
		log.Error("failed to save team members to cache", "error", err)
		return usermodels.ErrInternal
	}
	log.Debug("team members saved to cache", slog.Int("count", len(members)))
	return nil
}

func (c *TeamCache) DeleteTeamMembers(teamID uint) error {
	op := "TeamCache.DeleteTeamMembers"
	key := teamMembersKey(teamID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		log.Error("failed to delete team members from cache", "error", err)
	} else {
		log.Debug("team members deleted from cache")
	}
	return nil
}

// --- User's Teams Cache ---

func (c *TeamCache) GetUserTeams(userID uint) ([]*team.Team, error) {
	op := "TeamCache.GetUserTeams"
	key := userTeamsKey(userID) // Простой ключ, без учета поиска. Поиск будет фильтровать результат.
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := c.rdb.Get(context.Background(), key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			log.Debug("user's teams list not found in cache")
			return nil, usermodels.ErrNotFound
		}
		log.Error("failed to get user's teams list from cache", "error", err)
		return nil, usermodels.ErrInternal
	}

	var teams []*team.Team
	if err := json.Unmarshal(val, &teams); err != nil {
		log.Error("failed to unmarshal user's teams list from cache", "error", err)
		_ = c.rdb.Del(context.Background(), key)
		return nil, usermodels.ErrInternal
	}
	log.Debug("user's teams list retrieved from cache", slog.Int("count", len(teams)))
	return teams, nil
}

func (c *TeamCache) SaveUserTeams(userID uint, teams []*team.Team) error {
	op := "TeamCache.SaveUserTeams"
	key := userTeamsKey(userID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	val, err := json.Marshal(teams)
	if err != nil {
		log.Error("failed to marshal user's teams list for cache", "error", err)
		return usermodels.ErrInternal
	}
	if err := c.rdb.Set(context.Background(), key, val, c.ttlCfg.DefaultTeamListCacheTtl).Err(); err != nil {
		log.Error("failed to save user's teams list to cache", "error", err)
		return usermodels.ErrInternal
	}
	log.Debug("user's teams list saved to cache", slog.Int("count", len(teams)))
	return nil
}

func (c *TeamCache) DeleteUserTeams(userID uint) error {
	op := "TeamCache.DeleteUserTeams"
	key := userTeamsKey(userID)
	log := c.log.With(slog.String("op", op), slog.String("key", key))

	if err := c.rdb.Del(context.Background(), key).Err(); err != nil {
		log.Error("failed to delete user's teams list from cache", "error", err)
	} else {
		log.Debug("user's teams list deleted from cache")
	}
	return nil
}
