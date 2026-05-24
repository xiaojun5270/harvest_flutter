import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harvest/core/utils/ui/responsive.dart';
import 'package:harvest/modules/dashboard/provider/privacy_provider.dart';
import 'package:harvest/modules/torrents/torrent_list_page.dart';
import 'package:harvest/widgets/app_menu.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../model/downloader.dart';
import '../model/downloader_speed.dart';
import '../provider/downloader_speed_provider.dart';
import 'downloader_card_menu.dart';
import 'downloader_live_info.dart';

class DownloaderCard extends ConsumerStatefulWidget {
  final Downloader downloader;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback onToggleBrush;

  const DownloaderCard({
    super.key,
    required this.downloader,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    required this.onToggleBrush,
  });

  @override
  ConsumerState<DownloaderCard> createState() => _DownloaderCardState();
}

class _DownloaderCardState extends ConsumerState<DownloaderCard> {
  bool _hovered = false;

  Downloader get d => widget.downloader;

  bool get isQb => d.isQb;

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final typo = theme.typography;
    final typeColor = isQb ? cs.primary : const Color(0xFFF97316);
    final successColor = const Color(0xFF10B981);
    final inactiveColor = cs.destructive;
    final active = d.isActive;
    final privacy = ref.watch(privacyModeProvider);
    final mutedPanel = cs.muted.withValues(alpha: 0.22);
    final typeLabel = isQb ? 'QB' : 'TR';
    final typeName = isQb ? 'qBittorrent' : 'Transmission';

    // 实时数据
    final speedMap = ref.watch(downloaderSpeedProvider);
    DownloaderSpeedData? liveData;
    DownloaderInfo? liveInfo;
    for (final entry in speedMap.entries) {
      final key = entry.key.toLowerCase();
      if (key == d.wsKey.toLowerCase() || key == d.id.toString()) {
        liveData = entry.value;
        liveInfo = liveData.info;
        break;
      }
    }
    final connected = liveInfo != null;
    final version = _versionFor(liveInfo, liveData);
    final headerTint = active
        ? typeColor.withValues(alpha: connected ? 0.11 : 0.07)
        : cs.muted.withValues(alpha: 0.24);
    final cardBorder = active
        ? typeColor.withValues(alpha: _hovered ? 0.32 : 0.18)
        : cs.border.withValues(alpha: 0.72);

    final menu = DownloaderCardMenu(
      downloader: d,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onToggleActive: widget.onToggleActive,
      onToggleBrush: widget.onToggleBrush,
    );

