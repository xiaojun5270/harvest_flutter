import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:harvest/core/http/http.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:harvest/core/utils/utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ══════════════════════════════════════════════════════════
//  全局管理器
// ══════════════════════════════════════════════════════════

class LogOverlayManager {
  static OverlayEntry? _entry;
  static bool _visible = false;

  static bool get isVisible => _visible;

  static void show(BuildContext context) {
    if (_entry != null) return;
    _visible = true;
    _entry = OverlayEntry(builder: (_) => const _LogWindowWorkspace());
    Overlay.of(context).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
    _visible = false;
  }

  static void toggle(BuildContext context) {
    _visible ? hide() : show(context);
  }
}

class _LogWindowWorkspace extends StatefulWidget {
  const _LogWindowWorkspace();

  @override
  State<_LogWindowWorkspace> createState() => _LogWindowWorkspaceState();
}

class _LogWindowWorkspaceState extends State<_LogWindowWorkspace> {
  final _navigatorKey = GlobalKey<shadcn.WindowNavigatorHandle>();
  final List<_LogWindowItem> _items = [];
  int _windowCount = 1;

  @override
  void initState() {
    super.initState();
    _items.add(_createItem(1));
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return _PassThroughHitTest(
            activeRects: _activeRects(size),
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  shadcn.WindowNavigator(
                    key: _navigatorKey,
                    initialWindows: _items.map((item) => item.window).toList(),
                    showTopSnapBar: false,
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _workspaceButton(
                          icon: shadcn.LucideIcons.plus,
                          label: '新窗口',
                          onTap: _addWindow,
                        ),
                        const SizedBox(width: 8),
                        _workspaceButton(
                          icon: shadcn.LucideIcons.x,
                          label: '关闭',
                          onTap: LogOverlayManager.hide,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addWindow() {
    _windowCount += 1;
    final item = _createItem(_windowCount);
    setState(() => _items.add(item));
    _navigatorKey.currentState?.pushWindow(item.window);
  }

  _LogWindowItem _createItem(int index) {
    final offset = ((index - 1) % 5) * 28.0;
    final controller = shadcn.WindowController(
      bounds: Rect.fromLTWH(24 + offset, 72 + offset, 560, 430),
      constraints: const BoxConstraints(
        minWidth: 360,
        minHeight: 260,
        maxWidth: 1280,
        maxHeight: 960,
      ),
    );
    late final _LogWindowItem item;
    final window = shadcn.Window.controlled(
      controller: controller,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(shadcn.LucideIcons.terminal, size: 14),
          const SizedBox(width: 6),
          Text('日志 $index'),
        ],
      ),
      content: const _LogFloatingWidget(),
    );
    item = _LogWindowItem(index: index, controller: controller, window: window);
    void update() {
      if (!mounted) return;
      if (window.closed.value) {
        setState(() => _items.remove(item));
      } else {
        setState(() {});
      }
    }
    controller.addListener(update);
    window.closed.addListener(update);
    item.disposeCallback = () {
      controller.removeListener(update);
      window.closed.removeListener(update);
      controller.dispose();
    };
    return item;
  }

  List<Rect> _activeRects(Size size) {
    final rects = <Rect>[
      Rect.fromLTWH(size.width - 190, 8, 182, 54),
    ];
    for (final item in _items) {
      if (item.window.closed.value) continue;
      final state = item.controller.value;
      if (state.minimized) continue;
      rects.add(state.bounds.inflate(14));
      if (state.maximized != null) {
        rects.add(Offset.zero & size);
      }
    }
    return rects;
  }

  Widget _workspaceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = _LogPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.panel.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colors.foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: colors.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogWindowItem {
  final int index;
  final shadcn.WindowController controller;
  final shadcn.Window window;
  VoidCallback? disposeCallback;

  _LogWindowItem({
    required this.index,
    required this.controller,
    required this.window,
  });

  void dispose() {
    disposeCallback?.call();
  }
}

class _PassThroughHitTest extends SingleChildRenderObjectWidget {
  final List<Rect> activeRects;

  const _PassThroughHitTest({
    required this.activeRects,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPassThroughHitTest(activeRects);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPassThroughHitTest renderObject,
  ) {
    renderObject.activeRects = activeRects;
  }
}

class _RenderPassThroughHitTest extends RenderProxyBox {
  List<Rect> _activeRects;

  _RenderPassThroughHitTest(this._activeRects);

  set activeRects(List<Rect> value) {
    _activeRects = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    for (final rect in _activeRects) {
      if (rect.contains(position)) {
        return super.hitTest(result, position: position);
      }
    }
    return false;
  }
}

// ══════════════════════════════════════════════════════════
//  日志级别过滤
// ══════════════════════════════════════════════════════════

enum _FilterLevel {
  all('ALL'),
  verbose('V'),
  debug('D'),
  info('I'),
  warn('W'),
  error('E');

  final String label;

  const _FilterLevel(this.label);
}

enum _LogSource {
  app('APP'),
  server('服务');

  final String label;

  const _LogSource(this.label);
}

class _LogPalette {
  final bool isDark;
  final Color surface;
  final Color panel;
  final Color border;
  final Color foreground;
  final Color muted;
  final Color subtle;
  final Color primary;
  final Color success;
  final Color verbose;
  final Color debug;
  final Color info;
  final Color warn;
  final Color error;
  final Color lineDefault;
  final Color shadow;

  const _LogPalette({
    required this.isDark,
    required this.surface,
    required this.panel,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.subtle,
    required this.primary,
    required this.success,
    required this.verbose,
    required this.debug,
    required this.info,
    required this.warn,
    required this.error,
    required this.lineDefault,
    required this.shadow,
  });

  factory _LogPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _LogPalette(
        isDark: true,
        surface: Color(0xFF0D1117),
        panel: Color(0xFF161B22),
        border: Color(0xFF30363D),
        foreground: Color(0xFFE6EDF3),
        muted: Color(0xFF8B949E),
        subtle: Color(0xFF484F58),
        primary: Color(0xFF58A6FF),
        success: Color(0xFF3FB950),
        verbose: Color(0xFF8B949E),
        debug: Color(0xFF7EE787),
        info: Color(0xFF58A6FF),
        warn: Color(0xFFD29922),
        error: Color(0xFFF85149),
        lineDefault: Color(0xFFC9D1D9),
        shadow: Color(0x66000000),
      );
    }
    return const _LogPalette(
      isDark: false,
      surface: Color(0xFFFFFFFF),
      panel: Color(0xFFF8FAFC),
      border: Color(0xFFD8DEE8),
      foreground: Color(0xFF0F172A),
      muted: Color(0xFF64748B),
      subtle: Color(0xFF94A3B8),
      primary: Color(0xFF2563EB),
      success: Color(0xFF16A34A),
      verbose: Color(0xFF64748B),
      debug: Color(0xFF15803D),
      info: Color(0xFF2563EB),
      warn: Color(0xFFB45309),
      error: Color(0xFFDC2626),
      lineDefault: Color(0xFF334155),
      shadow: Color(0x22000000),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  悬浮窗主体
// ══════════════════════════════════════════════════════════

class _LogFloatingWidget extends StatefulWidget {
  const _LogFloatingWidget();

  @override
  State<_LogFloatingWidget> createState() => _LogFloatingWidgetState();
}

class _LogFloatingWidgetState extends State<_LogFloatingWidget> {
  // ── 状态 ──
  bool _following = true;
  _LogSource _source = _LogSource.app;

  // ── 过滤 ──
  _FilterLevel _filter = _FilterLevel.all;
  LogLevel _streamLevel = LogLevel.info;
  static const int _streamLimit = 200;
  static const List<LogLevel> _streamLevels = [
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  ];

  // ── 日志数据 ──
  final List<String> _appLines = [];
  final List<String> _serverLines = [];
  Timer? _appTailTimer;
  int _appLastFileLength = 0;
  String? _appLogPath;
  CancelToken? _streamCancelToken;
  String? _connectionId;
  String? _streamError;
  bool _connected = false;
  DateTime? _lastHeartbeatAt;

  bool _showLevelPicker = false;

  // ── 滚动 ──
  final _scrollController = ScrollController();

  List<String> get _lines => _source == _LogSource.app ? _appLines : _serverLines;

  @override
  void initState() {
    super.initState();
    _startAppTailing();
  }

  @override
  void dispose() {
    _appTailTimer?.cancel();
    _cancelStream('日志浮窗关闭');
    _scrollController.dispose();
    super.dispose();
  }

  // ────────────────── 日志源 ──────────────────

  void _switchSource(_LogSource source) {
    if (_source == source) return;
    _appTailTimer?.cancel();
    _cancelStream('切换日志源');
    setState(() {
      _source = source;
      _showLevelPicker = false;
    });
    if (source == _LogSource.app) {
      _startAppTailing();
    } else {
      _connectStream();
    }
    if (_following) _scrollToBottom();
  }

  void _refreshCurrentSource() {
    if (_source == _LogSource.app) {
      _startAppTailing(reset: true);
    } else {
      _connectStream();
    }
  }

  // ────────────────── APP 文件日志 ──────────────────

  Future<void> _startAppTailing({bool reset = false}) async {
    _appTailTimer?.cancel();
    if (reset) {
      setState(() {
        _appLines.clear();
        _appLastFileLength = 0;
        _appLogPath = null;
      });
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final date = DateTime.now().toString().split(' ')[0];
      final logPath = p.join(dir.path, 'logs', 'app_$date.log');
      final file = File(logPath);

      if (!await file.exists()) {
        setState(() => _appLogPath = logPath);
        _appTailTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (await File(logPath).exists()) {
            _appTailTimer?.cancel();
            await _loadAppInitial(File(logPath));
            _startAppPeriodic();
          }
        });
        return;
      }

      await _loadAppInitial(file);
      _startAppPeriodic();
    } catch (e) {
      _addAppLine('[ERROR] APP日志追踪失败: $e');
    }
  }

  Future<void> _loadAppInitial(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final lines = content.split('\n').where((line) => line.isNotEmpty).toList();
      final tail = lines.length > 200 ? lines.sublist(lines.length - 200) : lines;
      setState(() {
        _appLogPath = file.path;
        _appLastFileLength = bytes.length;
        _appLines
          ..clear()
          ..addAll(tail);
      });
      if (_following) _scrollToBottom();
    } catch (e) {
      _addAppLine('[ERROR] APP日志读取失败: $e');
    }
  }

  void _startAppPeriodic() {
    _appTailTimer?.cancel();
    _appTailTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tailAppUpdate());
  }

  Future<void> _tailAppUpdate() async {
    final logPath = _appLogPath;
    if (logPath == null) return;
    try {
      final file = File(logPath);
      if (!await file.exists()) return;

      final stat = await file.stat();
      final currentLength = stat.size;
      if (currentLength == _appLastFileLength) return;

      if (currentLength < _appLastFileLength) {
        await _loadAppInitial(file);
        return;
      }

      final raf = file.openSync(mode: FileMode.read);
      raf.setPositionSync(_appLastFileLength);
      final newBytes = raf.readSync(currentLength - _appLastFileLength);
      raf.closeSync();
      _appLastFileLength = currentLength;

      final newContent = utf8.decode(newBytes, allowMalformed: true);
      final newLines = newContent.split('\n').where((line) => line.isNotEmpty).toList();
      if (newLines.isEmpty) return;

      setState(() {
        _appLines.addAll(newLines);
        if (_appLines.length > 2000) {
          _appLines.removeRange(0, _appLines.length - 1500);
        }
      });
      if (_source == _LogSource.app && _following) _scrollToBottom();
    } catch (_) {}
  }

  void _addAppLine(String line) {
    setState(() => _appLines.add(line));
    if (_source == _LogSource.app && _following) _scrollToBottom();
  }

  // ────────────────── 后端日志 SSE ──────────────────

  Future<void> _connectStream() async {
    _cancelStream('重新连接日志流');
    final cancelToken = CancelToken();
    _streamCancelToken = cancelToken;
    if (mounted) {
      setState(() {
        _connected = false;
        _streamError = null;
        _connectionId = null;
        _lastHeartbeatAt = null;
      });
    }
    try {
      final responseBody = await Http.get<ResponseBody>(
        '/api/auth/logs/stream',
        queryParameters: {
          'level': _levelParam(_streamLevel),
          'limit': _streamLimit,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
        ),
        cancelToken: cancelToken,
      );

      var buffer = '';
      await for (final chunk in responseBody.stream) {
        if (cancelToken.isCancelled) break;
        buffer += utf8
            .decode(chunk, allowMalformed: true)
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');

        while (buffer.contains('\n\n')) {
          final index = buffer.indexOf('\n\n');
          final event = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 2);
          _processStreamEvent(event);
        }
      }

      final remaining = buffer.trim();
      if (remaining.isNotEmpty) _processStreamEvent(remaining);
    } on DioException catch (e) {
      if (!cancelToken.isCancelled) _markStreamError(e.message ?? e.toString());
    } catch (e) {
      if (!cancelToken.isCancelled) _markStreamError(e.toString());
    } finally {
      if (identical(_streamCancelToken, cancelToken)) {
        _streamCancelToken = null;
      }
    }
  }

