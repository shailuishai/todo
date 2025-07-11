// file: internal/modules/team/usecase/team_usecase.go
package usecase

import (
	"bytes" // Для avatarManager
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io" // Для io.ReadAll
	"log/slog"
	"mime/multipart"
	"server/config"
	"server/internal/modules/team"
	usermodels "server/internal/modules/user"
	avatarManager "server/pkg/lib/avatarMenager" // Убедитесь, что путь корректен
	"strings"
	"time"

	"github.com/google/uuid"
)

type TeamUseCase struct {
	repo    team.Repo
	log     *slog.Logger
	s3Cfg   config.S3Config // Храним всю S3Config для доступа к разным бакетам и настройкам
	ttlCfg  config.CacheConfig
	httpCfg config.HttpServerConfig
	// maxTeamImageSizeBytes убран, будем брать из s3Cfg
}

func NewTeamUseCase(
	repo team.Repo,
	log *slog.Logger,
	appCfg config.Config, // Передаем всю конфигурацию
) team.UseCase {
	return &TeamUseCase{
		repo:    repo,
		log:     log,
		s3Cfg:   appCfg.S3Config, // Сохраняем S3Config
		ttlCfg:  appCfg.CacheConfig,
		httpCfg: appCfg.HttpServerConfig,
	}
}

// toTeamResponse Helper для конвертации модели команды в DTO ответа
func (uc *TeamUseCase) toTeamResponse(t *team.Team, role *team.TeamMemberRole, memberCount int) *team.TeamResponse {
	if t == nil {
		return nil
	}
	var fullImageURL *string
	if t.ImageURLS3Key != nil && *t.ImageURLS3Key != "" {
		// Используем метод репозитория, который делегирует в TeamS3
		// GetTeamImagePublicURL должен использовать s3TeamImageBaseURL, который формируется в NewTeamS3
		// или напрямую из конфигурации в TeamS3.
		// Передаем только ключ, как и для аватаров пользователей.
		urlValue := uc.repo.GetTeamImagePublicURL(*t.ImageURLS3Key)
		if urlValue != "" {
			fullImageURL = &urlValue
		}
	}

	return &team.TeamResponse{
		TeamID:          t.TeamID,
		Name:            t.Name,
		Description:     t.Description,
		Color:           t.Color,
		ImageURL:        fullImageURL,
		CreatedByUserID: t.CreatedByUserID,
		CreatedAt:       t.CreatedAt,
		UpdatedAt:       t.UpdatedAt,
		IsDeleted:       t.IsDeleted,
		CurrentUserRole: role,
		MemberCount:     memberCount,
	}
}

func (uc *TeamUseCase) CreateTeam(userID uint, req team.CreateTeamRequest /* imageFileHeader interface{} - убрано, будет в UpdateTeamDetails */) (*team.TeamResponse, error) {
	op := "TeamUseCase.CreateTeam"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)), slog.String("teamName", req.Name))

	if strings.TrimSpace(req.Name) == "" {
		return nil, team.ErrTeamNameRequired
	}

	teamModel := team.Team{
		Name:            req.Name,
		Description:     req.Description,
		Color:           req.Color,
		CreatedByUserID: userID,
		ImageURLS3Key:   nil, // Изображение не добавляется при создании команды напрямую через этот DTO
	}

	createdTeam, err := uc.repo.CreateTeam(&teamModel)
	if err != nil {
		log.Error("failed to create team in repo", "error", err)
		return nil, err
	}

	membership := team.UserTeamMembership{
		UserID: userID,
		TeamID: createdTeam.TeamID,
		Role:   team.RoleOwner,
	}
	if err := uc.repo.CreateMembership(&membership); err != nil {
		log.Error("failed to create owner membership", "error", err, "teamID", createdTeam.TeamID)
		// Рассмотреть откат создания команды
		// r.repo.DeleteTeamByID(createdTeam.TeamID) // Примерно так, если бы был такой метод
		return nil, team.ErrTeamInternal
	}

	_ = uc.repo.DeleteUserTeams(userID)
	_ = uc.repo.DeleteTeamMembers(createdTeam.TeamID) // Кэш участников пуст, но на всякий случай

	log.Info("team created successfully", slog.Uint64("teamID", uint64(createdTeam.TeamID)))
	ownerRole := team.RoleOwner
	// При создании команды 1 участник (владелец)
	return uc.toTeamResponse(createdTeam, &ownerRole, 1), nil
}

