// ========================
// pages/task/task_page.dart
// ========================

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harvest/core/theme/app_surface.dart';
import 'package:harvest/core/utils/utils.dart';
import 'package:harvest/modules/download/provider/downloader_provider.dart';
import 'package:harvest/widgets/app_menu.dart';
import 'package:harvest/widgets/app_sheet.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../widgets/cache_status_banner.dart';
import '../shell/provider/screenshot_provider.dart';
import '../shell/widgets/shell_scaffold.dart';
import '../torrents/widgets/torrent_stats_bar.dart';
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
    final horizontalInset = context.isMobile ? 12.0 : 24.0;
    final totalCount = enabledCount + disabledCount;

    return Container(
      padding: EdgeInsets.fromLTRB(horizontalInset, 8, horizontalInset, 8),
      decoration: BoxDecoration(
        color: appSurfaceColor(context, cs.background),
        border: Border(bottom: BorderSide(color: cs.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBarMetric(
                  icon: shadcn.LucideIcons.radio,
                  label: '启用',
                  value: '$enabledCount',
                  color: enabledCount > 0 ? cs.primary : cs.mutedForeground,
                ),
                StatusBarCount(label: '禁用', count: disabledCount),
                StatusBarCount(label: '总数', count: totalCount),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (buttonContext) => StatusBarIconButton(
              onTap: () => onAdd(buttonContext),
              icon: shadcn.LucideIcons.plus,
              tooltip: '添加任务',
              color: cs.mutedForeground,
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
    final isDesktop = context.isDesktop;
    final kwargsSummary = _taskKwargsSummary(task);
    final showExtraParamSlot = kwargsSummary != null || isDesktop;
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final typo = theme.typography;
    final gap = theme.density.baseGap * theme.scaling;
    final contentPadding = theme.density.baseContentPadding * theme.scaling;
    final heightScale = theme.scaling.clamp(0.92, 1.18).toDouble();
    final iconBadgeSize = (isMobile ? 42.0 : 44.0) * heightScale;
    final switchWidth = 36.0 * theme.scaling;
    final cardHeight =
        (isMobile ? (kwargsSummary == null ? 88.0 : 112.0) : 108.0) *
        heightScale;
    final accent = task.enabled ? cs.primary : cs.mutedForeground;
    final titleColor = task.enabled ? cs.foreground : cs.mutedForeground;
    final cardRadius = BorderRadius.circular(theme.radiusLg);
    final cardColor = task.enabled
        ? appSurfaceColor(context, cs.card)
        : appSurfaceColor(
            context,
            Color.alphaBlend(
              cs.mutedForeground.withValues(alpha: 0.035),
              cs.card,
            ),
          );
    final cardBorderColor = task.enabled
        ? cs.border.withValues(alpha: 0.78)
        : cs.border.withValues(alpha: 0.64);
    final shadowColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.black.withValues(alpha: 0.10);

    return AppContextMenu(
      items: _taskMenuItems(context, task),
      openOnTap: isMobile,
      openOnLongPress: !isMobile,
      child: SizedBox(
        height: cardHeight,
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: cardRadius,
            border: Border.all(color: cardBorderColor, width: 0.6),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: cs.primary.withValues(alpha: task.enabled ? 0.045 : 0),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: cardRadius,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: accent.withValues(alpha: task.enabled ? 0.42 : 0.18),
                    child: const SizedBox(width: 3),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    gap * 0.72,
                    contentPadding * 0.85,
                    gap * 0.72,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          _buildTaskIconBadge(
                            context,
                            icon,
                            task.enabled,
                            size: iconBadgeSize,
                          ),
                          SizedBox(width: gap * 0.85),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  task.name,
                                  style: typo.small.copyWith(
                                    color: titleColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: gap * 0.52),
                                _buildTaskParamLine(
                                  context,
                                  task: task,
                                  icon: icon,
                                  express: express,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: gap * 0.8),
                          SizedBox(
                            width: switchWidth,
                            child: Align(
                              alignment: Alignment.center,
                              child: shadcn.Switch(
                                value: task.enabled,
                                onChanged: (v) => ref
                                    .read(scheduleProvider.notifier)
                                    .toggle(task.id, v),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (showExtraParamSlot) ...[
                        SizedBox(height: gap * 0.42),
                        Row(
                          children: [
                            SizedBox(width: iconBadgeSize + gap * 0.85),
                            Expanded(
                              child: kwargsSummary != null
                                  ? _buildTaskExtraParamLine(
                                      context,
                                      task,
                                      kwargsSummary,
                                    )
                                  : const SizedBox(height: 22),
                            ),
                            SizedBox(width: gap * 0.8 + switchWidth),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskParamLine(
    BuildContext context, {
    required Schedule task,
    required IconData icon,
    required String express,
  }) {
    final children = <Widget>[
      Flexible(
        flex: 3,
        child: _buildTaskParamPill(
          context,
          icon: icon,
          label: task.task,
          color: _taskTagColor(context, 0),
          enabled: task.enabled,
        ),
      ),
    ];

    if (express.isNotEmpty) {
      children.add(const SizedBox(width: 6));
      children.add(
        Flexible(
          flex: 3,
          child: _buildTaskParamPill(
            context,
            icon: shadcn.LucideIcons.clock3,
            label: express,
            color: _taskTagColor(context, 1),
            enabled: task.enabled,
            monospace: true,
          ),
        ),
      );
    }

    return SizedBox(height: 24, child: Row(children: children));
  }

  Widget _buildTaskExtraParamLine(
    BuildContext context,
    Schedule task,
    String summary,
  ) {
    return SizedBox(
      height: 22,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildKwargsBadge(context, task, summary),
      ),
    );
  }

  Widget _buildTaskParamPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    bool monospace = false,
  }) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final gap = theme.density.baseGap * theme.scaling;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final contentColor = enabled
        ? color
        : Color.lerp(cs.mutedForeground, color, 0.58)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: contentColor.withValues(
          alpha: enabled ? (dark ? 0.18 : 0.11) : (dark ? 0.12 : 0.075),
        ),
        borderRadius: BorderRadius.circular(theme.radiusSm),
        border: Border.all(
          color: contentColor.withValues(alpha: enabled ? 0.30 : 0.20),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: gap * 0.62,
          vertical: gap * 0.28,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: contentColor),
            SizedBox(width: gap * 0.35),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.xSmall.copyWith(
                  color: contentColor,
                  fontFamily: monospace ? 'monospace' : null,
                  fontWeight: monospace ? FontWeight.w700 : FontWeight.w600,
                  fontSize: context.isMobile ? 10.5 : 11,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _taskTagColor(BuildContext context, int index) {
    final primary = shadcn.Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(primary);
    final saturation = (hsl.saturation * (dark ? 0.88 : 1.0))
        .clamp(0.46, 0.78)
        .toDouble();
    final lightness = dark
        ? hsl.lightness.clamp(0.58, 0.70).toDouble()
        : hsl.lightness.clamp(0.34, 0.50).toDouble();
    const offsets = <double>[0, -72, -144];
    final hue = (hsl.hue + offsets[index % offsets.length]) % 360;

    return hsl
        .withHue(hue < 0 ? hue + 360 : hue)
        .withSaturation(saturation)
        .withLightness(lightness)
        .toColor();
  }

  Widget _buildTaskIconBadge(
    BuildContext context,
    IconData icon,
    bool enabled, {
    required double size,
  }) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final accent = enabled ? cs.primary : cs.mutedForeground;

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
      child: Icon(icon, size: size * 0.5, color: accent),
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
        title: '执行',
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

  Widget _buildKwargsBadge(
    BuildContext context,
    Schedule task,
    String summary,
  ) {
    return _buildTaskParamPill(
      context,
      icon: shadcn.LucideIcons.listTree,
      label: summary,
      color: _taskTagColor(context, 2),
      enabled: task.enabled,
    );
  }

  String? _taskKwargsSummary(Schedule task) {
    final kwargsText = task.kwargs.trim();
    if (kwargsText.isEmpty || kwargsText == '{}') return null;

    final downloaders = ref.watch(downloaderListProvider).valueOrNull ?? [];

    try {
      final kwargs = jsonDecode(kwargsText) as Map<String, dynamic>;
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

      return parts.isEmpty ? null : parts.join(' · ');
    } catch (_) {
      return null;
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
