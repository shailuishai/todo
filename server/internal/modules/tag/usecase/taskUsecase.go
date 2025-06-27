package usecase

import (
	"errors"
	"log/slog"
	"server/internal/modules/tag" // Модели, DTO, интерфейсы и ошибки модуля tag
	"server/internal/modules/team"

	"strings"
	// "time" // Не используется напрямую здесь
)

// TeamServiceForTag - интерфейс, описывающий методы, которые TagUseCase ожидает от сервиса команд.
// Это нужно для проверки прав на управление командными тегами.
// В реальном приложении это будет интерфейс, реализуемый TeamUseCase из модуля team.
type TeamServiceForTag interface {
	IsUserMember(userID, teamID uint) (bool, error)
	GetUserRoleInTeam(userID, teamID uint) (*team.TeamMemberRole, error) // Используем team.TeamMemberRole из пакета tag (или общий enum)
	// Можно добавить более гранулярные права, если нужно:
	// CanUserManageTeamTags(userID, teamID uint) (bool, error)
}

// MockTeamServiceForTag - заглушка для TeamServiceForTag
type MockTeamServiceForTag struct{}

func (m *MockTeamServiceForTag) IsUserMember(userID, teamID uint) (bool, error) {
	slog.Warn("MockTeamServiceForTag: IsUserMember called, returning true by default", "userID", userID, "teamID", teamID)
	if teamID == 0 {
		return false, errors.New("mock: invalid teamID")
	}
	return true, nil
}
func (m *MockTeamServiceForTag) GetUserRoleInTeam(userID, teamID uint) (*team.TeamMemberRole, error) {
	slog.Warn("MockTeamServiceForTag: GetUserRoleInTeam called, returning 'editor' by default", "userID", userID, "teamID", teamID)
	if teamID == 0 {
		return nil, errors.New("mock: invalid teamID")
	}
	role := team.RoleEditor // По умолчанию даем права на управление тегами
	return &role, nil
}

// TagUseCase реализует интерфейс tag.UseCase.
type TagUseCase struct {
	repo        tag.Repo
	teamService TeamServiceForTag // Зависимость от сервиса команд
	log         *slog.Logger
}

// NewTagUseCase создает новый экземпляр TagUseCase.
func NewTagUseCase(repo tag.Repo, teamService TeamServiceForTag, log *slog.Logger) tag.UseCase {
	return &TagUseCase{
		repo:        repo,
		teamService: teamService,
		log:         log,
	}
}

// --- User Tags ---

