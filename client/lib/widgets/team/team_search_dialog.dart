// lib/widgets/team/team_search_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../team_provider.dart';
import '../CustomInputField.dart'; // Убедитесь, что путь корректен

class TeamSearchDialog extends StatefulWidget {
  const TeamSearchDialog({Key? key}) : super(key: key);

  @override
  _TeamSearchDialogState createState() => _TeamSearchDialogState();
}

class _TeamSearchDialogState extends State<TeamSearchDialog> {
  late TextEditingController _searchController;
  // _initialSearchQuery не нужен как поле состояния, так как мы берем его из провайдера при построении
  // и для логики активности кнопки "Сбросить" тоже лучше использовать актуальное значение из провайдера

  @override
  void initState() {
    super.initState();
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    _searchController = TextEditingController(text: teamProvider.currentSearchQuery ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch() {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final query = _searchController.text.trim();
    // Вызываем fetchMyTeams. Он сам обновит currentSearchQuery в случае успеха.
    teamProvider.fetchMyTeams(search: query.isNotEmpty ? query : null);
    Navigator.of(context).pop();
  }

  void _resetSearch() {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    _searchController.clear(); // Очищаем поле ввода
    teamProvider.clearTeamSearch(); // Этот метод вызовет fetchMyTeams(search: null)
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем изменения isLoadingMyTeams и currentSearchQuery для обновления состояния кнопок
    final teamProvider = Provider.of<TeamProvider>(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Поиск команд'),
      content: CustomInputField(
        controller: _searchController,
        label: 'Название команды',
        hintText: 'Введите название...',
        autofocus: true,
        textInputAction: TextInputAction.search,
        onFieldSubmitted: teamProvider.isLoadingMyTeams ? null : (_) => _performSearch(),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Сбросить'),
          onPressed: teamProvider.isLoadingMyTeams || (teamProvider.currentSearchQuery == null || teamProvider.currentSearchQuery!.isEmpty)
              ? null
              : _resetSearch,
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          onPressed: teamProvider.isLoadingMyTeams ? null : _performSearch,
          child: teamProvider.isLoadingMyTeams
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Найти'),
        ),
      ],
    );
  }
}