  void _cancelStream(String reason) {
    final token = _streamCancelToken;
    _streamCancelToken = null;
    if (token != null && !token.isCancelled) {
      token.cancel(reason);
    }
  }

  void _processStreamEvent(String event) {
    if (!mounted || event.trim().isEmpty) return;
    final jsonText = _eventData(event);
    if (jsonText.isEmpty) return;

    try {
      final payload = jsonDecode(jsonText) as Map<String, dynamic>;
      if (payload['code'] != 0 || payload['data'] is! Map) {
        final msg = payload['msg']?.toString();
        if (msg != null && msg.isNotEmpty) _markStreamError(msg);
        return;
      }

      final data = Map<String, dynamic>.from(payload['data'] as Map);
      final type = data['type']?.toString();
      final connectionId = data['connectionId']?.toString();

      if (type == 'connected') {
        setState(() {
          _connected = true;
          _streamError = null;
          _connectionId = connectionId;
        });
        return;
      }

      if (type == 'heartbeat') {
        setState(() {
          _connected = true;
          _streamError = null;
          _connectionId = connectionId ?? _connectionId;
          _lastHeartbeatAt = DateTime.now();
        });
        return;
      }

      final entries = data['entries'];
      if (entries is! List) return;
      final lines = entries
          .whereType<Map>()
          .map((entry) => _entryLine(Map<String, dynamic>.from(entry)))
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) return;

      setState(() {
        _connected = true;
        _streamError = null;
        _connectionId = connectionId ?? _connectionId;
        if (type == 'snapshot') {
          _serverLines
            ..clear()
            ..addAll(lines);
        } else {
          _serverLines.addAll(lines);
          if (_serverLines.length > 2000) {
            _serverLines.removeRange(0, _serverLines.length - 1500);
          }
        }
      });
      if (_source == _LogSource.server && _following) _scrollToBottom();
    } catch (e) {
      _markStreamError('日志流解析失败: $e');
    }
  }

  String _eventData(String event) {
    final dataLines = <String>[];
    for (final line in event.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('data:')) {
        dataLines.add(trimmed.substring(5).trim());
      } else if (trimmed.startsWith('{')) {
        dataLines.add(trimmed);
      }
    }
    return dataLines.join('\n').trim();
  }

  String _entryLine(Map<String, dynamic> entry) {
    final display = entry['display']?.toString();
    if (display != null && display.isNotEmpty) return display;
    final raw = entry['raw']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    final timestamp = entry['timestamp']?.toString() ?? entry['logged_at']?.toString() ?? '';
    final level = entry['level']?.toString() ?? '';
    final message = entry['message']?.toString() ?? '';
    return [timestamp, level, message].where((v) => v.isNotEmpty).join(' | ');
  }

  void _markStreamError(String message) {
    if (!mounted) return;
    setState(() {
      _connected = false;
      _streamError = message;
      _serverLines.add('[ERROR] $message');
      if (_serverLines.length > 2000) {
        _serverLines.removeRange(0, _serverLines.length - 1500);
      }
    });
    if (_source == _LogSource.server && _following) _scrollToBottom();
  }

  String _levelParam(LogLevel level) {
    switch (level) {
      case LogLevel.verbose:
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warn:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.off:
        return 'OFF';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ────────────────── 过滤后的行 ──────────────────

  List<_IndexedLine> get _filteredLines {
    if (_filter == _FilterLevel.all) {
      return List.generate(_lines.length, (i) => _IndexedLine(i, _lines[i]));
    }
    final result = <_IndexedLine>[];
    for (var i = 0; i < _lines.length; i++) {
      if (_matchesFilter(_lines[i])) {
        result.add(_IndexedLine(i, _lines[i]));
      }
    }
    return result;
  }

  bool _matchesFilter(String line) {
    final level = _lineLevel(line);
    switch (_filter) {
      case _FilterLevel.all:
        return true;
      case _FilterLevel.verbose:
        return level == 'VERBOSE' || level == 'TRACE';
      case _FilterLevel.debug:
        return level == 'DEBUG';
      case _FilterLevel.info:
        return level == 'INFO';
      case _FilterLevel.warn:
        return level == 'WARN' || level == 'WARNING';
      case _FilterLevel.error:
        return level == 'ERROR';
    }
  }

  // ────────────────── 操作 ──────────────────

  void _clearLogs() {
    setState(() => _lines.clear());
    Toast.success('已清空');
  }

  Future<void> _shareLogs() async {
    try {
      await AppLogger.shareLogs();
      Toast.success('日志已打包分享');
    } catch (e) {
      Toast.error('分享失败');
    }
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    Toast.success('已复制全部');
  }

  // ────────────────── 构建 ──────────────────

  @override
  Widget build(BuildContext context) {
    final colors = _LogPalette.of(context);
    return Container(
      color: colors.surface,
      child: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(child: _buildLogList()),
          _buildToolbar(),
          _buildStatusBar(),
        ],
      ),
    );
  }

  // ── 标题栏 ──

  Widget _buildHeader() {
    final colors = _LogPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          _sourceChip(_LogSource.app),
          _sourceChip(_LogSource.server),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _following = !_following),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _following
                    ? colors.success.withValues(alpha: 0.16)
                    : colors.subtle.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _following ? 'LIVE' : 'PAUSE',
                style: TextStyle(
                  color: _following ? colors.success : colors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceChip(_LogSource source) {
    final colors = _LogPalette.of(context);
    final selected = _source == source;
    return GestureDetector(
      onTap: () => _switchSource(source),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colors.primary.withValues(alpha: 0.32) : colors.border,
          ),
        ),
        child: Text(
          source.label,
          style: TextStyle(
            color: selected ? colors.primary : colors.muted,
            fontSize: 9,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── 级别过滤栏 ──

  Widget _buildFilterBar() {
    final colors = _LogPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: _FilterLevel.values.map((level) {
          final selected = level == _filter;
          final levelColor = _filterLevelColor(level);
          return GestureDetector(
            onTap: () {
              setState(() => _filter = level);
              if (_following) _scrollToBottom();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: selected ? levelColor.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: selected ? levelColor.withValues(alpha: 0.4) : Colors.transparent),
              ),
              child: Text(
                level.label,
                style: TextStyle(
                  color: selected ? levelColor : colors.subtle,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 日志列表 ──

  Widget _buildLogList() {
    final filtered = _filteredLines;
    final colors = _LogPalette.of(context);

    if (filtered.isEmpty) {
      return Center(
        child: Text('暂无日志', style: TextStyle(color: colors.subtle, fontSize: 11)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _buildLine(filtered[i]),
    );
  }

  Widget _buildLine(_IndexedLine item) {
    final colors = _LogPalette.of(context);
    final color = _getLevelColor(item.line);
    final isLast = item.originalIndex == _lines.length - 1;

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: item.line));
        Toast.success('已复制');
      },
      child: Container(
        color: isLast ? color.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${item.originalIndex + 1}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.subtle,
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Container(
              width: 2,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
            ),
            // 级别标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              margin: const EdgeInsets.only(right: 4, top: 1),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)),
              child: Text(
                _getLevelTag(item.line),
                style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                _stripLevelTag(item.line),
                style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10, fontFamily: 'monospace', height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 工具栏 ──
  Widget _buildToolbar() {
    final colors = _LogPalette.of(context);
    final currentLevel = _source == _LogSource.app ? AppLogger.level : _streamLevel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.panel,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              // ── 日志级别 ──
              GestureDetector(
                onTap: () => setState(() => _showLevelPicker = !_showLevelPicker),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 11, color: colors.primary),
                      const SizedBox(width: 3),
                      Text(
                        currentLevel.name.toUpperCase(),
                        style: TextStyle(color: colors.primary, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: _showLevelPicker ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.keyboard_arrow_down, size: 12, color: colors.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(width: 0.5, height: 14, color: colors.border),
              const SizedBox(width: 6),
              _toolBtn(icon: Icons.copy_rounded, label: '复制', onTap: _copyAll),
              _toolBtn(icon: shadcn.LucideIcons.share2, label: '分享', onTap: _shareLogs),
              _toolBtn(icon: shadcn.LucideIcons.trash2, label: '清空', onTap: _clearLogs),
              _toolBtn(
                icon: shadcn.LucideIcons.refreshCw,
                label: _source == _LogSource.app ? '刷新' : '重连',
                onTap: _refreshCurrentSource,
              ),
            ],
          ),
        ),
        // ── 级别下拉面板 ──
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _showLevelPicker ? _buildLevelDropdown() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildLevelDropdown() {
    final colors = _LogPalette.of(context);
    final current = _source == _LogSource.app ? AppLogger.level : _streamLevel;
    final levels = _source == _LogSource.app ? LogLevel.values : _streamLevels;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border),
          bottom: BorderSide(color: colors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('日志级别', style: TextStyle(color: colors.subtle, fontSize: 9)),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: levels.map((level) {
              final selected = level == current;
              final color = _levelColor(level);
              return GestureDetector(
                onTap: () {
                  if (_source == _LogSource.app) {
                    AppLogger.reinit(level);
                    setState(() => _showLevelPicker = false);
                    Toast.success('已切换为 ${level.name}');
                  } else {
                    setState(() {
                      _streamLevel = level;
                      _showLevelPicker = false;
                    });
                    _connectStream();
                    Toast.success('已切换为 ${_levelParam(level)}');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected ? color.withValues(alpha: 0.15) : colors.panel,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: selected ? color.withValues(alpha: 0.4) : colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        level.name[0].toUpperCase() + level.name.substring(1),
                        style: TextStyle(
                          color: selected ? color : colors.muted,
                          fontSize: 8,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _levelColor(LogLevel level) {
    final colors = _LogPalette.of(context);
    switch (level) {
      case LogLevel.verbose:
        return colors.verbose;
      case LogLevel.debug:
        return colors.debug;
      case LogLevel.info:
        return colors.info;
      case LogLevel.warn:
        return colors.warn;
      case LogLevel.error:
        return colors.error;
      case LogLevel.off:
        return colors.subtle;
    }
  }

  Color _filterLevelColor(_FilterLevel level) {
    final colors = _LogPalette.of(context);
    switch (level) {
      case _FilterLevel.all:
        return colors.lineDefault;
      case _FilterLevel.verbose:
        return colors.verbose;
      case _FilterLevel.debug:
        return colors.debug;
      case _FilterLevel.info:
        return colors.info;
      case _FilterLevel.warn:
        return colors.warn;
      case _FilterLevel.error:
        return colors.error;
    }
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final colors = _LogPalette.of(context);
    final color = destructive ? colors.error : colors.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── 状态栏 ──

  Widget _buildStatusBar() {
    final colors = _LogPalette.of(context);
    final filtered = _filteredLines;
    final filterColor = _filterLevelColor(_filter);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: filterColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
            child: Text(
              _filter == _FilterLevel.all ? '${_lines.length} 行' : '${filtered.length}/${_lines.length}',
              style: TextStyle(
                color: filterColor.withValues(alpha: 0.7),
                fontSize: 9,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          if (_source == _LogSource.app)
            Text(
              _appLogPath == null ? 'APP日志' : p.basename(_appLogPath!),
              style: TextStyle(color: colors.subtle, fontSize: 9),
            )
          else if (_streamError != null)
            Flexible(
              child: Text(
                _streamError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.error, fontSize: 9),
              ),
            )
          else
            Text(
              _connected
                  ? 'SSE ${_levelParam(_streamLevel)} ${_connectionId ?? ''}${_heartbeatText()}'
                  : '连接中...',
              style: TextStyle(color: colors.subtle, fontSize: 9),
            ),
        ],
      ),
    );
  }

  // ────────────────── 工具 ──────────────────

  Color _getLevelColor(String line) {
    final colors = _LogPalette.of(context);
    final level = _lineLevel(line);
    if (level == 'ERROR') {
      return colors.error;
    }
    if (level == 'WARN' || level == 'WARNING') {
      return colors.warn;
    }
    if (level == 'INFO') {
      return colors.info;
    }
    if (level == 'DEBUG') {
      return colors.debug;
    }
    if (level == 'VERBOSE' || level == 'TRACE') {
      return colors.verbose;
    }
    return colors.lineDefault;
  }

  String _getLevelTag(String line) {
    final level = _lineLevel(line);
    if (level.isEmpty) return '-';
    return level.substring(0, 1);
  }

  String _stripLevelTag(String line) {
    final bracketMatch = RegExp(r'^\[.*?\]\s*\[.*?\]\s*').matchAsPrefix(line);
    if (bracketMatch != null) {
      return line.substring(bracketMatch.end);
    }
    final pipeMatch = RegExp(r'^\s*\d{4}-\d{2}-\d{2}[^|]*\|\s*[A-Z]+\s*\|\s*').matchAsPrefix(line);
    if (pipeMatch != null) {
      return line.substring(pipeMatch.end);
    }
    return line;
  }

  String _lineLevel(String line) {
    final bracket = RegExp(r'\[(VERBOSE|TRACE|DEBUG|INFO|WARN|WARNING|ERROR)\]').firstMatch(line);
    if (bracket != null) return bracket.group(1)!;
    final pipe = RegExp(r'\|\s*(VERBOSE|TRACE|DEBUG|INFO|WARN|WARNING|ERROR)\s*\|').firstMatch(line);
    if (pipe != null) return pipe.group(1)!;
    final plain = RegExp(r'\b(VERBOSE|TRACE|DEBUG|INFO|WARN|WARNING|ERROR)\b').firstMatch(line);
    if (plain != null) return plain.group(1)!;
    return '';
  }

  String _heartbeatText() {
    final heartbeat = _lastHeartbeatAt;
    if (heartbeat == null) return '';
    final now = DateTime.now();
    final seconds = now.difference(heartbeat).inSeconds;
    if (seconds < 60) return ' · ${seconds}s';
    return ' · ${heartbeat.hour.toString().padLeft(2, '0')}:${heartbeat.minute.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════
//  辅助
// ══════════════════════════════════════════════════════════

class _IndexedLine {
  final int originalIndex;
  final String line;

  const _IndexedLine(this.originalIndex, this.line);
}
