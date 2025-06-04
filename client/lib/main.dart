// lib/main.dart
import 'dart:io'; // Для MyHttpOverrides
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, defaultTargetPlatform; // kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Для SystemChrome
import 'package:provider/provider.dart';
// import 'core/routing/app_route_path.dart'; // Не используется напрямую в main
import 'theme_provider.dart';
import 'tag_provider.dart';
import 'task_provider.dart';
import 'team_provider.dart';
import 'sidebar_state_provider.dart';
import 'core/routing/app_route_information_parser.dart';
import 'core/routing/app_router_delegate.dart';
import 'package:flutter_web_plugins/url_strategy.dart'; // Для usePathUrlStrategy
import 'auth_state.dart';
import 'deleted_tasks_provider.dart';
import 'dart:async'; // Для StreamSubscription
import 'services/api_service.dart';
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html_lib; // Для html.window

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart'; // Для initializeDateFormatting
// import 'themes.dart'; // themes.dart уже импортируется в theme_provider.dart или MyApp

// Класс для обхода проверки SSL сертификатов в debug режиме на НЕ-WEB платформах
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        // Разрешаем самоподписанные сертификаты для localhost и 10.0.2.2 на порту 8080
        final allowedHosts = ['localhost', '10.0.2.2'];
        return allowedHosts.contains(host) && port == 8080;
      };
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Обязательно для асинхронных операций до runApp
  await initializeDateFormatting('ru_RU', null); // Инициализация локализации для дат

  // Включение HttpOverrides только в debug режиме и НЕ для web
  if (kDebugMode && !kIsWeb) {
    HttpOverrides.global = MyHttpOverrides();
    debugPrint("HttpOverrides for self-signed certs enabled for debug mode on non-web platforms.");
  }

  usePathUrlStrategy(); // Используем "чистые" URL без # для веб

  // Установка предпочтительной ориентации для мобильных устройств
  if (!kIsWeb) {
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } catch (e) {
        // ignore: avoid_print
        print("Could not set preferred orientations: $e");
      }
    }
  }

  // Создаем ApiService один раз
  final ApiService apiService = ApiService();

  // Создаем AuthState, передавая ему ApiService
  final AuthState authState = AuthState(apiService: apiService);

  // Создаем TeamProvider, передавая ApiService и AuthState
  final TeamProvider teamProvider = TeamProvider(apiService, authState);

  // Создаем AppRouterDelegate, передавая AuthState и TeamProvider
  final AppRouterDelegate routerDelegate = AppRouterDelegate(authState: authState, teamProvider: teamProvider);


  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: apiService),
        ChangeNotifierProvider.value(value: authState),
        ChangeNotifierProvider.value(value: teamProvider),
        ChangeNotifierProvider.value(value: routerDelegate),

        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProxyProvider<AuthState, TaskProvider>(
          create: (context) => TaskProvider(
            Provider.of<ApiService>(context, listen: false),
            Provider.of<AuthState>(context, listen: false),
          ),
          update: (context, auth, previous) =>
          previous ?? TaskProvider(Provider.of<ApiService>(context, listen: false), auth),
        ),
        ChangeNotifierProxyProvider<AuthState, TagProvider>(
          create: (context) => TagProvider(
            Provider.of<ApiService>(context, listen: false),
            Provider.of<AuthState>(context, listen: false),
          ),
          update: (context, auth, previous) =>
          previous ?? TagProvider(Provider.of<ApiService>(context, listen: false), auth),
        ),
        ChangeNotifierProvider(create: (_) => SidebarStateProvider()),
        ChangeNotifierProvider(create: (context) => DeletedTasksProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppRouteInformationParser _routeInformationParser = AppRouteInformationParser();
  StreamSubscription? _uriLinkSubscription;

  @override
  void initState() {
    super.initState();

    final authState = Provider.of<AuthState>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    _loadThemeAndSubscribe(authState, themeProvider);

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleInitialWebUri();
        }
      });
      _uriLinkSubscription = html_lib.window.onPopState.listen((event) {
        if (mounted) {
          _handleWebUri(Uri.tryParse(html_lib.window.location.href));
        }
      });
    }
  }

  Future<void> _loadThemeAndSubscribe(AuthState authState, ThemeProvider themeProvider) async {
    // ЗАГЛУШКА: Реализуйте loadThemePreference в ThemeProvider
    // await themeProvider.loadThemePreference();
    debugPrint("ThemeProvider.loadThemePreference() - ЗАГЛУШКА, РЕАЛИЗУЙТЕ В ПРОВАЙДЕРЕ");
    await Future.delayed(Duration.zero);

    if (authState.isLoggedIn && authState.currentUser != null) {
      _applyProfileThemeSettings(authState.currentUser!, themeProvider);
    }

    authState.addListener(() { // Используем addListener
      if (authState.isLoggedIn && authState.currentUser != null) {
        _applyProfileThemeSettings(authState.currentUser!, themeProvider);
      }
    });
  }

  void _applyProfileThemeSettings(UserProfile profile, ThemeProvider themeProvider) {
    final userTheme = profile.theme;
    if (userTheme != null) {
      // ЗАГЛУШКА: Реализуйте setThemeByName в ThemeProvider
      // themeProvider.setThemeByName(userTheme);
      debugPrint("ThemeProvider.setThemeByName('$userTheme') - ЗАГЛУШКА, РЕАЛИЗУЙТЕ В ПРОВАЙДЕРЕ");
    }
    final userAccentColor = profile.accentColor;
    if (userAccentColor != null) {
      try {
        String colorString = userAccentColor.startsWith('#') ? userAccentColor.substring(1) : userAccentColor;
        if (colorString.length == 6) colorString = 'FF$colorString';
        themeProvider.setAccentColor(Color(int.parse(colorString, radix: 16)));
      } catch (e) {
        debugPrint("Error parsing accent color from profile: $e");
      }
    }
  }


  void _handleInitialWebUri() {
    if (!kIsWeb || !mounted) return;
    try {
      final initialUri = Uri.tryParse(html_lib.window.location.href);
      _handleWebUri(initialUri);
    } catch (e) {
      debugPrint("_MyAppState: Error processing initial web URI: $e");
    }
  }

  Future<void> _handleWebUri(Uri? uri) async {
    if (uri == null || !kIsWeb || !mounted ) return;

    final routerDelegate = Provider.of<AppRouterDelegate>(context, listen: false);
    debugPrint("_MyAppState: Handling WEB URI: $uri. Path: ${uri.path}, Query: ${uri.queryParameters}, Fragment: ${uri.fragment}");
    final authState = routerDelegate.authState;
    bool handledOAuthRedirect = false;

    const String frontendSuccessPathSuffix = 'oauth-callback-success';
    const String frontendErrorPathSuffix = 'oauth-callback-error';

    if (uri.pathSegments.isNotEmpty && uri.pathSegments.last == frontendSuccessPathSuffix) {
      debugPrint("_MyAppState: OAuth success redirect detected: $uri");
      await authState.handleOAuthCallback(uri);
      handledOAuthRedirect = true;
    } else if (uri.pathSegments.isNotEmpty && uri.pathSegments.last == frontendErrorPathSuffix) {
      final errorParam = uri.queryParameters['error_description'] ?? uri.queryParameters['error'] ?? 'unknown_oauth_error';
      final providerParam = uri.queryParameters['provider'] ?? 'unknown_provider';
      debugPrint("_MyAppState: OAuth error redirect detected: $uri, error: $errorParam, provider: $providerParam");
      authState.setOAuthError("Ошибка аутентификации через $providerParam: $errorParam");
      handledOAuthRedirect = true;
    }

    if (handledOAuthRedirect) {
      try {
        html_lib.window.history.replaceState(null, '', '/');
        debugPrint("_MyAppState: Cleared OAuth params from URL, effectively navigating to '/' for router to re-evaluate.");
      } catch (e) {
        debugPrint("_MyAppState: Error clearing/replacing URI after OAuth: $e");
      }
      if (mounted) {
        final newPath = await _routeInformationParser.parseRouteInformation(RouteInformation(uri: Uri(path: '/')) );
        await routerDelegate.setNewRoutePath(newPath);
      }
    } else {
      debugPrint("_MyAppState: URI $uri is not an OAuth redirect. Router should handle it.");
    }
  }


  @override
  void dispose() {
    _uriLinkSubscription?.cancel();
    // AuthState listener удалится автоматически при dispose самого AuthState.
    // Если бы мы добавляли listener с помощью authState.addListener(myMethod),
    // то нужно было бы authState.removeListener(myMethod) здесь.
    // Но т.к. мы используем ChangeNotifierProvider.value, жизненный цикл AuthState
    // управляется им, и он вызовет dispose у AuthState.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routerDelegate = Provider.of<AppRouterDelegate>(context);

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        // ЗАГЛУШКА: Реализуйте currentThemeData в ThemeProvider
        final ThemeData currentTheme = themeProvider.currentTheme ?? ThemeData.light(); // Используем дефолт, если нет
        final ColorScheme colorScheme = currentTheme.colorScheme;

        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: currentTheme.appBarTheme.backgroundColor ?? colorScheme.surface,
          statusBarIconBrightness: colorScheme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: colorScheme.brightness,
          systemNavigationBarColor: currentTheme.bottomNavigationBarTheme.backgroundColor ?? colorScheme.surface,
          systemNavigationBarDividerColor: currentTheme.dividerColor,
          systemNavigationBarIconBrightness: colorScheme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp.router(
          title: 'ChronosHub',
          theme: currentTheme,
          debugShowCheckedModeBanner: false,
          routerDelegate: routerDelegate,
          routeInformationParser: _routeInformationParser,
          backButtonDispatcher: RootBackButtonDispatcher(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ru', 'RU'),
            Locale('en', ''),
          ],
          locale: const Locale('ru', 'RU'),
        );
      },
    );
  }
}