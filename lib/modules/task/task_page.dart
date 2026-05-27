// ========================
// pages/task/task_page.dart
// ========================

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:harvest/core/theme/app_surface.dart';
import 'package:harvest/widgets/app_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:harvest/core/utils/utils.dart';
import 'package:harvest/modules/download/provider/downloader_provider.dart';
import 'package:harvest/widgets/app_menu.dart';

import '../../widgets/cache_status_banner.dart';
import '../shell/provider/screenshot_provider.dart';
import '../shell/widgets/shell_scaffold.dart';
import 'model/schedule.dart';
import 'provider/crontab_provider.dart';
import 'provider/schedule_provider.dart';
import 'widgets/schedule_edit_sheet.dart';
import 'widgets/torrent_move_edit_sheet.dart';

class TaskPage extends ConsumerWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(scheduleProvider);
    final theme = shadcn.Theme.of(context);
    final pageBackground = appSurfaceColor(
      context,
      theme.colorScheme.background,
    );

    return AppBackground(
      child: shadcn.Scaffold(
        backgroundColor: pageBackground,
        child: tasksAsync.when(
          loading: () => const Center(
            child: shadcn.CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => _ErrorView(
            error: e,
            onRetry: () => ref.invalidate(scheduleProvider),
          ),
          data: (tasks) => _TaskListView(
            tasks: tasks,
            onAdd: (buttonContext) => _openAdd(buttonContext, ref),
          ),
        ),
      ),
    );
  }

  void _openAdd(BuildContext context, WidgetRef ref) {
    shadcn.showDropdown<void>(
      context: context,
      alignment: Alignment.topCenter,
      offset: const Offset(0, 8),
      widthConstraint: shadcn.PopoverConstraint.intrinsic,
      heightConstraint: shadcn.PopoverConstraint.intrinsic,
      consumeOutsideTaps: false,
      builder: (_) => shadcn.DropdownMenu(
        children: [
          shadcn.MenuLabel(child: const Text('添加任务')),
          const shadcn.MenuDivider(),
          shadcn.MenuButton(
            leading: const Icon(shadcn.LucideIcons.calendarClock),
            onPressed: (overlayContext) async {
              await shadcn.closeOverlay(overlayContext);
              if (!context.mounted) return;
              _openEdit(context, ref, null, isTorrentMove: false);
            },
            child: const Text('普通任务'),
          ),
          shadcn.MenuButton(
            leading: const Icon(shadcn.LucideIcons.arrowRightLeft),
            onPressed: (overlayContext) async {
              await shadcn.closeOverlay(overlayContext);
              if (!context.mounted) return;
              _openEdit(context, ref, null, isTorrentMove: true);
            },
            child: const Text('种子迁移任务'),
          ),
        ],
      ),
    );
  }
}

/// 打开编辑
void _openEdit(
  BuildContext context,
  WidgetRef ref,
  Schedule? task, {
  bool? isTorrentMove,
}) {
  final useTorrentMove = isTorrentMove ?? task?.task.contains('种子迁移') ?? false;
  final isMobile = context.isMobile;

  final sheet = useTorrentMove
      ? TorrentMoveEditSheet(task: task)
      : ScheduleEditSheet(task: task);

  if (isMobile) {
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  } else {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: shadcn.Theme.of(context).colorScheme.background,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: sheet,
        ),
      ),
    );
  }
}

