// lib/sidebar_state_provider.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Переименовываем settings на management
enum TeamDetailSection { tasks, chat, members, teamTags, management } // <<< ИЗМЕНЕНО

class SidebarStateProvider with ChangeNotifier {
  bool _isCollapsed = false;
  static const String _sidebarCollapsedKey = 'sidebar_collapsed_state_v1';

  SidebarStateProvider() {
    _loadState();
  }

  bool get isCollapsed => _isCollapsed;

  TeamDetailSection _currentTeamDetailSection = TeamDetailSection.tasks;
  TeamDetailSection get currentTeamDetailSection => _currentTeamDetailSection;

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _isCollapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;
    // notifyListeners(); // Не нужно здесь, если нет немедленного UI ответа
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidebarCollapsedKey, _isCollapsed);
  }

  void toggleCollapse() {
    _isCollapsed = !_isCollapsed;
    _saveState();
    notifyListeners();
  }

  void setCollapsedState(bool collapsed) {
    if (_isCollapsed != collapsed) {
      _isCollapsed = collapsed;
      _saveState();
      notifyListeners();
    }
  }

  void setCurrentTeamDetailSection(TeamDetailSection section) {
    if (_currentTeamDetailSection != section) {
      _currentTeamDetailSection = section;
      notifyListeners();
      debugPrint("SidebarStateProvider: currentTeamDetailSection set to $section");
    }
  }
}