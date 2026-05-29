import 'package:harvest/core/storage/hive_manager.dart';
import 'package:harvest/core/storage/storage_keys.dart';

class SearchSettings {
  static bool? _draftSitesEnabled;
  static List<String>? _draftSites;

  final int maxCount;

  /// Effective site list used by resource search.
  final List<String> sites;
  final List<String> storedSites;
  final bool sitesEnabled;

  const SearchSettings({
    this.maxCount = 5,
    this.sites = const [],
    List<String>? storedSites,
    this.sitesEnabled = true,
  }) : storedSites = storedSites ?? sites;

  static bool get hasSiteDraft =>
      _draftSitesEnabled != null || _draftSites != null;

  static void setSiteDraft({
    required bool sitesEnabled,
    required List<String> storedSites,
  }) {
    _draftSitesEnabled = sitesEnabled;
    _draftSites = List.unmodifiable(storedSites);
  }

  static void clearSiteDraft() {
    _draftSitesEnabled = null;
    _draftSites = null;
  }

  static SearchSettings load({bool includeDraft = true}) {
    final persisted = loadPersisted();
    if (!includeDraft || !hasSiteDraft) return persisted;

    final sitesEnabled = _draftSitesEnabled ?? persisted.sitesEnabled;
    final storedSites = _draftSites ?? persisted.storedSites;
    return SearchSettings(
      maxCount: persisted.maxCount,
      sites: sitesEnabled ? storedSites : const [],
      storedSites: storedSites,
      sitesEnabled: sitesEnabled,
    );
  }

  static SearchSettings loadPersisted() {
    final raw = HiveManager.get<Map>(StorageKeys.searchSettings);
    final sitesEnabled =
        HiveManager.get<bool>(StorageKeys.searchSitesEnabled) ?? true;
    if (raw == null) return SearchSettings(sitesEnabled: sitesEnabled);

    final storedSites =
        (raw['sites'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return SearchSettings(
      maxCount: raw['max_count'] as int? ?? 5,
      sites: sitesEnabled ? storedSites : const [],
      storedSites: storedSites,
      sitesEnabled: sitesEnabled,
    );
  }

  void save({bool clearDraft = true}) {
    HiveManager.set(StorageKeys.searchSettings, {
      'max_count': maxCount,
      'sites': storedSites,
    });
    HiveManager.set(StorageKeys.searchSitesEnabled, sitesEnabled);
    if (clearDraft) clearSiteDraft();
  }
}
