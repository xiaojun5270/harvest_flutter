import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harvest/core/utils/utils.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/hive_manager.dart';
import 'core/storage/storage_keys.dart';
import 'core/theme/theme_storage.dart';
import 'modules/auth/auth_provider.dart';
import 'modules/notice/service/local_notice_notification_service.dart';
import 'modules/option/widgets/app_upgrade_page.dart';

void main() {
  runZonedGuarded(_startApp, (error, stack) {
    _logUnhandledError('未捕获的 Zone 异常', error, stack);
  });
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  _installGlobalErrorHandlers();

  await HiveManager.init();
  await ThemeStorage.init();
  // 初始化日志
  await AppLogger.init();
  // await AppLogger.init();
  // 固定写法，处理状态栏背景颜色透明问题
  AppLogger.debug("============尝试访问网络===========");
  var canConnectInternet = await HiveManager.get('canConnectInternet');
  if (!kIsWeb && (canConnectInternet == null || !canConnectInternet)) {
    try {
      // Windows 下跳过网络检测，避免代理未启动时崩溃
      if (!PlatformTool.isWindows()) {
        final res = await Dio()
            .get('https://www.baidu.com')
            .timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) {
          AppLogger.debug("============尝试访问网络失败: ${res.statusCode}===========");
        } else {
          HiveManager.set('canConnectInternet', true);
          AppLogger.debug("============网络访问成功！${res.statusCode}===========");
        }
      } else {
        // Windows 下直接标记为已连接
        HiveManager.set('canConnectInternet', true);
        AppLogger.debug("============Windows 平台，跳过网络检测===========");
      }
    } catch (e) {
      AppLogger.debug("============网络访问异常: $e===========");
    }
  } else {
    AppLogger.debug("============已有网络标记，跳过检测===========");
  }

  if (PlatformTool.isAndroid() || PlatformTool.isIOS()) {
    AppLogger.debug("============处理状态栏背景颜色透明问题===========");
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
    AppLogger.debug("============处理状态栏背景颜色透明问题完成===========");
    AppLogger.debug("============设置SystemUiMode为edgeToEdge===========");
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AppLogger.debug("============设置SystemUiMode为edgeToEdge完成===========");
  }

  // 必须加上这一行。
  AppLogger.debug("============初始化窗口管理器===========");
  if (PlatformTool.isDesktopOS()) {
    try {
      await windowManager.ensureInitialized();

      // 读取窗口尺寸，增加容错处理
      double height = 900;
      double width = 1440;

      try {
        final savedHeight = HiveManager.get(StorageKeys.windowSizeHeight);
        final savedWidth = HiveManager.get(StorageKeys.windowSizeWidth);

        if (savedHeight != null && savedHeight is num && savedHeight > 0) {
          height = savedHeight.toDouble().clamp(400, 4096);
        }
        if (savedWidth != null && savedWidth is num && savedWidth > 0) {
          width = savedWidth.toDouble().clamp(600, 7680);
        }
      } catch (e) {
        AppLogger.warn('读取窗口尺寸失败，使用默认值: $e');
      }

      final isWindows = PlatformTool.isWindows();
      WindowOptions windowOptions = WindowOptions(
        size: Size(width, height),
        center: true,
        minimumSize: const Size(600, 400),
        backgroundColor: isWindows ? Colors.white : Colors.transparent,
        title: 'Harvest',
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        try {
          if (PlatformTool.isMacOS()) {
            await windowManager.setTitleBarStyle(
              TitleBarStyle.hidden,
              windowButtonVisibility: false,
            );
          }
          await windowManager.show();
          await windowManager.focus();
        } catch (e, st) {
          AppLogger.error('显示窗口失败', e, st);
        }
      });
    } catch (e, st) {
      AppLogger.error('窗口管理器初始化失败', e, st);
    }
  }
  AppLogger.debug("============窗口管理器初始化完成===========");
  final container = ProviderContainer();

  /// 🔥 恢复登录
  // 触发 auth 初始化（build 自动恢复）
  AuthState authState;
  try {
    authState = container.read(authNotifierProvider);
  } catch (e, st) {
    AppLogger.error('恢复登录状态失败，清理本地登录态后继续启动', e, st);
    await Future.wait([
      HiveManager.delete(StorageKeys.accessToken),
      HiveManager.delete(StorageKeys.refreshToken),
      HiveManager.delete(StorageKeys.authState),
    ]);
    container.invalidate(authNotifierProvider);
    try {
      authState = container.read(authNotifierProvider);
    } catch (retryError, retryStack) {
      AppLogger.error('清理登录态后恢复仍失败', retryError, retryStack);
      authState = const AuthState();
    }
  }

  // 如果已登录，先写入 token 再获取最新用户信息
  if (authState.loggedIn && authState.accessToken != null) {
    await HiveManager.set(StorageKeys.accessToken, authState.accessToken!);
    if (authState.refreshToken != null) {
      await HiveManager.set(StorageKeys.refreshToken, authState.refreshToken!);
    }
  }

  // ✅ 确认状态
  AppLogger.debug("启动 auth: ${container.read(authNotifierProvider).loggedIn}");
  if (!kIsWeb) {
    unawaited(
      container
          .read(appUpgradeStatusProvider.future)
          .then<void>((_) {})
          .catchError((Object error) {
            AppLogger.warn('启动预加载 APP 版本信息失败: $error');
          }),
    );
  }
  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
  if (!PlatformTool.isWindows()) {
    try {
      await LocalNoticeNotificationService.instance
          .handleLaunchNotificationTap();
    } catch (e, st) {
      AppLogger.error('处理通知启动事件失败', e, st);
    }
  }
  if (kIsWeb || PlatformTool.isAndroid() || PlatformTool.isIOS()) {
    await Future.delayed(const Duration(seconds: 2), () {
      FlutterNativeSplash.remove();
    });
  }
}

void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logUnhandledError(
      '未捕获的 Flutter 异常',
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    _logUnhandledError('未捕获的平台异常', error, stack);
    return true;
  };
}

void _logUnhandledError(String message, Object error, StackTrace stack) {
  try {
    AppLogger.error(message, error, stack);
  } catch (_) {
    debugPrint('$message: $error\n$stack');
  }
}
