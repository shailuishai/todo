// lib/screens/auth_screen.dart
import 'package:client/core/constants/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/utils/responsive_utils.dart';
import '../widgets/CustomInputField.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/auth/LoginForm.dart';
import '../widgets/auth/RegisterForm.dart';
import '../widgets/auth/auth_screen_logo.dart';
import '../widgets/auth/social_auth_button.dart';
import '../widgets/auth/auth_form_container.dart';

import '../core/constants/app_assets.dart';
import '../auth_state.dart';

// Виджет для отображения сообщения о необходимости подтверждения email
class EmailConfirmationPrompt extends StatelessWidget {
  final String email;
  final VoidCallback onResendCode;
  final VoidCallback onGoToCodeInput;
  final bool isLoadingResend;

  const EmailConfirmationPrompt({
    super.key,
    required this.email,
    required this.onResendCode,
    required this.onGoToCodeInput,
    this.isLoadingResend = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_unread_outlined, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Подтвердите ваш Email',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Мы отправили письмо с кодом подтверждения на адрес $email. Пожалуйста, проверьте вашу почту.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            text: 'Отправить код повторно',
            onPressed: isLoadingResend ? null : onResendCode,
            isLoading: isLoadingResend,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: isLoadingResend ? null : onGoToCodeInput,
            child: const Text('Ввести код подтверждения'),
          ),
        ],
      ),
    );
  }
}

// Виджет для ввода кода подтверждения
class EmailConfirmationCodeInput extends StatefulWidget {
  final String email;
  final Function(String code) onConfirmCode;
  final VoidCallback onCancel;
  final bool isLoading;

  const EmailConfirmationCodeInput({
    super.key,
    required this.email,
    required this.onConfirmCode,
    required this.onCancel,
    this.isLoading = false,
  });

  @override
  State<EmailConfirmationCodeInput> createState() => _EmailConfirmationCodeInputState();
}

class _EmailConfirmationCodeInputState extends State<EmailConfirmationCodeInput> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onConfirmCode(_codeController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pin_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Введите код подтверждения',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Код был отправлен на ${widget.email}.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            CustomInputField(
              controller: _codeController,
              label: 'Код подтверждения',
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autofocus: true,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите код';
                }
                if (value.trim().length < 4) {
                  return 'Код слишком короткий';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              text: 'Подтвердить Email',
              onPressed: widget.isLoading ? null : _submit,
              isLoading: widget.isLoading,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.isLoading ? null : widget.onCancel,
              child: const Text('Отмена / Отправить код заново'),
            ),
          ],
        ),
      ),
    );
  }
}


class AuthScreen extends StatefulWidget {
  final String? pendingInviteToken; // <<< ДОБАВЛЕНО ПОЛЕ >>>

  const AuthScreen({super.key, this.pendingInviteToken}); // <<< ОБНОВЛЕН КОНСТРУКТОР >>>

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _usernameController;
  late TextEditingController _confirmPasswordController;

  late FocusNode _loginEmailFocusNode;
  late FocusNode _loginPasswordFocusNode;
  late FocusNode _registerUsernameFocusNode;
  late FocusNode _registerEmailFocusNode;
  late FocusNode _registerPasswordFocusNode;
  late FocusNode _registerConfirmPasswordFocusNode;

  StreamSubscription? _oauthSubscription;
  bool _showCodeInputPrompt = false;

  AuthState? _authStateInstance;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _usernameController = TextEditingController();
    _confirmPasswordController = TextEditingController();

    _loginEmailFocusNode = FocusNode();
    _loginPasswordFocusNode = FocusNode();
    _registerUsernameFocusNode = FocusNode();
    _registerEmailFocusNode = FocusNode();
    _registerPasswordFocusNode = FocusNode();
    _registerConfirmPasswordFocusNode = FocusNode();

    _authStateInstance = Provider.of<AuthState>(context, listen: false);
    _oauthSubscription = _authStateInstance!.oauthRedirectStreamWeb.listen((url) {
      if (url != null && url.isNotEmpty) {
        _launchURL(url);
      }
    });

    // <<< УСТАНОВКА PENDING TOKEN ИЗ WIDGET >>>
    if (widget.pendingInviteToken != null && widget.pendingInviteToken!.isNotEmpty) {
      _authStateInstance!.setPendingInviteToken(widget.pendingInviteToken);
      debugPrint("AuthScreen initState: pendingInviteToken '${widget.pendingInviteToken}' from widget passed to AuthState.");
    }


