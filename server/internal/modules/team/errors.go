package team

import "errors"

var (
	// ErrTeamNotFound используется, когда команда не найдена.
	ErrTeamNotFound = errors.New("team not found")

	// ErrTeamAccessDenied используется, когда пользователь не имеет прав на выполнение операции с командой или её участниками.
	ErrTeamAccessDenied = errors.New("access to team or team operation denied")

	// ErrTeamNameRequired используется, если имя команды не предоставлено при создании.
	ErrTeamNameRequired = errors.New("team name is required")

	// ErrTeamNameTooLong используется, если имя команды превышает допустимую длину.
	ErrTeamNameTooLong = errors.New("team name is too long") // Макс. 100 символов по схеме БД

	// ErrTeamDescriptionTooLong используется, если описание команды превышает допустимую длину.
	ErrTeamDescriptionTooLong = errors.New("team description is too long")

	// ErrTeamColorInvalid используется, если формат цвета команды некорректен.
	ErrTeamColorInvalid = errors.New("invalid team color format (must be hex, e.g., #RRGGBB)")

	// ErrTeamAlreadyExists используется, если пользователь пытается создать команду с именем, которое уже занято (если будет такое ограничение).
	// Пока что у нас нет такого ограничения на уникальность имени команды глобально или для пользователя.
	// ErrTeamAlreadyExists = errors.New("team with this name already exists")

	// ErrUserAlreadyMember используется при попытке добавить пользователя, который уже является участником команды.
	ErrUserAlreadyMember = errors.New("user is already a member of this team")
	ErrTeamNoChanges     = errors.New("team has no changes")
	// ErrUserNotMember используется, когда операция требует, чтобы пользователь был участником, а он не является.
	// Или когда целевой пользователь для операции (например, изменение роли) не является участником.
	ErrUserNotMember = errors.New("user is not a member of this team")

	// ErrCannotRemoveLastOwner используется, если делается попытка удалить единственного владельца команды.
	ErrCannotRemoveLastOwner = errors.New("cannot remove the last owner of the team")

	// ErrCannotChangeOwnerRole используется, если делается попытка изменить роль владельца команды.
	// (т.к. передача владения не предусмотрена, роль owner-а не меняется).
	ErrCannotChangeOwnerRole = errors.New("cannot change the role of the team owner")

	// ErrCannotPerformActionOnSelf используется, когда пользователь пытается выполнить определенное действие над собой, которое не разрешено (например, админ пытается кикнуть сам себя).
	ErrCannotPerformActionOnSelf = errors.New("cannot perform this action on oneself")

	// ErrRoleChangeNotAllowed используется для ситуаций, когда изменение роли не разрешено логикой (например, member пытается назначить admin).
	ErrRoleChangeNotAllowed = errors.New("role change is not allowed by current user or for target user")

	// ErrTeamImageUploadFailed общая ошибка при неудачной загрузке изображения команды.
	ErrTeamImageUploadFailed = errors.New("team image upload failed")

	// ErrTeamImageInvalidType ошибка неверного типа файла изображения команды.
	ErrTeamImageInvalidType = errors.New("invalid team image file type") // Аналогично аватару пользователя

	// ErrTeamImageInvalidSize ошибка превышения размера файла изображения команды.
	ErrTeamImageInvalidSize = errors.New("team image file size exceeds allowed limit") // Аналогично аватару пользователя

	// ErrTeamInviteFailed общая ошибка при генерации или обработке приглашения.
	ErrTeamInviteFailed = errors.New("team invitation process failed")

	// ErrTeamInviteTokenInvalid или Expired.
	ErrTeamInviteTokenInvalid = errors.New("team invite link/token is invalid or expired")

	// ErrTeamIsDeleted используется при попытке выполнить операции с логически удаленной командой (кроме, возможно, восстановления).
	ErrTeamIsDeleted = errors.New("operation not allowed on a deleted team")

	// ErrTeamInternal специфичная для модуля ошибка, если не подходит общая из usermodels.
	ErrTeamInternal = errors.New("team module internal error")
)
