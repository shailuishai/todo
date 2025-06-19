// internal/modules/team/usecase/teamUsecase.go
package usecase

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime/multipart"
	"server/config"
	"server/internal/modules/team"
	usermodels "server/internal/modules/user"
	avatarManager "server/pkg/lib/avatarMenager"
	"strings"
	"time"

	"github.com/google/uuid"
)

type TeamUseCase struct {
	repo    team.Repo
	log     *slog.Logger
	s3Cfg   config.S3Config
	ttlCfg  config.CacheConfig
	httpCfg config.HttpServerConfig
}

func NewTeamUseCase(
	repo team.Repo,
	log *slog.Logger,
	appCfg config.Config,
) team.UseCase {
	return &TeamUseCase{
		repo:    repo,
		log:     log,
		s3Cfg:   appCfg.S3Config,
		ttlCfg:  appCfg.CacheConfig,
		httpCfg: appCfg.HttpServerConfig,
	}
}

// ... (все существующие методы без изменений) ...

func (uc *TeamUseCase) toTeamResponse(t *team.Team, role *team.TeamMemberRole, memberCount int) *team.TeamResponse {
	if t == nil {
		return nil
	}
	var fullImageURL *string
	if t.ImageURLS3Key != nil && *t.ImageURLS3Key != "" {
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

func (uc *TeamUseCase) CreateTeam(userID uint, req team.CreateTeamRequest) (*team.TeamResponse, error) {
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
		ImageURLS3Key:   nil,
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
		return nil, team.ErrTeamInternal
	}

	_ = uc.repo.DeleteUserTeams(userID)
	_ = uc.repo.DeleteTeamMembers(createdTeam.TeamID)

	log.Info("team created successfully", slog.Uint64("teamID", uint64(createdTeam.TeamID)))
	ownerRole := team.RoleOwner
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
		log.Warn("failed to get team from DB", "error", err)
		return nil, err
	}

	members, membersErr := uc.getAndCacheTeamMembersDetails(teamID, userID)
	if membersErr != nil {
		log.Warn("failed to get/cache team members", "error", membersErr)
	}
	memberCount := len(members)

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

	cachedMemberships, err := uc.repo.GetTeamMembers(teamID)
	if err == nil && len(cachedMemberships) > 0 {
		log.Info("team memberships retrieved from cache, converting")
		return uc.convertToTeamMemberResponses(cachedMemberships, currentUserIDForLog)
	}
	if err != nil && !errors.Is(err, usermodels.ErrNotFound) {
		log.Error("error getting team memberships from cache", "error", err)
	}

	dbMemberships, err := uc.repo.GetTeamMemberships(teamID)
	if err != nil {
		log.Error("failed to get team memberships from DB", "error", err)
		return nil, team.ErrTeamInternal
	}

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
			count = 0
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
	}

	membership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		return nil, team.ErrTeamAccessDenied
	}

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

		if int(len(fileBytes)) > uc.s3Cfg.MaxTeamImageSizeBytes {
			log.Warn("team image file too large", "size", len(fileBytes), "limit", uc.s3Cfg.MaxTeamImageSizeBytes)
			return nil, team.ErrTeamImageInvalidSize
		}

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
		newS3Key = nil
		madeChangesToImage = true
	}

	changedInDB := false
	if req.Name != nil && *req.Name != "" && *req.Name != existingTeam.Name {
		existingTeam.Name = *req.Name
		changedInDB = true
	}
	if req.Description != nil {
		if (existingTeam.Description == nil && req.Description != nil) || (existingTeam.Description != nil && *req.Description != *existingTeam.Description) {
			existingTeam.Description = req.Description
			changedInDB = true
		}
	}
	if req.Color != nil {
		if (existingTeam.Color == nil && req.Color != nil) || (existingTeam.Color != nil && *req.Color != *existingTeam.Color) {
			existingTeam.Color = req.Color
			changedInDB = true
		}
	}

	if madeChangesToImage {
		existingTeam.ImageURLS3Key = newS3Key
		changedInDB = true
	}

	if !changedInDB {
		log.Info("no details changed for team update in DB fields")
		if !madeChangesToImage {
			return nil, team.ErrTeamNoChanges
		}
	}

	existingTeam.UpdatedAt = time.Now()
	updatedTeamDB, err := uc.repo.UpdateTeam(existingTeam)
	if err != nil {
		log.Error("failed to update team in repo", "error", err)
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

	oldS3Key := teamToDelete.ImageURLS3Key
	teamToDelete.ImageURLS3Key = nil

	if _, errDB := uc.repo.UpdateTeam(teamToDelete); errDB != nil {
		log.Error("failed to logically delete team in DB", "error", errDB)
		return team.ErrTeamInternal
	}

	if oldS3Key != nil && *oldS3Key != "" {
		log.Info("deleting S3 team image during team delete", "s3_key", *oldS3Key)
		if errS3 := uc.repo.DeleteTeamImage(uc.s3Cfg.BucketTeamImages, *oldS3Key); errS3 != nil {
			log.Error("failed to delete team image from S3 during team delete, but proceeding", "s3_key", *oldS3Key, "error", errS3)
		}
	}

	if err := uc.repo.LogicallyDeleteTasksByTeamID(teamID, userID); err != nil {
		log.Error("failed to logically delete tasks for team", "error", err)
	}

	_ = uc.repo.DeleteTeam(teamID)
	membershipsForCacheInvalidation, _ := uc.repo.GetTeamMemberships(teamID)
	_ = uc.repo.DeleteTeamMembers(teamID)
	for _, m := range membershipsForCacheInvalidation {
		_ = uc.repo.DeleteUserTeams(m.UserID)
	}

	log.Info("team logically deleted successfully")
	return nil
}

