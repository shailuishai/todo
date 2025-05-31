// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException, HttpException; // Для Platform
// import 'package:http/browser_client.dart' as http; // <<<< УДАЛИТЕ ЭТУ СТРОКУ

import '../models/task_model.dart';
import '../models/team_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http; // Этот импорт содержит http.Client, http.Response и т.д.
import 'http_client_factory_io.dart'
if (dart.library.html) 'http_client_factory_web.dart' as httpClientFactory;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show Uint8List, debugPrint, kIsWeb;

// --- UserProfile Model (оставляем как есть) ---
class UserProfile {
  final int userId;
  final String login;
  final String email;
  final String? avatarUrl;
  final String? theme;
  final String? accentColor;
  final bool? isSidebarCollapsed;
  final bool? hasMobileDeviceLinked;
  final bool? notificationsEmailEnabled;
  final bool? notificationsPushTaskAssigned;
  final bool? notificationsPushTaskDeadline;
  final bool? notificationsPushTeamMention;

  UserProfile({
    required this.userId,
    required this.login,
    required this.email,
    this.avatarUrl,
    this.theme,
    this.accentColor,
    this.isSidebarCollapsed,
    this.hasMobileDeviceLinked,
    this.notificationsEmailEnabled,
    this.notificationsPushTaskAssigned,
    this.notificationsPushTaskDeadline,
    this.notificationsPushTeamMention,
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
      notificationsEmailEnabled: json['notifications_email_enabled'] as bool?,
      notificationsPushTaskAssigned: json['notifications_push_task_assigned'] as bool?,
      notificationsPushTaskDeadline: json['notifications_push_task_deadline'] as bool?,
      notificationsPushTeamMention: json['notifications_push_team_mention'] as bool?,
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
    'notifications_email_enabled': notificationsEmailEnabled,
    'notifications_push_task_assigned': notificationsPushTaskAssigned,
    'notifications_push_task_deadline': notificationsPushTaskDeadline,
    'notifications_push_team_mention': notificationsPushTeamMention,
  };
}

// --- AuthResponse Model (оставляем как есть) ---
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

// --- Exceptions (оставляем как есть) ---
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
  static String _baseUrl = kIsWeb
      ? 'https://localhost:8080/v1'
      : (Platform.isAndroid ? 'https://10.0.2.2:8080/v1' : 'https://localhost:8080/v1');

  static const String _accessTokenKeyPrefs = 'auth_access_token_prefs_v1';
  static const String _refreshTokenKeySecure = 'app_refresh_token_secure_v1';

  String? _cachedAccessToken;
  bool _isRefreshingToken = false;
  Completer<void>? _refreshTokenCompleter;

  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  ApiService() : _httpClient = httpClientFactory.createHttpClient(){
    debugPrint("ApiService: Initialized with client type: ${_httpClient.runtimeType}");
  }

  Future<void> _loadAccessToken() async {
    if (_cachedAccessToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = prefs.getString(_accessTokenKeyPrefs);
    // debugPrint("ApiService (_loadAccessToken): Loaded access token from prefs: ${_cachedAccessToken != null ? 'found' : 'not found'}");
  }

  Future<void> _saveAccessToken(String token) async {
    _cachedAccessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKeyPrefs, token);
    // debugPrint("ApiService (_saveAccessToken): Access token saved to SharedPreferences.");
  }