    final card = AppContextMenu(
      items: menu.buildContextMenuItems(context),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _openTorrentList,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: cs.card.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.10 : 0.055),
                  blurRadius: _hovered ? 18 : 10,
                  offset: Offset(0, _hovered ? 8 : 4),
                ),
              ],
            ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: theme.scaling * 70,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: headerTint,
                      border: Border(
                        bottom: BorderSide(color: cs.border.withValues(alpha: 0.48)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    color: active ? typeColor : cs.mutedForeground.withValues(alpha: 0.24),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    theme.density.baseContentPadding * theme.scaling * 0.95,
                    theme.density.baseContentPadding * theme.scaling * 0.85,
                    theme.density.baseContentPadding * theme.scaling * 0.85,
                    theme.density.baseContentPadding * theme.scaling * 0.85,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _typeMark(typeLabel, typeColor, active, connected),
                          SizedBox(width: theme.density.baseGap * theme.scaling),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        d.name.isEmpty ? '未命名下载器' : d.name,
                                        style: typo.small.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.foreground,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (version.isNotEmpty)
                                      _miniBadge(version, typeColor, cs),
                                  ],
                                ),
                                SizedBox(height: theme.density.baseGap * theme.scaling * 0.45),
                                Wrap(
                                  spacing: theme.density.baseGap * theme.scaling * 0.55,
                                  runSpacing: theme.density.baseGap * theme.scaling * 0.45,
                                  children: [
                                    _statusPill(
                                      icon: connected ? shadcn.LucideIcons.link : shadcn.LucideIcons.unlink,
                                      label: connected ? '已连接' : '未连接',
                                      color: connected ? successColor : inactiveColor,
                                    ),
                                    _statusPill(
                                      icon: active ? shadcn.LucideIcons.power : shadcn.LucideIcons.powerOff,
                                      label: active ? '已启用' : '已停用',
                                      color: active ? successColor : inactiveColor,
                                    ),
                                    _statusPill(
                                      icon: shadcn.LucideIcons.zap,
                                      label: d.brush ? '辅种关闭' : '辅种开启',
                                      color: d.brush ? cs.mutedForeground : typeColor,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: theme.density.baseGap * theme.scaling),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: theme.density.baseContentPadding * theme.scaling * 0.65,
                          vertical: theme.density.baseGap * theme.scaling * 0.7,
                        ),
                        decoration: BoxDecoration(
                          color: mutedPanel,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: cs.border.withValues(alpha: 0.58)),
                        ),
                        child: Column(
                          children: [
                            _infoLine(
                              icon: shadcn.LucideIcons.server,
                              label: typeName,
                              value: _downloaderAddress(privacy),
                              accent: typeColor,
                            ),
                            SizedBox(height: theme.density.baseGap * theme.scaling * 0.55),
                            _infoLine(
                              icon: shadcn.LucideIcons.folder,
                              label: '种子路径',
                              value: d.torrentPath.isEmpty ? '-' : d.torrentPath,
                              accent: cs.mutedForeground,
                            ),
                          ],
                        ),
                      ),

                      if (liveInfo != null) ...[
                        SizedBox(height: theme.density.baseGap * theme.scaling),
                        DownloaderLiveInfo(info: liveInfo, isQb: isQb),
                      ] else ...[
                        const Spacer(),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: theme.density.baseContentPadding * theme.scaling * 0.65,
                            vertical: theme.density.baseGap * theme.scaling * 0.65,
                          ),
                          decoration: BoxDecoration(
                            color: inactiveColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: inactiveColor.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            children: [
                              Icon(shadcn.LucideIcons.activity, size: theme.scaling * 13, color: inactiveColor),
                              SizedBox(width: theme.density.baseGap * theme.scaling * 0.65),
                              Expanded(
                                child: Text(
                                  '暂无实时状态',
                                  style: typo.xSmall.copyWith(color: inactiveColor, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
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
      ),
    );

    if (!context.isMobile) return card;

    return shadcn.OverlayManagerLayer(
      popoverHandler: const shadcn.PopoverOverlayHandler(),
      tooltipHandler: const shadcn.FixedTooltipOverlayHandler(),
      menuHandler: const shadcn.PopoverOverlayHandler(),
      child: card,
    );
  }

  Future<void> _openTorrentList() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TorrentListPage(
          downloaderId: d.id,
          downloaderName: d.name,
          downloaderType: d.isQb
              ? DownloaderType.qbittorrent
              : DownloaderType.transmission,
        ),
      ),
    );
  }

  String _versionFor(DownloaderInfo? liveInfo, DownloaderSpeedData? liveData) {
    final candidates = <dynamic>[
      liveInfo?.version,
      liveData?.prefs['version'],
      liveData?.prefs['app_version'],
      liveData?.prefs['appVersion'],
      liveData?.prefs['qb_version'],
      liveData?.prefs['qbVersion'],
      d.status?['version'],
      d.status?['app_version'],
      d.status?['appVersion'],
      d.status?['qb_version'],
      d.status?['qbVersion'],
      _mapValue(d.status?['prefs'], 'version'),
      _mapValue(d.status?['preferences'], 'version'),
      d.prefs?['version'],
      d.prefs?['app_version'],
      d.prefs?['appVersion'],
      d.prefs?['qb_version'],
      d.prefs?['qbVersion'],
      isQb ? d.qbPrefs?.version : d.trPrefs?.version,
    ];
    for (final candidate in candidates) {
      final version = _normalizeVersion(candidate);
      if (version.isNotEmpty) return version;
    }
    return '';
  }

  dynamic _mapValue(dynamic value, String key) {
    if (value is Map<String, dynamic>) return value[key];
    if (value is Map) return value[key];
    return null;
  }

  String _normalizeVersion(dynamic value) {
    var text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    while (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    if (text.contains(' ')) text = text.substring(0, text.indexOf(' '));
    if (text.startsWith('v') || text.startsWith('V')) return text;
    return 'v$text';
  }

  String _downloaderAddress(bool privacy) {
    final address = '${d.protocol}://${d.host}:${d.port}';
    if (!privacy) return address;
    final uri = Uri.tryParse(address);
    if (uri == null || uri.host.isEmpty) return _maskText(address);
    final maskedHost = uri.host
        .split('.')
        .map(_maskText)
        .join('.');
    final authority = uri.hasPort ? '$maskedHost:${uri.port}' : maskedHost;
    return uri.hasScheme ? '${uri.scheme}://$authority' : authority;
  }

  String _maskText(String text) {
    if (text.length <= 1) return '*';
    if (text.length == 2) return '${text[0]}*';
    return '${text[0]}*${text[text.length - 1]}';
  }

  Widget _typeMark(String label, Color color, bool active, bool connected) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: theme.scaling * 42,
          height: theme.scaling * 42,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.14) : cs.muted.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? color.withValues(alpha: 0.32) : cs.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.typography.small.copyWith(
              color: active ? color : cs.mutedForeground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: theme.scaling * 10,
            height: theme.scaling * 10,
            decoration: BoxDecoration(
              color: connected ? const Color(0xFF10B981) : cs.mutedForeground,
              shape: BoxShape.circle,
              border: Border.all(color: cs.card, width: theme.scaling * 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = shadcn.Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.density.baseGap * theme.scaling * 0.62,
        vertical: theme.density.baseGap * theme.scaling * 0.28,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: theme.scaling * 10, color: color),
          SizedBox(width: theme.density.baseGap * theme.scaling * 0.38),
          Text(
            label,
            style: theme.typography.xSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String label, Color color, shadcn.ColorScheme cs) {
    final theme = shadcn.Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.density.baseGap * theme.scaling * 0.6,
        vertical: theme.density.baseGap * theme.scaling * 0.25,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: theme.typography.xSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _infoLine({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: theme.scaling * 20,
          height: theme.scaling * 20,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: theme.scaling * 12, color: accent),
        ),
        SizedBox(width: theme.density.baseGap * theme.scaling * 0.55),
        SizedBox(
          width: theme.scaling * 74,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.xSmall.copyWith(
              color: cs.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: theme.density.baseGap * theme.scaling * 0.45),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.xSmall.copyWith(
              color: cs.foreground.withValues(alpha: 0.82),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