func (uc *TeamUseCase) GetTeamByID(teamID uint, userID uint) (*team.TeamDetailResponse, error) {
	op := "TeamUseCase.GetTeamByID"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	currentUserMembership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		if errors.Is(err, team.ErrUserNotMember) {
			log.Warn("user is not a member of the team", "error", err)
			return nil, team.ErrTeamAccessDenied
		}
		log.Error("failed to get current user membership", "error", err)
		return nil, team.ErrTeamInternal
	}

	dbTeam, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		log.Warn("failed to get team from DB", "error", err) // GetTeamByID уже проверяет is_deleted
		return nil, err
	}

	members, membersErr := uc.getAndCacheTeamMembersDetails(teamID, userID)
	if membersErr != nil {
		log.Warn("failed to get/cache team members", "error", membersErr)
	}
	memberCount := len(members)

	// Кэширование основной информации о команде
	// if errSave := uc.repo.SaveTeam(dbTeam); errSave != nil {
	// log.Warn("failed to save team to cache", "error", errSave)
	// } // repo.GetTeamByID уже может использовать кэш

	log.Info("team details retrieved", slog.Int("member_count", memberCount))
	baseTeamResponse := uc.toTeamResponse(dbTeam, &currentUserMembership.Role, memberCount)
	if baseTeamResponse == nil {
		return nil, team.ErrTeamInternal
	}
	return &team.TeamDetailResponse{
		TeamResponse: *baseTeamResponse,
		Members:      members,
	}, nil
}

func (uc *TeamUseCase) getAndCacheTeamMembersDetails(teamID uint, currentUserIDForLog uint) ([]*team.TeamMemberResponse, error) {
	op := "TeamUseCase.getAndCacheTeamMembersDetails"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("currentUserID_for_log", uint64(currentUserIDForLog)))

	// Сначала пытаемся получить из кэша (repo.GetTeamMembers должен это делать)
	cachedMemberships, err := uc.repo.GetTeamMembers(teamID)
	if err == nil && len(cachedMemberships) > 0 { // Проверяем, что список не пуст
		log.Info("team memberships retrieved from cache, converting")
		return uc.convertToTeamMemberResponses(cachedMemberships, currentUserIDForLog)
	}
	if err != nil && !errors.Is(err, usermodels.ErrNotFound) { // Если ошибка не "не найдено", логируем
		log.Error("error getting team memberships from cache", "error", err)
		// Не возвращаем ошибку, пытаемся получить из БД
	}

	// Если в кэше нет или ошибка (кроме NotFound), идем в БД
	dbMemberships, err := uc.repo.GetTeamMemberships(teamID)
	if err != nil {
		log.Error("failed to get team memberships from DB", "error", err)
		return nil, team.ErrTeamInternal // Здесь возвращаем ошибку, если БД не смогла
	}

	// Сохраняем в кэш, если что-то получили из БД
	if len(dbMemberships) > 0 {
		if errSave := uc.repo.SaveTeamMembers(teamID, dbMemberships); errSave != nil {
			log.Warn("failed to save team memberships to cache", "error", errSave)
		}
	}

	log.Info("team memberships retrieved from DB, converting")
	return uc.convertToTeamMemberResponses(dbMemberships, currentUserIDForLog)
}

func (uc *TeamUseCase) convertToTeamMemberResponses(memberships []*team.UserTeamMembership, currentUserIDForLog uint) ([]*team.TeamMemberResponse, error) {
	op := "TeamUseCase.convertToTeamMemberResponses"
	log := uc.log.With(slog.String("op", op), slog.Uint64("currentUserID_for_log", uint64(currentUserIDForLog)))

	memberResponses := make([]*team.TeamMemberResponse, 0, len(memberships))
	for _, m := range memberships {
		userLite, err := uc.repo.GetUserLiteByID(m.UserID)
		if err != nil {
			log.Error("failed to get user lite details for member response", "error", err, "memberUserID", m.UserID, "teamID", m.TeamID)
			// Можно пропустить этого участника или вернуть ошибку для всего списка
			// Пока пропускаем
			continue
		}
		memberResponses = append(memberResponses, &team.TeamMemberResponse{
			User:     *userLite,
			Role:     m.Role,
			JoinedAt: m.JoinedAt,
		})
	}
	return memberResponses, nil
}