    _authStateInstance!.addListener(_handleAuthStateChanges);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _authStateInstance != null) {
        _handleInitialAuthStateError(_authStateInstance!);
      }
    });
  }

  void _handleAuthStateChanges() {
    if (!mounted || _authStateInstance == null) return;
    final authState = _authStateInstance!;

    if (authState.isLoggedIn && _showCodeInputPrompt) {
      setState(() { _showCodeInputPrompt = false; });
      // Если есть pendingInviteToken, AppRouterDelegate обработает его
      return;
    }

    if ((authState.errorMessage != null && authState.errorMessage!.contains('Email не подтвержден') && !authState.isLoggedIn) ||
        (authState.emailPendingConfirmation != null && !_isLogin && !_showCodeInputPrompt)) {
      if (!_showCodeInputPrompt) {
        final emailForPrompt = _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : authState.emailPendingConfirmation;

        if (emailForPrompt != null && emailForPrompt.isNotEmpty) {
          if ((_isLogin && authState.errorMessage != null && authState.errorMessage!.contains('Email не подтвержден')) ||
              (!_isLogin && authState.emailPendingConfirmation != null)) {
            setState(() {
              _showCodeInputPrompt = true;
            });
          }
        }
      }
    } else if (_showCodeInputPrompt && authState.emailPendingConfirmation == null && !authState.isLoading) {
      if (!authState.isLoggedIn) {
        setState(() {
          _showCodeInputPrompt = false;
          if (!_isLogin) _isLogin = true;
        });
      }
    }

    if (authState.oauthErrorMessage != null && authState.oauthErrorMessage!.isNotEmpty) {
      _showErrorSnackbar(authState.oauthErrorMessage!);
      authState.clearOAuthError();
    }
  }

  void _handleInitialAuthStateError(AuthState authState) {
    if (mounted && authState.errorMessage != null && !authState.isLoggedIn) {
      if (authState.errorMessage!.contains('Email не подтвержден')) {
        final emailForPrompt = _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : authState.emailPendingConfirmation;
        if (emailForPrompt != null && emailForPrompt.isNotEmpty) {
          setState(() {
            if (_isLogin) _showCodeInputPrompt = true;
          });
        }
      } else {
        _showErrorSnackbar(authState.errorMessage!);
      }
      authState.clearErrorMessage();
    }
    if (mounted && authState.oauthErrorMessage != null && !authState.isLoggedIn) {
      _showErrorSnackbar(authState.oauthErrorMessage!);
      authState.clearOAuthError();
    }
  }

  @override
  void dispose() {
    _authStateInstance?.removeListener(_handleAuthStateChanges);
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    _loginEmailFocusNode.dispose();
    _loginPasswordFocusNode.dispose();
    _registerUsernameFocusNode.dispose();
    _registerEmailFocusNode.dispose();
    _registerPasswordFocusNode.dispose();
    _registerConfirmPasswordFocusNode.dispose();
    _oauthSubscription?.cancel();
    super.dispose();
  }

  void _showErrorSnackbar(String message) {
    if (mounted && message.isNotEmpty) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, duration: const Duration(seconds: 5)),
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted && message.isNotEmpty) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 3)),
      );
    }
  }

  void _toggleAuthMode() {
    if (_authStateInstance?.isLoading ?? true) return;
    setState(() {
      _isLogin = !_isLogin;
      _autovalidateMode = AutovalidateMode.disabled;
      _showCodeInputPrompt = false;
      _authStateInstance?.clearEmailPendingConfirmation();
      _authStateInstance?.clearErrorMessage();
      _authStateInstance?.clearOAuthError();
      // _authStateInstance?.clearPendingInviteToken(); // Не очищаем здесь, он может быть нужен
      _emailController.clear();
      _passwordController.clear();
      _usernameController.clear();
      _confirmPasswordController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loginFormKey.currentState?.reset();
        _registerFormKey.currentState?.reset();
      });
    });
  }

  Future<void> _submitForm() async {
    final authState = _authStateInstance;
    if (authState == null || authState.isLoading) return;

    setState(() { _autovalidateMode = AutovalidateMode.onUserInteraction; });
    final formKey = _isLogin ? _loginFormKey : _registerFormKey;
    final isValid = formKey.currentState?.validate() ?? false;

    if (!isValid) return;
    authState.clearErrorMessage();
    authState.clearOAuthError();

    bool success = false;
    String submittedEmail = _emailController.text.trim();

    if (_isLogin) {
      success = await authState.signIn(
        emailOrLogin: submittedEmail,
        password: _passwordController.text.trim(),
      );
      // После успешного signIn, AuthState.isLoggedIn станет true,
      // и AppRouterDelegate._onAuthStateChanged должен обработать _pendingInviteToken, если он есть.
    } else { // Регистрация
      success = await authState.signUp(
        email: submittedEmail,
        login: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (success && mounted) {
        if (authState.emailPendingConfirmation != null) {
          bool emailSent = await authState.sendConfirmationEmail(authState.emailPendingConfirmation!);
          if (mounted) {
            if (emailSent) {
              _showSuccessSnackbar('Код подтверждения отправлен на ${authState.emailPendingConfirmation}.');
              setState(() { _showCodeInputPrompt = true; });
            } else {
              _showErrorSnackbar(authState.errorMessage ?? 'Не удалось отправить код подтверждения.');
            }
          }
        } else {
          _showErrorSnackbar('Не удалось получить email для отправки кода подтверждения после регистрации.');
        }
        return; // Выходим после начала процесса подтверждения email
      }
    }

    // Этот блок выполняется, если signIn был неуспешен или signUp не требовал подтверждения email (что сейчас не так)
    if (mounted && !success && authState.errorMessage != null) {
      if (authState.errorMessage!.contains('Email не подтвержден')) {
        if (authState.emailPendingConfirmation == null && submittedEmail.isNotEmpty && submittedEmail.contains('@')) {
          authState.setEmailPendingConfirmation(submittedEmail);
        }
        setState(() { _showCodeInputPrompt = true; });
      } else {
        _showErrorSnackbar(authState.errorMessage!);
      }
    }
    // Если success=true после signIn, то AppRouterDelegate должен перенаправить.
  }

  Future<void> _handleSocialLogin(String provider) async {
    if (_authStateInstance?.isLoading ?? true) return;
    _authStateInstance?.clearErrorMessage();
    _authStateInstance?.clearOAuthError();
    // Просто вызываем initiateOAuth с провайдером.
    // AuthState сам разберется, веб это или натив.
    _authStateInstance?.initiateOAuth(provider);
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (kIsWeb) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      } else {
        if (mounted) _showErrorSnackbar('Не удалось открыть URL: $url');
      }
    } else {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _showErrorSnackbar('Не удалось открыть URL: $url');
      }
    }
  }

  Future<void> _resendConfirmationCode() async {
    if (_authStateInstance == null) return;
    final authState = _authStateInstance!;
    final emailToResend = authState.emailPendingConfirmation ?? _emailController.text.trim();

    if (emailToResend.isEmpty || !emailToResend.contains('@')) {
      _showErrorSnackbar('Введите корректный Email для повторной отправки кода.');
      return;
    }
    if (authState.emailPendingConfirmation == null || authState.emailPendingConfirmation != emailToResend) {
      authState.setEmailPendingConfirmation(emailToResend);
    }

    final success = await authState.sendConfirmationEmail(emailToResend);
    if (mounted) {
      if (success) {
        _showSuccessSnackbar('Новый код подтверждения отправлен на $emailToResend.');
        if (!_showCodeInputPrompt) {
          setState(() { _showCodeInputPrompt = true; });
        }
      } else {
        _showErrorSnackbar(authState.errorMessage ?? 'Не удалось отправить код.');
      }
    }
  }

  Future<void> _handleConfirmCode(String code) async {
    if (_authStateInstance == null) return;
    final authState = _authStateInstance!;
    final emailToConfirm = authState.emailPendingConfirmation ?? _emailController.text.trim();

    if (emailToConfirm.isEmpty || !emailToConfirm.contains('@')) {
      _showErrorSnackbar("Email для подтверждения не найден или некорректен.");
      setState(() {
        _showCodeInputPrompt = false;
        authState.clearEmailPendingConfirmation();
      });
      return;
    }

    final emailUsedForConfirmation = emailToConfirm;
    final success = await authState.confirmEmail(emailUsedForConfirmation, code);

    if (mounted) {
      if (success) {
        _showSuccessSnackbar('Email успешно подтвержден! Теперь вы можете войти.');
        setState(() {
          _isLogin = true;
          _showCodeInputPrompt = false;
          _emailController.text = emailUsedForConfirmation;
          _passwordController.clear();
          _usernameController.clear();
          _confirmPasswordController.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) FocusScope.of(context).requestFocus(_loginPasswordFocusNode);
          });
        });
      } else {
        _showErrorSnackbar(authState.errorMessage ?? 'Неверный код или другая ошибка.');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = Provider.of<AuthState>(context);

    Widget currentScreenContent;

    if (_showCodeInputPrompt && authState.emailPendingConfirmation != null) {
      currentScreenContent = AuthFormContainer(
        key: const ValueKey('code_input_prompt'),
        child: EmailConfirmationCodeInput(
          email: authState.emailPendingConfirmation!,
          isLoading: authState.isLoading,
          onConfirmCode: _handleConfirmCode,
          onCancel: () {
            setState(() {
              _showCodeInputPrompt = false;
              if (!_isLogin && authState.emailPendingConfirmation != null) {
                // Остаемся в режиме "prompt for resend"
              } else {
                authState.clearEmailPendingConfirmation();
                _isLogin = true; // Возвращаемся к логину по умолчанию
              }
            });
          },
        ),
      );
    } else if (!_isLogin && authState.emailPendingConfirmation != null) {
      // Показываем EmailConfirmationPrompt если: мы в режиме регистрации И email ожидает подтверждения
      currentScreenContent = AuthFormContainer(
        key: const ValueKey('email_confirm_prompt'),
        child: EmailConfirmationPrompt(
          email: authState.emailPendingConfirmation!,
          isLoadingResend: authState.isLoading,
          onResendCode: _resendConfirmationCode,
          onGoToCodeInput: () {
            setState(() { _showCodeInputPrompt = true; });
          },
        ),
      );
    }
    else { // Обычная форма логина или регистрации
      Widget formSpecificContent = _isLogin
          ? LoginForm(
        key: const ValueKey('login_form'),
        formKey: _loginFormKey,
        emailController: _emailController,
        passwordController: _passwordController,
        onSubmit: _submitForm,
        autovalidateMode: _autovalidateMode,
      )
          : RegisterForm(
        key: const ValueKey('register_form'),
        formKey: _registerFormKey,
        usernameController: _usernameController,
        emailController: _emailController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        onSubmit: _submitForm,
        autovalidateMode: _autovalidateMode,
      );

      currentScreenContent = AuthFormContainer(
        key: ValueKey<bool>(_isLogin), // Ключ для переключения анимации
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuthScreenLogo(),
            const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                final bool isLoginFormKey = child.key == const ValueKey('login_form');
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(isLoginFormKey ? -0.2 : 0.2, 0.0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: formSpecificContent,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              text: _isLogin ? AppStrings.loginTitle : AppStrings.registerTitle,
              onPressed: authState.isLoading ? null : _submitForm,
              isLoading: authState.isLoading,
            ),
            // Показ ошибки, если это не ошибка "Email не подтвержден" ИЛИ если мы не в процессе показа промпта
            if (authState.errorMessage != null && authState.oauthErrorMessage == null &&
                !( ( (_showCodeInputPrompt || (!_isLogin && authState.emailPendingConfirmation != null)) &&
                    authState.errorMessage!.contains('Email не подтвержден')) )
            )
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  authState.errorMessage!,
                  style: TextStyle(color: colorScheme.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            if (authState.oauthErrorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  authState.oauthErrorMessage!,
                  style: TextStyle(color: colorScheme.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            _buildSocialAuthRow(context, authState.isLoading),
            const SizedBox(height: 24),
            _buildToggleModeLink(theme, authState.isLoading),
            // <<< ОТОБРАЖЕНИЕ СООБЩЕНИЯ О ТОКЕНЕ ПРИГЛАШЕНИЯ >>>
            if (widget.pendingInviteToken != null && widget.pendingInviteToken!.isNotEmpty && !authState.isLoggedIn && !authState.isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: theme.colorScheme.secondary, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, color: theme.colorScheme.secondary, size: 20),
                        const SizedBox(height: 8),
                        Text(
                          'После входа или регистрации вы будете автоматически добавлены в команду по приглашению.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtil.isMobile(context) ? 16.0 : 24.0,
            vertical: 24.0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580), // Максимальная ширина контента
            child: AnimatedSize( // Для плавной смены размера при переключении
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutExpo,
                switchOutCurve: Curves.easeInExpo,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(
                    key: child.key, // Важно для правильной работы AnimatedSwitcher
                    scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: const ElasticOutCurve(0.7))), // Немного "пружинистый" эффект
                    child: FadeTransition(
                      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  // Это позволяет старым и новым виджетам анимироваться одновременно
                  return Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: currentScreenContent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialAuthRow(BuildContext context, bool isLoading) {
    final bool isNarrow = MediaQuery.of(context).size.width < 380; // Более точный порог для вертикального расположения
    return Flex(
      direction: isNarrow ? Axis.vertical : Axis.horizontal,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min, // Чтобы не занимать лишнее место
      children: [
        SocialAuthButton(
          assetPath: AppAssets.googleIcon,
          providerName: 'Google',
          onPressed: isLoading ? null : () => _handleSocialLogin('google'),
        ),
        SizedBox(width: isNarrow ? 0 : 16, height: isNarrow ? 12 : 0),
        SocialAuthButton(
          assetPath: AppAssets.yandexIcon,
          providerName: 'Яндекс',
          onPressed: isLoading ? null : () => _handleSocialLogin('yandex'),
        ),
      ],
    );
  }

  Widget _buildToggleModeLink(ThemeData theme, bool isLoading) {
    return TextButton(
      onPressed: isLoading ? null : _toggleAuthMode,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: theme.colorScheme.primary,
        textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(
        _isLogin ? AppStrings.createAccountLink : AppStrings.alreadyHaveAccountLink,
        textAlign: TextAlign.center,
      ),
    );
  }
}