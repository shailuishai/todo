// lib/team_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:collection';
import 'models/team_model.dart';
import 'services/api_service.dart';
import 'auth_state.dart';
// Импортируем новые виджеты диалогов
import '../widgets/team/create_team_dialog_widget.dart';
import '../widgets/team/join_team_dialog_widget.dart';

class TeamProvider with ChangeNotifier {
  final ApiService _apiService;
  final AuthState _authState;

  List<Team> _myTeams = [];
  TeamDetail? _currentTeamDetail;

  bool _isLoadingMyTeams = false;
  bool _isLoadingTeamDetail = false;
  bool _isProcessingTeamAction = false;
  String? _error;
  String? _currentSearchQuery;

  TeamProvider(this._apiService, this._authState) {
    debugPrint("[TeamProvider] Initialized. AuthState isLoggedIn: ${_authState.isLoggedIn}");
    _authState.addListener(_onAuthStateChanged);
    if (_authState.isLoggedIn) {
      fetchMyTeams();
    }
  }

  void _onAuthStateChanged() {
    debugPrint("[TeamProvider] AuthState changed. New isLoggedIn state: ${_authState.isLoggedIn}");
    if (_authState.isLoggedIn) {
      _currentSearchQuery = null;
      fetchMyTeams();
    } else {
      _myTeams = [];
      _currentTeamDetail = null;
      _error = null;
      _currentSearchQuery = null;
      _isLoadingMyTeams = false;
      _isLoadingTeamDetail = false;
      _isProcessingTeamAction = false;
      notifyListeners();
    }
  }

  // --- Getters ---
  List<Team> get myTeams => UnmodifiableListView(_myTeams);
  TeamDetail? get currentTeamDetail => _currentTeamDetail;
  bool get isLoadingMyTeams => _isLoadingMyTeams;
  bool get isLoadingTeamDetail => _isLoadingTeamDetail;
  bool get isProcessingTeamAction => _isProcessingTeamAction;
  String? get error => _error;
  String? get currentSearchQuery => _currentSearchQuery;

  // --- Методы ---
  Future<void> fetchMyTeams({String? search}) async {
    if (!_authState.isLoggedIn) {
      _myTeams = [];
      _currentSearchQuery = null;
      _isLoadingMyTeams = false;
      notifyListeners();
      return;
    }
    _isLoadingMyTeams = true;
    _error = null;
    notifyListeners();
    try {
      final fetchedTeams = await _apiService.getMyTeams(search: search);
      _myTeams = fetchedTeams;
      _myTeams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _currentSearchQuery = search;
      _error = null;
    } on ApiException catch (e) {
      _error = "Ошибка загрузки команд: ${e.message}";
    } on NetworkException catch (e) {
      _error = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _error = "Неизвестная ошибка при загрузке команд: $e";
    }
    _isLoadingMyTeams = false;
    notifyListeners();
  }

  void clearTeamSearch() {
    if (_currentSearchQuery != null || (_currentSearchQuery?.isNotEmpty ?? false) ) {
      fetchMyTeams(search: null);
    }
  }

