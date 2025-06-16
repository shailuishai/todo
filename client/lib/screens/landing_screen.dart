// lib/screens/landing_screen.dart
import 'dart:ui'; // Для ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html; // Для User-Agent

import '../core/constants/app_assets.dart';
import '../core/routing/app_pages.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';
import '../core/utils/responsive_utils.dart';
import '../theme_provider.dart';
import '../auth_state.dart';
import '../widgets/sidebar/app_logo.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _downloadSectionKey = GlobalKey();
  String _detectedOS = "Unknown";
  String _detectedArch = "Unknown";

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _detectOSAndArchFromUserAgent();
    }
  }

  void _detectOSAndArchFromUserAgent() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    if (userAgent.contains("windows") || userAgent.contains("win")) {
      _detectedOS = "Windows";
    } else if (userAgent.contains("linux") && !userAgent.contains("android")) {
      _detectedOS = "Linux";
    } else if (userAgent.contains("macintosh") || userAgent.contains("mac os x")) {
      _detectedOS = "macOS";
    } else if (userAgent.contains("android")) {
      _detectedOS = "Android";
    } else if (userAgent.contains("iphone") || userAgent.contains("ipad") || userAgent.contains("ipod")) {
      _detectedOS = "iOS";
    }

    if (userAgent.contains("arm64") || userAgent.contains("aarch64")) {
      _detectedArch = "ARM64";
    } else if (userAgent.contains("x86_64") || userAgent.contains("amd64") || userAgent.contains("win64")) {
      _detectedArch = "x64";
    } else if (userAgent.contains("x86")) {
      _detectedArch = "x86";
    }

    if (_detectedOS == "Android" || _detectedOS == "iOS") {
      _detectedArch = "Universal";
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _scrollToDownloadSection() {
    final context = _downloadSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    } else {
      // <<< ИСПРАВЛЕНИЕ: Альтернативный метод, если контекст не найден >>>
      // Прокручиваем на примерную высоту двух секций.
      // Это не идеально, но сработает в большинстве случаев.
      _scrollController.animateTo(
        1400, // Примерное значение, можно подобрать точнее
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
      debugPrint("[LandingScreen] Download section context not found. Scrolling by offset.");
    }
  }

  Future<void> _launchURL(String urlString) async {
    if (urlString == "#") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл для скачивания еще не готов.')),
        );
      }
      return;
    }

    Uri url;
    if (urlString.startsWith('/')) {
      final origin = html.window.location.origin;
      if (origin == null) {
        debugPrint("Could not determine window.location.origin. Cannot launch URL.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось определить адрес сайта.')),
          );
        }
        return;
      }
      url = Uri.parse(origin + urlString);
    } else {
      url = Uri.parse(urlString);
    }

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть ссылку: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(
        body: Center(
          child: Text("Эта страница доступна только в веб-версии."),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDark = themeProvider.isEffectivelyDark;
    final bool isMobile = ResponsiveUtil.isMobile(context);

    final appLogoWidget = AppLogo(currentSize: isMobile ? 32 : 40, isActuallyCollapsedState: false);

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: colorScheme.surface.withOpacity(isMobile ? 0.90 : 0.75),
        elevation: 0,
        scrolledUnderElevation: 2.0,
        titleSpacing: isMobile ? 16 : NavigationToolbar.kMiddleSpacing,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            appLogoWidget,
            const SizedBox(width: 12),
            Text(
              "ToDo",
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 20 : 22,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextButton.icon(
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text("Скачать"),
                onPressed: _scrollToDownloadSection,
                style: TextButton.styleFrom(foregroundColor: colorScheme.onSurface),
              ),
            ),
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            tooltip: isDark ? "Светлая тема" : "Темная тема",
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              themeProvider.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          const SizedBox(width: 4),
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 12.0 : 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.app_registration_rounded, size: 18),
              label: Text(isMobile ? "Вход" : "Войти / Регистрация"),
              onPressed: () {
                Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const AuthPath());
              },
              style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 12),
                  textStyle: TextStyle(fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.w500)
              ),
            ),
          ),
        ],
      ),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: kIsWeb,
        child: ListView(
          controller: _scrollController,
          children: [
            _buildHeroSection(context, textTheme, colorScheme, isMobile),
            _buildFeatureSection(
              context, textTheme, colorScheme, isMobile,
              title: "Организуйте свои задачи",
              description: "ToDo помогает вам легко управлять личными и командными задачами. Создавайте проекты, назначайте ответственных, отслеживайте прогресс и достигайте целей вместе.",
              assetPath: AppAssets.placeholder1,
              imageAspectRatio: 740 / 415,
              isSvg: false,
            ),
            _buildFeatureSection(
              context, textTheme, colorScheme, isMobile,
              title: "Командная работа без усилий",
              description: "Приглашайте коллег в команды, общайтесь во встроенном чате, используйте общие Kanban-доски и теги для эффективного взаимодействия и достижения общих результатов.",
              assetPath: AppAssets.placeholder2,
              imageAspectRatio: 416 / 416,
              isSvg: false,
              textOnRight: !isMobile,
            ),
            _buildDownloadSectionWrapper(context, theme, colorScheme, isMobile, _detectedOS, _detectedArch),
            _buildFooter(context, textTheme, colorScheme, isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, TextTheme textTheme, ColorScheme colorScheme, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: isMobile ? 50 : 100),
      decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary.withOpacity(0.1), colorScheme.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "ToDo: Ваш центр управления временем и задачами",
                style: (isMobile ? textTheme.headlineMedium : textTheme.displaySmall)?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                "Организуйте свою жизнь и работу команды с помощью интуитивно понятного интерфейса, мощных инструментов планирования и совместной работы.",
                style: (isMobile ? textTheme.bodyLarge : textTheme.titleLarge)?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.rocket_launch_outlined),
                    label: const Text("Начать работу"),
                    onPressed: () {
                      Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const AuthPath());
                    },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 32, vertical: isMobile ? 14 : 18),
                      textStyle: TextStyle(fontSize: isMobile ? 15 : 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 20),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text("Скачать приложение"),
                      onPressed: _scrollToDownloadSection,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          side: BorderSide(color: colorScheme.primary, width: 1.5)
                      ),
                    ),
                  ]
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureSection(
      BuildContext context,
      TextTheme textTheme,
      ColorScheme colorScheme,
      bool isMobile,
      {required String title, required String description, required String assetPath, bool isSvg = false, bool textOnRight = false, required double imageAspectRatio}) {

    Widget textContent = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 450),
      child: Column(
        crossAxisAlignment: isMobile ? CrossAxisAlignment.center : (textOnRight ? CrossAxisAlignment.start : CrossAxisAlignment.start),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: (isMobile ? textTheme.headlineSmall : textTheme.displaySmall?.copyWith(fontSize: 36))?.copyWith(
              color: colorScheme.onBackground,
              fontWeight: FontWeight.bold,
            ),
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: (isMobile ? textTheme.bodyLarge : textTheme.titleMedium)?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
          ),
        ],
      ),
    );

    Widget imageWidget;
    if (isSvg) {
      imageWidget = SvgPicture.asset(
        assetPath,
        fit: BoxFit.contain,
      );
    } else {
      imageWidget = Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (c,o,s) => Icon(Icons.image_not_supported_rounded, size: 100, color: colorScheme.outline.withOpacity(0.5)),
      );
    }

    Widget imageContent = Container(
      constraints: BoxConstraints(
        maxWidth: isMobile ? 320 : 480,
        maxHeight: isMobile ? (320 / imageAspectRatio) : (480 / imageAspectRatio),
      ),
      child: AspectRatio(
        aspectRatio: imageAspectRatio,
        child: Material(
          elevation: 8.0,
          borderRadius: BorderRadius.circular(16),
          shadowColor: colorScheme.shadow.withOpacity(0.25),
          clipBehavior: Clip.antiAlias,
          child: imageWidget,
        ),
      ),
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          children: [
            textContent,
            const SizedBox(height: 30),
            imageContent,
          ],
        ),
      );
    }

    List<Widget> children = textOnRight
        ? [Expanded(flex: 5, child: Center(child: imageContent)), const SizedBox(width: 60), Expanded(flex: 4, child: textContent)]
        : [Expanded(flex: 4, child: textContent), const SizedBox(width: 60), Expanded(flex: 5, child: Center(child:imageContent))];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 70),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadSectionWrapper(BuildContext context, ThemeData currentTheme, ColorScheme colorScheme, bool isMobile, String detectedOS, String detectedArch) {
    final textTheme = currentTheme.textTheme;
    return Container(
      key: _downloadSectionKey,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: isMobile ? 50 : 80),
      color: colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Text(
                "Загрузите ToDo",
                style: (isMobile ? textTheme.headlineLarge : textTheme.displaySmall)?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "Работайте эффективнее на любой платформе. Доступно для Windows, Linux, Android и прямо в вашем браузере.",
                style: (isMobile ? textTheme.bodyLarge : textTheme.titleLarge)?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              _buildPlatformSpecificDownloadButton(context, detectedOS, detectedArch, colorScheme),
              const SizedBox(height: 30),
              _buildDownloadTable(context, currentTheme, colorScheme, isMobile),
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text("Открыть веб-версию ToDo"),
                onPressed: () {
                  final authState = Provider.of<AuthState>(context, listen: false);
                  if (authState.isLoggedIn) {
                    Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const HomePath());
                  } else {
                    Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(const AuthPath());
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformSpecificDownloadButton(BuildContext context, String os, String arch, ColorScheme colorScheme) {
    String buttonText = "Скачать для Desktop";
    IconData buttonIcon = Icons.desktop_windows_rounded;
    String? downloadUrl;
    const String baseUrl = "https://github.com/shailuishai/todo/releases/download/latest/";

    if (os == "Windows") {
      buttonText = "Скачать для Windows";
      buttonIcon = Icons.desktop_windows_rounded;
      downloadUrl = "${baseUrl}ToDo_Windows-x86_64.zip";
    } else if (os == "Linux") {
      buttonText = "Скачать для Linux";
      buttonIcon = Icons.laptop_chromebook_rounded;
      downloadUrl = "${baseUrl}ToDo_Linux-x86_64.AppImage";
    } else if (os == "Android") {
      buttonText = "Скачать для Android";
      buttonIcon = Icons.android_rounded;
      downloadUrl = "${baseUrl}ToDo.apk";
    } else if (os == "macOS") {
      buttonText = "Скачать для macOS";
      buttonIcon = Icons.laptop_mac_rounded;
      downloadUrl = "#";
    }

    if (downloadUrl == null) {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      icon: Icon(buttonIcon, size: 22),
      label: Text(buttonText),
      onPressed: () => _launchURL(downloadUrl!),
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildDownloadTable(BuildContext context, ThemeData currentTheme, ColorScheme colorScheme, bool isMobile) {
    final textTheme = currentTheme.textTheme;
    const String baseUrl = "https://github.com/shailuishai/todo/releases/download/latest/";

    // <<< ИСПРАВЛЕНИЕ: Функция для создания ячейки с выравниванием по левому краю >>>
    DataCell buildCell(String text, {String? url, bool isPlatform = false}) {
      Widget content = Text(
        text,
        style: isPlatform ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500) : textTheme.bodyMedium,
      );
      if (url != null) {
        content = TextButton(
          onPressed: () => _launchURL(url),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: colorScheme.primary,
              // Выравнивание текста внутри кнопки
              alignment: Alignment.centerLeft
          ),
          child: Text(text, style: TextStyle(decoration: TextDecoration.underline, color: colorScheme.primary)),
        );
      }
      return DataCell(
          SizedBox( // Оборачиваем в SizedBox, чтобы занять всю ширину ячейки
            width: double.infinity,
            child: content,
          )
      );
    }

    return Theme(
      data: currentTheme.copyWith(
          dividerTheme: DividerThemeData(
            color: colorScheme.outlineVariant.withOpacity(0.3),
            thickness: 0.8,
          )
      ),
      child: DataTable(
        columnSpacing: isMobile ? 12.0 : 24.0,
        horizontalMargin: 0,
        headingRowHeight: 40,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 60,
        // <<< ИСПРАВЛЕНИЕ: Выравниваем заголовки по левому краю >>>
        columns: const [
          DataColumn(label: Expanded(child: Text('Платформа', textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold)))),
          DataColumn(label: Expanded(child: Text('Тип файла', textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold)))),
          DataColumn(label: Expanded(child: Text('Скачать', textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold)))),
        ],
        rows: [
          DataRow(cells: [
            buildCell('Windows (x64)', isPlatform: true),
            buildCell('ZIP Archive'),
            buildCell('ToDo_Windows-x86_64.zip', url: '${baseUrl}ToDo_Windows-x86_64.zip'),
          ]),
          DataRow(cells: [
            buildCell('Linux (x64)', isPlatform: true),
            buildCell('AppImage'),
            buildCell('ToDo_Linux-x86_64.AppImage', url: '${baseUrl}ToDo_Linux-x86_64.AppImage'),
          ]),
          DataRow(cells: [
            buildCell('Android', isPlatform: true),
            buildCell('APK (Universal)'),
            buildCell('ToDo.apk', url: '${baseUrl}ToDo.apk'),
          ]),
        ],
      ),
    );
  }


  Widget _buildFooter(BuildContext context, TextTheme textTheme, ColorScheme colorScheme, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: isMobile ? 30 : 40),
      color: colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: isMobile ? 24 : 30,
                      height: isMobile ? 24 : 30,
                      child: SvgPicture.asset(AppAssets.logo, colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn))
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "ToDo",
                    style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: isMobile ? 10 : 20,
                runSpacing: 8,
                children: [
                  TextButton(onPressed: () => _launchURL("mailto:ToDoAppResp@yandex.by?subject=Вопрос по ToDo App"), child: const Text("Контакты")),
                  TextButton(onPressed: () => _launchURL("/assets/assets/documents/privacy_policy.pdf"), child: const Text("Политика конфиденциальности")),
                  TextButton(onPressed: () => _launchURL("https://github.com/shailuishai/todo"), child: const Text("GitHub")),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "© ${DateTime.now().year} ToDo Team. Все права защищены.",
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}