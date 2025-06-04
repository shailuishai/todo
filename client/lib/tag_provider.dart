// lib/tag_provider.dart
import 'package:flutter/material.dart';
import 'dart:collection';
import 'models/task_model.dart';
import 'services/api_service.dart';
import 'auth_state.dart';

class TagProvider with ChangeNotifier {
  final ApiService _apiService;
  final AuthState _authState;

  List<ApiTag> _userTags = [];
  Map<int, List<ApiTag>> _teamTagsByTeamId = {};

  bool _isLoadingUserTags = false;
  bool _isLoadingTeamTags = false;
  String? _error;
  bool _isProcessingTag = false;

  TagProvider(this._apiService, this._authState) {
    _authState.addListener(_onAuthStateChanged);
    if (_authState.isLoggedIn) {
      fetchUserTags();
    }
  }

  void _onAuthStateChanged() {
    if (_authState.isLoggedIn) {
      fetchUserTags();
      _teamTagsByTeamId.clear();
    } else {
      _userTags = [];
      _teamTagsByTeamId.clear();
      _error = null;
      _isLoadingUserTags = false;
      _isLoadingTeamTags = false;
      _isProcessingTag = false;
      notifyListeners();
    }
  }

  List<ApiTag> get userTags => UnmodifiableListView(_userTags);
  Map<int, List<ApiTag>> get teamTagsByTeamId => UnmodifiableMapView(_teamTagsByTeamId);
  bool get isLoadingUserTags => _isLoadingUserTags;
  bool get isLoadingTeamTags => _isLoadingTeamTags;
  bool get isProcessingTag => _isProcessingTag;
  String? get error => _error;

  Future<void> fetchUserTags() async {
    if (!_authState.isLoggedIn) return;
    _isLoadingUserTags = true;
    _error = null;
    notifyListeners();
    try {
      _userTags = await _apiService.getUserTags();
      _userTags.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } on ApiException catch (e) {
      _error = "Ошибка загрузки пользовательских тегов: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка при загрузке тегов: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка при загрузке тегов: $e";
    }
    _isLoadingUserTags = false;
    notifyListeners();
  }

  Future<bool> createUserTag({required String name, String? colorHex}) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      final newTag = await _apiService.createUserTag(name: name, colorHex: colorHex);
      _userTags.add(newTag);
      _userTags.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка создания тега: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка при создании тега: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка при создании тега: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateUserTag(int tagId, {String? name, String? colorHex}) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      final updatedTag = await _apiService.updateUserTag(tagId, name: name, colorHex: colorHex);
      final index = _userTags.indexWhere((tag) => tag.id == tagId);
      if (index != -1) {
        _userTags[index] = updatedTag;
        _userTags.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка обновления тега: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка при обновлении тега: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка при обновлении тега: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteUserTag(int tagId) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      await _apiService.deleteUserTag(tagId);
      _userTags.removeWhere((tag) => tag.id == tagId);
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка удаления тега: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка при удалении тега: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка при удалении тега: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  Future<void> fetchTeamTags(int teamId, {bool forceRefresh = false}) async {
    if (!_authState.isLoggedIn) return;
    if (_teamTagsByTeamId.containsKey(teamId) && !forceRefresh && (_teamTagsByTeamId[teamId]?.isNotEmpty ?? false)) {
      debugPrint("[TagProvider.fetchTeamTags] Tags for team $teamId already loaded. Skipping.");
      return;
    }
    debugPrint("[TagProvider.fetchTeamTags] Fetching tags for team $teamId. Force refresh: $forceRefresh");
    _isLoadingTeamTags = true;
    _error = null;
    notifyListeners();
    try {
      final tags = await _apiService.getTeamTags(teamId);
      _teamTagsByTeamId[teamId] = tags;
      _teamTagsByTeamId[teamId]?.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint("[TagProvider.fetchTeamTags] Successfully fetched ${tags.length} tags for team $teamId.");
    } on ApiException catch (e) {
      _error = "Ошибка загрузки тегов команды $teamId: ${e.message}";
      debugPrint("[TagProvider.fetchTeamTags] ApiException for team $teamId: $_error");
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка при загрузке тегов команды $teamId: ${e.message}";
      debugPrint("[TagProvider.fetchTeamTags] NetworkException for team $teamId: $_error");
    } catch (e) {
      _error = "Неизвестная ошибка при загрузке тегов команды $teamId: $e";
      debugPrint("[TagProvider.fetchTeamTags] Unknown error for team $teamId: $e");
    }
    _isLoadingTeamTags = false;
    notifyListeners();
  }

  Future<bool> createTeamTag(int teamId, {required String name, String? colorHex}) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      final newTag = await _apiService.createTeamTag(teamId, name: name, colorHex: colorHex);
      // Убедимся, что список для teamId существует
      if (!_teamTagsByTeamId.containsKey(teamId)) {
        _teamTagsByTeamId[teamId] = [];
      }
      _teamTagsByTeamId[teamId]!.add(newTag);
      _teamTagsByTeamId[teamId]?.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка создания тега команды: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateTeamTag(int tagId, int teamId, {String? name, String? colorHex}) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      final updatedTag = await _apiService.updateTeamTag(teamId, tagId, name: name, colorHex: colorHex);
      if (_teamTagsByTeamId.containsKey(teamId)) {
        final index = _teamTagsByTeamId[teamId]!.indexWhere((tag) => tag.id == tagId);
        if (index != -1) {
          _teamTagsByTeamId[teamId]![index] = updatedTag;
          _teamTagsByTeamId[teamId]?.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        } else {
          // Если тега нет в локальном кеше, но он успешно обновлен на сервере,
          // можно его добавить или перезапросить все теги для команды.
          // Пока просто сообщим в лог.
          debugPrint("[TagProvider.updateTeamTag] Updated tag $tagId for team $teamId was not in local cache. Consider refreshing.");
        }
      }
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка обновления тега команды: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteTeamTag(int tagId, int teamId) async {
    if (!_authState.isLoggedIn) {
      _error = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }
    _isProcessingTag = true;
    _error = null;
    notifyListeners();
    try {
      await _apiService.deleteTeamTag(teamId, tagId);
      if (_teamTagsByTeamId.containsKey(teamId)) {
        _teamTagsByTeamId[teamId]!.removeWhere((tag) => tag.id == tagId);
      }
      _isProcessingTag = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = "Ошибка удаления тега команды: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка: $e";
    }
    _isProcessingTag = false;
    notifyListeners();
    return false;
  }

  ApiTag? getTagById(int id, {int? teamIdContext}) {
    try {
      return _userTags.firstWhere((tag) => tag.id == id && tag.type == 'user');
    } catch (e) { /* not found in user tags */ }

    if (teamIdContext != null && _teamTagsByTeamId.containsKey(teamIdContext)) {
      try {
        return _teamTagsByTeamId[teamIdContext]!.firstWhere((tag) => tag.id == id && tag.type == 'team');
      } catch (e) { /* not found in specific team tags */ }
    }
    return null;
  }

  List<ApiTag> getTagsForTaskContext({String? teamIdStr}) {
    List<ApiTag> availableTags = List.from(_userTags);
    if (teamIdStr != null) {
      final teamId = int.tryParse(teamIdStr);
      if (teamId != null && _teamTagsByTeamId.containsKey(teamId)) {
        availableTags.addAll(_teamTagsByTeamId[teamId]!);
      }
    }
    availableTags.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return availableTags;
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthStateChanged);
    super.dispose();
  }
}