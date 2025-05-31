// lib/widgets/team/edit_team_info_dialog.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/team_model.dart';
import '../../team_provider.dart';
import '../CustomInputField.dart';
import '../PrimaryButton.dart';
import '../common/user_avatar.dart'; // Для отображения текущего аватара команды (адаптируем)

class EditTeamInfoDialog extends StatefulWidget {
  final TeamDetail teamToEdit;

  const EditTeamInfoDialog({
    Key? key,
    required this.teamToEdit,
  }) : super(key: key);

  @override
  _EditTeamInfoDialogState createState() => _EditTeamInfoDialogState();
}

class _EditTeamInfoDialogState extends State<EditTeamInfoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late Color _selectedColor;

  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  bool _resetImageFlag = false; // Флаг для явного сброса изображения

  String? _currentImageUrlOnLoad; // Чтобы отслеживать, было ли изображение изначально

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teamToEdit.name);
    _descriptionController = TextEditingController(text: widget.teamToEdit.description ?? '');
    _selectedColor = widget.teamToEdit.displayColor;
    _currentImageUrlOnLoad = widget.teamToEdit.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024, maxHeight: 1024);
      if (image != null) {
        final bytes = await image.readAsBytes();
        // TODO: Добавить проверку размера файла из конфигурации (например, teamProvider.s3Config.maxTeamImageSizeBytes)
        // final maxSize = Provider.of<TeamProvider>(context, listen: false).s3Cfg.MaxTeamImageSizeBytes ?? 2 * 1024 * 1024;
        const maxSize = 2 * 1024 * 1024; // Пока хардкод 2MB
        if (bytes.lengthInBytes > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Файл слишком большой. Максимум ${maxSize / (1024 * 1024)}MB.'), backgroundColor: Colors.red),
            );
          }
          return;
        }
        setState(() {
          _pickedImageFile = image;
          _pickedImageBytes = bytes;
          _resetImageFlag = false; // Если выбрали новое, сброс не нужен
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _triggerResetImage() {
    setState(() {
      _pickedImageFile = null;
      _pickedImageBytes = null;
      _resetImageFlag = true;
    });
  }

  Future<Color?> _showColorPickerDialog(BuildContext context, Color initialColor) {
    Color tempPickedColor = initialColor;
    return showDialog<Color>(
      context: context,
      builder: (BuildContext alertContext) {
        return AlertDialog(
          title: const Text('Выберите цвет команды'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: initialColor,
              onColorChanged: (Color color) => tempPickedColor = color,
              availableColors: Colors.primaries.map((e) => e.shade400).toList()
                ..addAll(Colors.accents.map((e) => e.shade200).toList())
                ..addAll([Colors.grey.shade500, Colors.brown.shade400, Colors.black]),
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('Отмена'), onPressed: () => Navigator.of(alertContext).pop(null)),
            TextButton(child: const Text('Выбрать'), onPressed: () => Navigator.of(alertContext).pop(tempPickedColor)),
          ],
        );
      },
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    Map<String, dynamic>? imageFileMap;
    if (_pickedImageFile != null && _pickedImageBytes != null) {
      imageFileMap = {'bytes': _pickedImageBytes!, 'filename': _pickedImageFile!.name};
    }

    final newName = _nameController.text.trim();
    final newDescription = _descriptionController.text.trim();
    final newColorHex = '#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';

    bool nameChanged = newName != widget.teamToEdit.name;
    bool descriptionChanged = newDescription != (widget.teamToEdit.description ?? '');
    // Сравниваем HEX строки, приводя к одному формату (без # и в нижнем регистре)
    bool colorChanged = newColorHex.toLowerCase() != (widget.teamToEdit.colorHex?.toLowerCase() ?? '');
    bool imageChanged = _pickedImageFile != null || _resetImageFlag;


    if (!nameChanged && !descriptionChanged && !colorChanged && !imageChanged) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет изменений для сохранения.')),
        );
      }
      return;
    }

    final request = UpdateTeamDetailsRequest(
      name: nameChanged ? newName : null,
      description: descriptionChanged ? (newDescription.isNotEmpty ? newDescription : "") : null, // Передаем пустую строку для сброса
      colorHex: colorChanged ? newColorHex : null,
      resetImage: _resetImageFlag ? true : null, // Отправляем только если true
    );

    final updatedTeam = await teamProvider.updateTeam(
      widget.teamToEdit.teamId,
      request,
      imageFile: imageFileMap, // imageFileMap будет null, если изображение не выбрано
    );

    if (mounted) {
      Navigator.of(context).pop(); // Закрываем диалог
      if (updatedTeam != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Команда "${updatedTeam.name}" обновлена!')),
        );
      } else if (teamProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: ${teamProvider.error}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final teamProvider = context.watch<TeamProvider>(); // Для isProcessingTeamAction
    final isProcessing = teamProvider.isProcessingTeamAction;

    Widget currentTeamAvatar;
    if (_pickedImageBytes != null) {
      currentTeamAvatar = CircleAvatar(radius: 40, backgroundImage: MemoryImage(_pickedImageBytes!));
    } else if (_resetImageFlag || (_currentImageUrlOnLoad == null || _currentImageUrlOnLoad!.isEmpty)) {
      // Если сброс или изначально не было картинки, показываем инициалы с _selectedColor
      currentTeamAvatar = UserAvatar(
          login: _nameController.text.isNotEmpty ? _nameController.text : widget.teamToEdit.name, // Используем текущее имя из контроллера для инициалов
          accentColorHex: '#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}', // Используем текущий выбранный цвет
          radius: 40
      );
    } else { // Отображаем текущее изображение с сервера
      currentTeamAvatar = UserAvatar(
          login: widget.teamToEdit.name,
          avatarUrl: _currentImageUrlOnLoad,
          accentColorHex: widget.teamToEdit.colorHex, // Для случая ошибки загрузки NetworkImage
          radius: 40
      );
    }


    return AlertDialog(
      title: const Text("Редактировать команду"),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 0.0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Column(
                  children: [
                    currentTeamAvatar,
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.image_search_rounded, size: 18),
                          label: const Text("Выбрать", style: TextStyle(fontSize: 13)),
                          onPressed: isProcessing ? null : _pickImage,
                        ),
                        if ((_currentImageUrlOnLoad != null && _currentImageUrlOnLoad!.isNotEmpty) || _pickedImageFile != null)
                          TextButton.icon(
                            icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error, size: 18),
                            label: Text("Удалить", style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                            onPressed: isProcessing ? null : _triggerResetImage,
                          ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CustomInputField(
                label: "Название команды",
                controller: _nameController,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Название не может быть пустым';
                  if (value.trim().length < 3) return 'Минимум 3 символа';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: "Описание (опционально)",
                controller: _descriptionController,
                keyboardType: TextInputType.multiline,
                // maxLines: 3,
                // minLines: 1,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
              ),
              const SizedBox(height: 20),
              Text("Цвет команды:", style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              InkWell(
                onTap: isProcessing ? null : () async {
                  Color? pickedColor = await _showColorPickerDialog(context, _selectedColor);
                  if (pickedColor != null && mounted) {
                    setState(() { _selectedColor = pickedColor; });
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _selectedColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _selectedColor, width: 1.5)
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Выбрать цвет", style: TextStyle(color: _selectedColor, fontWeight: FontWeight.w500)),
                      Container(width: 24, height: 24, decoration: BoxDecoration(color: _selectedColor, shape: BoxShape.circle)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Отмена'),
          onPressed: isProcessing ? null : () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          onPressed: isProcessing ? null : _submitForm,
          child: isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}