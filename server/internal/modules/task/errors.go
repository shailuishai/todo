package task

import "errors"

var (
	// ErrTaskNotFound используется, когда задача не найдена в хранилище.
	// Хотя мы можем использовать общую usermodels.ErrNotFound, специфичная ошибка
	// может быть полезна для более точной обработки или логирования.
	ErrTaskNotFound = errors.New("task not found")
	ErrTaskInternal = errors.New("internal error")

	// ErrTaskAccessDenied используется, когда пользователь не имеет прав на выполнение операции с задачей.
	// Например, попытка редактировать или удалить чужую личную задачу,
	// или командную задачу без соответствующих прав в команде.
	// Может пересекаться с usermodels.ErrForbidden, но может быть более специфичным.
	ErrTaskAccessDenied = errors.New("access to task denied")

	// ErrTaskInvalidStatusTransition используется, если попытка перевести задачу в недопустимый статус.
	// (например, из "done" обратно в "todo" без специальных прав или логики) - если такая логика будет.
	ErrTaskInvalidStatusTransition = errors.New("invalid status transition for task")

	// ErrTaskTeamRequired используется, если для операции с командной задачей не указан TeamID,
	// или если личная задача ошибочно обрабатывается как командная.
	ErrTaskTeamRequired = errors.New("team context is required for this task operation")

	// ErrTaskAssigneeNotInTeam используется, если пользователь, которому назначается командная задача,
	// не является участником этой команды.
	ErrTaskAssigneeNotInTeam = errors.New("assignee is not a member of the task's team")

	// ErrTaskCannotChangeTeam используется, если есть попытка изменить TeamID существующей задачи,
	// что обычно не разрешается (задачу нельзя "переместить" между командами или из личных в командные простым обновлением).
	ErrTaskCannotChangeTeam = errors.New("cannot change the team assignment of an existing task")

	// ErrTaskInvalidInput используется для общих ошибок валидации входных данных,
	// специфичных для задач, которые не покрываются стандартным валидатором.
	ErrTaskInvalidInput = errors.New("invalid input for task operation")

	// ErrTaskAlreadyCompleted используется, если пытаются выполнить действие над уже завершенной задачей,
	// которое для нее не предусмотрено (например, изменить дедлайн).
	ErrTaskAlreadyCompleted = errors.New("operation not allowed on a completed task")

	// ErrTaskAlreadyDeleted используется, если пытаются выполнить действие над уже удаленной задачей.
	ErrTaskAlreadyDeleted = errors.New("operation not allowed on a deleted task")
)
