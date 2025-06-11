// lib/screens/oauth_callback_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_state.dart';
import 'package:universal_html/html.dart' as html;

class OAuthCallbackScreen extends StatefulWidget {
  final String provider;

  const OAuthCallbackScreen({super.key, required this.provider});

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Вызываем обработчик сразу после построения первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleCallback();
      }
    });
  }

  Future<void> _handleCallback() async {
    final authState = Provider.of<AuthState>(context, listen: false);

    // Получаем полный текущий URL из браузера
    final currentUri = Uri.parse(html.window.location.href);

    // Очищаем URL от параметров, чтобы избежать повторной обработки при обновлении
    final cleanUrl = currentUri.removeFragment().replace(queryParameters: {});
    html.window.history.replaceState(null, '', cleanUrl.path);

    final success = await authState.handleOAuthCallbackFromUrl(currentUri, widget.provider);

    // После завершения обработки, AppRouterDelegate сам перенаправит
    // на нужный экран (Home или Auth) на основе нового состояния isLoggedIn.
    // Если произошла ошибка, AuthState сохранит ее, и она отобразится на экране Auth.
    if (!success && mounted) {
      setState(() {
        _errorMessage = authState.oauthErrorMessage ?? 'Произошла неизвестная ошибка авторизации.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Простой экран загрузки, пока идет обработка
    return Scaffold(
      body: Center(
        child: _errorMessage == null
            ? const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Завершение авторизации...'),
          ],
        )
            : Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 64),
              const SizedBox(height: 20),
              Text(
                'Ошибка авторизации',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}