func (uc *TeamUseCase) GetMyTeams(userID uint, params team.GetMyTeamsRequest) ([]*team.TeamResponse, error) {
	op := "TeamUseCase.GetMyTeams"
	log := uc.log.With(slog.String("op", op), slog.Uint64("userID", uint64(userID)))

	dbTeams, err := uc.repo.GetTeamsByUserID(userID, params.Search)
	if err != nil {
		log.Error("failed to get user's teams from DB", "error", err)
		return nil, team.ErrTeamInternal
	}

	responses := make([]*team.TeamResponse, 0, len(dbTeams))
	for _, t := range dbTeams {
		var rolePtr *team.TeamMemberRole
		membership, errRole := uc.repo.GetMembership(userID, t.TeamID)
		if errRole == nil {
			rolePtr = &membership.Role
		} else {
			log.Warn("could not get user role for team in list", "teamID", t.TeamID, "userID", userID, "error", errRole)
		}

		count, errCount := uc.repo.GetTeamMembershipsCount(t.TeamID)
		if errCount != nil {
			log.Warn("could not get member count for team in list", "teamID", t.TeamID, "error", errCount)
			count = 0 // По умолчанию 0, если не удалось получить
		}
		responses = append(responses, uc.toTeamResponse(t, rolePtr, count))
	}
	log.Info("user's teams list retrieved", slog.Int("count", len(responses)))
	return responses, nil
}

