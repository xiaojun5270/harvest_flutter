import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:harvest/core/config/app_config.dart';
import 'package:harvest/core/http/api.dart';
import 'package:harvest/core/storage/hive_manager.dart';
import 'package:harvest/core/storage/storage_keys.dart';
import 'package:harvest/core/utils/utils.dart';
import 'package:harvest/modules/option/widgets/app_upgrade_page.dart';
import 'package:harvest/modules/shell/widgets/log_floating_overlay.dart';
import 'package:harvest/router/app_router.dart';
import 'package:harvest/widgets/shad_text_field.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../login/login_history_provider.dart';
import '../login/login_record.dart';
import 'auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _appUpgradeController = AppUpgradeController();
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _filledFromHistory = false;
  static const _debugUsername = 'admin';
  static const _debugPassword = 'adminadmin';
  static const _debugServer = 'http://127.0.0.1:8000';

  @override
  void initState() {
    super.initState();
    final savedServer = HiveManager.get<String>(StorageKeys.baseUrl) ?? '';
    final webServer = kIsWeb ? _webServerFromPageUrl() : null;
    if (kDebugMode) {
      _serverController = TextEditingController(
        text:
            webServer ?? (savedServer.isNotEmpty ? savedServer : _debugServer),
      );
      _usernameController = TextEditingController(text: _debugUsername);
      _passwordController = TextEditingController(text: _debugPassword);
    } else {
      _serverController = TextEditingController(text: webServer ?? savedServer);
      _usernameController = TextEditingController();
      _passwordController = TextEditingController();
    }
    Future<void>.delayed(Duration.zero, () {
      ref.read(postLogoutRouteProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final loginHistory = ref.watch(loginHistoryProvider);
    final showLoginHistory = loginHistory.length >= 2;
    final tokens = _LoginThemeTokens.of(context);
    final theme = tokens.theme;
    final cs = theme.colorScheme;

    _fillFromLoginHistory(loginHistory);
    ref.listen(
      loginHistoryProvider,
      (prev, next) => _fillFromLoginHistory(next),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ColoredBox(
        color: cs.background,
        child: Stack(
          children: [
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final verticalPadding = tokens.size(24);
                    final minHeight =
                        (constraints.maxHeight - verticalPadding * 2)
                            .clamp(0.0, double.infinity)
                            .toDouble();

                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: tokens.edgeSymmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minHeight),
                        child: Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: tokens.formWidth,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                tokens.vGap(40),
                                Image.asset(
                                  'assets/images/logo.png',
                                  width: tokens.logoSize,
                                  height: tokens.logoSize,
                                  fit: BoxFit.contain,
                                ),
                                tokens.vGap(16),
                                Text(
                                  kDebugMode ? '调试模式' : 'PT 一下',
                                  style: theme.typography.xLarge.copyWith(
                                    color: cs.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                tokens.vGap(20),
                                ShadTextField(
                                  controller: _serverController,
                                  placeholder: const Text('服务器地址'),
                                  enabled: !kIsWeb,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                ),
                                tokens.fieldGap,
                                ShadTextField(
                                  controller: _usernameController,
                                  placeholder: const Text('账号'),
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                ),
                                tokens.fieldGap,
                                ShadTextField(
                                  controller: _passwordController,
                                  placeholder: const Text('密码'),
                                  obscureText: true,
                                  maxLines: 1,
                                  features: const [
                                    shadcn.InputFeature.passwordToggle(),
                                  ],
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                ),
                                tokens.vGap(20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: shadcn.Button.primary(
                                        onPressed: auth.loading
                                            ? null
                                            : () async {
                                                final serverError =
                                                    _validateServerAddress(
                                                      _serverController.text,
                                                    );
                                                if (serverError != null) {
                                                  Toast.error(serverError);
                                                  return;
                                                }
                                                final baseUrl =
                                                    AppConfig.normalizeBaseUrl(
                                                      _serverController.text,
                                                    );
                                                final setupStatus =
                                                    await _fetchSetupStatus(
                                                      baseUrl,
                                                    );
                                                if (setupStatus?.needsSetup ==
                                                    true) {
                                                  await _showSetupDialog(
                                                    baseUrl,
                                                  );
                                                  return;
                                                }
                                                try {
                                                  await ref
                                                      .read(
                                                        authNotifierProvider
                                                            .notifier,
                                                      )
                                                      .login(
                                                        baseUrl,
                                                        _usernameController.text
                                                            .trim(),
                                                        _passwordController
                                                            .text,
                                                      );
                                                } catch (e, trace) {
                                                  AppLogger.error(e);
                                                  AppLogger.error(trace);
                                                  if (_isSetupRequiredError(
                                                    e,
                                                  )) {
                                                    if (context.mounted) {
                                                      await _showSetupDialog(
                                                        baseUrl,
                                                      );
                                                    }
                                                    return;
                                                  }
                                                  if (context.mounted) {
                                                    Toast.error(
                                                      _loginErrorMessage(e),
                                                    );
                                                  }
                                                }
                                              },
                                        child: Center(
                                          child: Text(
                                            auth.loading ? '登录中...' : '登录',
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (showLoginHistory) ...[
                                      tokens.actionGap,
                                      shadcn.IconButton.outline(
                                        onPressed: auth.loading
                                            ? null
                                            : () =>
                                                  context.go('/login-history'),
                                        icon: shadcn.Tooltip(
                                          tooltip: (_) => const Text('登录历史'),
                                          child: Icon(
                                            shadcn.LucideIcons.history,
                                            size: tokens.iconSize,
                                          ),
                                        ),
                                      ),
                                    ],
                                    tokens.actionGap,
                                    shadcn.IconButton.outline(
                                      onPressed: () =>
                                          LogOverlayManager.toggle(context),
                                      icon: shadcn.Tooltip(
                                        tooltip: (_) => const Text('日志中心'),
                                        child: Icon(
                                          shadcn.LucideIcons.terminal,
                                          size: tokens.iconSize,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (!kIsWeb) ...[
              IgnorePointer(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: AppUpgradePage(
                    autoCheck: false,
                    controller: _appUpgradeController,
                    child: const SizedBox.shrink(),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: tokens.edgeSymmetric(horizontal: 16, vertical: 12),
                    child: shadcn.IconButton.outline(
                      onPressed: () =>
                          unawaited(_appUpgradeController.openDialog()),
                      icon: shadcn.Tooltip(
                        tooltip: (_) => const Text('APP 升级'),
                        child: Icon(
                          shadcn.LucideIcons.circleArrowUp,
                          size: tokens.iconSize,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _fillFromLoginHistory(List<LoginRecord> history) {
    if (_filledFromHistory || history.isEmpty) return;
    final latest = history.first;
    if (!kIsWeb && _canFillServer()) {
      _serverController.text = latest.server;
    }
    if (_canFillUsername()) {
      _usernameController.text = latest.username;
    }
    if (_canFillPassword()) {
      _passwordController.text = latest.password;
    }
    _filledFromHistory = true;
  }

  bool _canFillServer() {
    final value = _serverController.text.trim();
    return value.isEmpty || (kDebugMode && value == _debugServer);
  }

  bool _canFillUsername() {
    final value = _usernameController.text.trim();
    return value.isEmpty || (kDebugMode && value == _debugUsername);
  }

  bool _canFillPassword() {
    final value = _passwordController.text;
    return value.isEmpty || (kDebugMode && value == _debugPassword);
  }

  Future<_SetupStatus?> _fetchSetupStatus(String baseUrl) async {
    try {
      final res = await Dio().get<Map<String, dynamic>>(
        '$baseUrl${API.setupStatus}',
        options: Options(validateStatus: (_) => true),
      );
      final body = res.data;
      if (body == null || body['succeed'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return _SetupStatus.fromMap(data);
    } catch (e) {
      AppLogger.warn('获取初始化状态失败: $e');
      return null;
    }
  }

  Future<void> _showSetupDialog(String baseUrl) async {
    if (!mounted) return;
    final credentials = await shadcn.showDialog<_SetupCredentials>(
      context: context,
      builder: (ctx) => shadcn.AlertDialog(
        content: SizedBox(
          width: min(MediaQuery.sizeOf(ctx).width - 32, 760),
          child: _SetupDialogContent(baseUrl: baseUrl),
        ),
      ),
    );
    if (!mounted || credentials == null) return;
    _usernameController.text = credentials.username;
    _passwordController.text = credentials.password;
    Toast.success('初始化完成，请登录');
  }

  bool _isSetupRequiredError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final message =
          _extractLoginErrorMessage(data) ?? error.error?.toString();
      return status == 503 &&
          message != null &&
          (message.contains('尚未初始化') || message.contains('/setup'));
    }
    return false;
  }

  String _loginErrorMessage(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel &&
          _isCredentialErrorMessage(error.error?.toString())) {
        return '账号或密码错误';
      }
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final serverMessage = _extractLoginErrorMessage(data);
      if (_isCredentialErrorMessage(serverMessage)) return '账号或密码错误';
      if (serverMessage != null) return serverMessage;
      if (status == 400 || status == 401) return '账号或密码错误';
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '服务器连接失败，请检查网络或服务器地址';
      }
    }
    return '登录失败，请检查账号信息';
  }

  bool _isCredentialErrorMessage(String? message) {
    final normalized = message?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return normalized == 'token_expired' ||
        normalized.contains('token_expired') ||
        normalized.contains('no active account') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('incorrect');
  }

  String? _extractLoginErrorMessage(dynamic data) {
    if (data is! Map) return null;
    for (final key in const ['msg', 'message', 'detail', 'error']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _webServerFromPageUrl() {
    final uri = Uri.base;
    if (uri.host.isEmpty) return uri.origin;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  String? _validateServerAddress(String input) {
    final server = input.trim();
    if (server.length < 10) return '服务器地址长度不能少于 10 位';
    if (!(server.startsWith('http://') || server.startsWith('https://'))) {
      return '服务器地址必须以 http:// 或 https:// 开头';
    }
    return null;
  }
}

class _LoginThemeTokens {
  final shadcn.ThemeData theme;
  final double densityScale;
  final double textScale;

  _LoginThemeTokens._({
    required this.theme,
    required this.densityScale,
    required this.textScale,
  });

  factory _LoginThemeTokens.of(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final densityScale =
        ((theme.density.baseContentPadding / 16.0) * theme.scaling).clamp(
          0.62,
          1.45,
        );
    final textScale = theme.scaling.clamp(0.86, 1.30);
    return _LoginThemeTokens._(
      theme: theme,
      densityScale: densityScale.toDouble(),
      textScale: textScale.toDouble(),
    );
  }

  double size(num value) => value * densityScale;

  double font(num value) => value * textScale;

  double get formWidth => size(320);

  double get logoSize => size(136);

  double get iconSize => font(18);

  SizedBox get fieldGap => vGap(12);

  SizedBox get actionGap => hGap(10);

  EdgeInsets edgeSymmetric({num horizontal = 0, num vertical = 0}) =>
      EdgeInsets.symmetric(
        horizontal: size(horizontal),
        vertical: size(vertical),
      );

  SizedBox hGap(num value) => SizedBox(width: size(value));

  SizedBox vGap(num value) => SizedBox(height: size(value));
}

class _SetupStatus {
  final bool initialized;
  final bool needsSetup;

  const _SetupStatus({required this.initialized, required this.needsSetup});

  factory _SetupStatus.fromMap(Map<dynamic, dynamic> data) {
    return _SetupStatus(
      initialized: data['initialized'] == true,
      needsSetup: data['needs_setup'] == true,
    );
  }
}

class _SetupCredentials {
  final String username;
  final String password;

  const _SetupCredentials({required this.username, required this.password});
}

class _SetupDialogContent extends StatefulWidget {
  final String baseUrl;

  const _SetupDialogContent({required this.baseUrl});

  @override
  State<_SetupDialogContent> createState() => _SetupDialogContentState();
}

class _SetupDialogContentState extends State<_SetupDialogContent> {
  final _hostCtrl = TextEditingController(text: '127.0.0.1');
  final _portCtrl = TextEditingController(text: '5432');
  final _nameCtrl = TextEditingController(text: 'goharvest');
  final _userCtrl = TextEditingController(text: 'goharvest');
  final _passCtrl = TextEditingController();
  final _adminUserCtrl = TextEditingController(text: 'admin');
  final _adminEmailCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();
  final _jwtSecretCtrl = TextEditingController();
  String _databaseType = 'pgsql';
  bool _debug = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _jwtSecretCtrl.text = _randomHex(32);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _adminUserCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPassCtrl.dispose();
    _jwtSecretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final cs = theme.colorScheme;
    final sqlite = _databaseType == 'sqlite';

    return shadcn.OverlayManagerLayer(
      popoverHandler: const shadcn.PopoverOverlayHandler(),
      tooltipHandler: const shadcn.FixedTooltipOverlayHandler(),
      menuHandler: const shadcn.PopoverOverlayHandler(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Go Harvest 初始化',
                          style: theme.typography.large.copyWith(
                            color: cs.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '填写数据库连接和管理员账户后即可完成初始化。',
                          style: theme.typography.small.copyWith(
                            color: cs.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(context),
                ],
              ),
              const SizedBox(height: 18),
              _sectionTitle(context, '数据库'),
              const SizedBox(height: 10),
              _fieldGrid(
                context,
                children: [
                  _databaseTypeSelect(context),
                  if (!sqlite)
                    ShadTextField(
                      controller: _hostCtrl,
                      labelText: '地址',
                      placeholder: const Text('127.0.0.1'),
                      keyboardType: TextInputType.url,
                    ),
                  if (!sqlite)
                    ShadTextField(
                      controller: _portCtrl,
                      labelText: '端口',
                      placeholder: const Text('5432'),
                      keyboardType: TextInputType.number,
                    ),
                  if (!sqlite)
                    ShadTextField(
                      controller: _nameCtrl,
                      labelText: '数据库名',
                      placeholder: const Text('goharvest'),
                    ),
                  if (sqlite)
                    ShadTextField(
                      controller: _nameCtrl,
                      labelText: '数据库文件',
                      readOnly: true,
                      enabled: false,
                    ),
                  if (!sqlite)
                    ShadTextField(
                      controller: _userCtrl,
                      labelText: '数据库用户',
                      placeholder: const Text('goharvest'),
                    ),
                ],
              ),
              if (!sqlite) ...[
                const SizedBox(height: 10),
                ShadTextField(
                  controller: _passCtrl,
                  labelText: '数据库密码',
                  obscureText: true,
                  maxLines: 1,
                  features: const [shadcn.InputFeature.passwordToggle()],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  shadcn.Checkbox(
                    state: _debug
                        ? shadcn.CheckboxState.checked
                        : shadcn.CheckboxState.unchecked,
                    onChanged: (value) => setState(
                      () => _debug = value == shadcn.CheckboxState.checked,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '开启数据库调试日志',
                    style: theme.typography.small.copyWith(
                      color: cs.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionTitle(context, '管理员'),
              const SizedBox(height: 10),
              _fieldGrid(
                context,
                children: [
                  ShadTextField(
                    controller: _adminUserCtrl,
                    labelText: '用户名',
                    placeholder: const Text('admin'),
                  ),
                  ShadTextField(
                    controller: _adminEmailCtrl,
                    labelText: '邮箱',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShadTextField(
                controller: _adminPassCtrl,
                labelText: '密码',
                obscureText: true,
                maxLines: 1,
                features: const [shadcn.InputFeature.passwordToggle()],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ShadTextField(
                      controller: _jwtSecretCtrl,
                      labelText: 'JWT Secret',
                    ),
                  ),
                  const SizedBox(width: 10),
                  shadcn.Button.primary(
                    onPressed: _submitting
                        ? null
                        : () => setState(
                            () => _jwtSecretCtrl.text = _randomHex(32),
                          ),
                    alignment: Alignment.center,
                    child: const Text('重新生成'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.typography.small.copyWith(
                    color: cs.destructive,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  shadcn.Button.outline(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    alignment: Alignment.center,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  shadcn.Button.primary(
                    onPressed: _submitting ? null : _submit,
                    alignment: Alignment.center,
                    child: Text(_submitting ? '初始化中...' : '开始初始化'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '待初始化',
        style: shadcn.Theme.of(context).typography.small.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = shadcn.Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Text(
        title,
        style: theme.typography.small.copyWith(
          color: theme.colorScheme.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _fieldGrid(BuildContext context, {required List<Widget> children}) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    if (compact) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        for (final child in children) SizedBox(width: 340, child: child),
      ],
    );
  }

  Widget _databaseTypeSelect(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '类型',
          style: shadcn.Theme.of(context).typography.small.copyWith(
            color: shadcn.Theme.of(context).colorScheme.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        shadcn.Select<String>(
          value: _databaseType,
          itemBuilder: (_, value) =>
              Text(value == 'sqlite' ? 'SQLite' : 'PostgreSQL'),
          popup: shadcn.SelectPopup<String>(
            items: shadcn.SelectItemList(
              children: const [
                shadcn.SelectItemButton<String>(
                  value: 'pgsql',
                  child: Text('PostgreSQL'),
                ),
                shadcn.SelectItemButton<String>(
                  value: 'sqlite',
                  child: Text('SQLite'),
                ),
              ],
            ),
          ).call,
          onChanged: _submitting
              ? null
              : (value) {
                  if (value == null || value == _databaseType) return;
                  setState(() {
                    _databaseType = value;
                    if (value == 'sqlite') {
                      _nameCtrl.text = 'db/data.sqlite3';
                    } else {
                      if (_portCtrl.text.trim().isEmpty) {
                        _portCtrl.text = '5432';
                      }
                      if (_nameCtrl.text.trim().isEmpty ||
                          _nameCtrl.text.trim() == 'db/data.sqlite3') {
                        _nameCtrl.text = 'goharvest';
                      }
                    }
                  });
                },
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final adminUser = _adminUserCtrl.text.trim();
    final adminPass = _adminPassCtrl.text;
    final validationError = _validate(adminUser, adminPass);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'database_type': _databaseType,
      'host': _hostCtrl.text.trim(),
      'port': _portCtrl.text.trim(),
      'name': _databaseType == 'sqlite'
          ? 'db/data.sqlite3'
          : _nameCtrl.text.trim(),
      'user': _userCtrl.text.trim(),
      'pass': _passCtrl.text,
      'debug': _debug,
      'admin_user': adminUser,
      'admin_pass': adminPass,
      'admin_email': _adminEmailCtrl.text.trim(),
      'jwt_secret': _jwtSecretCtrl.text.trim(),
    };

    try {
      final res = await Dio().post<Map<String, dynamic>>(
        '${widget.baseUrl}${API.setupInit}',
        data: payload,
        options: Options(validateStatus: (_) => true),
      );
      final body = res.data;
      if (body == null || body['succeed'] != true) {
        throw StateError(_extractSetupMessage(body) ?? '初始化失败');
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop(_SetupCredentials(username: adminUser, password: adminPass));
      }
    } catch (e, st) {
      AppLogger.error('初始化失败', e, st);
      if (mounted) setState(() => _error = _extractSetupMessage(e) ?? '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validate(String adminUser, String adminPass) {
    if (_databaseType == 'pgsql') {
      if (_hostCtrl.text.trim().isEmpty) return '数据库地址不能为空';
      if (_portCtrl.text.trim().isEmpty) return '数据库端口不能为空';
      if (_nameCtrl.text.trim().isEmpty) return '数据库名称不能为空';
      if (_userCtrl.text.trim().isEmpty) return '数据库用户名不能为空';
    }
    if (adminUser.isEmpty) return '管理员用户名不能为空';
    if (adminPass.isEmpty) return '管理员密码不能为空';
    if (adminPass.length < 6) return '管理员密码至少需要 6 位';
    return null;
  }

  String? _extractSetupMessage(dynamic value) {
    if (value is DioException) {
      return _extractSetupMessage(value.response?.data) ??
          value.error?.toString();
    }
    if (value is StateError) return value.message;
    if (value is Map) {
      for (final key in const ['msg', 'message', 'detail', 'error']) {
        final message = value[key]?.toString().trim();
        if (message != null && message.isNotEmpty) return message;
      }
    }
    return null;
  }

  String _randomHex(int bytes) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
