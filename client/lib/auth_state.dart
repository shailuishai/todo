// lib/auth_state.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpServer, Platform;

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
  bool _isLoading = true; // Изначально true, пока идет _checkInitialAuthStatus
  bool _initialAuthCheckCompleted = false;

  String? _errorMessage;
  UserProfile? _currentUser;
  String? _emailPendingConfirmation;
  String? _oauthErrorMessage;
  String? _pendingInviteToken; // <<< ПОЛЕ ДЛЯ ТОКЕНА ПРИГЛАШЕНИЯ >>>


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
  String? get pendingInviteToken => _pendingInviteToken; // <<< ГЕТТЕР ДЛЯ ТОКЕНА >>>


  AuthState({required ApiService apiService}) : _apiService = apiService {
    _checkInitialAuthStatus();
  }

  Future<void> _checkInitialAuthStatus() async {
    // Устанавливаем isLoading в true в начале, если проверка еще не завершена
    if (!_initialAuthCheckCompleted) {
      _isLoading = true;
      // Уведомляем только если это самый первый запуск _checkInitialAuthStatus,
      // чтобы избежать лишних перестроек, если он вызывается повторно.
      // Однако, если _isLoading уже true, notifyListeners() не сделает хуже.
      notifyListeners();
    }

    _initialAuthCheckCompleted = false; // Сбрасываем перед началом проверки
    _emailPendingConfirmation = null;
    _oauthErrorMessage = null;
    // _pendingInviteToken НЕ сбрасываем здесь, он мог быть установлен парсером URL
    // и должен быть обработан после проверки логина.

    try {
      debugPrint("AuthState (_checkInitialAuthStatus): Attempting to get user profile with existing access token (if any).");
      final user = await _apiService.getUserProfile(); // Этот метод должен сам обрабатывать TokenRefreshedException
      _currentUser = user;
      _isLoggedIn = true;
      _errorMessage = null;
      debugPrint("AuthState (_checkInitialAuthStatus): Success with existing access token. User: ${_currentUser?.login}");

      // Если пользователь залогинен и есть ожидающий токен, он будет обработан в AppRouterDelegate._onAuthStateChanged
      if (_isLoggedIn && _pendingInviteToken != null) {
        debugPrint("AuthState (_checkInitialAuthStatus): User logged in, pending invite token '$_pendingInviteToken' is ready to be processed by router.");
      }

    } on TokenRefreshedException {
      debugPrint("AuthState (_checkInitialAuthStatus): TokenRefreshedException caught. Attempting to get profile again.");
      try {
        final user = await _apiService.getUserProfile(); // Повторная попытка после исключения
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
        // _pendingInviteToken остается, чтобы пользователь мог залогиниться и потом обработать его
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
      _applyProfileUISettings(_currentUser!);
    } else {
      _isLoggedIn = false; // Убеждаемся, что false, если нет currentUser
      _currentUser = null;
    }

    _isLoading = false; // Завершаем общую загрузку
    _initialAuthCheckCompleted = true; // <<< УСТАНАВЛИВАЕМ ФЛАГ В КОНЦЕ >>>
    debugPrint("AuthState (_checkInitialAuthStatus) FINISHING: isLoggedIn: $_isLoggedIn, initialAuthCheckCompleted: $_initialAuthCheckCompleted, currentUser: ${_currentUser?.login}, error: $_errorMessage, pendingToken: $_pendingInviteToken");
    notifyListeners();
  }

  Future<void> checkInitialAuthStatusAgain() async {
    debugPrint("AuthState: Manually re-checking initial auth status via checkInitialAuthStatusAgain().");
    // _isLoading = true; // _checkInitialAuthStatus сам управляет этим флагом
    // notifyListeners(); // _checkInitialAuthStatus вызовет notifyListeners
    await _checkInitialAuthStatus();
  }

  void _applyProfileUISettings(UserProfile profile) {
    debugPrint("AuthState (_applyProfileUISettings): Applying UI settings from profile (login: ${profile.login}, email: ${profile.email}). UserID: ${profile.userId}");
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
      // Access token уже должен быть сохранен в ApiService._saveAccessToken

      // После успешного signIn, мы немедленно вызываем _checkInitialAuthStatus.
      // _checkInitialAuthStatus обновит _isLoggedIn, _currentUser, и вызовет notifyListeners().
      // Если был _pendingInviteToken, он будет обработан в AppRouterDelegate при следующем _onAuthStateChanged.
      await _checkInitialAuthStatus(); // Это вызовет notifyListeners() в конце
      return _isLoggedIn; // Возвращаем актуальное состояние после _checkInitialAuthStatus

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
    // Блок _isLoading = false; notifyListeners(); не нужен здесь, т.к. _checkInitialAuthStatus сделает это.
  }

  Future<void> logout() async {
    _errorMessage = null;
    _oauthErrorMessage = null;
    _emailPendingConfirmation = null;
    _pendingInviteToken = null; // <<< СБРАСЫВАЕМ ТОКЕН ПРИ ЛОГАУТЕ >>>

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
    _isLoading = true; _oauthErrorMessage = null; _errorMessage = null; _emailPendingConfirmation = null; notifyListeners();
    String backendInitiationUrl = _apiService.getOAuthUrl(provider);

    if (kIsWeb) {
      debugPrint('AuthState (initiateOAuth): Web. URL: $backendInitiationUrl');
      _oauthRedirectControllerWeb.add(backendInitiationUrl);
      Future.delayed(const Duration(seconds: 10), () {
        if (_isLoading) {
          _isLoading = false;
          _oauthErrorMessage = "Не удалось инициировать OAuth через $provider.";
          notifyListeners();
        }
      });
    } else {
      backendInitiationUrl += '?native_final_redirect_uri=${Uri.encodeComponent(nativeClientLandingUri)}';
      debugPrint('AuthState (initiateOAuth): Native. Backend URL: $backendInitiationUrl. Landing: $nativeClientLandingUri');
      _nativeOAuthCompleter = Completer<bool>();
      try {
        await _startNativeOAuthHttpServer();
        final uri = Uri.parse(backendInitiationUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Could not launch $uri for provider $provider');
        }
        bool success = await _nativeOAuthCompleter!.future;
        if (!success && _oauthErrorMessage == null) {
          _oauthErrorMessage = "Авторизация через $provider не была завершена или была отменена.";
        }
      } catch (e) {
        _oauthErrorMessage = "Ошибка запуска OAuth $provider: $e";
        if (!(_nativeOAuthCompleter?.isCompleted == true)) _nativeOAuthCompleter?.complete(false);
      } finally {
        await _stopNativeOAuthHttpServer();
        _nativeOAuthCompleter = null;
        _isLoading = false;
        notifyListeners();
      }
    }
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

  Future<shelf.Response> _nativeOAuthLandingHandler(shelf.Request request) async {
    debugPrint('AuthState (_nativeOAuthLandingHandler): Received: ${request.requestedUri}');
    bool success = false;
    String responseMessage = "Ошибка авторизации. Пожалуйста, попробуйте снова. Можете закрыть эту вкладку.";

    try {
      final accessToken = request.requestedUri.queryParameters['access_token'];
      final refreshToken = request.requestedUri.queryParameters['refresh_token'];
      final providerFromQuery = request.requestedUri.queryParameters['provider'] ?? "неизвестного провайдера";
      final errorParam = request.requestedUri.queryParameters['error'];
      final errorDescriptionParam = request.requestedUri.queryParameters['error_description'];

      if (errorParam != null || errorDescriptionParam != null) {
        _oauthErrorMessage = "Ошибка OAuth от $providerFromQuery: ${errorDescriptionParam ?? errorParam}";
        responseMessage = 'Ошибка авторизации: ${errorDescriptionParam ?? errorParam}. Можете закрыть эту вкладку.';
      } else if (accessToken != null && accessToken.isNotEmpty) {
        await _apiService.saveAccessTokenForNative(accessToken);
        debugPrint('AuthState (_nativeOAuthLandingHandler): Access token saved.');
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _secureStorage.write(key: _refreshTokenKeySecure, value: refreshToken);
          debugPrint('AuthState (_nativeOAuthLandingHandler): Native refresh token saved to secure storage.');
        } else {
          debugPrint('AuthState (_nativeOAuthLandingHandler): Refresh token not found/empty in callback for native client.');
        }

        await _checkInitialAuthStatus();

        if (_isLoggedIn) {
          _oauthErrorMessage = null;
          success = true;
          responseMessage = 'Авторизация успешна! Можете вернуться в приложение.';
        } else {
          _oauthErrorMessage = _errorMessage ?? "Не удалось войти после OAuth через $providerFromQuery.";
          responseMessage = _oauthErrorMessage ?? 'Ошибка входа после OAuth. Можете закрыть эту вкладку.';
        }
      } else {
        _oauthErrorMessage = "Токены не найдены в URL после OAuth через $providerFromQuery.";
        responseMessage = 'Ошибка авторизации: токены не предоставлены. Можете закрыть эту вкладку.';
      }
    } catch (e) {
      _oauthErrorMessage = "Внутренняя ошибка обработки OAuth: $e";
      responseMessage = 'Внутренняя ошибка сервера. Можете закрыть эту вкладку.';
      debugPrint('AuthState (_nativeOAuthLandingHandler) Error: $e');
    } finally {
      if (!(_nativeOAuthCompleter?.isCompleted == true)) {
        _nativeOAuthCompleter?.complete(success);
      }
    }
    return shelf.Response.ok(responseMessage, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  Future<void> handleOAuthCallback(Uri uri) async {
    debugPrint("AuthState (handleOAuthCallback Web): Received URI: $uri. Will re-check auth status.");
    _isLoading = true;
    _oauthErrorMessage = null;
    notifyListeners();

    await _checkInitialAuthStatus();

    if (!_isLoggedIn) {
      _oauthErrorMessage = _errorMessage ?? "Не удалось завершить OAuth авторизацию.";
      debugPrint("AuthState (handleOAuthCallback Web): OAuth failed or cookies not set properly. Error: $_oauthErrorMessage");
    }
    _isLoading = false;
    notifyListeners();
  }

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
    String? login, String? theme, String? accentColor,
    bool? isSidebarCollapsed, bool? resetAvatar, Map<String, dynamic>? avatarFile,
    bool? notificationsEmailEnabled,
    bool? notificationsPushTaskAssigned,
    bool? notificationsPushTaskDeadline,
    bool? notificationsPushTeamMention,
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
          login: login, theme: theme, accentColor: accentColor,
          isSidebarCollapsed: isSidebarCollapsed, resetAvatar: resetAvatar, avatarFile: avatarFile,
          notificationsEmailEnabled: notificationsEmailEnabled,
          notificationsPushTaskAssigned: notificationsPushTaskAssigned,
          notificationsPushTaskDeadline: notificationsPushTaskDeadline,
          notificationsPushTeamMention: notificationsPushTeamMention
      );
      _currentUser = updatedProfile;
      _applyProfileUISettings(updatedProfile);
      _isLoading = false;
      debugPrint("AuthState (updateUserProfile) SUCCESS: currentUser: ${_currentUser?.login}");
      notifyListeners();
      return true;
    } on ApiException catch (e) { operationError = e.message;
    } on NetworkException catch (e) { operationError = e.message;
    } catch (e) { operationError = 'Ошибка обновления профиля: ${e.toString()}'; }

    _errorMessage = operationError;
    _isLoading = false;
    debugPrint("AuthState (updateUserProfile) FAILED: error: $_errorMessage");
    notifyListeners();
    return false;
  }

  Future<bool> deleteUserAccount() async {
    if (!_isLoggedIn) return false;
    _isLoading = true; _errorMessage = null; _oauthErrorMessage = null; notifyListeners();
    try {
      await _apiService.deleteUserAccount();
      _isLoggedIn = false;
      _currentUser = null;
      _emailPendingConfirmation = null;
      _pendingInviteToken = null; // <<< СБРОС ПРИ УДАЛЕНИИ АККАУНТА >>>
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

  // <<< МЕТОДЫ ДЛЯ УПРАВЛЕНИЯ PENDING INVITE TOKEN >>>
  void setPendingInviteToken(String? token) {
    if (_pendingInviteToken != token) {
      _pendingInviteToken = token;
      debugPrint("AuthState: Pending invite token set to: $token");
      // Не вызываем notifyListeners(), чтобы не спровоцировать лишних перестроек,
      // этот токен будет проверен при следующем изменении состояния аутентификации или навигации.
      // Если пользователь не залогинен, notifyListeners() из checkInitialAuthStatus или signIn/signUp
      // вызовет обновление AppRouterDelegate, который увидит токен.
      // Если пользователь уже залогинен и получает токен (не через URL), то нужно будет
      // инициировать навигацию явно. Но здесь это для случая получения токена из URL.
    }
  }

  void clearPendingInviteToken() {
    if (_pendingInviteToken != null) {
      _pendingInviteToken = null;
      debugPrint("AuthState: Pending invite token cleared.");
      // notifyListeners(); // Возможно, потребуется, если это состояние используется где-то в UI напрямую
    }
  }
  // <<< КОНЕЦ НОВЫХ МЕТОДОВ >>>


  @override
  void dispose() {
    _oauthRedirectControllerWeb.close();
    _stopNativeOAuthHttpServer();
    super.dispose();
  }
}