func (uc *TeamUseCase) GetTeamMembers(teamID uint, userID uint) ([]*team.TeamMemberResponse, error) {
	panic("implement me")
}

func (uc *TeamUseCase) AddTeamMember(teamID uint, currentUserID uint, req team.AddTeamMemberRequest) (*team.TeamMemberResponse, error) {
	_ = uc.repo.DeleteTeam(teamID)

	createdMembership, err := uc.repo.GetMembership(req.UserID, teamID)
	if err != nil {
		uc.log.Error("failed to retrieve created membership after add for response", "error", err, "targetUserID", req.UserID, "teamID", teamID)
		return nil, team.ErrTeamInternal
	}

	targetUserLite, errUser := uc.repo.GetUserLiteByID(req.UserID)
	if errUser != nil {
		uc.log.Error("failed to get target user lite for response after add", "error", errUser, "targetUserID", req.UserID)
		return nil, team.ErrTeamInternal
	}

	return &team.TeamMemberResponse{
		User:     *targetUserLite,
		Role:     createdMembership.Role,
		JoinedAt: createdMembership.JoinedAt,
	}, nil
}

func (uc *TeamUseCase) UpdateTeamMemberRole(teamID, currentUserID, targetUserID uint, req team.UpdateTeamMemberRoleRequest) (*team.TeamMemberResponse, error) {
	op := "TeamUseCase.UpdateTeamMemberRole"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("currentUserID", uint64(currentUserID)), slog.Uint64("targetUserID", uint64(targetUserID)))

	if currentUserID == targetUserID {
		return nil, team.ErrCannotPerformActionOnSelf
	}

	currentUserMembership, err := uc.repo.GetMembership(currentUserID, teamID)
	if err != nil {
		log.Error("failed to get current user membership", "error", err)
		return nil, team.ErrTeamAccessDenied
	}

	if currentUserMembership.Role != team.RoleOwner && currentUserMembership.Role != team.RoleAdmin {
		log.Warn("user lacks permission to change roles", "currentUserRole", currentUserMembership.Role)
		return nil, team.ErrTeamAccessDenied
	}

	memberToUpdate, err := uc.repo.GetMembership(targetUserID, teamID)
	if err != nil {
		log.Error("failed to get target user membership", "error", err)
		return nil, team.ErrUserNotMember
	}

	if currentUserMembership.Role == team.RoleAdmin && (memberToUpdate.Role == team.RoleAdmin || memberToUpdate.Role == team.RoleOwner) {
		log.Warn("admin attempted to change role of another admin or owner")
		return nil, team.ErrTeamAccessDenied
	}
	if memberToUpdate.Role == team.RoleOwner {
		log.Warn("attempted to change owner's role")
		return nil, team.ErrCannotChangeOwnerRole
	}

	updatedMembership, err := uc.repo.UpdateTeamMemberRole(targetUserID, teamID, req.Role)
	if err != nil {
		log.Error("failed to update team member role in repo", "error", err)
		return nil, team.ErrTeamInternal
	}

	_ = uc.repo.DeleteTeamMembers(teamID)
	_ = uc.repo.DeleteTeam(teamID)
	log.Info("team members and team cache invalidated", slog.Uint64("teamID", uint64(teamID)))

	targetUserLite, errUser := uc.repo.GetUserLiteByID(targetUserID)
	if errUser != nil {
		log.Error("failed to get target user lite for response after role update", "error", errUser, "targetUserID", targetUserID)
		targetUserLite = &team.UserLiteResponse{UserID: targetUserID, Login: "Unknown"}
	}

	return &team.TeamMemberResponse{
		User:     *targetUserLite,
		Role:     updatedMembership.Role,
		JoinedAt: updatedMembership.JoinedAt,
	}, nil
}

