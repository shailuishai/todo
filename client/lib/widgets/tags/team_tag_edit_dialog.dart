// lib/widgets/tags/team_tag_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Используем этот пакет
import '../../models/task_model.dart'; // Для ApiTag

class TeamTagEditDialog extends StatefulWidget {
  final String teamId;
  final ApiTag? tagToEdit;
  final Function(String name, String colorHex) onSave; // Возвращает имя и цвет

  const TeamTagEditDialog({
    Key? key,
    required this.teamId,
    this.tagToEdit,
    required this.onSave,
  }) : super(key: key);

  @override
  _TeamTagEditDialogState createState() => _TeamTagEditDialogState();
}

class _TeamTagEditDialogState extends State<TeamTagEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late Color _selectedColor;

  // Предустановленные цвета для быстрого выбора + возможность выбрать любой
  final List<Color> _presetColors = [
    Colors.red.shade400, Colors.pink.shade300, Colors.purple.shade400, Colors.deepPurple.shade300,
    Colors.indigo.shade300, Colors.blue.shade400, Colors.lightBlue.shade300, Colors.cyan.shade400,
    Colors.teal.shade400, Colors.green.shade400, Colors.lightGreen.shade500, Colors.lime.shade600,
    Colors.yellow.shade700, Colors.amber.shade600, Colors.orange.shade600, Colors.deepOrange.shade500,
    Colors.brown.shade400, Colors.grey.shade500, Colors.blueGrey.shade400,
    const Color(0xFF5457FF), // Ультрамарин
    const Color(0xFFFF5454), // Коралл
    const Color(0xFFE2FF54), // Лайм
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tagToEdit?.name ?? '');
    if (widget.tagToEdit != null && widget.tagToEdit!.colorHex != null) {
      try {
        _selectedColor = Color(int.parse(widget.tagToEdit!.colorHex!.replaceFirst('#', '0xff')));
      } catch (e) {
        _selectedColor = _presetColors.first;
      }
    } else {
      _selectedColor = _presetColors.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showColorPicker() {
    Color pickerColor = _selectedColor;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Выберите цвет тега'),
          content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Быстрый выбор:", style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _presetColors.map((color) {
                      bool isSelected = color.value == _selectedColor.value;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColor = color;
                          });
                          Navigator.of(context).pop(); // Закрываем этот диалог быстрого выбора
                          // Если нужно, чтобы основной диалог оставался открытым, этот pop не нужен
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(isSelected ? 1 : 0.5),
                              width: isSelected ? 2.5 : 1.5,
                            ),
                          ),
                          child: isSelected ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 20) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),
                  Text("Расширенный выбор:", style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ColorPicker( // MaterialPicker или BlockPicker тоже можно
                    pickerColor: pickerColor,
                    onColorChanged: (color) => pickerColor = color,
                    colorPickerWidth: 300.0,
                    pickerAreaHeightPercent: 0.7,
                    enableAlpha: false, // Обычно для тегов альфа не нужна
                    displayThumbColor: true,
                    paletteType: PaletteType.hsl,
                    // pickerActionButtonsAlign: MainAxisAlignment.end,
                    // labelTypes: const [ColorLabelType.hex], // Можно показывать HEX
                    // hexInputBar: true, // Позволяет вводить HEX
                  ),
                ],
              )
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Выбрать'),
              onPressed: () {
                setState(() {
                  _selectedColor = pickerColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(widget.tagToEdit == null ? 'Новый тег команды' : 'Редактировать тег'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название тега *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Название не может быть пустым';
                  }
                  // TODO: Добавить проверку на уникальность имени тега в команде (через TagProvider)
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text('Цвет тега:', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showColorPicker,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: _selectedColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _selectedColor.computeLuminance() > 0.8
                                    ? Colors.black.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.3),
                                width: 1.5
                            )
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _nameController.text.isNotEmpty ? _nameController.text : 'Предпросмотр',
                          style: TextStyle(
                            color: _selectedColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Preview chip
                        // Chip(
                        //   label: Text(_nameController.text.isNotEmpty ? _nameController.text : 'Предпросмотр'),
                        //   backgroundColor: _selectedColor,
                        //   labelStyle: TextStyle(color: _selectedColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white),
                        //   padding: EdgeInsets.symmetric(horizontal: 12),
                        // ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Icon(Icons.colorize_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Отмена'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: Text(widget.tagToEdit == null ? 'Создать' : 'Сохранить'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final colorHex = '#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
              widget.onSave(_nameController.text.trim(), colorHex);
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }
}