  Future<void> clearLocalAccessToken() async {
    _cachedAccessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKeyPrefs);
    // debugPrint("ApiService (clearLocalAccessToken): Access token cleared from SharedPreferences.");
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
        bool directData = false,
      }) async {
    final String responseBodyString = utf8.decode(response.bodyBytes);
    Map<String, dynamic> responseBody;

    // debugPrint("ApiService (_handleResponse) - URL: ${response.request?.url}, Status: ${response.statusCode}, directData: $directData, isList: $isList");
    // debugPrint("ApiService (_handleResponse) - Raw Body: $responseBodyString");

    if (response.statusCode == 204) {
      if (isList) return fromJson({'items': []});
      try {
        return fromJson({});
      } catch (e) {
        // debugPrint("ApiService (_handleResponse): fromJson failed for empty map on 204. Error: $e");
        if (!isList) {
          throw ApiException(response.statusCode, "Получен пустой ответ (204) там, где ожидались данные объекта.");
        }
        return fromJson({'items': []});
      }
    }

    try {
      responseBody = json.decode(responseBodyString);
    } catch (e) {
      // debugPrint("ApiService (_handleResponse): Failed to decode JSON. Status: ${response.statusCode}, Body: $responseBodyString, Error: $e");
      throw ApiException(response.statusCode, "Ошибка сервера: не удалось обработать ответ. Body: $responseBodyString");
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (directData) {
        // debugPrint("ApiService (_handleResponse with directData=true): Passing entire responseBody to fromJson. ResponseBody keys: ${responseBody.keys}");
        if (responseBody is Map<String, dynamic>) {
          return fromJson(responseBody);
        } else {
          // debugPrint("ApiService (_handleResponse with directData=true): responseBody is not a Map. Body: $responseBodyString");
          throw ApiException(response.statusCode, "Неверный формат ответа (directData, не Map): $responseBodyString");
        }
      } else {
        if (responseBody.containsKey('data')) {
          final dataField = responseBody['data'];
          if (isList) {
            if (dataField is List) {
              return fromJson({'items': dataField});
            } else if (dataField is Map<String, dynamic> && dataField.containsKey('items') && dataField['items'] is List) {
              return fromJson(dataField);
            } else {
              // debugPrint("ApiService (_handleResponse): Expected list but 'data' is not a list or does not conform. Data: $dataField");
              throw ApiException(response.statusCode, "Неверный формат ответа: ожидался список в 'data'.");
            }
          } else {
            if (dataField is Map<String, dynamic>) {
              return fromJson(dataField);
            } else if (dataField == null && response.statusCode < 300 ) {
              // debugPrint("ApiService (_handleResponse): 'data' is null for non-list response. Status: ${response.statusCode}. FromJson might fail.");
              try {
                return fromJson({});
              } catch (e) {
                throw ApiException(response.statusCode, "Поле 'data' равно null в успешном ответе, но ожидался объект.");
              }
            } else {
              // debugPrint("ApiService (_handleResponse): 'data' field is not a Map for non-list response. Data: $dataField");
              throw ApiException(response.statusCode, "Неверный формат поля 'data' в ответе (ожидался объект).");
            }
          }
        } else if (isList && responseBody.containsKey('items') && responseBody['items'] is List) {
          return fromJson(responseBody);
        }
        else {
          // debugPrint("ApiService (_handleResponse): 'data' field (or 'items' for list) missing. ResponseBody: $responseBodyString");
          throw ApiException(response.statusCode, "Отсутствует поле 'data' (или 'items') в успешном ответе.");
        }
      }
    } else if (response.statusCode == 401) {
      // debugPrint("ApiService (_handleResponse): Received 401 for ${response.request?.url}. Attempting token refresh.");
      final Map<String, String?>? newTokens = await _tryRefreshTokenInternal();
      if (newTokens != null && newTokens['access_token'] != null) {
        await _saveAccessToken(newTokens['access_token']!);
        if (!kIsWeb && newTokens['refresh_token'] != null && newTokens['refresh_token']!.isNotEmpty) {
          await _secureStorage.write(key: _refreshTokenKeySecure, value: newTokens['refresh_token']!);
          // debugPrint("ApiService (_handleResponse): Native refresh token updated in secure storage.");
        } else if (!kIsWeb && (newTokens['refresh_token'] == null || newTokens['refresh_token']!.isEmpty)) {
          // debugPrint("ApiService (_handleResponse): Native access token refreshed, existing refresh token in secure storage remains.");
        }
        // debugPrint("ApiService (_handleResponse): Token refresh successful. Throwing TokenRefreshedException.");
        throw TokenRefreshedException();
      }
      // debugPrint("ApiService (_handleResponse): Token refresh failed. Clearing local access token for ${response.request?.url}.");
      await clearLocalAccessToken();
      String errorMessage = responseBody['error'] as String? ?? 'Ошибка аутентификации. Пожалуйста, войдите снова.';
      if (response.request?.url.path.endsWith('/auth/refresh-token-native') == true || response.request?.url.path.endsWith('/auth/refresh-token') == true ) {
        errorMessage = responseBody['error'] as String? ?? 'Сессия истекла или недействительна. Пожалуйста, войдите снова.';
      }
      throw ApiException(response.statusCode, errorMessage);
    } else {
      throw ApiException(response.statusCode, responseBody['error'] as String? ?? 'Неизвестная ошибка API');
    }
  }

  Future<Map<String, String?>?> _tryRefreshTokenInternal() async {
    if (_isRefreshingToken) {
      // debugPrint("ApiService (_tryRefreshTokenInternal): Refresh already in progress. Awaiting.");
      await _refreshTokenCompleter?.future;
      await _loadAccessToken();
      return _cachedAccessToken != null ? {'access_token': _cachedAccessToken, 'refresh_token': null} : null;
    }

    _isRefreshingToken = true;
    _refreshTokenCompleter = Completer<void>();
    // debugPrint("ApiService (_tryRefreshTokenInternal): Starting token refresh process.");

    Map<String, String?>? newTokens;
    try {
      if (kIsWeb) {
        newTokens = await _platformTryRefreshTokenForWeb();
      } else {
        final storedRefreshToken = await _secureStorage.read(key: _refreshTokenKeySecure);
        if (storedRefreshToken != null) {
          // debugPrint("ApiService (_tryRefreshTokenInternal): Found native refresh token in secure storage.");
          newTokens = await _platformTryRefreshTokenForNative(storedRefreshToken);
        } else {
          // debugPrint("ApiService (_tryRefreshTokenInternal): No native refresh token in secure storage.");
        }
      }
    } catch (e) {
      // debugPrint("ApiService (_tryRefreshTokenInternal): Exception during platform refresh call: $e");
    } finally {
      _isRefreshingToken = false;
      if (newTokens != null && newTokens['access_token'] != null) {
        if (!(_refreshTokenCompleter?.isCompleted == true)) _refreshTokenCompleter!.complete();
      } else {
        if (!(_refreshTokenCompleter?.isCompleted == true)) _refreshTokenCompleter!.completeError(Exception("Refresh token failed in _tryRefreshTokenInternal"));
      }
    }

    if (newTokens == null || newTokens['access_token'] == null) {
      // debugPrint("ApiService (_tryRefreshTokenInternal): Refresh failed, clearing local access token.");
      await clearLocalAccessToken();
    }
    return newTokens;
  }

  Future<Map<String, String?>?> _platformTryRefreshTokenForWeb() async {
    // debugPrint("ApiService (_platformTryRefreshTokenForWeb): Refreshing for web.");
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/refresh-token'),
        headers: await _getHeaders(includeAuth: false),
      );
      // debugPrint("ApiService (_platformTryRefreshTokenForWeb): Response status: ${response.statusCode}, body: ${response.body}");
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
        if (responseBody['data']?['access_token'] != null) {
          return {'access_token': responseBody['data']['access_token'], 'refresh_token': null};
        }
      }
    } catch (e) {
      // debugPrint("ApiService (_platformTryRefreshTokenForWeb): Error: $e");
    }
    return null;
  }

  Future<Map<String, String?>?> _platformTryRefreshTokenForNative(String currentRefreshToken) async {
    // debugPrint("ApiService (_platformTryRefreshTokenForNative): Refreshing for native with token: $currentRefreshToken");
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/refresh-token-native'),
        headers: await _getHeaders(includeAuth: false),
        body: json.encode({'refresh_token': currentRefreshToken}),
      );
      // debugPrint("ApiService (_platformTryRefreshTokenForNative): Response status: ${response.statusCode}, body: ${response.body}");
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(utf8.decode(response.bodyBytes));
        final newAccessToken = responseBody['data']?['access_token'] as String?;
        final newRefreshToken = responseBody['data']?['refresh_token'] as String?;
        if (newAccessToken != null) {
          return {'access_token': newAccessToken, 'refresh_token': newRefreshToken};
        }
      }
    } catch (e) {
      // debugPrint("ApiService (_platformTryRefreshTokenForNative): Error: $e");
    }
    return null;
  }

  Future<T> _retryRequest<T>(Future<T> Function() requestFunction) async {
    try {
      return await requestFunction();
    } on TokenRefreshedException {
      // debugPrint("ApiService (_retryRequest): Token was refreshed. Retrying original request.");
      return await requestFunction();
    }
  }

  Future<void> saveAccessTokenForNative(String accessToken) async {
    await _saveAccessToken(accessToken);
  }

  // --- User Profile ---
  Future<UserProfile> getUserProfile() async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/profile'), headers: await _getHeaders());
      return _handleResponse(response, UserProfile.fromJson, directData: false);
    });
  }

  Future<UserProfile> updateUserProfile({
    String? login, String? theme, String? accentColor, bool? isSidebarCollapsed,
    bool? resetAvatar, Map<String, dynamic>? avatarFile,
    bool? notificationsEmailEnabled,
    bool? notificationsPushTaskAssigned,
    bool? notificationsPushTaskDeadline,
    bool? notificationsPushTeamMention,
  }) async {
    return _retryRequest(() async {
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseUrl/profile'));
      request.headers.addAll(await _getHeaders(isMultipart: true));

      final Map<String, dynamic> jsonData = {};
      if (login != null) jsonData['login'] = login;
      if (theme != null) jsonData['theme'] = theme;
      if (accentColor != null) jsonData['accent_color'] = accentColor;
      if (isSidebarCollapsed != null) jsonData['is_sidebar_collapsed'] = isSidebarCollapsed;
      if (notificationsEmailEnabled != null) jsonData['notifications_email_enabled'] = notificationsEmailEnabled;
      if (notificationsPushTaskAssigned != null) jsonData['notifications_push_task_assigned'] = notificationsPushTaskAssigned;
      if (notificationsPushTaskDeadline != null) jsonData['notifications_push_task_deadline'] = notificationsPushTaskDeadline;
      if (notificationsPushTeamMention != null) jsonData['notifications_push_team_mention'] = notificationsPushTeamMention;
      if (resetAvatar != null) jsonData['reset_avatar'] = resetAvatar;

      request.fields['json_data'] = json.encode(jsonData);

      if (avatarFile != null && avatarFile.containsKey('bytes') && avatarFile.containsKey('filename')) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar', avatarFile['bytes'] as Uint8List, filename: avatarFile['filename'] as String,
        ));
      }
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, UserProfile.fromJson, directData: false);
    });
  }
  Future<void> deleteUserAccount() async {
    return _retryRequest(() async {
      final response = await _httpClient.delete( Uri.parse('$_baseUrl/profile'), headers: await _getHeaders());
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

  // --- Auth ---
  Future<AuthResponse> signUp({required String email, String? login, required String password}) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/auth/sign-up'),
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
      Uri.parse('$_baseUrl/auth/sign-in'),
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
      if (!kIsWeb && authData.refreshToken != null && authData.refreshToken!.isNotEmpty) { // Сохраняем RT для нативных клиентов
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
      await _httpClient.post( Uri.parse('$_baseUrl/auth/logout'), headers: await _getHeaders());
    } catch (e) { /* ignore */ }
    finally {
      await clearLocalAccessToken();
      if (!kIsWeb) {
        await _secureStorage.delete(key: _refreshTokenKeySecure);
      }
    }
  }
  String getOAuthUrl(String provider) => '$_baseUrl/auth/$provider';

  // --- Email ---
  Future<void> sendConfirmationEmail(String email) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/email/send-code'),
      headers: await _getHeaders(includeAuth: false), body: json.encode({'email': email}),
    );
    if (response.statusCode != 202) {
      final Map<String, dynamic> rb = json.decode(utf8.decode(response.bodyBytes));
      throw ApiException(response.statusCode, rb['error'] as String? ?? 'Ошибка отправки кода');
    }
  }
  Future<void> confirmEmail(String email, String code) async {
    final response = await _httpClient.put(
      Uri.parse('$_baseUrl/email/confirm'),
      headers: await _getHeaders(includeAuth: false), body: json.encode({'email': email, 'code': code}),
    );
    if (response.statusCode != 200) {
      final Map<String, dynamic> rb = json.decode(utf8.decode(response.bodyBytes));
      throw ApiException(response.statusCode, rb['error'] as String? ?? 'Ошибка подтверждения email');
    }
  }

  // --- Tasks ---
  Future<Task> createTask(Task taskData) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/tasks'),
        headers: await _getHeaders(),
        body: json.encode(taskData.toJsonForCreate()),
      );
      return _handleResponse(response, Task.fromJson, directData: false);
    });
  }

  Future<List<Task>> getTasks({Map<String, String>? queryParams}) async {
    return _retryRequest(() async {
      final uri = Uri.parse('$_baseUrl/tasks').replace(queryParameters: queryParams);
      final response = await _httpClient.get(uri, headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? []); // Пытаемся обработать оба варианта
        return items.map((item) => Task.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true, directData: false);
    });
  }

  Future<Task> getTaskById(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/tasks/$taskId'), headers: await _getHeaders());
      return _handleResponse(response, Task.fromJson, directData: false);
    });
  }

  Future<Task> updateTask(String taskId, Task taskData) async {
    return _retryRequest(() async {
      final response = await _httpClient.put(
        Uri.parse('$_baseUrl/tasks/$taskId'),
        headers: await _getHeaders(),
        body: json.encode(taskData.toJsonForUpdate()),
      );
      return _handleResponse(response, Task.fromJson, directData: false);
    });
  }

  Future<Task> patchTask(String taskId, Map<String, dynamic> patchData) async {
    return _retryRequest(() async {
      final response = await _httpClient.patch(
        Uri.parse('$_baseUrl/tasks/$taskId'),
        headers: await _getHeaders(),
        body: json.encode(patchData),
      );
      return _handleResponse(response, Task.fromJson, directData: false);
    });
  }
  Future<void> deleteTask(String taskId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseUrl/tasks/$taskId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления задачи (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  // --- User Tags ---
  Future<ApiTag> createUserTag({required String name, String? colorHex}) async {
    return _retryRequest(() async {
      final Map<String, dynamic> body = {'name': name};
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.post(Uri.parse('$_baseUrl/user-tags'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson, directData: false);
    });
  }
  Future<List<ApiTag>> getUserTags() async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/user-tags'), headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? [];
        return items.map((item) => ApiTag.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true, directData: false);
    });
  }
  Future<ApiTag> updateUserTag(int tagId, {String? name, String? colorHex}) async {
    if (name == null && colorHex == null) throw ArgumentError("Для обновления тега нужно указать имя или цвет.");
    return _retryRequest(() async {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.put(Uri.parse('$_baseUrl/user-tags/$tagId'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson, directData: false);
    });
  }
  Future<void> deleteUserTag(int tagId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseUrl/user-tags/$tagId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления тега (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  // --- Team Tags ---
  Future<List<ApiTag>> getTeamTags(int teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/teams/$teamId/tags'), headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        final items = jsonMap['items'] as List<dynamic>? ?? [];
        return items.map((item) => ApiTag.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true, directData: false);
    });
  }
  Future<ApiTag> createTeamTag(int teamId, {required String name, String? colorHex}) async {
    return _retryRequest(() async {
      final Map<String, dynamic> body = {'name': name};
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.post(Uri.parse('$_baseUrl/teams/$teamId/tags'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson, directData: false);
    });
  }
  Future<ApiTag> updateTeamTag(int teamId, int tagId, {String? name, String? colorHex}) async {
    if (name == null && colorHex == null) throw ArgumentError("Для обновления тега команды нужно указать имя или цвет.");
    return _retryRequest(() async {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (colorHex != null) body['color'] = colorHex;
      final response = await _httpClient.put(Uri.parse('$_baseUrl/teams/$teamId/tags/$tagId'), headers: await _getHeaders(), body: json.encode(body));
      return _handleResponse(response, ApiTag.fromJson, directData: false);
    });
  }
  Future<void> deleteTeamTag(int teamId, int tagId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseUrl/teams/$teamId/tags/$tagId'), headers: await _getHeaders());
      if (response.statusCode != 204) {
        String errMsg = 'Ошибка удаления тега команды (status: ${response.statusCode})';
        try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
        throw ApiException(response.statusCode, errMsg);
      }
    });
  }

  // --- Teams ---
  Future<Team> createTeam(CreateTeamRequest requestData) async {
    return _retryRequest(() async {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/teams'),
        headers: await _getHeaders(),
        body: json.encode(requestData.toJson()),
      );
      return _handleResponse(response, Team.fromJson, directData: false);
    });
  }

  Future<List<Team>> getMyTeams({String? search}) async {
    return _retryRequest(() async {
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      final uri = Uri.parse('$_baseUrl/teams/my').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await _httpClient.get(uri, headers: await _getHeaders());
      return _handleResponse(response, (jsonMap) {
        // Swagger указывает TeamResponse, но это список. Если это обертка {"data": [TeamResponse, ...]}
        final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? []);
        return items.map((item) => Team.fromJson(item as Map<String, dynamic>)).toList();
      }, isList: true, directData: false);
    });
  }

  Future<TeamDetail> getTeamDetails(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/teams/$teamId'), headers: await _getHeaders());
      return _handleResponse(response, TeamDetail.fromJson, directData: false);
    });
  }

  Future<Team> updateTeam(String teamId, UpdateTeamDetailsRequest details, {Map<String, dynamic>? imageFile}) async {
    return _retryRequest(() async {
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseUrl/teams/$teamId'));
      request.headers.addAll(await _getHeaders(isMultipart: true));
      request.fields['json_data'] = json.encode(details.toJson());

      if (imageFile != null && imageFile.containsKey('bytes') && imageFile.containsKey('filename')) {
        request.files.add(http.MultipartFile.fromBytes(
          'image', imageFile['bytes'] as Uint8List, filename: imageFile['filename'] as String,
        ));
      }
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, Team.fromJson, directData: false);
    });
  }

  Future<void> deleteTeam(String teamId) async {
    return _retryRequest(() async {
      final response = await _httpClient.delete(Uri.parse('$_baseUrl/teams/$teamId'), headers: await _getHeaders());
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
          Uri.parse('$_baseUrl/teams/join'),
          headers: await _getHeaders(),
          body: json.encode(requestData.toJson()),
        );
        return _handleResponse(response, Team.fromJson, directData: false);
      });
    }

    Future<void> leaveTeam(String teamId) async {
      return _retryRequest(() async {
        final response = await _httpClient.post(Uri.parse('$_baseUrl/teams/$teamId/leave'), headers: await _getHeaders());
        if (response.statusCode != 204) {
          String errMsg = 'Ошибка выхода из команды (status: ${response.statusCode})';
          try {errMsg = json.decode(utf8.decode(response.bodyBytes))['error'] ?? errMsg;} catch (_){}
          throw ApiException(response.statusCode, errMsg);
        }
      });
    }

    Future<List<TeamMember>> getTeamMembers(String teamId) async {
      return _retryRequest(() async {
        final response = await _httpClient.get(Uri.parse('$_baseUrl/teams/$teamId/members'), headers: await _getHeaders());
        return _handleResponse(response, (jsonMap) {
          // Swagger: TeamMemberResponse. Это может быть список напрямую в 'data' или 'data.items'
          final items = jsonMap['items'] as List<dynamic>? ?? (jsonMap['data'] as List<dynamic>? ?? []);
          return items.map((item) => TeamMember.fromJson(item as Map<String, dynamic>)).toList();
        }, isList: true, directData: false);
      });
    }

    Future<TeamMember> addTeamMember(String teamId, int userId, String role) async {
      return _retryRequest(() async {
        final requestData = AddTeamMemberRequest(userId: userId, role: TeamMemberRoleExtension.fromJson(role));
        final response = await _httpClient.post(
          Uri.parse('$_baseUrl/teams/$teamId/members'),
          headers: await _getHeaders(),
          body: json.encode(requestData.toJson()),
        );
        return _handleResponse(response, TeamMember.fromJson, directData: false);
      });
    }

    Future<void> removeTeamMember(String teamId, int userId) async {
      return _retryRequest(() async {
        final response = await _httpClient.delete(Uri.parse('$_baseUrl/teams/$teamId/members/$userId'), headers: await _getHeaders());
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
          Uri.parse('$_baseUrl/teams/$teamId/members/$userId/role'),
          headers: await _getHeaders(),
          body: json.encode(requestData.toJson()),
        );
        return _handleResponse(response, TeamMember.fromJson, directData: false);
      });
    }

    Future<TeamInviteTokenResponse> generateInviteToken(String teamId, {int? expiresInHours, String? roleToAssign}) async {
      return _retryRequest(() async {
        final requestData = GenerateInviteTokenRequest(
          expiresInHours: expiresInHours,
          roleToAssign: roleToAssign != null ? TeamMemberRoleExtension.fromJson(roleToAssign) : null,
        );
        final response = await _httpClient.post(
          Uri.parse('$_baseUrl/teams/$teamId/invites'),
          headers: await _getHeaders(),
          body: json.encode(requestData.toJson()),
        );
        return _handleResponse(response, TeamInviteTokenResponse.fromJson, directData: false);
      });
    }

    void dispose() {
      _httpClient.close();
      debugPrint("ApiService: HttpClient closed.");
    }
  }