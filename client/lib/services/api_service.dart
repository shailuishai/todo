// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpException, Platform, SecurityContext, SocketException, X509Certificate; // Для Platform и SSL
import 'package:web_socket_channel/io.dart';

import '../models/chat_model.dart';
import '../models/task_model.dart';
import '../models/team_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'http_client_factory_io.dart'
if (dart.library.html) 'http_client_factory_web.dart' as httpClientFactory;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show Uint8List, debugPrint, kIsWeb, kDebugMode;

// --- UserProfile Model (без изменений) ---
class UserProfile {
  final int userId;
  final String login;
  final String email;
  final String? avatarUrl;
  final String? theme;
  final String? accentColor;
  final bool? isSidebarCollapsed;
  final bool? hasMobileDeviceLinked;
  final String emailNotificationsLevel;
  final String pushNotificationsTasksLevel;
  final bool pushNotificationsChatMentions;
  final bool taskDeadlineRemindersEnabled;
  final String taskDeadlineReminderTimePreference;

  UserProfile({
    required this.userId,
    required this.login,
    required this.email,
    this.avatarUrl,
    this.theme,
    this.accentColor,
    this.isSidebarCollapsed,
    this.hasMobileDeviceLinked,
    required this.emailNotificationsLevel,
    required this.pushNotificationsTasksLevel,
    required this.pushNotificationsChatMentions,
    required this.taskDeadlineRemindersEnabled,
    required this.taskDeadlineReminderTimePreference,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as int? ?? 0,
      login: json['login'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      theme: json['theme'] as String?,
      accentColor: json['accent_color'] as String?,
      isSidebarCollapsed: json['is_sidebar_collapsed'] as bool?,
      hasMobileDeviceLinked: json['has_mobile_device_linked'] as bool?,
      emailNotificationsLevel: json['email_notifications_level'] as String? ?? 'important',
      pushNotificationsTasksLevel: json['push_notifications_tasks_level'] as String? ?? 'my_tasks',
      pushNotificationsChatMentions: json['push_notifications_chat_mentions'] as bool? ?? true,
      taskDeadlineRemindersEnabled: json['task_deadline_reminders_enabled'] as bool? ?? true,
      taskDeadlineReminderTimePreference: json['task_deadline_reminder_time_preference'] as String? ?? 'one_day',
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'login': login,
    'email': email,
    'avatar_url': avatarUrl,
    'theme': theme,
    'accent_color': accentColor,
    'is_sidebar_collapsed': isSidebarCollapsed,
    'has_mobile_device_linked': hasMobileDeviceLinked,
    'email_notifications_level': emailNotificationsLevel,
    'push_notifications_tasks_level': pushNotificationsTasksLevel,
    'push_notifications_chat_mentions': pushNotificationsChatMentions,
    'task_deadline_reminders_enabled': taskDeadlineRemindersEnabled,
    'task_deadline_reminder_time_preference': taskDeadlineReminderTimePreference,
  };
}

class AuthResponse {
  final String accessToken;
  final String? refreshToken;

  AuthResponse({required this.accessToken, this.refreshToken});

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    return AuthResponse(
      accessToken: data?['access_token'] as String? ?? '',
      refreshToken: data?['refresh_token'] as String?,
    );
  }
}
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException: $statusCode, $message';
}
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}
class EmailNotConfirmedException implements Exception {
  final String message = 'Email не подтвержден. Пожалуйста, проверьте свою почту.';
  EmailNotConfirmedException();
  @override
  String toString() => message;
}
class TokenRefreshedException implements Exception {
  final String message = 'Access token was refreshed. Please retry the request.';
  TokenRefreshedException();
  @override
  String toString() => message;
}

class ApiService {
  static const String _prodBaseUrl = 'https://todo-vd2m.onrender.com';
  static final String _devBaseUrl = kIsWeb
      ? 'https://todo-vd2m.onrender.com'
      : (Platform.isAndroid ? 'https://todo-vd2m.onrender.com' : 'https://todo-vd2m.onrender.com');

