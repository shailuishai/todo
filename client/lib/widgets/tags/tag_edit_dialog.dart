// lib/widgets/tags/tag_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../../models/task_model.dart';
import '../../tag_provider.dart';
import '../../theme_provider.dart';

class TagEditDialog extends StatefulWidget {
  final bool isTeamTag;
  final String? teamId;
  final ApiTag? tagToEdit;
  final Future<void> Function(String name, String colorHex, {int? tagId}) onSave; // ИЗМЕНЕНО

  const TagEditDialog({
    Key? key,
    required this.isTeamTag,
    this.teamId,
    this.tagToEdit,
    required this.onSave,
  })  : assert(isTeamTag ? teamId != null : true, 'teamId is required for team tags'),
        super(key: key);

  @override
  _TagEditDialogState createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late Color _selectedColor;

  final List<Color> _presetColors = [
    Colors.red.shade400, Colors.pink.shade300, Colors.purple.shade400, Colors.deepPurple.shade300,
    Colors.indigo.shade300, Colors.blue.shade400, Colors.lightBlue.shade300, Colors.cyan.shade400,
    Colors.teal.shade400, Colors.green.shade400, Colors.lightGreen.shade500, Colors.lime.shade600,
    Colors.yellow.shade700, Colors.amber.shade600, Colors.orange.shade600, Colors.deepOrange.shade500,
    Colors.brown.shade400, Colors.grey.shade500, Colors.blueGrey.shade400,
    const Color(0xFF5457FF), const Color(0xFFFF5454), const Color(0xFFE2FF54),
    const Color(0xFF7E57C2), const Color(0xFF26A69A), const Color(0xFFFF7043),
  ].toSet().toList();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tagToEdit?.name ?? '');
    _nameController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    if (widget.tagToEdit?.colorHex != null) {
      try {
        _selectedColor = Color(int.parse(widget.tagToEdit!.colorHex!.replaceFirst('#', '0xff')));
      } catch (e) {
        _selectedColor = _presetColors.first;
      }
    } else {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      _selectedColor = _presetColors.firstWhere(
              (c) => c.value != themeProvider.accentColor.value,
          orElse: () => _presetColors.isNotEmpty ? _presetColors.first : Colors.grey.shade600
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showColorPickerDialog() {
    Color pickerColor = _selectedColor;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Выберите цвет тега'),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
          content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text("Быстрый выбор:", style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Wrap(
                      spacing: 10.0,
                      runSpacing: 10.0,
                      alignment: WrapAlignment.center,
                      children: _presetColors.map((color) {
                        bool isCurrentlySelectedInPicker = color.value == pickerColor.value;
                        return GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _selectedColor = color;
                              });
                            }
                            Navigator.of(dialogContext).pop();
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(isCurrentlySelectedInPicker ? 1 : 0.6),
                                width: isCurrentlySelectedInPicker ? 3 : 1.5,
                              ),
                              boxShadow: isCurrentlySelectedInPicker ? [
                                BoxShadow(color: color.withOpacity(0.5), blurRadius: 3, spreadRadius: 1)
                              ] : [],
                            ),
                            child: _selectedColor.value == color.value
                                ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(height: 32, thickness: 0.8, indent: 20, endIndent: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text("Расширенный выбор:", style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 12),
                  ColorPicker(
                    pickerColor: pickerColor,
                    onColorChanged: (color) {
                      pickerColor = color;
                    },
                    colorPickerWidth: 280.0,
                    pickerAreaHeightPercent: 0.7,
                    enableAlpha: false,
                    displayThumbColor: true,
                    paletteType: PaletteType.hsl,
                    labelTypes: const [],
                    hexInputBar: true,
                    pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                ],
              )
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Выбрать'),
              onPressed: () {
                if (mounted) {
                  setState(() {
                    _selectedColor = pickerColor;
                  });
                }
                Navigator.of(dialogContext).pop();
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
    final tagProvider = Provider.of<TagProvider>(context, listen: false);

    return AlertDialog(
      title: Text(widget.tagToEdit == null
          ? (widget.isTeamTag ? 'Новый тег команды' : 'Новый личный тег')
          : 'Редактировать тег'
      ),
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
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Название тега *',
                  border: OutlineInputBorder(),
                  hintText: 'Например, "Важно" или "Проект X"',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Название не может быть пустым';
                  }
                  List<ApiTag> existingTags;
                  if (widget.isTeamTag && widget.teamId != null) {
                    final teamIdInt = int.tryParse(widget.teamId!);
                    existingTags = teamIdInt != null ? (tagProvider.teamTagsByTeamId[teamIdInt] ?? []) : [];
                  } else {
                    existingTags = tagProvider.userTags;
                  }
                  if (existingTags.any((t) =>
                  t.name.trim().toLowerCase() == value.trim().toLowerCase() &&
                      t.id != widget.tagToEdit?.id)) {
                    return 'Тег с таким именем уже существует';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text('Цвет тега:', style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _showColorPickerDialog,
                child: AbsorbPointer(
                  child: Chip(
                    label: Text(
                      _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Предпросмотр',
                      style: TextStyle(
                        color: _selectedColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: _selectedColor.withOpacity(0.15),
                    side: BorderSide(color: _selectedColor.withOpacity(0.5), width: 1.0),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.colorize_outlined, color: _selectedColor, size: 18),
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
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              final colorHex = '#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
              await widget.onSave(
                  _nameController.text.trim(),
                  colorHex,
                  tagId: widget.tagToEdit?.id
              );
              if (mounted) {
                Navigator.of(context).pop();
              }
            }
          },
        ),
      ],
    );
  }
}