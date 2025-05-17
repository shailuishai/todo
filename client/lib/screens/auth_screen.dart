// lib/screens/auth_screen.dart
import 'package:client/core/constants/app_strings.dart'; // Оставляем, так как другие строки могут использоваться
import 'package:client/widgets/PrimaryButton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/auth/LoginForm.dart';
import '../widgets/auth/RegisterFrom.dart';
import '../widgets/auth/auth_screen_logo.dart';
import '../widgets/auth/social_auth_button.dart';
import '../widgets/auth/auth_form_container.dart';

import '../core/constants/app_assets.dart';
import '../core/routing/app_router_delegate.dart'; // Для AuthState

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _usernameController;
  late TextEditingController _confirmPasswordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _usernameController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    if (_isLoading) return;
    setState(() {
      _isLogin = !_isLogin;
      _autovalidateMode = AutovalidateMode.disabled;

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
    if (_isLoading) return;

    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    final formKey = _isLogin ? _loginFormKey : _registerFormKey;
    final isValid = formKey.currentState?.validate() ?? false;

    if (!isValid) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Имитация сетевого запроса
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isLogin
                ? 'Вход успешен (демо)' // Используем строки напрямую, как было
                : 'Регистрация успешна (демо)')), // Используем строки напрямую, как было
      );

      // ИЗМЕНЕНИЕ: Используем AuthState для изменения состояния аутентификации
      Provider.of<AuthState>(context, listen: false).login();
      // RouterDelegate сам обработает переход на HomePage
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      // AppStrings.loginVia все еще может быть полезной константой
      SnackBar(content: Text('${AppStrings.loginVia} $provider...')),
    );
    // Имитация входа через соцсеть
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Provider.of<AuthState>(context, listen: false).login();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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

    Widget currentAuthWidget = AuthFormContainer(
      key: ValueKey<bool>(_isLogin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AuthScreenLogo(),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(child.key == const ValueKey('login_form') ? -0.3 : 0.3, 0.0),
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
            onPressed: _submitForm,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 24),
          _buildSocialAuthRow(),
          const SizedBox(height: 24),
          _buildToggleModeLink(theme),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                switchInCurve: Curves.easeInOutQuart,
                switchOutCurve: Curves.easeInOutQuart,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final bool isLoginAuthBlock = (child.key == const ValueKey<bool>(true));
                  final offset = Tween<Offset>(
                    begin: isLoginAuthBlock ? const Offset(1.0, 0) : const Offset(-1.0, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutQuart));
                  final scale = Tween<double>(
                    begin: 0.9,
                    end: 1.0,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.elasticOut));

                  return SlideTransition(
                    position: offset,
                    child: ScaleTransition(
                      scale: scale,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                  );
                },
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  return Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: currentAuthWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialAuthRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SocialAuthButton(
          assetPath: AppAssets.googleIcon,
          providerName: 'Google',
          onPressed: () => _handleSocialLogin('Google'),
        ),
        const SizedBox(width: 16),
        SocialAuthButton(
          assetPath: AppAssets.yandexIcon,
          providerName: 'Яндекс',
          onPressed: () => _handleSocialLogin('Яндекс'),
        ),
      ],
    );
  }

  Widget _buildToggleModeLink(ThemeData theme) {
    return TextButton(
      onPressed: _isLoading ? null : _toggleAuthMode,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: theme.colorScheme.primary,
        overlayColor: theme.colorScheme.primary.withOpacity(0.1),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      child: Text(
        _isLogin ? AppStrings.createAccountLink : AppStrings.alreadyHaveAccountLink,
        textAlign: TextAlign.center,
      ),
    );
  }
}