  static final String _baseUrl = kDebugMode ? _devBaseUrl : _prodBaseUrl;

  final String _baseApiUrl = '$_baseUrl/v1';


  static const String _accessTokenKeyPrefs = 'auth_access_token_prefs_v1';
  static const String _refreshTokenKeySecure = 'app_refresh_token_secure_v1';

  String? _cachedAccessToken;
  bool _isRefreshingToken = false;
  Completer<void>? _refreshTokenCompleter;

  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  ApiService() : _httpClient = httpClientFactory.createHttpClient(){
    debugPrint("ApiService: Initialized with base URL: $_baseUrl");
    debugPrint("ApiService: Initialized with client type: ${_httpClient.runtimeType}");
  }

  Future<void> _loadAccessToken() async {
    if (_cachedAccessToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = prefs.getString(_accessTokenKeyPrefs);
  }

  Future<void> _saveAccessToken(String token) async {
    _cachedAccessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKeyPrefs, token);
  }

  Future<void> clearLocalAccessToken() async {
    _cachedAccessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKeyPrefs);
  }

  Future<Map<String, String>> _getHeaders({bool includeAuth = true, bool isMultipart = false}) async {
    await _loadAccessToken();
    final headers = {
      if (!isMultipart) 'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (includeAuth && _cachedAccessToken != null) {
      headers['Authorization'] = 'Bearer $_cachedAccessToken';
    }
    return headers;
  }

  Future<T> _handleResponse<T>(
      http.Response response,
      T Function(Map<String, dynamic> json) fromJson, {
        bool isList = false,
        bool isChatHistory = false,
        bool directData = false,
      }) async {
    final String responseBodyString = utf8.decode(response.bodyBytes);
    Map<String, dynamic> responseBody;

    if (response.statusCode == 204) {
      if (isList) return fromJson({'items': []});
      try {
        return fromJson({});
      } catch (e) {
        if (!isList) {
          throw ApiException(response.statusCode, "Получен пустой ответ (204) там, где ожидались данные объекта.");
        }
        return fromJson({'items': []});
      }
    }

    try {
      responseBody = json.decode(responseBodyString);
    } catch (e) {
      throw ApiException(response.statusCode, "Ошибка сервера: не удалось обработать ответ. Body: $responseBodyString");
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (directData) {
        if (responseBody is Map<String, dynamic>) {
          return fromJson(responseBody);
        } else {
          throw ApiException(response.statusCode, "Неверный формат ответа (directData, не Map): $responseBodyString");
        }
      } else if (responseBody.containsKey('data')) {
        final dataField = responseBody['data'];

        if (isChatHistory) {
          if (dataField is Map<String, dynamic> && dataField.containsKey('messages') && dataField['messages'] is List) {
            return fromJson({'items': dataField['messages'], 'has_more': dataField['has_more']});
          } else {
            throw ApiException(response.statusCode, "Неверный формат истории чата в 'data'.");
          }
        }

        if (isList) {
          if (dataField is List) {
            return fromJson({'items': dataField});
          } else {
            throw ApiException(response.statusCode, "Неверный формат ответа: ожидался список в 'data'.");
          }
        } else {
          if (dataField is Map<String, dynamic>) {
            return fromJson(dataField);
          } else {
            throw ApiException(response.statusCode, "Неверный формат поля 'data' в ответе (ожидался объект).");
          }
        }
      } else {
        throw ApiException(response.statusCode, "Отсутствует поле 'data' в успешном ответе.");
      }
    } else if (response.statusCode == 401) {
      final Map<String, String?>? newTokens = await _tryRefreshTokenInternal();
      if (newTokens != null && newTokens['access_token'] != null) {
        await _saveAccessToken(newTokens['access_token']!);
        if (!kIsWeb && newTokens['refresh_token'] != null && newTokens['refresh_token']!.isNotEmpty) {
          await _secureStorage.write(key: _refreshTokenKeySecure, value: newTokens['refresh_token']!);
        }
        throw TokenRefreshedException();
      }
      await clearLocalAccessToken();
      String errorMessage = responseBody['error'] as String? ?? 'Ошибка аутентификации. Пожалуйста, войдите снова.';
      throw ApiException(response.statusCode, errorMessage);
    } else {
      throw ApiException(response.statusCode, responseBody['error'] as String? ?? 'Неизвестная ошибка API');
    }
  }

  Future<Map<String, String?>?> _tryRefreshTokenInternal() async {
    if (_isRefreshingToken) {
      await _refreshTokenCompleter?.future;
      await _loadAccessToken();
      return _cachedAccessToken != null ? {'access_token': _cachedAccessToken, 'refresh_token': null} : null;
    }
    _isRefreshingToken = true;
    _refreshTokenCompleter = Completer<void>();
    Map<String, String?>? newTokens;
    try {
      if (kIsWeb) {
        newTokens = await _platformTryRefreshTokenForWeb();
      } else {
        final storedRefreshToken = await _secureStorage.read(key: _refreshTokenKeySecure);
        if (storedRefreshToken != null) {
          newTokens = await _platformTryRefreshTokenForNative(storedRefreshToken);
        }
      }
    } catch (e) {
      debugPrint("Error during refresh: $e");
    } finally {
      _isRefreshingToken = false;
      if (newTokens != null && newTokens['access_token'] != null) {
        if (!(_refreshTokenCompleter?.isCompleted == true)) _refreshTokenCompleter!.complete();
      } else {
        if (!(_refreshTokenCompleter?.isCompleted == true)) _refreshTokenCompleter!.completeError(Exception("Refresh token failed in _tryRefreshTokenInternal"));
      }
    }
    if (newTokens == null || newTokens['access_token'] == null) {
      await clearLocalAccessToken();
    }
    return newTokens;
  }
  Future<Map<String, String?>?> _platformTryRefreshTokenForWeb() async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/auth/refresh-token'),
        headers: await _getHeaders(includeAuth: false),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
        if (responseBody['data']?['access_token'] != null) {
          return {'access_token': responseBody['data']['access_token'], 'refresh_token': null};
        }
      }
    } catch (e) { /* ignore */ }
    return null;
  }
  Future<Map<String, String?>?> _platformTryRefreshTokenForNative(String currentRefreshToken) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/auth/refresh-token-native'),
        headers: await _getHeaders(includeAuth: false),
        body: json.encode({'refresh_token': currentRefreshToken}),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
        final newAccessToken = responseBody['data']?['access_token'] as String?;
        final newRefreshToken = responseBody['data']?['refresh_token'] as String?;
        if (newAccessToken != null) {
          return {'access_token': newAccessToken, 'refresh_token': newRefreshToken};
        }
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  Future<T> _retryRequest<T>(Future<T> Function() requestFunction) async {
    try {
      return await requestFunction();
    } on TokenRefreshedException {
      return await requestFunction();
    }
  }

  Future<AuthResponse> oAuthExchange({
    required String provider,
    required String code,
    required String state,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseApiUrl/auth/oauth/exchange'),
      headers: await _getHeaders(includeAuth: false),
      body: json.encode({
        'provider': provider,
        'code': code,
        'state': state,
      }),
    );
    final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200) {
      final authData = AuthResponse.fromJson(responseBody);
      await _saveAccessToken(authData.accessToken);
      // Нативный refreshToken здесь не обрабатываем, так как это веб-поток
      return authData;
    }
    throw ApiException(response.statusCode, responseBody['error'] as String? ?? 'Ошибка обмена OAuth кода');
  }

  String getOAuthUrl(String provider, {String? redirectUri}) {
    final uri = Uri.parse('$_baseApiUrl/auth/$provider');
    if (kIsWeb && redirectUri != null) {
      return uri.replace(queryParameters: {'redirect_uri': redirectUri}).toString();
    }
    return uri.toString();
  }

  // ... (остальные методы без изменений)
  // ... (getChatHistory, getWebSocketChannel, ... signIn, signUp, etc.)
  Future<Map<String, dynamic>> getChatHistory(String teamId, {String? beforeMessageId, int limit = 50}) async {
    return _retryRequest(() async {
      final queryParams = <String, String>{'limit': limit.toString()};
      if (beforeMessageId != null) {
        queryParams['before_message_id'] = beforeMessageId;
      }
      final uri = Uri.parse('$_baseApiUrl/chat/teams/$teamId/messages').replace(queryParameters: queryParams);
      final response = await _httpClient.get(uri, headers: await _getHeaders());

      return await _handleResponse(response, (jsonMap) => jsonMap, isChatHistory: true);
    });
  }

  Future<dynamic> getWebSocketChannel(String teamId) async {
    await _loadAccessToken();
    if (_cachedAccessToken == null) {
      throw Exception("Access token not available for WebSocket connection.");
    }

    String wsScheme = _baseUrl.startsWith('https') ? 'wss' : 'ws';
    final authority = Uri.parse(_baseUrl).authority;
    var wsUrl = '$wsScheme://$authority/v1/chat/ws/teams/$teamId';

    if (kIsWeb) {
      final finalWsUrl = '$wsUrl?token=$_cachedAccessToken';
      debugPrint("[ApiService] Correct WebSocket URL for Web: $finalWsUrl");
      return Uri.parse(finalWsUrl);
    } else {
      final headers = {'Authorization': 'Bearer $_cachedAccessToken'};
      HttpClient client = HttpClient();
      if (kDebugMode) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          final isAllowedHost = host == '10.0.2.2' || host == 'localhost';
          debugPrint("[ApiService getWebSocketChannel] SSL cert check: host=$host, port=$port. Is allowed: $isAllowedHost");
          return isAllowedHost;
        };
      }
      debugPrint("[ApiService] Correct WebSocket URL for Mobile: $wsUrl with headers");
      return IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: headers,
        customClient: client,
      );
    }
  }

  Future<void> saveAccessTokenForNative(String accessToken) async {
    await _saveAccessToken(accessToken);
  }

  Future<UserProfile> getUserProfile() async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/profile'), headers: await _getHeaders());
      return _handleResponse(response, UserProfile.fromJson);
    });
  }

  Future<UserProfile> patchUserProfile(Map<String, dynamic> patchData, {Map<String, dynamic>? avatarFile}) async {
    return _retryRequest(() async {
      var request = http.MultipartRequest('PATCH', Uri.parse('$_baseApiUrl/profile'));
      request.headers.addAll(await _getHeaders(isMultipart: true));
      request.fields['json_data'] = json.encode(patchData);
      if (avatarFile != null && avatarFile.containsKey('bytes') && avatarFile.containsKey('filename')) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar', avatarFile['bytes'] as Uint8List, filename: avatarFile['filename'] as String,
        ));
      }
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, UserProfile.fromJson);
    });
  }

  Future<void> registerDeviceToken(String deviceToken, String deviceType) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/profile/device-tokens'),
        headers: await _getHeaders(),
        body: json.encode({'device_token': deviceToken, 'device_type': deviceType}),
      );
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка регистрации токена (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  Future<void> unregisterDeviceToken(String deviceToken) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(
        Uri.parse('$_baseApiUrl/profile/device-tokens'),
        headers: await _getHeaders(),
        body: json.encode({'device_token': deviceToken}),
      );
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления токена (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<UserProfile> updateUserProfile({
    String? login, String? theme, String? accentColor, bool? isSidebarCollapsed,
    bool? resetAvatar, Map<String, dynamic>? avatarFile,
    String? emailNotificationsLevel,
    String? pushNotificationsTasksLevel,
    bool? pushNotificationsChatMentions,
    bool? taskDeadlineRemindersEnabled,
    String? taskDeadlineReminderTimePreference,
  }) async {
    return _retryRequest(() async {
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseApiUrl/profile'));
      request.headers.addAll(await _getHeaders(isMultipart: true));

      final Map<String, dynamic> jsonData = {};
      if (login != null) jsonData['login'] = login;
      if (theme != null) jsonData['theme'] = theme;
      if (accentColor != null) jsonData['accent_color'] = accentColor;
      if (isSidebarCollapsed != null) jsonData['is_sidebar_collapsed'] = isSidebarCollapsed;
      if (resetAvatar != null) jsonData['reset_avatar'] = resetAvatar;
      if (emailNotificationsLevel != null) jsonData['email_notifications_level'] = emailNotificationsLevel;
      if (pushNotificationsTasksLevel != null) jsonData['push_notifications_tasks_level'] = pushNotificationsTasksLevel;
      if (pushNotificationsChatMentions != null) jsonData['push_notifications_chat_mentions'] = pushNotificationsChatMentions;
      if (taskDeadlineRemindersEnabled != null) jsonData['task_deadline_reminders_enabled'] = taskDeadlineRemindersEnabled;
      if (taskDeadlineReminderTimePreference != null) jsonData['task_deadline_reminder_time_preference'] = taskDeadlineReminderTimePreference;

      request.fields['json_data'] = json.encode(jsonData);

      if (avatarFile != null && avatarFile.containsKey('bytes') && avatarFile.containsKey('filename')) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar', avatarFile['bytes'] as Uint8List, filename: avatarFile['filename'] as String,
        ));
      }
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, UserProfile.fromJson);
    });
  }
  Future<void> deleteUserAccount() async {
    return _retryRequest(() async {
      final response = await _httpClient.delete( Uri.parse('$_baseApiUrl/profile'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
      await clearLocalAccessToken();
      if (!kIsWeb) {
        await _secureStorage.delete(key: _refreshTokenKeySecure);
      }
    });
  }
  Future<AuthResponse> signUp({required String email, String? login, required String password}) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseApiUrl/auth/sign-up'),
      headers: await _getHeaders(includeAuth: false),
      body: json.encode({'email': email, if (login != null && login.isNotEmpty) 'login': login, 'password': password}),
    );
    final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 201) return AuthResponse.fromJson(responseBody);
    throw ApiException(response.statusCode, responseBody['error'] as String? ?? 'Ошибка регистрации');
  }
  Future<AuthResponse> signIn({required String password, String? email, String? login}) async {
    if ((email == null || email.isEmpty) && (login == null || login.isEmpty)) {
      throw ArgumentError('Необходимо указать email или login.');
    }
    final response = await _httpClient.post(
      Uri.parse('$_baseApiUrl/auth/sign-in'),
      headers: await _getHeaders(includeAuth: false),
      body: json.encode({
        if (email != null && email.isNotEmpty) 'email': email,
        if (login != null && login.isNotEmpty) 'login': login,
        'password': password,
      }),
    );
    final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200) {
      final authData = AuthResponse.fromJson(responseBody);
      await _saveAccessToken(authData.accessToken);
      if (!kIsWeb && authData.refreshToken != null && authData.refreshToken!.isNotEmpty) {
        await _secureStorage.write(key: _refreshTokenKeySecure, value: authData.refreshToken!);
      }
      return authData;
    } else if (response.statusCode == 403 && (responseBody['error'] as String?)?.toLowerCase().contains('email not confirmed') == true) {
      throw EmailNotConfirmedException();
    }
    throw ApiException(response.statusCode, responseBody['error'] as String? ?? 'Ошибка входа');
  }
  Future<void> logout() async {
    try {
      await _httpClient.post( Uri.parse('$_baseApiUrl/auth/logout'), headers: await _getHeaders());
    } catch (e) { /* ignore */ }
    finally {
      await clearLocalAccessToken();
      if (!kIsWeb) {
        await _secureStorage.delete(key: _refreshTokenKeySecure);
      }
    }
  }

  Future<void> sendConfirmationEmail(String email) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseApiUrl/email/send-code'),
      headers: await _getHeaders(includeAuth: false), body: json.encode({'email': email}),
    );
    if (response.statusCode != 202) {
      final Map<String, dynamic> rb = json.decode(utf8.decode(response.bodyBytes));
      throw ApiException(response.statusCode, rb['error'] as String? ?? 'Ошибка отправки кода');
    }
  }
  Future<void> confirmEmail(String email, String code) async {
    final response = await _httpClient.put(
      Uri.parse('$_baseApiUrl/email/confirm'),
      headers: await _getHeaders(includeAuth: false), body: json.encode({'email': email, 'code': code}),
    );
    if (response.statusCode != 200) {
      final Map<String, dynamic> rb = json.decode(utf8.decode(response.bodyBytes));
      throw ApiException(response.statusCode, rb['error'] as String? ?? 'Ошибка подтверждения email');
    }
  }

  Future<Task> createTask(Task taskData) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/tasks'),
        headers: await _getHeaders(),
        body: json.encode(taskData.toJsonForCreate()),
      );
      return _handleResponse(response, Task.fromJson);
    });
  }
  Future<List<Task>> getTasks({Map<String, String>? queryParams}) async {
    return _retryRequest(() async {
      final uri = Uri.parse('$_baseApiUrl/tasks').replace(queryParameters: queryParams);
      final response = await _httpClient.get(uri, headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? []);
        return items.map((item) => Task.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true);
    });
  }
  Future<Task> getTaskById(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/tasks/$taskId'), headers: await _getHeaders());
      return _handleResponse(response, Task.fromJson);
    });
  }
  Future<Task> updateTask(String taskId, Task taskData) async {
    return _retryRequest(() async {
      final response = await _httpClient.put(
        Uri.parse('$_baseApiUrl/tasks/$taskId'),
        headers: await _getHeaders(),
        body: json.encode(taskData.toJsonForUpdate()),
      );
      return _handleResponse(response, Task.fromJson);
    });
  }
  Future<Task> patchTask(String taskId, Map<String, dynamic> patchData) async {
    return _retryRequest(() async {
      final response = await _httpClient.patch(
        Uri.parse('$_baseApiUrl/tasks/$taskId'),
        headers: await _getHeaders(),
        body: json.encode(patchData),
      );
      return _handleResponse(response, Task.fromJson);
    });
  }
  Future<void> deleteTask(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseApiUrl/tasks/$taskId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления задачи (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  Future<Task> restoreTask(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/tasks/$taskId/restore'),
        headers: await _getHeaders(),
      );
      return _handleResponse(response, Task.fromJson);
    });
  }

  Future<void> deleteTaskPermanently(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(
        Uri.parse('$_baseApiUrl/tasks/$taskId/permanent'),
        headers: await _getHeaders(),
      );
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка полного удаления задачи (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  Future<ApiTag> createUserTag({required String name, String? colorHex}) async {
    return _retryRequest(() async {
      final Map<String, dynamic> body = {'name': name};
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.post(Uri.parse('$_baseApiUrl/user-tags'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson);
    });
  }
  Future<List<ApiTag>> getUserTags() async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/user-tags'), headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap as List<dynamic>? ?? []);
        return items.map((item) => ApiTag.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true);
    });
  }
  Future<ApiTag> updateUserTag(int tagId, {String? name, String? colorHex}) async {
    if (name == null && colorHex == null) throw ArgumentError("Для обновления тега нужно указать имя или цвет.");
    return _retryRequest(() async {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.put(Uri.parse('$_baseApiUrl/user-tags/$tagId'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson);
    });
  }
  Future<void> deleteUserTag(int tagId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseApiUrl/user-tags/$tagId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления тега (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<List<ApiTag>> getTeamTags(int teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/teams/$teamId/tags'), headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap as List<dynamic>? ?? []);
        return items.map((item) => ApiTag.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true);
    });
  }
  Future<ApiTag> createTeamTag(int teamId, {required String name, String? colorHex}) async {
    return _retryRequest(() async {
      final Map<String, dynamic> body = {'name': name};
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.post(Uri.parse('$_baseApiUrl/teams/$teamId/tags'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson);
    });
  }
  Future<ApiTag> updateTeamTag(int teamId, int tagId, {String? name, String? colorHex}) async {
    if (name == null && colorHex == null) throw ArgumentError("Для обновления тега команды нужно указать имя или цвет.");
    return _retryRequest(() async {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.put(Uri.parse('$_baseApiUrl/teams/$teamId/tags/$tagId'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson);
    });
  }
  Future<void> deleteTeamTag(int teamId, int tagId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseApiUrl/teams/$teamId/tags/$tagId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления тега команды (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<Team> createTeam(CreateTeamRequest requestData) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/teams'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, Team.fromJson);
    });
  }
  Future<List<Team>> getMyTeams({String? search}) async {
    return _retryRequest(() async {
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      final uri = Uri.parse('$_baseApiUrl/teams/my').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await _httpClient.get(uri, headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? (jsonMap as List<dynamic>? ?? []));
        return items.map((item) => Team.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true);
    });
  }
  Future<TeamDetail> getTeamDetails(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/teams/$teamId'), headers: await _getHeaders());
      return _handleResponse(response, TeamDetail.fromJson);
    });
  }
  Future<Team> updateTeam(String teamId, UpdateTeamDetailsRequest details, {Map<String, dynamic>? imageFile}) async {
    return _retryRequest(() async {
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseApiUrl/teams/$teamId'));
      request.headers.addAll(await _getHeaders(isMultipart: true));
      request.fields['json_data'] = json.encode(details.toJson());

      if (imageFile != null && imageFile.containsKey('bytes') && imageFile.containsKey('filename')) {
        request.files.add(http.MultipartFile.fromBytes(
          'image', imageFile['bytes'] as Uint8List, filename: imageFile['filename'] as String,
        ));
      }
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, Team.fromJson);
    });
  }
  Future<void> deleteTeam(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseApiUrl/teams/$teamId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления команды (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<Team> joinTeamByToken(String token) async {
    return _retryRequest(() async {
      final requestData = JoinTeamByTokenRequest(inviteToken: token);
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/teams/join'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, Team.fromJson);
    });
  }
  Future<void> leaveTeam(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(Uri.parse('$_baseApiUrl/teams/$teamId/leave'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка выхода из команды (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<List<TeamMember>> getTeamMembers(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseApiUrl/teams/$teamId/members'), headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? []);
        return items.map((item) => TeamMember.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true);
    });
  }
  Future<TeamMember> addTeamMember(String teamId, int userId, String role) async {
    return _retryRequest(() async {
      final requestData = AddTeamMemberRequest(userId: userId, role: TeamMemberRoleExtension.fromJson(role));
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/teams/$teamId/members'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, TeamMember.fromJson);
    });
  }
  Future<void> removeTeamMember(String teamId, int userId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseApiUrl/teams/$teamId/members/$userId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления участника (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }
  Future<TeamMember> updateTeamMemberRole(String teamId, int userId, String newRole) async {
    return _retryRequest(() async {
      final requestData = UpdateTeamMemberRoleRequest(role: TeamMemberRoleExtension.fromJson(newRole));
      final response = await _httpClient.put(
        Uri.parse('$_baseApiUrl/teams/$teamId/members/$userId/role'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, TeamMember.fromJson);
    });
  }
  Future<TeamInviteTokenResponse> generateInviteToken(String teamId, {int? expiresInHours, String? roleToAssign}) async {
    return _retryRequest(() async {
      final requestData = GenerateInviteTokenRequest(
        expiresInHours: expiresInHours,
        roleToAssign: roleToAssign != null ? TeamMemberRoleExtension.fromJson(roleToAssign) : null,
      );
      final response = await _httpClient.post(
        Uri.parse('$_baseApiUrl/teams/$teamId/invites'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, TeamInviteTokenResponse.fromJson);
    });
  }
  void dispose() {
    _httpClient.close();
    debugPrint("ApiService: HttpClient closed.");
  }
}