// ==================== 错误视图 ====================
class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            shadcn.LucideIcons.triangleAlert,
            size: 48,
            color: shadcn.Theme.of(context).colorScheme.destructive,
          ),
          const SizedBox(height: 16),
          Text('加载失败', style: shadcn.Theme.of(context).typography.large),
          const SizedBox(height: 8),
          Text(
            '$error',
            style: shadcn.Theme.of(context).typography.small.copyWith(
              color: shadcn.Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          shadcn.Button.primary(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

// ==================== 列表视图 ====================
class _TaskListView extends ConsumerStatefulWidget {
  final List<Schedule> tasks;
  final ValueChanged<BuildContext> onAdd;

  const _TaskListView({required this.tasks, required this.onAdd});

  @override
  ConsumerState<_TaskListView> createState() => _TaskListViewState();
}

class _TaskStatusBar extends StatelessWidget {
  final int enabledCount;
  final int disabledCount;
  final ValueChanged<BuildContext> onAdd;

  const _TaskStatusBar({
    required this.enabledCount,
    required this.disabledCount,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final horizontalInset = context.isMobile ? 12.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 10, horizontalInset, 4),
      child: Row(
        children: [
          Icon(
            shadcn.LucideIcons.circle,
            size: 8,
            color: enabledCount > 0 ? cs.primary : cs.mutedForeground,
          ),
          const SizedBox(width: 6),
          Text(
            '任务状态',
            style: theme.typography.xSmall.copyWith(color: cs.mutedForeground),
          ),
          const SizedBox(width: 8),
          shadcn.SecondaryBadge(child: Text('启用 $enabledCount')),
          const SizedBox(width: 6),
          shadcn.OutlineBadge(child: Text('禁用 $disabledCount')),
          const Spacer(),
          shadcn.OverlayManagerLayer(
            popoverHandler: const shadcn.PopoverOverlayHandler(),
            tooltipHandler: const shadcn.FixedTooltipOverlayHandler(),
            menuHandler: const shadcn.PopoverOverlayHandler(),
            child: Builder(
              builder: (buttonContext) => shadcn.IconButton.ghost(
                onPressed: () => onAdd(buttonContext),
                icon: shadcn.Tooltip(
                  tooltip: (_) => const Text('添加任务'),
                  child: const Icon(shadcn.LucideIcons.plus, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskListViewState extends ConsumerState<_TaskListView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeScrollControllerProvider.notifier).state =
          _scrollController;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cacheInfo = ref.watch(scheduleCacheInfoProvider);
    final enabledCount = widget.tasks.where((task) => task.enabled).length;
    final disabledCount = widget.tasks.length - enabledCount;

    if (widget.tasks.isEmpty) {
      return Column(
        children: [
          CacheStatusBanner(
            info: cacheInfo,
            margin: EdgeInsets.fromLTRB(
              context.isMobile ? 12 : 16,
              8,
              context.isMobile ? 12 : 16,
              6,
            ),
          ),
          _TaskStatusBar(
            enabledCount: enabledCount,
            disabledCount: disabledCount,
            onAdd: widget.onAdd,
          ),
          Expanded(
            child: EasyRefresh(
              onRefresh: _refresh,
              header: appRefreshHeader(context),
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: 16 + ShellBottomSpacing.value(context),
                ),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          shadcn.LucideIcons.calendarOff,
                          size: 48,
                          color: shadcn.Theme.of(
                            context,
                          ).colorScheme.mutedForeground,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无计划任务',
                          style: shadcn.Theme.of(context).typography.large,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        CacheStatusBanner(
          info: cacheInfo,
          margin: EdgeInsets.fromLTRB(
            context.isMobile ? 12 : 16,
            8,
            context.isMobile ? 12 : 16,
            2,
          ),
        ),
        _TaskStatusBar(
          enabledCount: enabledCount,
          disabledCount: disabledCount,
          onAdd: widget.onAdd,
        ),
        Expanded(
          child: EasyRefresh(
            onRefresh: _refresh,
            header: appRefreshHeader(context),
            child: context.isDesktop
                ? _buildDesktopGrid(context)
                : _buildMobileList(context),
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    await ref.read(scheduleProvider.notifier).refresh();
    if (!mounted) return;
    ref.invalidate(crontabListProvider);
    ref.invalidate(downloaderListProvider);
  }

  /// 手机端：单列 ListView，统一间距
  Widget _buildMobileList(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        16 + ShellBottomSpacing.value(context),
      ),
      itemCount: widget.tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildTile(context, widget.tasks[index]),
    );
  }

  /// 桌面端：网格布局，列数随屏幕宽度自适应
  Widget _buildDesktopGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = (width / 320).floor().clamp(2, 6).toInt();
        const spacing = 8.0;
        final itemWidth =
            (width - 32 - (crossAxisCount - 1) * spacing) / crossAxisCount;

        return ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + ShellBottomSpacing.value(context),
          ),
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final task in widget.tasks)
                  SizedBox(width: itemWidth, child: _buildTile(context, task)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTile(BuildContext context, Schedule task) {
    final crontabList = ref.watch(crontabListProvider).valueOrNull ?? [];
    final taskCrontabExpress = task.crontab?.express.trim() ?? '';
    final matchedCrontabExpress =
        crontabList
            .firstWhereOrNull((c) => c.id == task.crontabId)
            ?.express
            .trim() ??
        '';
    final express = taskCrontabExpress.isNotEmpty
        ? taskCrontabExpress
        : matchedCrontabExpress;

    final icon = _taskIcon(task.task);
    final isMobile = context.isMobile;
    final kwargs = task.kwargs.trim();
    final hasKwargs = kwargs.isNotEmpty && kwargs != '{}';
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final typo = theme.typography;
    final gap = theme.density.baseGap * theme.scaling;
    final contentPadding = theme.density.baseContentPadding * theme.scaling;
    final heightScale = theme.scaling.clamp(0.92, 1.18).toDouble();
    final cardHeight = (isMobile ? 112.0 : 108.0) * heightScale;
    final titleColor = task.enabled ? cs.foreground : cs.mutedForeground;
    final bodyColor = task.enabled
        ? cs.mutedForeground
        : cs.mutedForeground.withValues(alpha: 0.72);

    return AppContextMenu(
      items: _taskMenuItems(context, task),
      openOnTap: isMobile,
      openOnLongPress: !isMobile,
      child: SizedBox(
        height: cardHeight,
        child: AppSurfaceContainer(
          color: appSurfaceColor(context, cs.card),
          borderColor: cs.border,
          borderRadius: BorderRadius.circular(theme.radiusLg),
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (task.enabled ? cs.primary : cs.mutedForeground)
                        .withValues(alpha: task.enabled ? 0.42 : 0.18),
                  ),
                  child: const SizedBox(width: 3),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentPadding,
                  gap * 0.9,
                  contentPadding,
                  gap * 0.9,
                ),
                child: Row(
                  children: [
                    _buildTaskIconBadge(context, icon, task.enabled),
                    SizedBox(width: gap * 0.85),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.name,
                                  style: typo.small.copyWith(
                                    color: titleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (express.isNotEmpty) ...[
                                SizedBox(width: gap * 0.75),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isMobile ? 116 : 138,
                                  ),
                                  child: _buildCronBadge(context, express),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: gap * 0.45),
                          Text(
                            task.task,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typo.xSmall.copyWith(
                              color: bodyColor,
                              fontSize: isMobile ? null : 13,
                            ),
                          ),
                          SizedBox(height: gap * 0.45),
                          _buildKwargsSlot(context, task, hasKwargs),
                        ],
                      ),
                    ),
                    SizedBox(width: gap),
                    shadcn.Switch(
                      value: task.enabled,
                      onChanged: (v) => ref
                          .read(scheduleProvider.notifier)
                          .toggle(task.id, v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskIconBadge(
    BuildContext context,
    IconData icon,
    bool enabled,
  ) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final accent = enabled ? cs.primary : cs.mutedForeground;
    final size = context.isMobile ? 34.0 : 36.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: enabled ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(
          color: accent.withValues(alpha: enabled ? 0.24 : 0.16),
          width: 0.5,
        ),
      ),
      child: Icon(icon, size: context.isMobile ? 16 : 17, color: accent),
    );
  }

  Widget _buildCronBadge(BuildContext context, String expression) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final gap = theme.density.baseGap * theme.scaling;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(theme.radiusSm),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.26),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: gap * 0.7,
          vertical: gap * 0.28,
        ),
        child: Text(
          expression,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.xSmall.copyWith(
            color: cs.primary,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            fontSize: context.isMobile ? 11 : 12,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _buildKwargsSlot(BuildContext context, Schedule task, bool hasKwargs) {
    final scale = shadcn.Theme.of(context).scaling.clamp(0.92, 1.18).toDouble();

    return SizedBox(
      height: (context.isMobile ? 30.0 : 28.0) * scale,
      child: Align(
        alignment: Alignment.centerLeft,
        child: hasKwargs ? _buildKwargsBadge(context, task) : null,
      ),
    );
  }

  List<shadcn.MenuItem> _taskMenuItems(BuildContext context, Schedule task) {
    final pageContext = this.context;
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;

    shadcn.MenuButton item({
      required IconData icon,
      required String title,
      required Future<void> Function(BuildContext overlayContext) onPressed,
      bool destructive = false,
    }) {
      final color = destructive ? cs.destructive : cs.foreground;
      return shadcn.MenuButton(
        leading: Icon(icon, size: theme.scaling * 15, color: color),
        autoClose: false,
        onPressed: onPressed,
        child: SizedBox(
          width: 140,
          child: Text(
            title,
            style: theme.typography.small.copyWith(color: color),
          ),
        ),
      );
    }

    return [
      item(
        icon: shadcn.LucideIcons.play,
        title: '立即执行',
        onPressed: (ctx) async {
          unawaited(shadcn.closeOverlay(ctx));
          await ref.read(scheduleProvider.notifier).runOnce(task.id);
        },
      ),
      item(
        icon: shadcn.LucideIcons.pencil,
        title: '编辑',
        onPressed: (ctx) async {
          unawaited(shadcn.closeOverlay(ctx));
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (!mounted || !pageContext.mounted) return;
          _openEdit(pageContext, ref, task);
        },
      ),
      const shadcn.MenuDivider(),
      item(
        icon: shadcn.LucideIcons.trash2,
        title: '删除',
        destructive: true,
        onPressed: (ctx) async {
          unawaited(shadcn.closeOverlay(ctx));
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (!mounted || !pageContext.mounted) return;
          _DeleteConfirmDialog.show(pageContext, ref, task);
        },
      ),
    ];
  }

  Widget _buildKwargsBadge(BuildContext context, Schedule task) {
    final downloaders = ref.watch(downloaderListProvider).valueOrNull ?? [];

    try {
      final kwargs = jsonDecode(task.kwargs) as Map<String, dynamic>;
      final parts = <String>[];

      if (task.task.contains('种子迁移')) {
        final srcId = kwargs['source_downloader_id'];
        final distId = kwargs['dist_downloader_id'];
        final srcName =
            downloaders.firstWhereOrNull((d) => d.id == srcId)?.name ??
            '#$srcId';
        final distName =
            downloaders.firstWhereOrNull((d) => d.id == distId)?.name ??
            '#$distId';
        parts.add('$srcName → $distName');

        final folders = kwargs['folder_map'] as List?;
        if (folders != null && folders.isNotEmpty) {
          parts.add('${folders.first}');
        }
        if (kwargs['remove_source_torrents'] == true) parts.add('删除源种子');
      }

      if (parts.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: EdgeInsets.only(
          top:
              shadcn.Theme.of(context).density.baseGap *
              shadcn.Theme.of(context).scaling *
              0.4,
        ),
        child: AppSurfaceContainer(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          borderRadius: shadcn.Theme.of(context).borderRadiusSm,
          color: appSurfaceColor(
            context,
            shadcn.Theme.of(context).colorScheme.muted,
          ),
          borderColor: shadcn.Theme.of(
            context,
          ).colorScheme.border.withValues(alpha: 0.55),
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shadcn.Theme.of(context).typography.xSmall.copyWith(
              color: shadcn.Theme.of(context).colorScheme.mutedForeground,
              fontSize: context.isMobile ? 11 : 12,
            ),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  IconData _taskIcon(String type) {
    return switch (type) {
      '自动签到任务' || '阿里云签到' => shadcn.LucideIcons.check,
      '批量抓取站点信息' => shadcn.LucideIcons.globe,
      'RSS订阅' => shadcn.LucideIcons.rss,
      '下载器辅种任务' => shadcn.LucideIcons.copy,
      '种子迁移任务' => shadcn.LucideIcons.arrowRightLeft,
      '自动清理内存' => shadcn.LucideIcons.trash2,
      _ => shadcn.LucideIcons.calendarClock,
    };
  }
}

// ==================== 删除确认 ====================
class _DeleteConfirmDialog {
  static void show(BuildContext context, WidgetRef ref, Schedule task) {
    shadcn.showDialog(
      context: context,
      builder: (ctx) => shadcn.AlertDialog(
        leading: const Icon(shadcn.LucideIcons.trash2),
        title: const Text('确认删除'),
        content: Text('确定要删除任务「${task.name}」吗？'),
        actions: [
          shadcn.Button.outline(
            onPressed: () => closeAppSheet(ctx),
            child: const Text('取消'),
          ),
          shadcn.Button.destructive(
            onPressed: () async {
              closeAppSheet(ctx);
              await ref.read(scheduleProvider.notifier).delete(task.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
