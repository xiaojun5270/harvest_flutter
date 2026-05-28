import 'package:hive/hive.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../storage/hive_manager.dart';
import '../storage/storage_keys.dart';
import 'app_theme.dart';
import 'theme_presets.dart';

class ThemeStorage {
  static const _legacyBoxName = 'settings';
  static const _legacyThemeKey = 'theme';
  static const _legacyModeKey = 'mode';
  static const _legacyThemeStateKey = 'theme_state';
  static const _themeKey = StorageKeys.theme;
  static const _modeKey = StorageKeys.themeMode;
  static const _themeStateKey = StorageKeys.themeState;
  static Future<void>? _migrationFuture;

  static Future<void> init() async {
    _migrationFuture ??= _migrateLegacyBoxIfNeeded();
    await _migrationFuture;
  }

  static Future<void> saveTheme(String name) async {
    await HiveManager.set(_themeKey, name);
  }

  static Future<void> saveMode(String mode) async {
    await HiveManager.set(_modeKey, mode);
  }

  static Future<void> saveState(ThemeState state) async {
    await HiveManager.set(_themeStateKey, state.toJson());
    await HiveManager.set(_themeKey, state.theme.name);
    await HiveManager.set(_modeKey, state.mode.name);
  }

  static Future<String?> getTheme() async {
    return getThemeSync();
  }

  static String? getThemeSync() {
    if (!HiveManager.isInitialized) return null;
    return HiveManager.get<String>(_themeKey);
  }

  static Future<String?> getMode() async {
    return getModeSync();
  }

  static String? getModeSync() {
    if (!HiveManager.isInitialized) return null;
    return HiveManager.get<String>(_modeKey);
  }

  static Future<ThemeState?> getState() async {
    return getStateSync();
  }

  static ThemeState? getStateSync() {
    if (!HiveManager.isInitialized) return null;
    final raw = HiveManager.get<dynamic>(_themeStateKey);
    if (raw is Map) {
      return ThemeState.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static ThemeState getPersistedStateSync() {
    final savedState = getStateSync();
    if (savedState != null) return savedState;

    final themeName = getThemeSync();
    final modeStr = getModeSync();
    if (themeName == null && modeStr == null) {
      return const ThemeState();
    }

    final theme = AppThemes.byName(themeName);
    final mode = switch (modeStr) {
      'light' => shadcn.ThemeMode.light,
      'dark' => shadcn.ThemeMode.dark,
      'system' => shadcn.ThemeMode.system,
      _ => shadcn.ThemeMode.system,
    };

    return ThemeState(
      baseScheme: theme.baseScheme,
      accent: theme.accent,
      mode: mode,
    );
  }

  static Future<void> _migrateLegacyBoxIfNeeded() async {
    if (!HiveManager.isInitialized || _hasPersistedTheme()) return;

    Box? box;
    var openedHere = false;
    try {
      if (Hive.isBoxOpen(_legacyBoxName)) {
        box = Hive.box(_legacyBoxName);
      } else {
        box = await Hive.openBox(_legacyBoxName);
        openedHere = true;
      }

      final rawState = box.get(_legacyThemeStateKey);
      final themeName = box.get(_legacyThemeKey);
      final mode = box.get(_legacyModeKey);

      if (rawState is Map) {
        await HiveManager.set(
          _themeStateKey,
          Map<String, dynamic>.from(rawState),
        );
      }
      if (themeName != null) {
        await HiveManager.set(_themeKey, themeName.toString());
      }
      if (mode != null) {
        await HiveManager.set(_modeKey, mode.toString());
      }
    } catch (_) {
      // The legacy settings box may be locked by an older app instance. It is
      // only used for migration, so startup should continue with defaults.
    } finally {
      if (openedHere && box != null) {
        try {
          await box.close();
        } catch (_) {}
      }
    }
  }

  static bool _hasPersistedTheme() {
    return HiveManager.contains(_themeStateKey) ||
        HiveManager.contains(_themeKey) ||
        HiveManager.contains(_modeKey);
  }
}