  Future<Team?> createTeam(CreateTeamRequest request) async {
    if (!_authState.isLoggedIn) return _handleAuthErrorAndReturnNull();
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    Team? newTeam;
    try {
      newTeam = await _apiService.createTeam(request);
      _currentSearchQuery = null;
      await fetchMyTeams();
    } catch (e) { _handleGenericError(e, "создания команды"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return newTeam;
  }

  Future<void> fetchTeamDetails(String teamId, {bool forceRefresh = false}) async {
    if (!_authState.isLoggedIn) {
      _currentTeamDetail = null;
      _isLoadingTeamDetail = false;
      notifyListeners();
      return;
    }
    if (_currentTeamDetail?.teamId == teamId && !forceRefresh && _currentTeamDetail != null) return;

    _isLoadingTeamDetail = true;
    _error = null;
    if (_currentTeamDetail?.teamId != teamId) _currentTeamDetail = null;
    notifyListeners();
    try {
      _currentTeamDetail = await _apiService.getTeamDetails(teamId);
      _updateTeamInList(_currentTeamDetail);
    } catch (e) {
      _currentTeamDetail = null;
      _handleGenericError(e, "загрузки деталей команды $teamId");
    }
    _isLoadingTeamDetail = false;
    notifyListeners();
  }

  void _updateTeamInList(Team? team) {
    if (team == null) return;
    final index = _myTeams.indexWhere((t) => t.teamId == team.teamId);
    if (index != -1) {
      // Создаем новый экземпляр Team на основе TeamDetail, если нужно
      _myTeams[index] = team is TeamDetail
          ? Team(
          teamId: team.teamId, name: team.name, description: team.description,
          colorHex: team.colorHex, imageUrl: team.imageUrl, createdByUserId: team.createdByUserId,
          currentUserRole: team.currentUserRole, createdAt: team.createdAt, updatedAt: team.updatedAt,
          isDeleted: team.isDeleted, memberCount: team.members.length)
          : team;
      _myTeams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }


  Future<Team?> updateTeam(String teamId, UpdateTeamDetailsRequest details, {Map<String, dynamic>? imageFile}) async {
    if (!_authState.isLoggedIn) return _handleAuthErrorAndReturnNull();
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    Team? updatedTeam;
    try {
      updatedTeam = await _apiService.updateTeam(teamId, details, imageFile: imageFile);
      _updateTeamInList(updatedTeam);
      if (_currentTeamDetail?.teamId == teamId) {
        await fetchTeamDetails(teamId, forceRefresh: true);
      }
    } catch (e) { _handleGenericError(e, "обновления команды"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return updatedTeam;
  }

  Future<bool> deleteTeam(String teamId) async {
    if (!_authState.isLoggedIn) { _handleAuthError(); return false; }
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    bool success = false;
    try {
      await _apiService.deleteTeam(teamId);
      _myTeams.removeWhere((t) => t.teamId == teamId);
      if (_currentTeamDetail?.teamId == teamId) _currentTeamDetail = null;
      if (_myTeams.isEmpty && _currentSearchQuery != null) _currentSearchQuery = null;
      success = true;
    } catch (e) { _handleGenericError(e, "удаления команды"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return success;
  }

  Future<Team?> joinTeamByToken(String token) async {
    if (!_authState.isLoggedIn) return _handleAuthErrorAndReturnNull();
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    Team? joinedTeam;
    try {
      joinedTeam = await _apiService.joinTeamByToken(token);
      _currentSearchQuery = null;
      await fetchMyTeams();
    } catch (e) { _handleGenericError(e, "присоединения к команде"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return joinedTeam;
  }

  Future<bool> leaveTeam(String teamId) async {
    if (!_authState.isLoggedIn) { _handleAuthError(); return false; }
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    bool success = false;
    try {
      await _apiService.leaveTeam(teamId);
      _myTeams.removeWhere((t) => t.teamId == teamId);
      if (_currentTeamDetail?.teamId == teamId) _currentTeamDetail = null;
      if (_myTeams.isEmpty && _currentSearchQuery != null) _currentSearchQuery = null;
      success = true;
    } catch (e) { _handleGenericError(e, "выхода из команды"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return success;
  }

  Future<TeamInviteTokenResponse?> generateTeamInviteToken(String teamId, {int? expiresInHours, String? roleToAssign}) async {
    if (!_authState.isLoggedIn) return _handleAuthErrorAndReturnNull();
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    TeamInviteTokenResponse? inviteResponse;
    try {
      inviteResponse = await _apiService.generateInviteToken(teamId, expiresInHours: expiresInHours, roleToAssign: roleToAssign);
    } catch (e) { _handleGenericError(e, "генерации ссылки-приглашения"); }
    _isProcessingTeamAction = false;
    notifyListeners();
    return inviteResponse;
  }

  // <<< МЕТОД ДЛЯ ОБНОВЛЕНИЯ РОЛИ УЧАСТНИКА >>>
  Future<bool> updateTeamMemberRole(String teamId, int targetUserId, TeamMemberRole newRole) async {
    if (!_authState.isLoggedIn) { _handleAuthError(); return false; }
    if (_currentTeamDetail == null || _currentTeamDetail!.teamId != teamId) {
      _error = "Детали команды не загружены или ID не совпадает.";
      notifyListeners();
      return false;
    }
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    bool success = false;
    try {
      await _apiService.updateTeamMemberRole(teamId, targetUserId, newRole.toJson());
      // После успешного обновления перезагружаем детали команды, чтобы обновить список участников
      await fetchTeamDetails(teamId, forceRefresh: true);
      success = _error == null; // Если fetchTeamDetails не установил ошибку
    } catch (e) {
      _handleGenericError(e, "обновления роли участника");
    }
    _isProcessingTeamAction = false;
    notifyListeners();
    return success;
  }

  // <<< МЕТОД ДЛЯ УДАЛЕНИЯ УЧАСТНИКА ИЗ КОМАНДЫ >>>
  Future<bool> removeTeamMember(String teamId, int targetUserId) async {
    if (!_authState.isLoggedIn) { _handleAuthError(); return false; }
    if (_currentTeamDetail == null || _currentTeamDetail!.teamId != teamId) {
      _error = "Детали команды не загружены или ID не совпадает.";
      notifyListeners();
      return false;
    }
    _isProcessingTeamAction = true;
    _error = null;
    notifyListeners();
    bool success = false;
    try {
      await _apiService.removeTeamMember(teamId, targetUserId);
      // После успешного удаления перезагружаем детали команды
      await fetchTeamDetails(teamId, forceRefresh: true);
      success = _error == null;
    } catch (e) {
      _handleGenericError(e, "удаления участника из команды");
    }
    _isProcessingTeamAction = false;
    notifyListeners();
    return success;
  }


  Future<void> displayCreateTeamDialog(BuildContext context) async {
    if (!_authState.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Для создания команды необходимо авторизоваться.")),
      );
      return;
    }
    clearError();
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: this,
          child: const CreateTeamDialogWidget(),
        );
      },
    );
  }

  Future<void> displayJoinTeamDialog(BuildContext context) async {
    if (!_authState.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Для присоединения к команде необходимо авторизоваться.")),
      );
      return;
    }
    clearError();
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider.value(
          value: this,
          child: const JoinTeamDialogWidget(),
        );
      },
    );
  }

  void _handleAuthError() {
    _error = "Пользователь не авторизован.";
    notifyListeners();
  }

  T? _handleAuthErrorAndReturnNull<T>() {
    _handleAuthError();
    return null;
  }

  void _handleGenericError(Object e, String operation) {
    if (e is ApiException) {
      _error = "Ошибка $operation: ${e.message} (код: ${e.statusCode})";
    } else if (e is NetworkException) {
      _error = "Сетевая ошибка во время $operation: ${e.message}";
    } else {
      _error = "Неизвестная ошибка во время $operation: ${e.toString()}";
    }
    debugPrint("[TeamProvider] Error during $operation: $_error");
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