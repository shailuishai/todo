// lib/widgets/team/change_member_role_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/team_model.dart';
import '../../team_provider.dart';

class ChangeMemberRoleDialog extends StatefulWidget {
  final String teamId;
  final TeamMember memberToUpdate;
  final Function(TeamMemberRole newRole) onRoleChanged;

  const ChangeMemberRoleDialog({
    Key? key,
    required this.teamId,
    required this.memberToUpdate,
    required this.onRoleChanged,
  }) : super(key: key);

  @override
  _ChangeMemberRoleDialogState createState() => _ChangeMemberRoleDialogState();
}

class _ChangeMemberRoleDialogState extends State<ChangeMemberRoleDialog> {
  late TeamMemberRole _selectedRole;

  // Доступные роли для назначения (владельца нельзя назначить через этот диалог)
  final List<TeamMemberRole> _assignableRoles = [
    TeamMemberRole.admin,
    TeamMemberRole.editor,
    TeamMemberRole.member,
  ];

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.memberToUpdate.role;
  }

  void _submitChange() {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    if (teamProvider.isProcessingTeamAction) return;

    widget.onRoleChanged(_selectedRole);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = Provider.of<TeamProvider>(context); // Слушаем isProcessingTeamAction
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Изменить роль ${widget.memberToUpdate.user.login}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _assignableRoles.map((role) {
          return RadioListTile<TeamMemberRole>(
            title: Text(role.localizedName),
            value: role,
            groupValue: _selectedRole,
            onChanged: teamProvider.isProcessingTeamAction || widget.memberToUpdate.role == TeamMemberRole.owner
                ? null // Нельзя менять роль владельца или если идет операция
                : (TeamMemberRole? value) {
              if (value != null) {
                setState(() {
                  _selectedRole = value;
                });
              }
            },
            activeColor: theme.colorScheme.primary,
          );
        }).toList(),
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
          // Блокируем кнопку, если роль не изменилась, идет операция, или это владелец
          onPressed: teamProvider.isProcessingTeamAction || _selectedRole == widget.memberToUpdate.role || widget.memberToUpdate.role == TeamMemberRole.owner
              ? null
              : _submitChange,
          child: teamProvider.isProcessingTeamAction
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}