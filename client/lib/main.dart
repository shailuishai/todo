// lib/main.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'core/routing/app_route_path.dart';
import 'theme_provider.dart';
import 'tag_provider.dart';
import 'task_provider.dart';
import 'team_provider.dart';
import 'sidebar_state_provider.dart';
import 'core/routing/app_route_information_parser.dart';
import 'core/routing/app_router_delegate.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'auth_state.dart';
import 'deleted_tasks_provider.dart';
import 'dart:async';
import 'services/api_service.dart';
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html_lib;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        final allowedHosts = ['localhost', '10.0.2.2'];
        return allowedHosts.contains(host) && port == 8080;
      };
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);

  if (kDebugMode && !kIsWeb) {
    HttpOverrides.global = MyHttpOverrides();
  }
  usePathUrlStrategy();

  final ApiService apiService = ApiService();
  final AuthState authState = AuthState(apiService: apiService);
  final TeamProvider teamProvider = TeamProvider(apiService, authState);
  final AppRouterDelegate routerDelegate = AppRouterDelegate(authState: authState, teamProvider: teamProvider);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: apiService),
        ChangeNotifierProvider.value(value: authState),
        ChangeNotifierProvider.value(value: teamProvider),
        ChangeNotifierProvider.value(value: routerDelegate),

        ChangeNotifierProxyProvider<AuthState, ThemeProvider>(
          create: (context) => ThemeProvider(context.read<AuthState>()),
          update: (context, auth, previous) => ThemeProvider(auth),
        ),

        ChangeNotifierProxyProvider<AuthState, ChatProvider>(
          create: (context) => ChatProvider(
            context.read<ApiService>(),
            context.read<AuthState>(),
          ),
          update: (context, auth, previous) => ChatProvider(
              context.read<ApiService>(), auth
          ),
        ),

        ChangeNotifierProxyProvider<AuthState, DeletedTasksProvider>(
          create: (context) => DeletedTasksProvider(
            context.read<ApiService>(),
            context.read<AuthState>(),
          ),
          update: (context, auth, previous) => DeletedTasksProvider(
            context.read<ApiService>(),
            auth,
          ),
        ),

        ChangeNotifierProxyProvider2<AuthState, DeletedTasksProvider, TaskProvider>(
          create: (context) => TaskProvider(
              context.read<ApiService>(),
              context.read<AuthState>(),
              context.read<DeletedTasksProvider>()
          ),
          update: (context, auth, deletedTasks, previous) => TaskProvider(
              context.read<ApiService>(),
              auth,
              deletedTasks
          ),
        ),

        ChangeNotifierProxyProvider<AuthState, TagProvider>(
          create: (context) => TagProvider(
              context.read<ApiService>(),
              context.read<AuthState>()),
          update: (context, auth, previous) =>
          previous ??
              TagProvider(context.read<ApiService>(), auth),
        ),
        ChangeNotifierProvider(create: (_) => SidebarStateProvider()),
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

  // Этот initState больше не нужен для обработки URI,
  // так как этим будет заниматься OAuthCallbackScreen
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routerDelegate = Provider.of<AppRouterDelegate>(context);

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final ThemeData currentTheme = themeProvider.currentTheme;

        return MaterialApp.router(
          title: 'ToDo',
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