// lib/widgets/team/generate_invite_link_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/team_model.dart';
import '../../team_provider.dart';

class GenerateInviteLinkDialog extends StatefulWidget {
  final String teamId;
  final Function(TeamInviteTokenResponse inviteResponse) onInviteGenerated;

  const GenerateInviteLinkDialog({
    Key? key,
    required this.teamId,
    required this.onInviteGenerated,
  }) : super(key: key);

  @override
  _GenerateInviteLinkDialogState createState() => _GenerateInviteLinkDialogState();
}

class _GenerateInviteLinkDialogState extends State<GenerateInviteLinkDialog> {
  int? _selectedExpirationHours; // null означает "по умолчанию"
  TeamMemberRole _selectedRole = TeamMemberRole.member; // По умолчанию "member"

  final Map<int?, String> _expirationOptions = {
    null: 'По умолчанию (от сервера)',
    1: '1 час',
    24: '24 часа (1 день)',
    168: '7 дней',
    720: '30 дней',
  };

  final Map<TeamMemberRole, String> _roleOptions = {
    TeamMemberRole.member: 'Участник (может просматривать и выполнять задачи)',
    TeamMemberRole.editor: 'Редактор (может управлять задачами и тегами)',
  };

  Future<void> _generateLink() async {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    String? roleToAssignString = _selectedRole.toJson();
    if (_selectedRole == TeamMemberRole.owner || _selectedRole == TeamMemberRole.admin) {
      roleToAssignString = TeamMemberRole.member.toJson();
      debugPrint("GenerateInviteLinkDialog: Requested role ${_selectedRole.toJson()} is not assignable via token, defaulting to 'member'.");
    }

    debugPrint("[GenerateInviteLinkDialog._generateLink] Calling teamProvider.generateTeamInviteToken for teamId: ${widget.teamId}"); // <<< DEBUG PRINT
    final inviteResponse = await teamProvider.generateTeamInviteToken(
      widget.teamId,
      expiresInHours: _selectedExpirationHours,
      roleToAssign: roleToAssignString,
    );
    debugPrint("[GenerateInviteLinkDialog._generateLink] teamProvider.generateTeamInviteToken returned: ${inviteResponse?.inviteToken}"); // <<< DEBUG PRINT

    if (mounted && inviteResponse != null) {
      debugPrint("[GenerateInviteLinkDialog._generateLink] Invite generated successfully. Calling widget.onInviteGenerated. Dialog context is mounted: $mounted"); // <<< DEBUG PRINT
      widget.onInviteGenerated(inviteResponse);
      debugPrint("[GenerateInviteLinkDialog._generateLink] After widget.onInviteGenerated. Popping dialog. Dialog context is mounted: $mounted"); // <<< DEBUG PRINT
      if (mounted) { // Дополнительная проверка перед pop
        Navigator.of(context).pop();
      }
    } else if (mounted && teamProvider.error != null) {
      debugPrint("[GenerateInviteLinkDialog._generateLink] Error generating invite: ${teamProvider.error}. Dialog context is mounted: $mounted"); // <<< DEBUG PRINT
      if (mounted) { // Дополнительная проверка перед SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка генерации ссылки: ${teamProvider.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      teamProvider.clearError();
    } else {
      debugPrint("[GenerateInviteLinkDialog._generateLink] Invite generation failed or dialog not mounted. Mounted: $mounted, inviteResponse: ${inviteResponse?.inviteToken}, error: ${teamProvider.error}"); // <<< DEBUG PRINT
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = Provider.of<TeamProvider>(context, listen: true);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Параметры ссылки-приглашения'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Срок действия ссылки:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _selectedExpirationHours,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _expirationOptions.entries.map((entry) {
                return DropdownMenuItem<int?>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedExpirationHours = value;
                });
              },
            ),
            const SizedBox(height: 20),
            Text('Роль нового участника:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<TeamMemberRole>(
              value: _selectedRole,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              isExpanded: true,
              items: _roleOptions.entries.map((entry) {
                return DropdownMenuItem<TeamMemberRole>(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRole = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Отмена'),
          onPressed: teamProvider.isProcessingTeamAction ? null : () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          onPressed: teamProvider.isProcessingTeamAction ? null : _generateLink,
          child: teamProvider.isProcessingTeamAction
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Создать'),
        ),
      ],
    );
  }
}