func (uc *TeamUseCase) UpdateTeamDetails(teamID uint, userID uint, req team.UpdateTeamDetailsRequest, imageFileHeader interface{}) (*team.TeamResponse, error) {
	op := "TeamUseCase.UpdateTeamDetails"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	existingTeam, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		return nil, err
	} // ErrTeamNotFound

	membership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		return nil, team.ErrTeamAccessDenied
	}

	// Разрешаем редактирование владельцу или администратору
	if membership.Role != team.RoleOwner && membership.Role != team.RoleAdmin {
		log.Warn("user not owner or admin for team update", "role", membership.Role)
		return nil, team.ErrTeamAccessDenied
	}

	var newS3Key *string
	var oldS3KeyToDelete *string
	madeChangesToImage := false

	if fh, ok := imageFileHeader.(*multipart.FileHeader); ok && fh != nil {
		log.Info("Processing new team image", "filename", fh.Filename)
		openedFile, errOpen := fh.Open()
		if errOpen != nil {
			log.Error("failed to open image file for team update", "error", errOpen)
			return nil, team.ErrTeamImageUploadFailed
		}
		defer openedFile.Close()

		fileBytes, errRead := io.ReadAll(openedFile)
		if errRead != nil {
			log.Error("failed to read image file for team update", "error", errRead)
			return nil, team.ErrTeamImageUploadFailed
		}

		if int(len(fileBytes)) > uc.s3Cfg.MaxTeamImageSizeBytes { // Используем из s3Cfg
			log.Warn("team image file too large", "size", len(fileBytes), "limit", uc.s3Cfg.MaxTeamImageSizeBytes)
			return nil, team.ErrTeamImageInvalidSize
		}

		// Используем avatarManager для обработки изображения команды
		_, processedBytes, errParse := avatarManager.ParsingAvatarImage(bytes.NewReader(fileBytes))
		if errParse != nil {
			log.Error("failed to parse team image", "error", errParse)
			if errors.Is(errParse, avatarManager.ErrInvalidTypeAvatar) {
				return nil, team.ErrTeamImageInvalidType
			}
			if errors.Is(errParse, avatarManager.ErrInvalidSizeAvatar) {
				return nil, team.ErrTeamImageInvalidSize
			}
			return nil, team.ErrTeamImageUploadFailed
		}

		// Генерируем ключ для S3
		// Используем расширение .webp так как ParsingAvatarImage конвертирует в WebP
		generatedKey := fmt.Sprintf("team_%d/image_%s.webp", teamID, uuid.NewString())

		errUpload := uc.repo.UploadTeamImage(uc.s3Cfg.BucketTeamImages, generatedKey, processedBytes, "image/webp")
		if errUpload != nil {
			log.Error("failed to upload team S3 image", "error", errUpload)
			return nil, team.ErrTeamImageUploadFailed
		}

		tempKey := generatedKey
		newS3Key = &tempKey
		if existingTeam.ImageURLS3Key != nil && *existingTeam.ImageURLS3Key != "" {
			oldS3KeyToDelete = existingTeam.ImageURLS3Key
		}
		madeChangesToImage = true
		log.Info("new team image uploaded", "s3Key", generatedKey)

	} else if req.ResetImage != nil && *req.ResetImage {
		log.Info("team image reset requested")
		if existingTeam.ImageURLS3Key != nil && *existingTeam.ImageURLS3Key != "" {
			oldS3KeyToDelete = existingTeam.ImageURLS3Key
		}
		newS3Key = nil // Указываем, что ключ нужно обнулить
		madeChangesToImage = true
	}

	changedInDB := false
	if req.Name != nil && *req.Name != "" && *req.Name != existingTeam.Name {
		existingTeam.Name = *req.Name
		changedInDB = true
	}
	if req.Description != nil { // Позволяем установить пустое описание
		// Если текущее описание nil, а новое не nil (даже если пустая строка), это изменение
		// Если текущее не nil, а новое отличается
		if (existingTeam.Description == nil && req.Description != nil) || (existingTeam.Description != nil && *req.Description != *existingTeam.Description) {
			existingTeam.Description = req.Description
			changedInDB = true
		}
	}
	if req.Color != nil { // Позволяем установить пустой цвет (для сброса)
		if (existingTeam.Color == nil && req.Color != nil) || (existingTeam.Color != nil && *req.Color != *existingTeam.Color) {
			existingTeam.Color = req.Color
			changedInDB = true
		}
	}

	if madeChangesToImage {
		existingTeam.ImageURLS3Key = newS3Key // Обновляем S3 ключ в модели
		changedInDB = true
	}

	if !changedInDB {
		log.Info("no details changed for team update in DB fields")
		// Если изменилось только изображение, changedInDB может быть false, но madeChangesToImage=true
		// В этом случае все равно нужно вернуть обновленный TeamResponse
		if !madeChangesToImage {
			return nil, team.ErrTeamNoChanges // Или просто вернуть текущее состояние
		}
	}

	existingTeam.UpdatedAt = time.Now() // Обновляем время изменения
	updatedTeamDB, err := uc.repo.UpdateTeam(existingTeam)
	if err != nil {
		log.Error("failed to update team in repo", "error", err)
		// Если загрузили новое изображение, но не смогли обновить команду, нужно удалить загруженное изображение
		if madeChangesToImage && newS3Key != nil && (req.ResetImage == nil || !*req.ResetImage) {
			_ = uc.repo.DeleteTeamImage(uc.s3Cfg.BucketTeamImages, *newS3Key)
		}
		return nil, err
	}

	if oldS3KeyToDelete != nil && *oldS3KeyToDelete != "" {
		if newS3Key == nil || (newS3Key != nil && *oldS3KeyToDelete != *newS3Key) {
			log.Info("deleting old S3 team image", "s3_key", *oldS3KeyToDelete)
			_ = uc.repo.DeleteTeamImage(uc.s3Cfg.BucketTeamImages, *oldS3KeyToDelete)
		}
	}

	// Инвалидация кэшей
	_ = uc.repo.DeleteTeam(teamID)
	membershipsForCacheInvalidation, _ := uc.repo.GetTeamMemberships(teamID)
	for _, m := range membershipsForCacheInvalidation {
		_ = uc.repo.DeleteUserTeams(m.UserID)
	}

	log.Info("team details updated successfully")
	memberCount, _ := uc.repo.GetTeamMembershipsCount(teamID)
	return uc.toTeamResponse(updatedTeamDB, &membership.Role, memberCount), nil
}

