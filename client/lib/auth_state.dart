// lib/auth_state.dart
import 'dart:async';
import 'dart:io' show HttpServer, Platform;

import 'package:client/core/routing/app_pages.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import 'services/api_service.dart';

class AuthState extends ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _refreshTokenKeySecure = 'app_refresh_token_secure_v1';

  bool _isLoggedIn = false;
  bool _isLoading = true;
  bool _initialAuthCheckCompleted = false;

  String? _errorMessage;
  UserProfile? _currentUser;
  String? _emailPendingConfirmation;
  String? _oauthErrorMessage;
  String? _pendingInviteToken;


  StreamController<String?> _oauthRedirectControllerWeb = StreamController.broadcast();
  Stream<String?> get oauthRedirectStreamWeb => _oauthRedirectControllerWeb.stream;

  HttpServer? _nativeOAuthHttpServer;
  static const int _nativeOAuthPort = 8989;
  String get nativeClientLandingUri => 'http://127.0.0.1:$_nativeOAuthPort/native-oauth-landing';
  Completer<bool>? _nativeOAuthCompleter;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get initialAuthCheckCompleted => _initialAuthCheckCompleted;

  String? get errorMessage => _errorMessage;
  UserProfile? get currentUser => _currentUser;
  String? get emailPendingConfirmation => _emailPendingConfirmation;
  String? get oauthErrorMessage => _oauthErrorMessage;
  String? get pendingInviteToken => _pendingInviteToken;


  AuthState({required ApiService apiService}) : _apiService = apiService {
    _checkInitialAuthStatus();
  }

  Future<void> _checkInitialAuthStatus() async {
    if (!_initialAuthCheckCompleted) {
      _isLoading = true;
      notifyListeners();
    }

    _initialAuthCheckCompleted = false;
    _emailPendingConfirmation = null;
    _oauthErrorMessage = null;

    try {
      debugPrint("AuthState (_checkInitialAuthStatus): Attempting to get user profile with existing access token (if any).");
      final user = await _apiService.getUserProfile();
      _currentUser = user;
      _isLoggedIn = true;
      _errorMessage = null;
      debugPrint("AuthState (_checkInitialAuthStatus): Success with existing access token. User: ${_currentUser?.login}");

      if (_isLoggedIn && _pendingInviteToken != null) {
        debugPrint("AuthState (_checkInitialAuthStatus): User logged in, pending invite token '$_pendingInviteToken' is ready to be processed by router.");
      }

    } on TokenRefreshedException {
      debugPrint("AuthState (_checkInitialAuthStatus): TokenRefreshedException caught. Attempting to get profile again.");
      try {
        final user = await _apiService.getUserProfile();
        _currentUser = user;
        _isLoggedIn = true;
        _errorMessage = null;
        debugPrint("AuthState (_checkInitialAuthStatus): Success after TokenRefreshedException and explicit retry. User: ${_currentUser?.login}");
        if (_isLoggedIn && _pendingInviteToken != null) {
          debugPrint("AuthState (_checkInitialAuthStatus after refresh): User logged in, pending invite token '$_pendingInviteToken' is ready.");
        }
      } catch (e) {
        _isLoggedIn = false;
        _currentUser = null;
        await _apiService.clearLocalAccessToken();
        if (!kIsWeb) await _secureStorage.delete(key: _refreshTokenKeySecure);
        _errorMessage = "Ошибка при проверке сессии (после обновления токена): $e";
        debugPrint("AuthState (_checkInitialAuthStatus): Failed to get profile even after TokenRefreshedException and explicit retry: $e");
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        debugPrint("AuthState (_checkInitialAuthStatus): API returned 401. Assuming session is invalid after all refresh attempts by ApiService.");
        _isLoggedIn = false;
        _currentUser = null;
        await _apiService.clearLocalAccessToken();
        if (!kIsWeb) await _secureStorage.delete(key: _refreshTokenKeySecure);
      } else {
        _errorMessage = "Не удалось проверить сессию: ${e.message}";
        debugPrint("AuthState (_checkInitialAuthStatus): API Exception ${e.statusCode}: ${e.message}");
      }
    } on NetworkException catch (e) {
      _errorMessage = e.message;
      debugPrint("AuthState (_checkInitialAuthStatus): Network Exception: ${e.message}");
    } catch (e) {
      _errorMessage = "Неизвестная ошибка при проверке сессии: $e";
      debugPrint("AuthState (_checkInitialAuthStatus): Unknown error: $e");
      _isLoggedIn = false;
      _currentUser = null;
      await _apiService.clearLocalAccessToken();
      if (!kIsWeb) await _secureStorage.delete(key: _refreshTokenKeySecure);
    }

    if (_isLoggedIn && _currentUser != null) {
    } else {
      _isLoggedIn = false;
      _currentUser = null;
    }

    _isLoading = false;
    _initialAuthCheckCompleted = true;
    debugPrint("AuthState (_checkInitialAuthStatus) FINISHING: isLoggedIn: $_isLoggedIn, initialAuthCheckCompleted: $_initialAuthCheckCompleted, currentUser: ${_currentUser?.login}, error: $_errorMessage, pendingToken: $_pendingInviteToken");
    notifyListeners();
  }

  Future<void> checkInitialAuthStatusAgain() async {
    debugPrint("AuthState: Manually re-checking initial auth status via checkInitialAuthStatusAgain().");
    await _checkInitialAuthStatus();
  }

  Future<bool> signUp({
    required String email, String? login, required String password,
  }) async {
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; _emailPendingConfirmation = null; notifyListeners();
    try {
      await _apiService.signUp(email: email, login: login, password: password);
      _emailPendingConfirmation = email;
      _isLoading = false;
      debugPrint("AuthState (signUp) FINISHING: emailPendingConfirmation: $_emailPendingConfirmation");
      notifyListeners();
      return true;
    } on ApiException catch (e) { _errorMessage = e.message;
    } on NetworkException catch (e) { _errorMessage = e.message;
    } catch (e) { _errorMessage = 'Неизвестная ошибка при регистрации: ${e.toString()}'; }
    _isLoading = false;
    debugPrint("AuthState (signUp) FAILED: error: $_errorMessage");
    notifyListeners();
    return false;
  }

  Future<bool> signIn({
    required String password, String? emailOrLogin,
  }) async {
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; _emailPendingConfirmation = null; notifyListeners();
    String? emailValue; String? loginStr;
    if (emailOrLogin != null && emailOrLogin.isNotEmpty) {
      if (emailOrLogin.contains('@')) emailValue = emailOrLogin; else loginStr = emailOrLogin;
    }

    try {
      final authResponse = await _apiService.signIn(email: emailValue, login: loginStr, password: password);

      if (!kIsWeb && authResponse.refreshToken != null && authResponse.refreshToken!.isNotEmpty) {
        await _secureStorage.write(key: _refreshTokenKeySecure, value: authResponse.refreshToken!);
        debugPrint("AuthState (signIn): Native refresh token saved from signIn API response.");
      }

      await _checkInitialAuthStatus();
      return _isLoggedIn;

    } on EmailNotConfirmedException catch (e) {
      _errorMessage = e.message;
      _emailPendingConfirmation = emailValue ?? ( (emailOrLogin!=null && emailOrLogin.contains("@")) ? emailOrLogin : null);
      _isLoggedIn = false; _currentUser = null; _isLoading = false; notifyListeners(); return false;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoggedIn = false; _currentUser = null; _isLoading = false; notifyListeners(); return false;
    } on NetworkException catch (e) {
      _errorMessage = e.message;
      _isLoggedIn = false; _currentUser = null; _isLoading = false; notifyListeners(); return false;
    } catch (e) {
      _errorMessage = 'Неизвестная ошибка при входе: ${e.toString()}';
      _isLoggedIn = false; _currentUser = null; _isLoading = false; notifyListeners(); return false;
    }
  }

  Future<void> logout() async {
    _errorMessage = null;
    _oauthErrorMessage = null;
    _emailPendingConfirmation = null;
    _pendingInviteToken = null;

    try {
      await _apiService.logout();
    } catch (e) {
      debugPrint("AuthState (logout): Error calling API logout (ignored): $e");
    } finally {
      _isLoggedIn = false;
      _currentUser = null;
      debugPrint("AuthState (logout): User logged out. Local state cleared.");
      notifyListeners();
    }
  }

  Future<void> initiateOAuth(String provider) async {
    _isLoading = true;
    _oauthErrorMessage = null;
    _errorMessage = null;
    _emailPendingConfirmation = null;
    notifyListeners();

    String backendInitiationUrl = _apiService.getOAuthUrl(provider);

    if (kIsWeb) {
      final frontendCallbackUrl = Uri.base.origin + AppRoutes.oAuthCallback(provider);
      debugPrint("Web OAuth: Frontend callback URL will be: $frontendCallbackUrl");

      final fullUrlToLaunch = Uri.parse(backendInitiationUrl).replace(queryParameters: {'redirect_uri': frontendCallbackUrl}).toString();

      debugPrint('Web OAuth: Redirecting to: $fullUrlToLaunch');
      _oauthRedirectControllerWeb.add(fullUrlToLaunch);

    } else {
      // ИЗМЕНЕНИЕ: Убираем finally, переносим остановку сервера в хендлер
      final fullUrlToLaunch = Uri.parse(backendInitiationUrl).replace(queryParameters: {'native_final_redirect_uri': nativeClientLandingUri}).toString();
      debugPrint('Native OAuth: Full URL to launch: $fullUrlToLaunch. Landing: $nativeClientLandingUri');

      _nativeOAuthCompleter = Completer<bool>();
      try {
        await _startNativeOAuthHttpServer();
        final uri = Uri.parse(fullUrlToLaunch);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Could not launch $uri for provider $provider');
        }
        await _nativeOAuthCompleter!.future;

      } catch (e) {
        _oauthErrorMessage = "Ошибка запуска OAuth $provider: $e";
        if (!(_nativeOAuthCompleter?.isCompleted == true)) _nativeOAuthCompleter?.complete(false);
        // Если произошла ошибка, сервер тоже нужно остановить
        await _stopNativeOAuthHttpServer();
      }

      // Сбрасываем состояние загрузки после завершения (успешного или нет)
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleOAuthCallbackFromUrl(Uri uri, String provider) async {
    debugPrint("AuthState (handleOAuthCallbackFromUrl): Received URI from frontend callback page for provider '$provider'");
    _isLoading = true;
    _oauthErrorMessage = null;
    notifyListeners();

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      _oauthErrorMessage = "Ошибка от провайдера OAuth: $error";
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (code == null || state == null) {
      _oauthErrorMessage = "Необходимые параметры 'code' или 'state' отсутствуют в URL";
      _isLoading = false;
      notifyListeners();
      return false;
    }

    try {
      final redirectUriUsed = Uri.base.origin + AppRoutes.oAuthCallback(provider);
      await _apiService.oAuthExchange(
        provider: provider,
        code: code,
        state: state,
        redirectUri: redirectUriUsed,
      );

      await _checkInitialAuthStatus();
      return _isLoggedIn;
    } on ApiException catch (e) {
      _oauthErrorMessage = "Ошибка при обмене кода на токен: ${e.message}";
    } on NetworkException catch (e) {
      _oauthErrorMessage = "Сетевая ошибка: ${e.message}";
    } catch (e) {
      _oauthErrorMessage = "Неизвестная ошибка: ${e.toString()}";
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> _startNativeOAuthHttpServer() async {
    if (_nativeOAuthHttpServer != null) await _stopNativeOAuthHttpServer();
    try {
      final router = shelf_router.Router();
      router.get('/native-oauth-landing', _nativeOAuthLandingHandler);
      final handler = const shelf.Pipeline().addHandler(router.call);
      _nativeOAuthHttpServer = await shelf_io.serve(handler, '127.0.0.1', _nativeOAuthPort);
      debugPrint('AuthState (_startNativeOAuthHttpServer): Server started on 127.0.0.1:${_nativeOAuthHttpServer?.port}');
    } catch (e) {
      _oauthErrorMessage = "Не удалось запустить сервер для OAuth: $e";
      if (!(_nativeOAuthCompleter?.isCompleted == true)) _nativeOAuthCompleter?.complete(false);
      rethrow;
    }
  }

  Future<void> _stopNativeOAuthHttpServer() async {
    if (_nativeOAuthHttpServer != null) {
      await _nativeOAuthHttpServer!.close(force: true);
      _nativeOAuthHttpServer = null;
      debugPrint('AuthState (_stopNativeOAuthHttpServer): Server stopped.');
    }
  }

  // ИЗМЕНЕННЫЙ ХЕНДЛЕР
  Future<shelf.Response> _nativeOAuthLandingHandler(shelf.Request request) async {
    debugPrint('AuthState (_nativeOAuthLandingHandler): Received: ${request.requestedUri}');
    bool success = false;
    String responseMessage = "Ошибка авторизации. Пожалуйста, попробуйте снова.";
    String script = '<script>setTimeout(function() { window.close(); }, 500);</script>';

    try {
      final accessToken = request.requestedUri.queryParameters['access_token'];
      final refreshToken = request.requestedUri.queryParameters['refresh_token'];
      final providerFromQuery = request.requestedUri.queryParameters['provider'] ?? "неизвестного провайдера";
      final errorParam = request.requestedUri.queryParameters['error'];
      final errorDescriptionParam = request.requestedUri.queryParameters['error_description'];

      if (errorParam != null || errorDescriptionParam != null) {
        _oauthErrorMessage = "Ошибка OAuth от $providerFromQuery: ${errorDescriptionParam ?? errorParam}";
        responseMessage = 'Ошибка авторизации: ${errorDescriptionParam ?? errorParam}';
      } else if (accessToken != null && accessToken.isNotEmpty) {
        await _apiService.saveAccessTokenForNative(accessToken);
        debugPrint('AuthState (_nativeOAuthLandingHandler): Access token saved.');
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _secureStorage.write(key: _refreshTokenKeySecure, value: refreshToken);
          debugPrint('AuthState (_nativeOAuthLandingHandler): Native refresh token saved.');
        }

        await _checkInitialAuthStatus();

        if (_isLoggedIn) {
          _oauthErrorMessage = null;
          success = true;
          responseMessage = 'Авторизация успешна!';
        } else {
          _oauthErrorMessage = _errorMessage ?? "Не удалось войти после OAuth через $providerFromQuery.";
          responseMessage = _oauthErrorMessage ?? 'Ошибка входа после OAuth.';
        }
      } else {
        _oauthErrorMessage = "Токены не найдены в URL после OAuth через $providerFromQuery.";
        responseMessage = 'Ошибка авторизации: токены не предоставлены.';
      }
    } catch (e) {
      _oauthErrorMessage = "Внутренняя ошибка обработки OAuth: $e";
      responseMessage = 'Внутренняя ошибка сервера.';
      debugPrint('AuthState (_nativeOAuthLandingHandler) Error: $e');
    } finally {
      if (!(_nativeOAuthCompleter?.isCompleted == true)) {
        _nativeOAuthCompleter?.complete(success);
      }
      // ОСТАНАВЛИВАЕМ СЕРВЕР ПОСЛЕ ОБРАБОТКИ, НО ПЕРЕД ОТПРАВКОЙ ОТВЕТА
      // Чтобы избежать гонки, сделаем это асинхронно с небольшой задержкой
      Future.delayed(const Duration(seconds: 1), () => _stopNativeOAuthHttpServer());
    }

    final responseBody = '<html><head><meta charset="utf-8"></head><body><p>$responseMessage</p><p>Это окно закроется автоматически.</p>$script</body></html>';
    return shelf.Response.ok(responseBody, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  // ... (остальные методы без изменений) ...
  Future<bool> sendConfirmationEmail(String email) async {
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; notifyListeners();
    try {
      await _apiService.sendConfirmationEmail(email);
      _isLoading = false; notifyListeners(); return true;
    } on ApiException catch (e) { _errorMessage = e.message;
    } on NetworkException catch (e) { _errorMessage = e.message;
    } catch (e) { _errorMessage = 'Ошибка отправки кода: ${e.toString()}'; }
    _isLoading = false; notifyListeners(); return false;
  }

  Future<bool> confirmEmail(String email, String code) async {
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; notifyListeners();
    try {
      await _apiService.confirmEmail(email, code);
      _emailPendingConfirmation = null;
      _isLoading = false; notifyListeners(); return true;
    } on ApiException catch (e) { _errorMessage = e.message;
    } on NetworkException catch (e) { _errorMessage = e.message;
    } catch (e) { _errorMessage = 'Ошибка подтверждения email: ${e.toString()}'; }
    _isLoading = false; notifyListeners(); return false;
  }

  Future<bool> updateUserProfile({
    String? login,
    bool? resetAvatar,
    Map<String, dynamic>? avatarFile,
  }) async {
    if (!_isLoggedIn || _currentUser == null) {
      _errorMessage = "Пользователь не авторизован для обновления профиля.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    String? operationError;
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedProfile = await _apiService.updateUserProfile(
        login: login,
        resetAvatar: resetAvatar,
        avatarFile: avatarFile,
      );
      _currentUser = updatedProfile;
      _isLoading = false;
      debugPrint("AuthState (updateUserProfile) SUCCESS: currentUser: ${_currentUser?.login}");
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      operationError = e.message;
    } on NetworkException catch (e) {
      operationError = e.message;
    } catch (e) {
      operationError = 'Ошибка обновления профиля: ${e.toString()}';
    }

    _errorMessage = operationError;
    _isLoading = false;
    debugPrint("AuthState (updateUserProfile) FAILED: error: $_errorMessage");
    notifyListeners();
    return false;
  }

  Future<bool> patchUserProfile({
    String? theme,
    String? accentColor,
    String? emailNotificationsLevel,
    String? pushNotificationsTasksLevel,
    bool? pushNotificationsChatMentions,
    bool? taskDeadlineRemindersEnabled,
    String? taskDeadlineReminderTimePreference,
  }) async {
    if (!_isLoggedIn || _currentUser == null) {
      _errorMessage = "Пользователь не авторизован.";
      notifyListeners();
      return false;
    }

    final Map<String, dynamic> patchData = {};
    if (theme != null) patchData['theme'] = theme;
    if (accentColor != null) patchData['accent_color'] = accentColor;
    if (emailNotificationsLevel != null) patchData['email_notifications_level'] = emailNotificationsLevel;
    if (pushNotificationsTasksLevel != null) patchData['push_notifications_tasks_level'] = pushNotificationsTasksLevel;
    if (pushNotificationsChatMentions != null) patchData['push_notifications_chat_mentions'] = pushNotificationsChatMentions;
    if (taskDeadlineRemindersEnabled != null) patchData['task_deadline_reminders_enabled'] = taskDeadlineRemindersEnabled;
    if (taskDeadlineReminderTimePreference != null) patchData['task_deadline_reminder_time_preference'] = taskDeadlineReminderTimePreference;

    if (patchData.isEmpty) {
      debugPrint("patchUserProfile called with no data to update.");
      return true;
    }

    final oldUser = _currentUser;
    _currentUser = _applyPatchToLocalUser(patchData);
    notifyListeners();

    try {
      final updatedProfileFromServer = await _apiService.patchUserProfile(patchData);
      _currentUser = updatedProfileFromServer;
      notifyListeners();
      return true;
    } catch (e) {
      _currentUser = oldUser;
      _errorMessage = "Ошибка сохранения настроек: $e";
      notifyListeners();
      return false;
    }
  }

  UserProfile? _applyPatchToLocalUser(Map<String, dynamic> patchData) {
    if (_currentUser == null) return null;

    final currentJson = _currentUser!.toJson();
    currentJson.addAll(patchData);
    return UserProfile.fromJson(currentJson);
  }

  Future<bool> deleteUserAccount() async {
    if (!_isLoggedIn) return false;
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; notifyListeners();
    try {
      await _apiService.deleteUserAccount();
      _isLoggedIn = false;
      _currentUser = null;
      _emailPendingConfirmation = null;
      _pendingInviteToken = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) { _errorMessage = e.message;
    } on NetworkException catch (e) { _errorMessage = e.message;
    } catch (e) { _errorMessage = 'Ошибка удаления аккаунта: ${e.toString()}'; }
    _isLoading = false; notifyListeners(); return false;
  }

  void clearErrorMessage() { if (_errorMessage != null) { _errorMessage = null; notifyListeners(); } }
  void clearOAuthError() { if (_oauthErrorMessage != null) { _oauthErrorMessage = null; notifyListeners(); } }
  void setOAuthError(String error) { _oauthErrorMessage = error; _errorMessage = null; _emailPendingConfirmation = null; _isLoading = false; notifyListeners(); }
  void clearEmailPendingConfirmation() { if (_emailPendingConfirmation != null) { _emailPendingConfirmation = null; notifyListeners(); } }
  void setEmailPendingConfirmation(String? email) { if (_emailPendingConfirmation != email) { _emailPendingConfirmation = email; notifyListeners(); } }

  void setPendingInviteToken(String? token) {
    if (_pendingInviteToken != token) {
      _pendingInviteToken = token;
      debugPrint("AuthState: Pending invite token set to: $token");
    }
  }

  void clearPendingInviteToken() {
    if (_pendingInviteToken != null) {
      _pendingInviteToken = null;
      debugPrint("AuthState: Pending invite token cleared.");
    }
  }

  @override
  void dispose() {
    _oauthRedirectControllerWeb.close();
    _stopNativeOAuthHttpServer();
    super.dispose();
  }
}