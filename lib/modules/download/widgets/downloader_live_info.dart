import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:harvest/core/utils/utils.dart';

import '../model/downloader_speed.dart';

class DownloaderLiveInfo extends StatelessWidget {
  final DownloaderInfo info;
  final bool isQb;

  const DownloaderLiveInfo({super.key, required this.info, required this.isQb});

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final typo = theme.typography;
    final uploadColor = cs.primary;
    final downloadColor = cs.destructive;
    final limitColor = Color.lerp(cs.primary, cs.destructive, 0.45)!;
    final gap = theme.density.baseGap * theme.scaling;

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: EdgeInsets.all(gap * 0.75),
        decoration: BoxDecoration(
          color: cs.muted.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: cs.border.withValues(alpha: 0.55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _speedTile(
                    icon: shadcn.LucideIcons.arrowDown,
                    label: '下载',
                    value: _formatSpeed(info.downloadSpeed),
                    color: downloadColor,
                    active: info.downloadSpeed > 0,
                    theme: theme,
                    cs: cs,
                    typo: typo,
                  ),
                ),
                SizedBox(width: gap * 0.65),
                Expanded(
                  child: _speedTile(
                    icon: shadcn.LucideIcons.arrowUp,
                    label: '上传',
                    value: _formatSpeed(info.uploadSpeed),
                    color: uploadColor,
                    active: info.uploadSpeed > 0,
                    theme: theme,
                    cs: cs,
                    typo: typo,
                  ),
                ),
              ],
            ),
            SizedBox(height: gap * 0.65),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _metricPill(
                    label: '已上传',
                    value: _formatSize(info.uploadedSession),
                    color: uploadColor,
                    cs: cs,
                    typo: typo,
                  ),
                  SizedBox(width: gap * 0.5),
                  _metricPill(
                    label: '已下载',
                    value: _formatSize(info.downloadedSession),
                    color: downloadColor,
                    cs: cs,
                    typo: typo,
                  ),
                  if (info.hasLimit) ...[
                    SizedBox(width: gap * 0.5),
                    _metricPill(
                      label: '限速',
                      value:
                          '↑${_formatLimit(info.uploadLimit)} ↓${_formatLimit(info.downloadLimit)}',
                      color: limitColor,
                      cs: cs,
                      typo: typo,
                    ),
                  ],
                  if (info.activeTorrentCount > 0) ...[
                    SizedBox(width: gap * 0.5),
                    _metricPill(
                      label: '活跃',
                      value: '${info.activeTorrentCount}',
                      color: uploadColor,
                      cs: cs,
                      typo: typo,
                    ),
                  ],
                  if (info.totalTorrentCount > 0) ...[
                    SizedBox(width: gap * 0.5),
                    _metricPill(
                      label: '总数',
                      value: '${info.totalTorrentCount}',
                      color: cs.mutedForeground,
                      cs: cs,
                      typo: typo,
                    ),
                  ],
                  if (info.freeSpace > 0) ...[
                    SizedBox(width: gap * 0.5),
                    _metricPill(
                      label: '剩余',
                      value: _formatSize(info.freeSpace),
                      color: cs.mutedForeground,
                      cs: cs,
                      typo: typo,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool active,
    required shadcn.ThemeData theme,
    required shadcn.ColorScheme cs,
    required shadcn.Typography typo,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: theme.scaling * 38),
      padding: EdgeInsets.symmetric(
        horizontal: theme.density.baseGap * theme.scaling * 0.75,
        vertical: theme.density.baseGap * theme.scaling * 0.55,
      ),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.10)
            : cs.mutedForeground.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.24)
              : cs.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: theme.scaling * 22,
            height: theme.scaling * 22,
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.14)
                  : cs.mutedForeground.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: theme.scaling * 13,
              color: active ? color : cs.mutedForeground.withValues(alpha: 0.48),
            ),
          ),
          SizedBox(width: theme.density.baseGap * theme.scaling * 0.55),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.xSmall.copyWith(
                    color: cs.mutedForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.xSmall.copyWith(
                    color: active ? color : cs.mutedForeground,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill({
    required String label,
    required String value,
    required Color color,
    required shadcn.ColorScheme cs,
    required shadcn.Typography typo,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: typo.xSmall.copyWith(
              color: cs.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.xSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSpeed(int bps) => formatBytes(bps, suffix: '/s');

  static String _formatSize(int bytes) => formatBytes(bytes);

  static String _formatLimit(int bps) =>
      formatBytes(bps, suffix: '/s', showZero: false);
}