func (uc *TeamUseCase) DeleteTeam(teamID uint, userID uint) error {
	op := "TeamUseCase.DeleteTeam"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	teamToDelete, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		return err
	}

	membership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		return team.ErrTeamAccessDenied
	}
	if membership.Role != team.RoleOwner {
		return team.ErrTeamAccessDenied
	}

	now := time.Now()
	teamToDelete.IsDeleted = true
	teamToDelete.DeletedAt = &now

	oldS3Key := teamToDelete.ImageURLS3Key // Сохраняем ключ перед обнулением
	teamToDelete.ImageURLS3Key = nil       // Обнуляем ключ S3 при удалении команды

	if _, errDB := uc.repo.UpdateTeam(teamToDelete); errDB != nil {
		log.Error("failed to logically delete team in DB", "error", errDB)
		return team.ErrTeamInternal
	}

	// Удаляем изображение из S3, если оно было
	if oldS3Key != nil && *oldS3Key != "" {
		log.Info("deleting S3 team image during team delete", "s3_key", *oldS3Key)
		if errS3 := uc.repo.DeleteTeamImage(uc.s3Cfg.BucketTeamImages, *oldS3Key); errS3 != nil {
			log.Error("failed to delete team image from S3 during team delete, but proceeding", "s3_key", *oldS3Key, "error", errS3)
			// Не фатально, команда все равно удалена логически
		}
	}

	if err := uc.repo.LogicallyDeleteTasksByTeamID(teamID, userID); err != nil {
		log.Error("failed to logically delete tasks for team", "error", err)
	}

	// Инвалидация кэшей
	_ = uc.repo.DeleteTeam(teamID)
	membershipsForCacheInvalidation, _ := uc.repo.GetTeamMemberships(teamID) // Получаем ДО удаления
	_ = uc.repo.DeleteTeamMembers(teamID)
	for _, m := range membershipsForCacheInvalidation {
		_ = uc.repo.DeleteUserTeams(m.UserID)
	}

	log.Info("team logically deleted successfully")
	return nil
}

// ... (Остальные методы AddTeamMember, UpdateTeamMemberRole, RemoveTeamMember, LeaveTeam, GenerateInviteToken, JoinTeamByToken, TeamService методы остаются с предыдущими исправлениями)
// Важно убедиться, что они вызывают uc.toTeamResponse с актуальным memberCount после модификаций.
func (uc *TeamUseCase) GetTeamMembers(teamID uint, userID uint) ([]*team.TeamMemberResponse, error) {
	//TODO implement me
	panic("implement me")
}

// Пример для AddTeamMember (нужно добавить получение memberCount)
func (uc *TeamUseCase) AddTeamMember(teamID uint, currentUserID uint, req team.AddTeamMemberRequest) (*team.TeamMemberResponse, error) {
	// ... (существующая логика до return) ...
	// Перед return:
	_ = uc.repo.DeleteTeam(teamID) // Инвалидация кэша команды для обновления MemberCount при следующем GetTeamByID

	createdMembership, err := uc.repo.GetMembership(req.UserID, teamID)
	if err != nil {
		uc.log.Error("failed to retrieve created membership after add for response", "error", err, "targetUserID", req.UserID, "teamID", teamID)
		return nil, team.ErrTeamInternal
	}

	// Получаем UserLite для ответа
	targetUserLite, errUser := uc.repo.GetUserLiteByID(req.UserID)
	if errUser != nil {
		uc.log.Error("failed to get target user lite for response after add", "error", errUser, "targetUserID", req.UserID)
		return nil, team.ErrTeamInternal // Или вернуть ошибку, что пользователь не найден
	}

	return &team.TeamMemberResponse{
		User:     *targetUserLite,
		Role:     createdMembership.Role,
		JoinedAt: createdMembership.JoinedAt,
	}, nil
}