func (uc *TagUseCase) CreateUserTag(userID uint, req tag.CreateUserTagRequest) (*tag.TagResponse, error) {
	op := "TagUseCase.CreateUserTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.String("tagName", req.Name))

	if strings.TrimSpace(req.Name) == "" {
		return nil, tag.ErrTagNameRequired
	}

	userTag := &tag.UserTag{
		OwnerUserID: userID,
		Name:        req.Name,
		Color:       req.Color,
	}

	createdTag, err := uc.repo.CreateUserTag(userTag)
	if err != nil {
		log.Error("failed to create user tag in repo", "error", err)
		if errors.Is(err, tag.ErrUserTagNameConflict) {
			return nil, tag.ErrUserTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}

	log.Info("user tag created successfully", "userTagID", createdTag.UserTagID)
	return &tag.TagResponse{
		ID:        createdTag.UserTagID,
		Name:      createdTag.Name,
		Color:     createdTag.Color,
		Type:      "user",
		OwnerID:   createdTag.OwnerUserID,
		CreatedAt: createdTag.CreatedAt,
		UpdatedAt: createdTag.UpdatedAt,
	}, nil
}

func (uc *TagUseCase) GetUserTags(userID uint) ([]*tag.TagResponse, error) {
	op := "TagUseCase.GetUserTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	userTags, err := uc.repo.GetUserTagsByOwnerID(userID) // repo.GetUserTagsByOwnerID должен сам обработать кэш
	if err != nil {
		log.Error("failed to get user tags from repo", "error", err)
		return nil, tag.ErrTagInternal
	}

	responses := make([]*tag.TagResponse, len(userTags))
	for i, t := range userTags {
		responses[i] = &tag.TagResponse{
			ID:        t.UserTagID,
			Name:      t.Name,
			Color:     t.Color,
			Type:      "user",
			OwnerID:   t.OwnerUserID,
			CreatedAt: t.CreatedAt,
			UpdatedAt: t.UpdatedAt,
		}
	}
	log.Info("user tags retrieved", slog.Int("count", len(responses)))
	return responses, nil
}

func (uc *TagUseCase) UpdateUserTag(tagID uint, userID uint, req tag.UpdateUserTagRequest) (*tag.TagResponse, error) {
	op := "TagUseCase.UpdateUserTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("userID", uint64(userID)))

	existingTag, err := uc.repo.GetUserTagByID(tagID, userID)
	if err != nil {
		if errors.Is(err, tag.ErrTagNotFound) {
			log.Warn("user tag not found or access denied for update")
			return nil, tag.ErrTagNotFound // Или ErrTagAccessDenied, если хотим быть точнее
		}
		log.Error("failed to get user tag for update", "error", err)
		return nil, tag.ErrTagInternal
	}

	// Проверка, что пользователь является владельцем (уже сделана в GetUserTagByID)
	// if existingTag.OwnerUserID != userID {
	// 	log.Warn("user is not the owner of the tag", "ownerUserID", existingTag.OwnerUserID)
	// 	return nil, tag.ErrTagAccessDenied
	// }

	changed := false
	if req.Name != nil && *req.Name != existingTag.Name {
		if strings.TrimSpace(*req.Name) == "" {
			return nil, tag.ErrTagNameRequired
		}
		existingTag.Name = *req.Name
		changed = true
	}
	if req.Color != nil { // Разрешаем установку пустого цвета (nil)
		if existingTag.Color == nil || *req.Color != *existingTag.Color {
			existingTag.Color = req.Color
			changed = true
		}
	} else if existingTag.Color != nil && req.Color == nil { // Явный сброс цвета
		existingTag.Color = nil
		changed = true
	}

	if !changed {
		log.Info("no changes detected for user tag update")
		return &tag.TagResponse{
			ID: existingTag.UserTagID, Name: existingTag.Name, Color: existingTag.Color, Type: "user",
			OwnerID: existingTag.OwnerUserID, CreatedAt: existingTag.CreatedAt, UpdatedAt: existingTag.UpdatedAt,
		}, nil
	}

	updatedTag, err := uc.repo.UpdateUserTag(existingTag)
	if err != nil {
		log.Error("failed to update user tag in repo", "error", err)
		if errors.Is(err, tag.ErrUserTagNameConflict) {
			return nil, tag.ErrUserTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}

	log.Info("user tag updated successfully", "userTagID", updatedTag.UserTagID)
	return &tag.TagResponse{
		ID: updatedTag.UserTagID, Name: updatedTag.Name, Color: updatedTag.Color, Type: "user",
		OwnerID: updatedTag.OwnerUserID, CreatedAt: updatedTag.CreatedAt, UpdatedAt: updatedTag.UpdatedAt,
	}, nil
}

func (uc *TagUseCase) DeleteUserTag(tagID uint, userID uint) error {
	op := "TagUseCase.DeleteUserTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("userID", uint64(userID)))

	// Проверяем, что тег существует и принадлежит пользователю перед удалением
	_, err := uc.repo.GetUserTagByID(tagID, userID)
	if err != nil {
		if errors.Is(err, tag.ErrTagNotFound) {
			log.Warn("user tag not found or access denied for delete")
			return tag.ErrTagNotFound // Или ErrTagAccessDenied
		}
		log.Error("failed to get user tag for delete", "error", err)
		return tag.ErrTagInternal
	}

	if err := uc.repo.DeleteUserTag(tagID, userID); err != nil {
		log.Error("failed to delete user tag in repo", "error", err)
		return tag.ErrTagInternal
	}
	// ON DELETE CASCADE в БД должен удалить связи из task_tags

	log.Info("user tag deleted successfully", "userTagID", tagID)
	return nil
}

// --- Team Tags ---

func (uc *TagUseCase) CreateTeamTag(teamID uint, userID uint, req tag.CreateTeamTagRequest) (*tag.TagResponse, error) {
	op := "TagUseCase.CreateTeamTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)), slog.String("tagName", req.Name))

	if strings.TrimSpace(req.Name) == "" {
		return nil, tag.ErrTagNameRequired
	}

	// Проверка прав пользователя на создание тега в команде
	role, err := uc.teamService.GetUserRoleInTeam(userID, teamID)
	if err != nil {
		log.Error("failed to get user role in team", "error", err)
		return nil, tag.ErrTagInternal
	}
	if role == nil {
		log.Warn("user not member of team, cannot create team tag")
		return nil, team.ErrTeamAccessDenied
	}

	if !(*role == team.RoleOwner || *role == team.RoleAdmin || *role == team.RoleEditor) {
		log.Warn("user does not have permission to create team tags", "role", *role)
		return nil, team.ErrTeamAccessDenied
	}

	teamTag := &tag.TeamTag{
		TeamID: teamID,
		Name:   req.Name,
		Color:  req.Color,
		// CreatedByUserID: &userID, // Если бы поле было в модели
	}

	createdTag, err := uc.repo.CreateTeamTag(teamTag)
	if err != nil {
		log.Error("failed to create team tag in repo", "error", err)
		if errors.Is(err, tag.ErrTeamTagNameConflict) {
			return nil, tag.ErrTeamTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}

	log.Info("team tag created successfully", "teamTagID", createdTag.TeamTagID)
	return &tag.TagResponse{
		ID: createdTag.TeamTagID, Name: createdTag.Name, Color: createdTag.Color, Type: "team",
		OwnerID: createdTag.TeamID, CreatedAt: createdTag.CreatedAt, UpdatedAt: createdTag.UpdatedAt,
	}, nil
}

func (uc *TagUseCase) GetTeamTags(teamID uint, userID uint) ([]*tag.TagResponse, error) {
	op := "TagUseCase.GetTeamTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	// Проверка, что пользователь является участником команды для просмотра тегов
	isMember, err := uc.teamService.IsUserMember(userID, teamID)
	if err != nil {
		log.Error("failed to check team membership", "error", err)
		return nil, tag.ErrTagInternal
	}
	if !isMember {
		log.Warn("user not member of team, cannot get team tags")
		return nil, team.ErrTeamAccessDenied
	}

	teamTags, err := uc.repo.GetTeamTagsByTeamID(teamID)
	if err != nil {
		log.Error("failed to get team tags from repo", "error", err)
		return nil, tag.ErrTagInternal
	}

	responses := make([]*tag.TagResponse, len(teamTags))
	for i, t := range teamTags {
		responses[i] = &tag.TagResponse{
			ID: t.TeamTagID, Name: t.Name, Color: t.Color, Type: "team",
			OwnerID: t.TeamID, CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt,
		}
	}
	log.Info("team tags retrieved", slog.Int("count", len(responses)))
	return responses, nil
}

func (uc *TagUseCase) UpdateTeamTag(tagID uint, teamID uint, userID uint, req tag.UpdateTeamTagRequest) (*tag.TagResponse, error) {
	op := "TagUseCase.UpdateTeamTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	// Проверка прав пользователя на редактирование тега в команде
	role, err := uc.teamService.GetUserRoleInTeam(userID, teamID)
	if err != nil {
		log.Error("failed to get user role", "error", err)
		return nil, tag.ErrTagInternal
	}
	if role == nil {
		log.Warn("user not member, cannot update")
		return nil, team.ErrTeamAccessDenied
	}
	if !(*role == team.RoleOwner || *role == team.RoleAdmin || *role == team.RoleEditor) {
		log.Warn("user lacks permission to update team tags", "role", *role)
		return nil, team.ErrTeamAccessDenied
	}

	existingTag, err := uc.repo.GetTeamTagByID(tagID, teamID) // Проверяем, что тег принадлежит команде
	if err != nil {
		if errors.Is(err, tag.ErrTagNotFound) {
			log.Warn("team tag not found")
			return nil, tag.ErrTagNotFound
		}
		log.Error("failed to get team tag for update", "error", err)
		return nil, tag.ErrTagInternal
	}

	changed := false
	if req.Name != nil && *req.Name != existingTag.Name {
		if strings.TrimSpace(*req.Name) == "" {
			return nil, tag.ErrTagNameRequired
		}
		existingTag.Name = *req.Name
		changed = true
	}
	if req.Color != nil {
		if existingTag.Color == nil || *req.Color != *existingTag.Color {
			existingTag.Color = req.Color
			changed = true
		}
	} else if existingTag.Color != nil && req.Color == nil {
		existingTag.Color = nil
		changed = true
	}

	if !changed {
		log.Info("no changes for team tag update")
		return &tag.TagResponse{
			ID: existingTag.TeamTagID, Name: existingTag.Name, Color: existingTag.Color, Type: "team",
			OwnerID: existingTag.TeamID, CreatedAt: existingTag.CreatedAt, UpdatedAt: existingTag.UpdatedAt,
		}, nil
	}

	updatedTag, err := uc.repo.UpdateTeamTag(existingTag)
	if err != nil {
		log.Error("failed to update team tag in repo", "error", err)
		if errors.Is(err, tag.ErrTeamTagNameConflict) {
			return nil, tag.ErrTeamTagNameConflict
		}
		return nil, tag.ErrTagInternal
	}

	log.Info("team tag updated", "teamTagID", updatedTag.TeamTagID)
	return &tag.TagResponse{
		ID: updatedTag.TeamTagID, Name: updatedTag.Name, Color: updatedTag.Color, Type: "team",
		OwnerID: updatedTag.TeamID, CreatedAt: updatedTag.CreatedAt, UpdatedAt: updatedTag.UpdatedAt,
	}, nil
}

func (uc *TagUseCase) DeleteTeamTag(tagID uint, teamID uint, userID uint) error {
	op := "TagUseCase.DeleteTeamTag"
	log := uc.log.With(slog.String("op", op), slog.Uint64("tagID", uint64(tagID)), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	role, err := uc.teamService.GetUserRoleInTeam(userID, teamID)
	if err != nil {
		log.Error("failed to get user role", "error", err)
		return tag.ErrTagInternal
	}
	if role == nil {
		log.Warn("user not member, cannot delete")
		return team.ErrTeamAccessDenied
	}
	if !(*role == team.RoleOwner || *role == team.RoleAdmin || *role == team.RoleEditor) {
		log.Warn("user lacks permission to delete team tags", "role", *role)
		return team.ErrTeamAccessDenied
	}

	// Проверяем, что тег существует и принадлежит команде
	_, err = uc.repo.GetTeamTagByID(tagID, teamID)
	if err != nil {
		if errors.Is(err, tag.ErrTagNotFound) {
			log.Warn("team tag not found for delete")
			return tag.ErrTagNotFound
		}
		log.Error("failed to get team tag for delete", "error", err)
		return tag.ErrTagInternal
	}

	if err := uc.repo.DeleteTeamTag(tagID, teamID); err != nil {
		log.Error("failed to delete team tag in repo", "error", err)
		return tag.ErrTagInternal
	}

	log.Info("team tag deleted", "teamTagID", tagID)
	return nil
}

// --- Методы для TaskUseCase ---

func (uc *TagUseCase) ValidateAndGetUserTags(userID uint, tagIDs []uint) ([]*tag.UserTag, error) {
	op := "TagUseCase.ValidateAndGetUserTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	if len(tagIDs) == 0 {
		return []*tag.UserTag{}, nil
	}

	foundTags, err := uc.repo.FindUserTagsByIDs(userID, tagIDs)
	if err != nil {
		log.Error("failed to find user tags by IDs", "error", err)
		return nil, tag.ErrTagInternal
	}

	if len(foundTags) != len(tagIDs) {
		log.Warn("not all user tags found or access denied for some tags")
		// Определить, какие теги не найдены/недоступны, может быть сложно без доп. логики
		// Пока что общая ошибка
		return nil, tag.ErrTagNotFound // Или более специфичная "one or more tags not found or access denied"
	}
	// Все запрошенные теги найдены и принадлежат пользователю
	return foundTags, nil
}

func (uc *TagUseCase) ValidateAndGetTeamTags(teamID uint, userID uint, tagIDs []uint) ([]*tag.TeamTag, error) {
	op := "TagUseCase.ValidateAndGetTeamTags"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	if len(tagIDs) == 0 {
		return []*tag.TeamTag{}, nil
	}

	// Проверка, что пользователь является участником команды
	isMember, err := uc.teamService.IsUserMember(userID, teamID)
	if err != nil {
		log.Error("failed to check team membership", "error", err)
		return nil, tag.ErrTagInternal
	}
	if !isMember {
		log.Warn("user not member of team, cannot validate team tags")
		return nil, team.ErrTeamAccessDenied
	}

	foundTags, err := uc.repo.FindTeamTagsByIDs(teamID, tagIDs)
	if err != nil {
		log.Error("failed to find team tags by IDs", "error", err)
		return nil, tag.ErrTagInternal
	}

	if len(foundTags) != len(tagIDs) {
		log.Warn("not all team tags found or belong to the specified team")
		return nil, tag.ErrTagNotFound // Или "one or more team tags not found"
	}
	// Все запрошенные теги найдены и принадлежат команде
	return foundTags, nil
}

func (uc *TagUseCase) GetUserTagsMap(userID uint, tagIDs []uint) (map[uint]*tag.UserTag, error) {
	tags, err := uc.ValidateAndGetUserTags(userID, tagIDs)
	if err != nil {
		return nil, err
	}
	tagsMap := make(map[uint]*tag.UserTag, len(tags))
	for _, t := range tags {
		tagsMap[t.UserTagID] = t
	}
	return tagsMap, nil
}

func (uc *TagUseCase) GetTeamTagsMap(teamID uint, userID uint, tagIDs []uint) (map[uint]*tag.TeamTag, error) {
	tags, err := uc.ValidateAndGetTeamTags(teamID, userID, tagIDs)
	if err != nil {
		return nil, err
	}
	tagsMap := make(map[uint]*tag.TeamTag, len(tags))
	for _, t := range tags {
		tagsMap[t.TeamTagID] = t
	}
	return tagsMap, nil
}
