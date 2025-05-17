// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'core/routing/app_route_information_parser.dart';
import 'core/routing/app_router_delegate.dart';
import 'core/routing/app_pages.dart'; // Для AuthState, если он там

// Добавьте этот импорт, если его нет
import 'package:flutter_web_plugins/url_strategy.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Используйте PathUrlStrategy для удаления '#' из URL
  usePathUrlStrategy(); // <--- ДОБАВЬТЕ ЭТУ СТРОКУ
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppRouterDelegate _routerDelegate;
  final AppRouteInformationParser _routeInformationParser = AppRouteInformationParser();
  final AuthState _authState = AuthState(); // Убедитесь, что AuthState импортирован

  @override
  void initState() {
    super.initState();
    _routerDelegate = AppRouterDelegate(authState: _authState);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: _authState),
        ChangeNotifierProvider.value(value: _routerDelegate),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Todo App',
            theme: themeProvider.currentTheme,
            darkTheme: themeProvider.currentTheme,
            themeMode: themeProvider.themeMode,
            routerDelegate: _routerDelegate,
            routeInformationParser: _routeInformationParser,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}