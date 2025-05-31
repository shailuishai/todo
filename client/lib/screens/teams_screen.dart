// lib/screens/teams_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/team_model.dart';
import '../widgets/team/team_card_widget.dart';
import '../widgets/CustomInputField.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../core/utils/responsive_utils.dart';
import '../team_provider.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/routing/app_route_path.dart';

// extension TeamsScreenStateActions on _TeamsScreenState { // <<< УДАЛЯЕМ ЭТО РАСШИРЕНИЕ
//   void teamsScreenState_showCreateTeamDialog(BuildContext contextForDialog) {
//     _showCreateTeamDialog(contextForDialog);
//   }
//   void teamsScreenState_showJoinTeamDialog(BuildContext contextForDialog) {
//     _showJoinTeamDialog(contextForDialog);
//   }
// }

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({Key? key}) : super(key: key);

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  // Контроллеры и ключи форм остаются здесь, так как они используются методами,
  // которые будут перенесены в TeamProvider, но вызываться с контекстом этого экрана.
  // Либо их тоже можно будет передавать в методы TeamProvider.
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _teamDescriptionController = TextEditingController();
  Color _selectedTeamColor = Colors.blue.shade700;
  final TextEditingController _inviteTokenController = TextEditingController();
  final _joinTeamFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final teamProvider = Provider.of<TeamProvider>(context, listen: false);
        if (teamProvider.myTeams.isEmpty && (!teamProvider.isLoadingMyTeams || teamProvider.error != null)) {
          debugPrint("[TeamsScreen.initState] myTeams is empty and not loading (or has error), calling fetchMyTeams.");
          teamProvider.fetchMyTeams();
        } else {
          debugPrint("[TeamsScreen.initState] myTeams not empty or already loading. Count: ${teamProvider.myTeams.length}, Loading: ${teamProvider.isLoadingMyTeams}");
        }
      }
    });
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _teamDescriptionController.dispose();
    _inviteTokenController.dispose();
    super.dispose();
  }

  void _navigateToTeamDetails(BuildContext context, Team team) {
    Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(TeamDetailPath(team.teamId));
  }

  // Эти методы теперь будут вызываться из TeamProvider, но им нужен context
  // для showDialog и доступа к локальным контроллерам/переменным.
  // Их можно оставить здесь как приватные хелперы для TeamProvider.
  // Или полностью перенести их логику в TeamProvider, создавая контроллеры там.
  // Для первого шага оставим их здесь, но приватными.

  void _showCreateTeamDialogForProvider(BuildContext dialogCallerContext, {
    required TextEditingController nameController,
    required TextEditingController descriptionController,
    required Color initialColor,
    required Function(Color) onColorChange, // Для обновления цвета в провайдере
    required Function(CreateTeamRequest) onCreate, // Коллбэк для создания
    // TeamProvider будет управлять isProcessingTeamAction
  }) {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    // nameController, descriptionController, initialColor используются из параметров

    final theme = Theme.of(dialogCallerContext);
    final colorScheme = theme.colorScheme;
    final teamProvider = Provider.of<TeamProvider>(dialogCallerContext, listen: false); // Для isProcessingTeamAction

    showDialog(
      context: dialogCallerContext,
      builder: (BuildContext alertContext) { // alertContext - это контекст самого AlertDialog
        // Нужен StatefulBuilder, чтобы обновлять цвет внутри диалога
        Color currentColorForDialog = initialColor;
        return StatefulBuilder(
            builder: (stfContext, stfSetState) {
              return AlertDialog(
                title: const Text("Создать новую команду"),
                contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        CustomInputField(
                          label: "Название команды (макс. 30)",
                          controller: nameController,
                          inputFormatters: [LengthLimitingTextInputFormatter(30)],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Название команды не может быть пустым';
                            }
                            if (value.trim().length < 3) return 'Минимум 3 символа';
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        CustomInputField(
                          label: "Описание (макс. 100, опционально)",
                          controller: descriptionController,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                        ),
                        const SizedBox(height: 20),
                        Text("Цвет команды:", style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            Color? pickedColor = await _showColorPickerDialogForProvider(stfContext, currentColorForDialog);
                            if (pickedColor != null) {
                              stfSetState(() { currentColorForDialog = pickedColor; });
                              onColorChange(pickedColor); // Обновляем цвет в провайдере/методе его вызвавшем
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: currentColorForDialog.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: currentColorForDialog, width: 1.5)
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Выбрать цвет", style: TextStyle(color: currentColorForDialog, fontWeight: FontWeight.w500)),
                                Container(width: 24, height: 24, decoration: BoxDecoration(color: currentColorForDialog, shape: BoxShape.circle)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Отмена'),
                    onPressed: teamProvider.isProcessingTeamAction ? null : () => Navigator.of(alertContext).pop(),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    onPressed: teamProvider.isProcessingTeamAction ? null : () {
                      if (formKey.currentState!.validate()) {
                        final request = CreateTeamRequest(
                          name: nameController.text.trim(),
                          description: descriptionController.text.trim().isNotEmpty ? descriptionController.text.trim() : null,
                          colorHex: '#${currentColorForDialog.value.toRadixString(16).padLeft(8,'f').substring(2)}',
                        );
                        onCreate(request); // Вызываем коллбэк, который обработает создание
                        Navigator.of(alertContext).pop(); // Закрываем диалог
                      }
                    },
                    child: teamProvider.isProcessingTeamAction
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Создать'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  Future<Color?> _showColorPickerDialogForProvider(BuildContext context, Color initialColor) {
    Color tempPickedColor = initialColor;
    return showDialog<Color>(
      context: context,
      builder: (BuildContext alertContext) {
        return AlertDialog(
          title: const Text('Выберите цвет команды'),
          content: SingleChildScrollView(
            child: BlockPicker( // Можно заменить на MaterialPicker или другой
              pickerColor: initialColor,
              onColorChanged: (Color color) {
                tempPickedColor = color;
              },
              availableColors: Colors.primaries.map((e) => e.shade400).toList()
                ..addAll(Colors.accents.map((e) => e.shade200).toList())
                ..addAll([Colors.grey.shade500, Colors.brown.shade400, Colors.black]),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(alertContext).pop(null),
            ),
            TextButton(
              child: const Text('Выбрать'),
              onPressed: () => Navigator.of(alertContext).pop(tempPickedColor),
            ),
          ],
        );
      },
    );
  }

  void _showJoinTeamDialogForProvider(BuildContext dialogCallerContext, {
    required TextEditingController tokenController,
    required GlobalKey<FormState> formKey,
    required Function(String) onJoin,
  }) {
    final teamProvider = Provider.of<TeamProvider>(dialogCallerContext, listen: false);
    // tokenController.clear(); // Очистка должна быть в TeamProvider перед показом

    showDialog(
      context: dialogCallerContext,
      builder: (alertContext) {
        return AlertDialog(
          title: const Text('Присоединиться к команде'),
          content: Form(
            key: formKey,
            child: CustomInputField(
              controller: tokenController,
              label: 'Код-приглашение',
              hintText: 'Введите код...',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Код не может быть пустым';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: teamProvider.isProcessingTeamAction
                  ? null
                  : () => Navigator.of(alertContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: teamProvider.isProcessingTeamAction
                  ? null
                  : () {
                if (formKey.currentState!.validate()) {
                  final token = tokenController.text.trim();
                  onJoin(token);
                  Navigator.of(alertContext).pop();
                }
              },
              child: teamProvider.isProcessingTeamAction
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Присоединиться'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final teamProvider = Provider.of<TeamProvider>(context);

    Widget content;

    if (teamProvider.isLoadingMyTeams && teamProvider.myTeams.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (teamProvider.error != null && teamProvider.myTeams.isEmpty) {
      content = Center( /* ... код ошибки ... */ );
    } else if (teamProvider.myTeams.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_work_outlined, size: 64, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
              const SizedBox(height: 24),
              Text(
                "У вас пока нет команд.",
                style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Создайте свою первую команду или присоединитесь к существующей, используя кнопки в боковой панели.", // <<< ОБНОВЛЕННЫЙ ТЕКСТ
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Кнопки здесь удалены
            ],
          ),
        ),
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = 2;
          double childAspectRatio = 1.2;
          double mainAxisSpacing = 12.0;
          double crossAxisSpacing = 12.0;

          if (constraints.maxWidth > 1200) {
            crossAxisCount = 6; childAspectRatio = 1.3;
          } else if (constraints.maxWidth > 900) {
            crossAxisCount = 3; childAspectRatio = 1.25;
          } else if (constraints.maxWidth > 600) {
            crossAxisCount = 2; childAspectRatio = 1.15;
          } else {
            crossAxisCount = 1; childAspectRatio = ResponsiveUtil.isMobile(context) ? 2.0 : 1.6; mainAxisSpacing = 16.0;
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisSpacing: mainAxisSpacing,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: teamProvider.myTeams.length,
            itemBuilder: (context, index) {
              final team = teamProvider.myTeams[index];
              return TeamCardWidget(
                team: team,
                onTap: () => _navigateToTeamDetails(context, team),
              );
            },
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 16.0, right: 0.0, bottom: 16.0, left: 0.0), // Добавил left отступ, т.к. правый сайдбар теперь есть
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content, // Stack больше не нужен здесь
    );
  }
}