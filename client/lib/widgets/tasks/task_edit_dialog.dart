// lib/widgets/tasks/task_edit_dialog.dart
import '../../core/utils/responsive_utils.dart';
import '../../models/task_model.dart';
import '../../tag_provider.dart';
import '../../task_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth_state.dart';

class TaskEditDialog extends StatefulWidget {
  final Task? taskToEdit;
  final Function(Task updatedTask)? onTaskSaved;

  const TaskEditDialog({Key? key, this.taskToEdit, this.onTaskSaved}) : super(key: key);

  @override
  State<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<TaskEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  KanbanColumnStatus _selectedStatus = KanbanColumnStatus.todo;
  TaskPriority _selectedPriority = TaskPriority.medium;
  DateTime? _selectedDeadline;
  List<ApiTag> _selectedUserTags = [];
  List<ApiTag> _selectedTeamTags = [];

  // Для отслеживания состояния кнопок тулбара (пока не используется для реального состояния)
  // Можно расширить, чтобы отслеживать, находится ли курсор внутри отформатированного блока.
  // Set<String> _activeMarkdownStyles = {};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.taskToEdit?.title ?? '');
    _descriptionController = TextEditingController(text: widget.taskToEdit?.description ?? '');
    _selectedStatus = widget.taskToEdit?.status ?? KanbanColumnStatus.todo;
    _selectedPriority = widget.taskToEdit?.priority ?? TaskPriority.medium;
    _selectedDeadline = widget.taskToEdit?.deadline;