// Пример для UpdateTeamMemberRole (нужно добавить получение memberCount, если toTeamResponse его требует, но здесь возвращается TeamMemberResponse)
func (uc *TeamUseCase) UpdateTeamMemberRole(teamID uint, currentUserID uint, targetUserID uint, req team.UpdateTeamMemberRoleRequest) (*team.TeamMemberResponse, error) {
	// ... (существующая логика до return) ...
	// После uc.repo.UpdateTeamMemberRole и uc.repo.DeleteTeamMembers(teamID):
	_ = uc.repo.DeleteTeam(teamID) // Инвалидация кэша команды для обновления MemberCount при следующем GetTeamByID

	updatedMembership, err := uc.repo.GetMembership(targetUserID, teamID) // Получаем обновленное
	if err != nil {
		uc.log.Error("failed to retrieve updated membership for response", "error", err, "targetUserID", targetUserID, "teamID", teamID)
		return nil, team.ErrTeamInternal
	}

	targetUserLite, errUser := uc.repo.GetUserLiteByID(targetUserID)
	if errUser != nil {
		uc.log.Error("failed to get target user lite for response after role update", "error", errUser, "targetUserID", targetUserID)
		// Можно вернуть ошибку или UserLite с дефолтными значениями
		targetUserLite = &team.UserLiteResponse{UserID: targetUserID, Login: "Unknown"}
	}

	return &team.TeamMemberResponse{
		User:     *targetUserLite,
		Role:     updatedMembership.Role,
		JoinedAt: updatedMembership.JoinedAt,
	}, nil
}

// Пример для RemoveTeamMember (нужно инвалидировать кэш команды для memberCount)
func (uc *TeamUseCase) RemoveTeamMember(teamID uint, currentUserID uint, targetUserID uint) error {
	// ... (существующая логика до return nil) ...
	// После успешного uc.repo.RemoveTeamMember и других инвалидаций:
	_ = uc.repo.DeleteTeam(teamID) // Инвалидация кэша команды для обновления MemberCount
	return nil
}

// Пример для LeaveTeam (нужно инвалидировать кэш команды для memberCount)
func (uc *TeamUseCase) LeaveTeam(teamID uint, userID uint) error {
	// ... (существующая логика до return nil) ...
	// После успешного uc.repo.RemoveTeamMember и других инвалидаций:
	_ = uc.repo.DeleteTeam(teamID) // Инвалидация кэша команды для обновления MemberCount
	return nil
}

// TeamService методы
func (uc *TeamUseCase) IsUserMember(userID, teamID uint) (bool, error) {
	return uc.repo.IsTeamMember(userID, teamID)
}
func (uc *TeamUseCase) GetUserRoleInTeam(userID, teamID uint) (*team.TeamMemberRole, error) {
	m, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		if errors.Is(err, team.ErrUserNotMember) {
			return nil, nil
		} // Не ошибка, просто не участник
		return nil, err
	}
	return &m.Role, nil
}
func (uc *TeamUseCase) CanUserCreateTeamTask(userID, teamID uint) (bool, error) {
	return uc.IsUserMember(userID, teamID)
}
func (uc *TeamUseCase) CanUserEditTeamTaskDetails(userID, teamID uint) (bool, error) {
	role, err := uc.GetUserRoleInTeam(userID, teamID)
	if err != nil || role == nil {
		return false, err
	}
	return *role == team.RoleOwner || *role == team.RoleAdmin || *role == team.RoleEditor, nil
}
func (uc *TeamUseCase) CanUserChangeTeamTaskStatus(userID, teamID uint, taskAssignedToUserID *uint) (bool, error) {
	role, err := uc.GetUserRoleInTeam(userID, teamID)
	if err != nil || role == nil {
		return false, err
	}
	if *role == team.RoleOwner || *role == team.RoleAdmin || *role == team.RoleEditor {
		return true, nil
	}
	return *role == team.RoleMember && taskAssignedToUserID != nil && *taskAssignedToUserID == userID, nil
}
func (uc *TeamUseCase) CanUserDeleteTeamTask(userID, teamID uint, taskCreatorID uint) (bool, error) {
	return uc.CanUserEditTeamTaskDetails(userID, teamID)
}
func (uc *TeamUseCase) IsUserTeamMemberWithUserID(teamID uint, targetUserID uint) (bool, error) {
	return uc.IsUserMember(targetUserID, teamID)
}

func generateSecureRandomToken(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(bytes), nil
}