func (uc *TeamUseCase) RemoveTeamMember(teamID uint, currentUserID uint, targetUserID uint) error {
	op := "TeamUseCase.RemoveTeamMember"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("currentUserID", uint64(currentUserID)), slog.Uint64("targetUserID", uint64(targetUserID)))

	if currentUserID == targetUserID {
		return team.ErrCannotPerformActionOnSelf
	}

	teamModel, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		return err
	}
	if teamModel.IsDeleted {
		return team.ErrTeamIsDeleted
	}

	currentUserMembership, err := uc.repo.GetMembership(currentUserID, teamID)
	if err != nil {
		return team.ErrTeamAccessDenied
	}
	if currentUserMembership.Role != team.RoleOwner && currentUserMembership.Role != team.RoleAdmin {
		log.Warn("user lacks permission", "role", currentUserMembership.Role)
		return team.ErrTeamAccessDenied
	}

	targetMembership, err := uc.repo.GetMembership(targetUserID, teamID)
	if err != nil {
		if errors.Is(err, team.ErrUserNotMember) {
			return team.ErrUserNotMember
		}
		log.Error("failed to get target membership", "error", err)
		return team.ErrTeamInternal
	}

	if targetMembership.Role == team.RoleOwner {
		return team.ErrCannotRemoveLastOwner
	}

	if currentUserMembership.Role == team.RoleAdmin && targetMembership.Role == team.RoleAdmin {
		log.Warn("admin cannot remove another admin")
		return team.ErrTeamAccessDenied
	}

	if err := uc.repo.RemoveTeamMember(targetUserID, teamID); err != nil {
		log.Error("failed to remove member in repo", "error", err)
		return err
	}

	_ = uc.repo.DeleteTeamMembers(teamID)
	_ = uc.repo.DeleteUserTeams(targetUserID)

	log.Info("team member removed successfully")
	return nil
}

func (uc *TeamUseCase) LeaveTeam(teamID uint, userID uint) error {
	op := "TeamUseCase.LeaveTeam"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	teamModel, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		return err
	}
	if teamModel.IsDeleted {
		return team.ErrTeamIsDeleted
	}

	membership, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		if errors.Is(err, team.ErrUserNotMember) {
			return team.ErrUserNotMember
		}
		log.Error("failed to get membership", "error", err)
		return team.ErrTeamInternal
	}

	if membership.Role == team.RoleOwner {
		members, _ := uc.repo.GetTeamMemberships(teamID)
		if len(members) == 1 {
			log.Warn("owner cannot leave as the only member")
			return team.ErrCannotRemoveLastOwner
		}
		log.Warn("owner cannot leave team")
		return team.ErrTeamAccessDenied
	}

	if err := uc.repo.RemoveTeamMember(userID, teamID); err != nil {
		log.Error("failed to leave team", "error", err)
		return err
	}

	_ = uc.repo.DeleteTeamMembers(teamID)
	_ = uc.repo.DeleteUserTeams(userID)

	log.Info("user successfully left team")
	return nil
}

