// lib/screens/oauth_callback_screen.dart
import 'package:client/core/routing/app_router_delegate.dart';
import 'package:client/core/routing/app_route_path.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleCallback();
      }
    });
  }

  Future<void> _handleCallback() async {
    final authState = Provider.of<AuthState>(context, listen: false);
    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);

    final currentUri = Uri.parse(html.window.location.href);

    // Очищаем URL от параметров, чтобы избежать повторной обработки при обновлении
    final cleanUrl = currentUri.removeFragment().replace(queryParameters: {});
    html.window.history.replaceState(null, '', cleanUrl.path);

    final success = await authState.handleOAuthCallbackFromUrl(currentUri, widget.provider);

    // После завершения обработки, независимо от результата,
    // мы явно говорим роутеру, куда идти.
    if (mounted) {
      if (success) {
        // ЯВНОЕ ПЕРЕНАПРАВЛЕНИЕ НА ДОМАШНЮЮ СТРАНИЦУ
        routerDelegate.navigateTo(const HomePath());
      } else {
        // Если была ошибка, AuthState сохранит ее, и мы перенаправим на страницу логина.
        routerDelegate.navigateTo(const AuthPath());
      }
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