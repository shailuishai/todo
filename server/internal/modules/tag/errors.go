package tag

import "errors"

var (
	ErrTagNotFound         = errors.New("tag not found")
	ErrTagAccessDenied     = errors.New("access to tag denied")
	ErrTagNameRequired     = errors.New("tag name is required")
	ErrTagNameTooLong      = errors.New("tag name is too long (max 50 chars)")
	ErrTagColorInvalid     = errors.New("invalid tag color format (must be hex, e.g., #RRGGBB)")
	ErrUserTagNameConflict = errors.New("a tag with this name already exists for this user")
	ErrTeamTagNameConflict = errors.New("a tag with this name already exists for this team")
	ErrTagTypeMismatch     = errors.New("operation not allowed for this tag type")                    // Например, попытка удалить TeamTag через эндпоинт UserTag
	ErrTagStillInUse       = errors.New("tag cannot be deleted as it is still associated with tasks") // Если решим не использовать ON DELETE CASCADE
	ErrTaskTagLinkFailed   = errors.New("failed to link tag to task")
	ErrTaskTagUnlinkFailed = errors.New("failed to unlink tag from task")
	ErrTagInternal         = errors.New("tag module internal error")
)
