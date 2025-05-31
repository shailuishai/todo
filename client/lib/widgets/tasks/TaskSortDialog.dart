// lib/widgets/tasks/task_sort_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../task_provider.dart';
import '../../core/utils/responsive_utils.dart'; // Если еще не импортирован

class TaskSortDialog extends StatefulWidget {
  const TaskSortDialog({Key? key}) : super(key: key);

  @override
  State<TaskSortDialog> createState() => _TaskSortDialogState();
}

class _TaskSortDialogState extends State<TaskSortDialog> {
  String? _currentSortByField;
  String? _currentSortOrder; // "ASC" или "DESC"

  // Поля, доступные для сортировки (ключ - значение для API, значение - отображаемое имя)
  // Соответствуют TaskSortableField на бэкенде
  final Map<String, String> _sortableFields = {
    'updated_at': 'Дата обновления',
    'created_at': 'Дата создания',
    'deadline': 'Дедлайн',
    'priority': 'Приоритет',
    'status': 'Статус', // Оставляем, т.к. API поддерживает
    'title': 'Название',
  };

  @override
  void initState() {
    super.initState();
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    _currentSortByField = taskProvider.localSortByField;
    _currentSortOrder = taskProvider.localSortOrder;

    // Если поле выбрано, а направление нет, ставим DESC по умолчанию (кроме title и status)
    if (_currentSortByField != null && _currentSortOrder == null) {
      if (_currentSortByField == 'title' || _currentSortByField == 'status') {
        _currentSortOrder = 'ASC';
      } else {
        _currentSortOrder = 'DESC';
      }
    }
  }

  void _applySorting() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    if (_currentSortByField != null && _currentSortOrder != null) {
      taskProvider.applySorting(_currentSortByField!, _currentSortOrder!);
    } else {
      // Если поле не выбрано, или направление не выбрано (хотя мы ставим по умолчанию)
      // то сбрасываем сортировку, чтобы вернуться к дефолтной из провайдера
      taskProvider.clearSorting();
    }
    Navigator.of(context).pop();
  }

  void _clearSorting() {
    setState(() {
      _currentSortByField = null;
      _currentSortOrder = null;
    });
    // Немедленно применяем сброс в провайдере, если пользователь нажал "Сбросить"
    // Provider.of<TaskProvider>(context, listen: false).clearSorting();
    // Оставим сброс только при нажатии "Применить", если пользователь выбрал "По умолчанию"
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtil.isMobile(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Сортировка задач'),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 24),
      content: SingleChildScrollView(
        child: SizedBox(
          width: isMobile ? MediaQuery.of(context).size.width * 0.8 : 380, // Немного увеличим ширину
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String?>(
                value: _currentSortByField,
                decoration: const InputDecoration(
                  labelText: 'Сортировать по полю',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14), // Уменьшил vertical padding
                ),
                hint: const Text('По умолчанию'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('По умолчанию (не сортировать)'),
                  ),
                  ..._sortableFields.entries.map((entry) {
                    return DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _currentSortByField = value;
                    if (value != null) {
                      // Устанавливаем направление по умолчанию при смене поля, если его не было
                      _currentSortOrder ??= (value == 'title' || value == 'status') ? 'ASC' : 'DESC';
                    } else {
                      _currentSortOrder = null; // Сбрасываем направление, если поле не выбрано
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_currentSortByField != null) // Показываем направление только если выбрано поле
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text("Направление:", style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    Center(
                      child: ToggleButtons(
                        isSelected: [ _currentSortOrder == 'ASC',_currentSortOrder == 'DESC',],
                        onPressed: (int index) {
                          setState(() {
                            _currentSortOrder = index == 0 ? 'ASC' : 'DESC';
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        constraints: BoxConstraints(
                          minHeight: 40.0,
                          // Делаем кнопки адаптивными по ширине, чтобы текст влезал
                          minWidth: (isMobile ? (MediaQuery.of(context).size.width * 0.8) - 44 : 380 - 44) / 2.1, // -44 для паддингов диалога, /2.1 для небольшого зазора
                        ),
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0), // Уменьшил горизонтальный паддинг
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.arrow_upward_rounded, size: 18),
                              const SizedBox(width: 4),
                              Text('По возр.', style: TextStyle(fontSize: isMobile ? 12 : 13)) // Уменьшил текст
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.arrow_downward_rounded, size: 18),
                              const SizedBox(width: 4),
                              Text('По убыв.', style: TextStyle(fontSize: isMobile ? 12 : 13))
                            ]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Сбросить'),
          onPressed: () {
            // Сбрасываем локальное состояние диалога и затем применяем сброс в провайдере
            setState(() {
              _currentSortByField = null;
              _currentSortOrder = null;
            });
            Provider.of<TaskProvider>(context, listen: false).clearSorting();
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('Применить'),
          onPressed: _applySorting,
        ),
      ],
    );
  }
}