    if (widget.taskToEdit != null) {
      _selectedUserTags = List<ApiTag>.from(widget.taskToEdit!.tags.where((t) => t.type == 'user'));
      _selectedTeamTags = List<ApiTag>.from(widget.taskToEdit!.tags.where((t) => t.type == 'team'));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tagProvider = Provider.of<TagProvider>(context, listen: false);
      if (tagProvider.userTags.isEmpty && !tagProvider.isLoadingUserTags && tagProvider.error == null) {
        tagProvider.fetchUserTags();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline(BuildContext pickerContext) async {
    final initialPickerDate = _selectedDeadline ?? DateTime.now();
    final initialPickerTime = TimeOfDay.fromDateTime(_selectedDeadline ?? DateTime(initialPickerDate.year, initialPickerDate.month, initialPickerDate.day, 12, 00));

    final DateTime? pickedDate = await showDatePicker(
      context: pickerContext,
      initialDate: initialPickerDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('ru', 'RU'),
    );

    if (!mounted) return;
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: pickerContext,
        initialTime: initialPickerTime,
      );
      if (!mounted) return;
      if (pickedTime != null) {
        setState(() {
          _selectedDeadline = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute,
          );
        });
      } else {
        setState(() {
          _selectedDeadline = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59);
        });
      }
    }
  }

  void _insertMarkdownSyntax(String prefix, String suffix, {String? hint}) {
    final text = _descriptionController.text;
    final selection = _descriptionController.selection;
    final middle = hint ?? selection.textInside(text);

    // Если нет выделения и есть hint, вставляем hint.
    // Если есть выделение, оборачиваем его.
    final String newTextContent = selection.isValid && selection.isCollapsed && hint != null
        ? prefix + hint + suffix
        : prefix + middle + suffix;

    final newText = selection.textBefore(text) +
        newTextContent +
        selection.textAfter(text);

    int newCursorPosition;
    if (selection.isValid && !selection.isCollapsed) { // Если было выделение
      newCursorPosition = selection.start + prefix.length + middle.length + suffix.length;
    } else { // Если не было выделения (или оно схлопнуто)
      newCursorPosition = selection.start + prefix.length + (hint?.length ?? 0);
    }

    _descriptionController.text = newText;
    _descriptionController.selection = TextSelection.fromPosition(
        TextPosition(offset: newCursorPosition));

    // Фокусируемся на поле после вставки
    FocusScope.of(context).requestFocus(_descriptionController.selection.isValid ? null : FocusNode()); // Эта строка может быть не нужна или улучшена
  }


  Widget _buildMarkdownToolbarButton(IconData icon, String tooltip, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 20, // Немного меньше для компактности тулбара
      splashRadius: 20,
      color: theme.colorScheme.onSurfaceVariant,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _buildMarkdownToolbar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.8),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5), width: 0.5)
      ),
      child: Wrap(
        spacing: 4.0, // Уменьшаем расстояние между кнопками
        runSpacing: 0,
        alignment: WrapAlignment.spaceAround, // Распределяем кнопки
        children: [
          _buildMarkdownToolbarButton(Icons.format_bold, "Жирный", () => _insertMarkdownSyntax("**", "**", hint: "жирный")),
          _buildMarkdownToolbarButton(Icons.format_italic, "Курсив", () => _insertMarkdownSyntax("*", "*", hint: "курсив")),
          _buildMarkdownToolbarButton(Icons.strikethrough_s, "Зачеркнутый", () => _insertMarkdownSyntax("~~", "~~", hint: "зачеркнутый")),
          VerticalDivider(width: 16, thickness: 1, indent: 8, endIndent: 8, color: theme.colorScheme.outlineVariant),
          _buildMarkdownToolbarButton(Icons.link, "Ссылка", () => _insertMarkdownSyntax("[текст ссылки](", ")", hint: "https://example.com")),
          _buildMarkdownToolbarButton(Icons.image_outlined, "Изображение", () => _insertMarkdownSyntax("![альт текст](", ")", hint: "https://url_картинки.png")),
          VerticalDivider(width: 16, thickness: 1, indent: 8, endIndent: 8, color: theme.colorScheme.outlineVariant),
          _buildMarkdownToolbarButton(Icons.format_list_bulleted, "Маркированный список", () => _insertMarkdownSyntax("\n- ", "", hint: "Элемент")),
          _buildMarkdownToolbarButton(Icons.format_list_numbered, "Нумерованный список", () => _insertMarkdownSyntax("\n1. ", "", hint: "Элемент")),
          _buildMarkdownToolbarButton(Icons.format_quote, "Цитата", () => _insertMarkdownSyntax("\n> ", "", hint: "Цитата")),
          VerticalDivider(width: 16, thickness: 1, indent: 8, endIndent: 8, color: theme.colorScheme.outlineVariant),
          _buildMarkdownToolbarButton(Icons.code, "Встроенный код", () => _insertMarkdownSyntax("`", "`", hint: "код")),
          _buildMarkdownToolbarButton(Icons.integration_instructions_outlined, "Блок кода", () => _insertMarkdownSyntax("\n```\n", "\n```", hint: "ваш код здесь")),
        ],
      ),
    );
  }


  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final authState = Provider.of<AuthState>(context, listen: false);

    if (authState.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка: пользователь не авторизован.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final allSelectedTags = [..._selectedUserTags, ..._selectedTeamTags];
    String? createdById = widget.taskToEdit?.createdByUserId ?? authState.currentUser!.userId.toString();

    Task taskData = Task(
      taskId: widget.taskToEdit?.taskId ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      status: _selectedStatus,
      priority: _selectedPriority,
      deadline: _selectedDeadline,
      tags: allSelectedTags,
      createdByUserId: createdById,
      teamId: widget.taskToEdit?.teamId,
      teamName: widget.taskToEdit?.teamName,
      assignedToUserId: widget.taskToEdit?.assignedToUserId,
      createdAt: widget.taskToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      completedAt: _selectedStatus == KanbanColumnStatus.done
          ? (widget.taskToEdit?.completedAt ?? DateTime.now())
          : null,
    );

    if (!taskData.isTeamTask && taskData.assignedToUserId == null) {
      taskData = taskData.copyWith(assignedToUserId: authState.currentUser!.userId.toString());
    }
    debugPrint("[TaskEditDialog._saveTask] TaskData being prepared - ID: ${taskData.taskId}, Title: ${taskData.title}, UpdatedAt: ${taskData.updatedAt}");

    bool success = false;
    String actionMessage = "";
    Task? resultTask;

    if (widget.taskToEdit == null) {
      actionMessage = "создана";
      resultTask = await taskProvider.createTaskAndReturn(taskData);
      success = resultTask != null;
    } else {
      actionMessage = "обновлена";
      debugPrint("[TaskEditDialog._saveTask] Calling updateTaskAndReturn with task ID: ${taskData.taskId} (from taskData)");
      resultTask = await taskProvider.updateTaskAndReturn(taskData);
      success = resultTask != null;
    }

    if (mounted) {
      if (success && resultTask != null) {
        debugPrint("[TaskEditDialog._saveTask] Success! Result Task ID: ${resultTask.taskId}, Title: ${resultTask.title}, UpdatedAt: ${resultTask.updatedAt}");
        widget.onTaskSaved?.call(resultTask);
        Navigator.of(context).pop(resultTask);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Задача "$actionMessage" успешно!')),
        );
      } else {
        debugPrint("[TaskEditDialog._saveTask] Failed. Error: ${taskProvider.error}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(taskProvider.error ?? 'Не удалось сохранить задачу'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tagProvider = Provider.of<TagProvider>(context);
    final taskProvider = Provider.of<TaskProvider>(context, listen: true);
    final bool isMobile = ResponsiveUtil.isMobile(context);

    bool currentIsLoading = taskProvider.isProcessingTask;

    Widget formContent = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 24.0, vertical: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Название задачи *',
                      border: const OutlineInputBorder(),
                      hintText: 'Например, "Разработать новый модуль"',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 12 : 16),
                    ),
                    style: TextStyle(fontSize: isMobile ? 15 : null),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Название не может быть пустым';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                  // Описание и тулбар
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Описание',
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                            // Убираем скругление снизу, если тулбар примыкает
                            bottomLeft: Radius.circular(0),
                            bottomRight: Radius.circular(0),
                          )
                      ),
                      alignLabelWithHint: true,
                      hintText: 'Детали задачи...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 10 : 12).copyWith(bottom: isMobile ? 8 : 10),
                    ),
                    style: TextStyle(fontSize: isMobile ? 14 : null, height: 1.4),
                    maxLines: isMobile ? 6 : 8, // Увеличил немного
                    minLines: isMobile ? 3 : 4,
                    keyboardType: TextInputType.multiline,
                  ),
                  _buildMarkdownToolbar(), // Тулбар теперь под полем
                  SizedBox(height: isMobile ? 16 : 20), // Увеличил отступ после тулбара

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<KanbanColumnStatus>(
                          decoration: InputDecoration(labelText: 'Статус', border: const OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isMobile ? 6 : 10)),
                          value: _selectedStatus,
                          style: TextStyle(fontSize: isMobile ? 14 : null, color: colorScheme.onSurface),
                          isDense: isMobile,
                          items: KanbanColumnStatus.values.map((status) {
                            return DropdownMenuItem(value: status, child: Text(status.title, style: TextStyle(fontSize: isMobile ? 14 : null)));
                          }).toList(),
                          onChanged: currentIsLoading ? null : (value) {
                            if (value != null) setState(() => _selectedStatus = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<TaskPriority>(
                          decoration: InputDecoration(labelText: 'Приоритет', border: const OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isMobile ? 6 : 10)),
                          value: _selectedPriority,
                          style: TextStyle(fontSize: isMobile ? 14 : null, color: colorScheme.onSurface),
                          isDense: isMobile,
                          items: TaskPriority.values.map((priority) {
                            return DropdownMenuItem(
                              value: priority,
                              child: Row(
                                children: [
                                  Icon(priority.icon, size: 18,
                                    color: priority == TaskPriority.high ? colorScheme.error :
                                    priority == TaskPriority.medium ? Colors.orange.shade700 :
                                    Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(priority.name, style: TextStyle(fontSize: isMobile ? 14 : null)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: currentIsLoading ? null : (value) {
                            if (value != null) setState(() => _selectedPriority = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_selectedDeadline == null
                        ? 'Установить дедлайн'
                        : 'Дедлайн: ${DateFormat('dd MMMM yyyy, HH:mm', 'ru_RU').format(_selectedDeadline!)}',
                      style: TextStyle(fontSize: isMobile ? 14 : null),
                    ),
                    trailing: Icon(Icons.calendar_today_rounded, color: colorScheme.primary),
                    onTap: currentIsLoading ? null : () => _pickDeadline(context),
                    leading: _selectedDeadline != null
                        ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                      tooltip: "Убрать дедлайн",
                      onPressed: currentIsLoading ? null : () => setState(() => _selectedDeadline = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                        : SizedBox(width: isMobile ? 30 : 40),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: theme.dividerColor.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text('Личные теги:', style: theme.textTheme.titleSmall?.copyWith(fontSize: isMobile ? 14: null)),
                  const SizedBox(height: 8),
                  if (tagProvider.isLoadingUserTags && tagProvider.userTags.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
                  else if (tagProvider.userTags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('Нет доступных личных тегов. Создайте их в Настройках.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                    )
                  else
                    AbsorbPointer(
                      absorbing: currentIsLoading,
                      child: Opacity(
                        opacity: currentIsLoading ? 0.5 : 1.0,
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: tagProvider.userTags.map((tag) {
                            final isSelected = _selectedUserTags.any((selected) => selected.id == tag.id);
                            return FilterChip(
                              label: Text(tag.name, style: TextStyle(
                                  fontSize: isMobile ? 12 : null,
                                  color: isSelected ? (tag.displayColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                                      : tag.textColorPreview
                              )),
                              selected: isSelected,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    if (!_selectedUserTags.any((t) => t.id == tag.id)) {
                                      _selectedUserTags.add(tag);
                                    }
                                  } else {
                                    _selectedUserTags.removeWhere((t) => t.id == tag.id);
                                  }
                                });
                              },
                              backgroundColor: tag.backgroundColorPreview.withOpacity(0.7),
                              selectedColor: tag.displayColor,
                              checkmarkColor: tag.displayColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                              shape: StadiumBorder(side: BorderSide(color: tag.borderColorPreview.withOpacity(isSelected ? 1 : 0.5))),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: isMobile ? 4 : 6),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.taskToEdit == null ? 'Новая задача' : 'Редактировать задачу', style: const TextStyle(fontSize: 18)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: currentIsLoading ? null : () => Navigator.of(context).pop(null),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                onPressed: currentIsLoading ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: currentIsLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.taskToEdit == null ? 'Создать' : 'Сохранить'),
              ),
            ),
          ],
        ),
        body: formContent,
      );
    }

    double dialogMaxWidth = 600;
    double currentDialogWidth = MediaQuery.of(context).size.width * 0.9 < dialogMaxWidth
        ? MediaQuery.of(context).size.width * 0.9
        : dialogMaxWidth;

    return AlertDialog(
      title: Text(widget.taskToEdit == null ? 'Новая задача' : 'Редактировать задачу'),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      contentPadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SizedBox(
        width: currentDialogWidth,
        height: MediaQuery.of(context).size.height * 0.8, // Увеличил немного высоту
        child: formContent,
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Отмена'),
          onPressed: currentIsLoading ? null : () => Navigator.of(context).pop(null),
        ),
        ElevatedButton.icon(
          icon: currentIsLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(widget.taskToEdit == null ? Icons.add_task_outlined : Icons.save_alt_outlined, size: 20),
          label: Text(widget.taskToEdit == null ? 'Создать задачу' : 'Сохранить'),
          onPressed: currentIsLoading ? null : _saveTask,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }
}