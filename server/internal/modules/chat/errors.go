package chat

import "errors"

var (
	ErrMessageNotFound         = errors.New("message not found")
	ErrChatAccessDenied        = errors.New("access to chat resource denied")
	ErrUserNotInTeam           = errors.New("user is not a member of this team")
	ErrUserNotInTeamChat       = errors.New("user is not a member of this team's chat")
	ErrCannotEditMessage       = errors.New("user cannot edit this message")
	ErrCannotDeleteMessage     = errors.New("user cannot delete this message")
	ErrInvalidMessageData      = errors.New("invalid message data provided")
	ErrWebSocketUpgradeFailed  = errors.New("failed to upgrade to websocket protocol")
	ErrInternalChatService     = errors.New("internal chat service error")
	ErrClientMessageIDConflict = errors.New("message with this client_message_id already processed")
)
