// lib/widgets/settings/profile_settings_tab.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../auth_state.dart';
import '../../services/api_service.dart';
import '../../theme_provider.dart';
import '../../sidebar_state_provider.dart';
import '../CustomInputField.dart';
import '../PrimaryButton.dart';
import '../../core/utils/responsive_utils.dart';

class ProfileSettingsTab extends StatefulWidget {
  const ProfileSettingsTab({super.key});

  @override
  State<ProfileSettingsTab> createState() => _ProfileSettingsTabState();
}

class _ProfileSettingsTabState extends State<ProfileSettingsTab> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _loginController;

  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  bool _resetAvatar = false;

  String? _initialLoginOnLoadFromAuthState;
  String? _currentAvatarUrlFromAuthState;

  bool _isLoading = false;
  String? _errorMessage;

  BuildContext? _scaffoldMessengerContext;

  @override
  void initState() {
    super.initState();
    _loginController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      _scaffoldMessengerContext = context;
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    if (!mounted) return;
    final currentContext = _scaffoldMessengerContext ?? context;

    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024, maxHeight: 1024);
      if (image != null) {
        final bytes = await image.readAsBytes();
        if (bytes.lengthInBytes > 2 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(content: Text('Файл слишком большой. Максимум 2MB.'), backgroundColor: Colors.red),
          );
          return;
        }
        if (!mounted) return;
        setState(() {
          _pickedImageFile = image;
          _pickedImageBytes = bytes;
          _resetAvatar = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(content: Text('Ошибка выбора изображения: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _prepareResetAvatar() {
    if (!mounted) return;
    setState(() {
      _pickedImageFile = null;
      _pickedImageBytes = null;
      _resetAvatar = true;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final currentContext = _scaffoldMessengerContext ?? context;
    final authState = Provider.of<AuthState>(currentContext, listen: false);

    Map<String, dynamic>? avatarFileMap;
    if (_pickedImageFile != null && _pickedImageBytes != null) {
      avatarFileMap = {
        'bytes': _pickedImageBytes!,
        'filename': _pickedImageFile!.name,
      };
    }

    final newLogin = _loginController.text.trim();
    bool loginChanged = newLogin != (_initialLoginOnLoadFromAuthState ?? '');
    bool avatarChanged = _pickedImageFile != null || _resetAvatar;

    if (!loginChanged && !avatarChanged) {
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('Нет изменений для сохранения.')),
        );
        setState(() { _isLoading = false; });
      }
      return;
    }

    // <<< ИСПРАВЛЕНИЕ: Вызываем updateUserProfile только с нужными полями >>>
    final success = await authState.updateUserProfile(
      login: loginChanged ? newLogin : null,
      resetAvatar: _resetAvatar ? true : null, // Отправляем true только если флаг установлен
      avatarFile: avatarFileMap,
    );

    if (!mounted) return;

    setState(() { _isLoading = false; });
    if (success) {
      ScaffoldMessenger.of(currentContext).showSnackBar(
        const SnackBar(content: Text('Профиль успешно обновлен!'), backgroundColor: Colors.green),
      );
      setState(() {
        _pickedImageFile = null;
        _pickedImageBytes = null;
        _resetAvatar = false;
      });
    } else {
      setState(() { _errorMessage = authState.errorMessage ?? 'Не удалось обновить профиль.'; });
    }
  }

  Future<void> _deleteAccount() async {
    if (!mounted) return;
    final currentContext = _scaffoldMessengerContext ?? context;
    final authState = Provider.of<AuthState>(currentContext, listen: false);

    final confirm = await showDialog<bool>(
      context: currentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Удалить аккаунт?'),
          content: const Text('Это действие нельзя будет отменить. Все ваши данные будут удалены.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text('Удалить', style: TextStyle(color: Theme.of(currentContext).colorScheme.error, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() { _isLoading = true; _errorMessage = null; });

      final success = await authState.deleteUserAccount();

      if (!mounted) return;

      if (!success) {
        setState(() {
          _isLoading = false;
          _errorMessage = authState.errorMessage ?? 'Не удалось удалить аккаунт.';
        });
      }
    }
  }

  Widget _buildInitialsAvatar(BuildContext context, UserProfile user, double radius) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String initials = "";
    String nameSource = user.login;

    if (nameSource.isNotEmpty) {
      final names = nameSource.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (names.isNotEmpty) {
        initials = names[0][0];
        if (names.length > 1 && names[1].isNotEmpty) {
          initials += names[1][0];
        } else if (names[0].length > 1) {
          initials = names[0].substring(0, initials.length == 1 ? 2 : 1).trim();
          if (initials.length > 2) initials = initials.substring(0,2);
        }
      }
    }

    initials = initials.toUpperCase();
    if (initials.isEmpty && user.email.isNotEmpty) {
      initials = user.email[0].toUpperCase();
    }
    if (initials.isEmpty) {
      initials = "?";
    }

    Color avatarBackgroundColor = colorScheme.primaryContainer;
    Color avatarTextColor = colorScheme.onPrimaryContainer;

    if (user.accentColor != null && user.accentColor!.isNotEmpty) {
      try {
        final userAccent = Color(int.parse(user.accentColor!.replaceFirst('#', '0xff')));
        avatarTextColor = ThemeData.estimateBrightnessForColor(userAccent) == Brightness.dark
            ? Colors.white.withOpacity(0.95)
            : Colors.black.withOpacity(0.8);
        avatarBackgroundColor = userAccent;
      } catch (_) { /* Используем дефолтные цвета */ }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: avatarBackgroundColor,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * (initials.length == 1 ? 0.8 : 0.6),
          fontWeight: FontWeight.bold,
          color: avatarTextColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mounted) {
      _scaffoldMessengerContext = context;
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<AuthState>(
      builder: (context, authState, child) {
        final UserProfile? currentUser = authState.currentUser;
        final double avatarRadius = isMobile ? 48 : 60;

        if (authState.isLoading && currentUser == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (currentUser == null && !authState.isLoading) {
          return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text('Не удалось загрузить данные профиля.', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: () => authState.checkInitialAuthStatusAgain(), child: const Text("Повторить"))
                  ],
                ),
              )
          );
        }

        if (_initialLoginOnLoadFromAuthState != currentUser!.login) {
          _initialLoginOnLoadFromAuthState = currentUser.login;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _loginController.text != (_initialLoginOnLoadFromAuthState ?? '')) {
              final currentFocus = FocusScope.of(context).focusedChild;
              bool isLoginFieldFocused = currentFocus != null &&
                  currentFocus.context?.widget is EditableText &&
                  (currentFocus.context!.widget as EditableText).controller == _loginController;
              if(!isLoginFieldFocused) _loginController.text = _initialLoginOnLoadFromAuthState ?? '';
            }
          });
        }
        if (_currentAvatarUrlFromAuthState != currentUser.avatarUrl) {
          _currentAvatarUrlFromAuthState = currentUser.avatarUrl;
        }

        Widget avatarDisplayWidget;
        String? displayableAvatarUrl = _currentAvatarUrlFromAuthState;

        if (_pickedImageBytes != null) {
          avatarDisplayWidget = CircleAvatar(
            radius: avatarRadius,
            backgroundImage: MemoryImage(_pickedImageBytes!),
          );
        } else if (_resetAvatar) {
          avatarDisplayWidget = _buildInitialsAvatar(context, currentUser, avatarRadius);
        } else if (displayableAvatarUrl != null && displayableAvatarUrl.isNotEmpty) {
          avatarDisplayWidget = CircleAvatar(
            radius: avatarRadius,
            backgroundImage: NetworkImage(displayableAvatarUrl),
            onBackgroundImageError: (exception, stackTrace) {
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if(mounted) {
                    setState(() {
                      _currentAvatarUrlFromAuthState = null;
                    });
                  }
                });
              }
            },
            backgroundColor: Colors.transparent,
          );
        } else {
          avatarDisplayWidget = _buildInitialsAvatar(context, currentUser, avatarRadius);
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0).copyWith(top: isMobile ? 20 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isMobile ? 400 : 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: avatarDisplayWidget,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: colorScheme.secondaryContainer,
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: InkWell(
                                onTap: _isLoading ? null : _pickImage,
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: isMobile ? 20 : 22,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((displayableAvatarUrl != null && displayableAvatarUrl.isNotEmpty) || _pickedImageFile != null)
                      Center(
                        child: TextButton(
                          onPressed: _isLoading ? null : _prepareResetAvatar,
                          child: Text('Удалить аватар', style: TextStyle(color: colorScheme.error, fontSize: 13)),
                        ),
                      ),
                    SizedBox(height: (displayableAvatarUrl != null && displayableAvatarUrl.isNotEmpty || _pickedImageFile != null) ? 12 : 28),

                    CustomInputField(
                      key: ValueKey('login_field_${currentUser.userId}_${_initialLoginOnLoadFromAuthState}'),
                      label: "Логин (никнейм)",
                      controller: _loginController,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Логин не может быть пустым';
                        }
                        if (value.trim().length < 3) {
                          return 'Минимум 3 символа';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _isLoading ? null : _saveProfile(),
                    ),
                    const SizedBox(height: 16),
                    CustomInputField(
                      label: "Email",
                      initialValue: currentUser.email,
                      readOnly: true,
                      enabled: false,
                    ),
                    const SizedBox(height: 28),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    PrimaryButton(
                      text: "Сохранить изменения",
                      onPressed: _isLoading ? null : _saveProfile,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 20),

                    const Divider(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.logout_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                            label: Text("Выйти", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                            onPressed: _isLoading ? null : () {
                              final currentContextForDialog = _scaffoldMessengerContext ?? context;
                              showDialog(
                                context: currentContextForDialog,
                                builder: (BuildContext dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Выход из аккаунта'),
                                    content: const Text('Вы уверены, что хотите выйти?'),
                                    actions: <Widget>[
                                      TextButton(
                                        child: const Text('Отмена'),
                                        onPressed: () => Navigator.of(dialogContext).pop(),
                                      ),
                                      TextButton(
                                        child: Text('Выйти', style: TextStyle(color: Theme.of(currentContextForDialog).colorScheme.error, fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop();
                                          Provider.of<AuthState>(currentContextForDialog, listen: false).logout();
                                        },
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.onSurfaceVariant,
                              side: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.delete_forever_outlined, color: colorScheme.error, size: 20),
                            label: Text("Удалить", style: TextStyle(color: colorScheme.error)),
                            onPressed: _isLoading ? null : _deleteAccount,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(color: colorScheme.error.withOpacity(0.7)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}