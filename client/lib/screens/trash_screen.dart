// lib/screens/trash_screen.dart
import 'package:client/core/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../deleted_tasks_provider.dart';
import '../models/task_model.dart';
import '../widgets/trash/deleted_task_card_widget.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);

    return Consumer<DeletedTasksProvider>(
      builder: (context, deletedTasksProvider, child) {
        final List<Task> deletedTasks = deletedTasksProvider.deletedTasks;

        if (deletedTasks.isEmpty) {
          return Center(
            child: Opacity(
              opacity: 0.7,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_sweep_outlined, size: isMobile ? 56 : 72, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 20),
                  Text(
                    "Корзина пуста",
                    style: theme.textTheme.headlineSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Удаленные задачи будут отображаться здесь.",
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Основной контент теперь LayoutBuilder с GridView
        Widget gridContent = LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount;
            double childAspectRatio;
            double mainAxisSpacing = 12.0;
            double crossAxisSpacing = 12.0;
            EdgeInsets padding = const EdgeInsets.all(16.0);

            if (constraints.maxWidth > 1200) { // Очень большие экраны
              crossAxisCount = 4;
              childAspectRatio = 1.8; // Карточки будут довольно широкими и невысокими
            } else if (constraints.maxWidth > 900) { // Большие экраны
              crossAxisCount = 3;
              childAspectRatio = 1.7;
            } else if (constraints.maxWidth > 600) { // Планшеты / небольшие десктопы
              crossAxisCount = 2;
              childAspectRatio = 1.6;
            } else { // Мобильные
              crossAxisCount = 1;
              childAspectRatio = 2.2; // Карточки будут выше
              mainAxisSpacing = 16.0;
              padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0);
            }
            // Для DeletedTaskCardWidget может понадобиться свой childAspectRatio,
            // так как у него контент может быть выше, чем у TeamCardWidget.
            // Поиграйся со значениями childAspectRatio, чтобы карточки выглядели хорошо.

            return GridView.builder(
              padding: padding,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: deletedTasks.length,
              itemBuilder: (context, index) {
                final task = deletedTasks[index];
                return DeletedTaskCardWidget(task: task);
              },
            );
          },
        );

        if (isMobile) {
          return Scaffold(
            backgroundColor: Colors.transparent, // Фон страницы из HomeScreen
            body: gridContent,
          );
        }

        // Для десктопа/планшета - встраиваемый контент с контейнером
        return Container(
          margin: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 16.0),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Убрали заголовок "Корзина", если есть задачи
              // Если нужен заголовок всегда, можно вернуть:
              // Padding(
              //   padding: const EdgeInsets.only(bottom: 16.0, left: 24.0, top: 24.0, right: 24.0),
              //   child: Text(
              //     'Корзина',
              //     style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              //   ),
              // ),
              Expanded(child: gridContent),
            ],
          ),
        );
      },
    );
  }
}