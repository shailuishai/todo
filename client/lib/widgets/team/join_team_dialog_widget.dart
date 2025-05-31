// lib/widgets/team/join_team_dialog_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../team_provider.dart';
import '../CustomInputField.dart'; // Убедитесь, что путь правильный

class JoinTeamDialogWidget extends StatefulWidget {
  const JoinTeamDialogWidget({Key? key}) : super(key: key);

  @override
  State<JoinTeamDialogWidget> createState() => _JoinTeamDialogWidgetState();
}

class _JoinTeamDialogWidgetState extends State<JoinTeamDialogWidget> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final bool isProcessing = context.watch<TeamProvider>().isProcessingTeamAction;

    return AlertDialog(
      title: const Text('Присоединиться к команде'),
      content: Form(
        key: _formKey,
        child: CustomInputField(
          controller: _tokenController,
          label: 'Код-приглашение',
          hintText: 'Введите код...',
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Код не может быть пустым';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: isProcessing
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: isProcessing
              ? null
              : () async {
            if (_formKey.currentState!.validate()) {
              final token = _tokenController.text.trim();
              final joinedTeam = await teamProvider.joinTeamByToken(token);
              if (mounted) {
                Navigator.of(context).pop(); // Закрываем диалог
                if (joinedTeam != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Вы присоединились к команде "${joinedTeam.name}"!')),
                  );
                } else if (teamProvider.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(teamProvider.error!), backgroundColor: Colors.red),
                  );
                }
              }
            }
          },
          child: isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Присоединиться'),
        ),
      ],
    );
  }
}