func (uc *TeamUseCase) IsUserMember(userID, teamID uint) (bool, error) {
	return uc.repo.IsTeamMember(userID, teamID)
}

func (uc *TeamUseCase) GetUserRoleInTeam(userID, teamID uint) (*team.TeamMemberRole, error) {
	m, err := uc.repo.GetMembership(userID, teamID)
	if err != nil {
		if errors.Is(err, team.ErrUserNotMember) {
			return nil, nil
		}
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

func (uc *TeamUseCase) GenerateInviteToken(teamID uint, userID uint, req team.GenerateInviteTokenRequest) (*team.TeamInviteTokenResponse, error) {
	op := "TeamUseCase.GenerateInviteToken"
	log := uc.log.With(slog.String("op", op), slog.Uint64("teamID", uint64(teamID)), slog.Uint64("userID", uint64(userID)))

	_, err := uc.repo.GetTeamByID(teamID)
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
	if err := uc.repo.CreateMembership(&membership); err != nil {
		return nil, err
	}

	_ = uc.repo.DeleteTeamMembers(teamID)
	_ = uc.repo.DeleteUserTeams(userID)
	_ = uc.repo.DeleteTeam(teamID)

	memberCountAfterJoin, _ := uc.repo.GetTeamMembershipsCount(teamID)
	return uc.toTeamResponse(teamModel, &roleToAssign, memberCountAfterJoin), nil
}

func generateSecureRandomToken(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(bytes), nil
}

func hashTokenForLog(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:8])
}

// ИЗМЕНЕНИЕ: Новые методы

// IsUserMemberByLogin проверяет, является ли пользователь с указанным логином участником команды.
func (uc *TeamUseCase) IsUserMemberByLogin(teamID uint, userLogin string) (bool, *team.UserLiteResponse, error) {
	log := uc.log.With("op", "TeamUseCase.IsUserMemberByLogin", "teamID", teamID, "userLogin", userLogin)

	// 1. Находим пользователя по логину
	user, err := uc.repo.GetUserByLoginOrEmail(userLogin)
	if err != nil {
		if errors.Is(err, usermodels.ErrUserNotFound) {
			log.Warn("user not found by login")
			return false, nil, nil // Не ошибка, просто пользователь не найден
		}
		log.Error("failed to get user by login", "error", err)
		return false, nil, team.ErrTeamInternal
	}

	// 2. Проверяем его членство в команде
	isMember, err := uc.repo.IsTeamMember(user.UserId, teamID)
	if err != nil {
		log.Error("failed to check team membership", "error", err)
		return false, nil, team.ErrTeamInternal
	}

	if !isMember {
		return false, nil, nil
	}

	// 3. Если он участник, возвращаем его UserLite DTO
	userLite, err := uc.repo.GetUserLiteByID(user.UserId)
	if err != nil {
		log.Error("failed to get user lite info for member", "error", err)
		return true, nil, team.ErrTeamInternal // Он участник, но не смогли получить DTO
	}

	return true, userLite, nil
}

// GetTeamName возвращает название команды по ее ID.
func (uc *TeamUseCase) GetTeamName(teamID uint) (string, error) {
	log := uc.log.With("op", "TeamUseCase.GetTeamName", "teamID", teamID)

	teamModel, err := uc.repo.GetTeamByID(teamID)
	if err != nil {
		if errors.Is(err, team.ErrTeamNotFound) {
			log.Warn("team not found by id")
			return "", team.ErrTeamNotFound
		}
		log.Error("failed to get team by id", "error", err)
		return "", team.ErrTeamInternal
	}
	return teamModel.Name, nil
}