func (uc *TeamUseCase) GenerateInviteToken(teamID uint, userID uint, req team.GenerateInviteTokenRequest) (*team.TeamInviteTokenResponse, error) {
	op := "TeamUseCase.GenerateInviteToken"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	_, err := uc.repo.GetTeamByID(teamID) // Проверяем, что команда существует и не удалена
	if err != nil {
		return nil, err
	}

	membership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		return nil, team.ErrTeamAccessDenied
	}
	if membership.Role != team.RoleOwner && membership.Role != team.RoleAdmin {
		return nil, team.ErrTeamAccessDenied
	}

	hoursToExpire := uint(24 * 7)
	if req.ExpiresInHours != nil && *req.ExpiresInHours > 0 {
		hoursToExpire = *req.ExpiresInHours
	}
	expiresAt := time.Now().Add(time.Duration(hoursToExpire) * time.Hour)

	roleOnJoin := team.RoleMember
	if req.RoleToAssign != nil && req.RoleToAssign.IsValid() {
		if *req.RoleToAssign == team.RoleEditor || *req.RoleToAssign == team.RoleMember {
			roleOnJoin = *req.RoleToAssign
		} else {
			return nil, team.ErrRoleChangeNotAllowed
		}
	}

	inviteToken, err := generateSecureRandomToken(32)
	if err != nil {
		return nil, team.ErrTeamInternal
	}

	if err := uc.repo.SaveInviteToken(inviteToken, teamID, roleOnJoin, expiresAt); err != nil {
		return nil, team.ErrTeamInternal
	}

	var frontendBase string
	if len(uc.httpCfg.AllowedOrigins) > 0 && uc.httpCfg.AllowedOrigins[0] != "" {
		frontendBase = strings.TrimSuffix(uc.httpCfg.AllowedOrigins[0], "/")
	} else {
		log.Warn("AllowedOrigins[0] is not configured for http server, invite link will be relative or use a placeholder")
		// ВАЖНО: Установите здесь дефолтный URL вашего фронтенда для таких случаев или сделайте его обязательным в конфигурации.
		frontendBase = "https://your-frontend-placeholder.com"
	}

	joinPath := "/join-team"
	fullInviteLink := fmt.Sprintf("%s%s/%s", frontendBase, joinPath, inviteToken)

	log.Info("invite token generated", "teamID", teamID, "roleOnJoin", roleOnJoin, "expiresAt", expiresAt, "link", fullInviteLink)
	return &team.TeamInviteTokenResponse{
		InviteToken: inviteToken,
		InviteLink:  fullInviteLink,
		ExpiresAt:   expiresAt,
		RoleOnJoin:  roleOnJoin,
	}, nil
}

func (uc *TeamUseCase) JoinTeamByToken(tokenValue string, userID uint) (*team.TeamResponse, error) {
	teamID, roleToAssign, isValid, err := uc.repo.GetInviteTokenData(tokenValue)
	if err != nil {
		return nil, team.ErrTeamInternal
	}
	if !isValid {
		return nil, team.ErrTeamInviteTokenInvalid
	}

	teamModel, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		_ = uc.repo.DeleteInviteToken(tokenValue)
		return nil, team.ErrTeamInviteTokenInvalid
	}

	isAlreadyMember, _ := uc.repo.IsTeamMember(userID, teamID)
	if isAlreadyMember {
		role, _ := uc.repo.GetMembership(userID, teamID)
		memberCount, _ := uc.repo.GetTeamMembershipsCount(teamID)
		return uc.toTeamResponse(teamModel, &role.Role, memberCount), nil
	}

	membership := team.UserTeamMembership{
		UserID: userID,
		TeamID: teamID,
		Role:   roleToAssign,
	}
	if err := uc.repo.CreateMembership(&membership); err != nil { // CreateMembership должен обработать уже существующее (хотя мы проверили)
		return nil, err
	}

	// Удаляем токен, если он одноразовый (сейчас он не помечен как одноразовый, но можно добавить логику)
	// _ = uc.repo.DeleteInviteToken(tokenValue)

	_ = uc.repo.DeleteTeamMembers(teamID) // Обновляем кэш участников
	_ = uc.repo.DeleteUserTeams(userID)   // Обновляем кэш списка команд пользователя
	_ = uc.repo.DeleteTeam(teamID)        // Обновляем кэш самой команды (например, для member_count)

	memberCountAfterJoin, _ := uc.repo.GetTeamMembershipsCount(teamID)
	return uc.toTeamResponse(teamModel, &roleToAssign, memberCountAfterJoin), nil
}

// hashTokenForLog - вспомогательная функция для логирования части хеша токена
func hashTokenForLog(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:8]) // Логируем только первые 8 байт хеша (16 символов)
}
