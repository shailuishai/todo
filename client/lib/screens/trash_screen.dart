// lib/screens/trash_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/routing/app_pages.dart';
import '../core/routing/app_route_path.dart';
import '../core/routing/app_router_delegate.dart';
import '../core/utils/responsive_utils.dart';
import '../deleted_tasks_provider.dart';
import '../models/task_model.dart';
import '../widgets/trash/deleted_task_card_widget.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({Key? key}) : super(key: key);

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {

  Future<void> _refreshData() {
    return Provider.of<DeletedTasksProvider>(context, listen: false).fetchDeletedTasks();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = ResponsiveUtil.isMobile(context);

    Widget bodyContent = Consumer<DeletedTasksProvider>(
      builder: (context, deletedTasksProvider, child) {
        final List<Task> deletedTasks = deletedTasksProvider.deletedTasks;

        Widget content;

        if (deletedTasksProvider.isLoading && deletedTasks.isEmpty) {
          content = const Center(child: CircularProgressIndicator());
        } else if (deletedTasksProvider.error != null && deletedTasks.isEmpty) {
          content = Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Ошибка: ${deletedTasksProvider.error}',
                        style: TextStyle(color: colorScheme.error), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                        onPressed: _refreshData,
                        child: const Text('Попробовать снова')
                    )
                  ],
                ),
              ));
        } else if (deletedTasks.isEmpty) {
          content = Center(
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
        } else {
          content = LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount;
              double childAspectRatio;
              double mainAxisSpacing = 12.0;
              double crossAxisSpacing = 12.0;
              EdgeInsets padding = const EdgeInsets.all(16.0);

              if (constraints.maxWidth > 1200) {
                crossAxisCount = 4;
                childAspectRatio = 1.8;
              } else if (constraints.maxWidth > 900) {
                crossAxisCount = 3;
                childAspectRatio = 1.7;
              } else if (constraints.maxWidth > 600) {
                crossAxisCount = 2;
                childAspectRatio = 1.6;
              } else {
                crossAxisCount = 1;
                childAspectRatio = 2.2;
                mainAxisSpacing = 16.0;
                padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0);
              }

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
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: content,
        );
      },
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text("Корзина"),
          leading: BackButton(onPressed: () => Provider.of<AppRouterDelegate>(context, listen: false).navigateTo(HomeSubPath(AppRouteSegments.home,showRightSidebar: false))),
        ),
        // <<< ИЗМЕНЕНИЕ: Оборачиваем body в SafeArea >>>
        body: SafeArea(child: bodyContent),
      );
    }

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
      child: bodyContent,
    );
  }
}