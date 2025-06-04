// lib/widgets/team/create_team_dialog_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/team_model.dart';
import '../../team_provider.dart';
import '../CustomInputField.dart'; // Убедитесь, что путь правильный

class CreateTeamDialogWidget extends StatefulWidget {
  const CreateTeamDialogWidget({Key? key}) : super(key: key);

  @override
  State<CreateTeamDialogWidget> createState() => _CreateTeamDialogWidgetState();
}

class _CreateTeamDialogWidgetState extends State<CreateTeamDialogWidget> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = Colors.primaries[DateTime.now().millisecond % Colors.primaries.length].shade400;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
              onColorChanged: (Color color) {
                tempPickedColor = color;
              },
              availableColors: Colors.primaries.map((e) => e.shade400).toList()
                ..addAll(Colors.accents.map((e) => e.shade200).toList())
                ..addAll([Colors.grey.shade500, Colors.brown.shade400, Colors.black]),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(alertContext).pop(null),
            ),
            TextButton(
              child: const Text('Выбрать'),
              onPressed: () => Navigator.of(alertContext).pop(tempPickedColor),
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
    final teamProvider = Provider.of<TeamProvider>(context, listen: false); // listen: false для вызова методов
    // Используем Consumer для isProcessingTeamAction, чтобы кнопка обновлялась
    final bool isProcessing = context.watch<TeamProvider>().isProcessingTeamAction;


    return AlertDialog(
      title: const Text("Создать новую команду"),
      contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CustomInputField(
                label: "Название команды (макс. 30)",
                controller: _nameController,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Название команды не может быть пустым';
                  }
                  if (value.trim().length < 3) return 'Минимум 3 символа';
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: "Описание (макс. 100, опционально)",
                controller: _descriptionController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
              ),
              const SizedBox(height: 20),
              Text("Цвет команды:", style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
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
          onPressed: isProcessing ? null : () async {
            if (_formKey.currentState!.validate()) {
              final request = CreateTeamRequest(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
                colorHex: '#${_selectedColor.value.toRadixString(16).padLeft(8,'f').substring(2)}',
              );
              final newTeam = await teamProvider.createTeam(request); // Вызываем метод из провайдера
              if (mounted) { // Проверяем mounted перед использованием context
                Navigator.of(context).pop(); // Закрываем диалог
                if (newTeam != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Команда "${newTeam.name}" создана!')),
                  );
                } else if (teamProvider.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка создания команды: ${teamProvider.error}'), backgroundColor: Colors.red),
                  );
                }
              }
            }
          },
          child: isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Создать'),
        ),
      ],
    );
  }
}