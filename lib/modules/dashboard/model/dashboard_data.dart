import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/kv/kv.dart';

part 'dashboard_data.freezed.dart';
part 'dashboard_data.g.dart';

@freezed
abstract class EarliestSite with _$EarliestSite {
  const factory EarliestSite({
    @Default(0) int id,
    required String site,
    @JsonKey(name: 'time_join') String? timeJoin,
    @JsonKey(name: 'latest_active') String? latestActive,
  }) = _EarliestSite;

  factory EarliestSite.fromJson(Map<String, dynamic> json) =>
      _$EarliestSiteFromJson(json);
}

@freezed
abstract class StatusRecord with _$StatusRecord {
  const factory StatusRecord({
    @JsonKey(name: 'created_at') required String createdAt,
    @Default(0) num uploaded,
    @Default(0) num downloaded,
    @Default(0) num published,
  }) = _StatusRecord;

  factory StatusRecord.fromJson(Map<String, dynamic> json) =>
      _$StatusRecordFromJson(json);
}

@freezed
abstract class UploadRecord with _$UploadRecord {
  const factory UploadRecord({
    @JsonKey(name: 'created_at') required String createdAt,
    @Default(0) num uploaded,
    @Default(0) num downloaded,
  }) = _UploadRecord;

  factory UploadRecord.fromJson(Map<String, dynamic> json) =>
      _$UploadRecordFromJson(json);
}

@freezed
abstract class MonthSiteData with _$MonthSiteData {
  const factory MonthSiteData({
    required String name,
    @Default([]) List<StatusRecord> value,
  }) = _MonthSiteData;

  factory MonthSiteData.fromJson(Map<String, dynamic> json) =>
      _$MonthSiteDataFromJson(json);
}

@freezed
abstract class SiteStatusData with _$SiteStatusData {
  const factory SiteStatusData({
    required String name,
    required StatusRecord value,
  }) = _SiteStatusData;

  factory SiteStatusData.fromJson(Map<String, dynamic> json) =>
      _$SiteStatusDataFromJson(json);
}

@freezed
abstract class StackSiteData with _$StackSiteData {
  const factory StackSiteData({
    required String name,
    @Default([]) List<UploadRecord> value,
  }) = _StackSiteData;

  factory StackSiteData.fromJson(Map<String, dynamic> json) =>
      _$StackSiteDataFromJson(json);
}

@freezed
abstract class DashboardData with _$DashboardData {
  const factory DashboardData({
    @Default([]) List<KV> emailCount,
    @Default([]) List<KV> usernameCount,
    @Default(0) num totalUploaded,
    @Default(0) num totalDownloaded,
    @Default(0) num totalSeedVol,
    @Default(0) num totalSeeding,
    @Default(0) num totalLeeching,
    @Default(0) num todayUploadIncrement,
    @Default(0) num todayDownloadIncrement,
    @Default(0) num totalPublished,
    @Default([]) List<KV> uploadIncrementDataList,
    @Default([]) List<KV> downloadIncrementDataList,
    @Default([]) List<MonthSiteData> uploadMonthIncrementDataList,
    @Default([]) List<SiteStatusData> statusList,
    @Default([]) List<StackSiteData> stackChartDataList,
    @Default([]) List<KV> seedDataList,
    @Default(0) num siteCount,
    String? updatedAt,
    EarliestSite? earliestSite, // ← 新增
  }) = _DashboardData;

  factory DashboardData.fromJson(Map<String, dynamic> json) =>
      _$DashboardDataFromJson(_normalizeDashboardDataJson(json));
}

Map<String, dynamic> _normalizeDashboardDataJson(Map<String, dynamic> json) {
  final data = Map<String, dynamic>.from(json);

  void copyAlias(String target, List<String> aliases) {
    if (data.containsKey(target)) return;
    for (final alias in aliases) {
      if (json.containsKey(alias)) {
        data[target] = json[alias];
        return;
      }
    }
  }

  copyAlias('emailCount', const ['email_count']);
  copyAlias('usernameCount', const ['username_count']);
  copyAlias('totalUploaded', const ['total_uploaded']);
  copyAlias('totalDownloaded', const ['total_downloaded']);
  copyAlias('totalSeedVol', const ['total_seed_vol', 'total_seed_volume']);
  copyAlias('totalSeeding', const ['total_seeding']);
  copyAlias('totalLeeching', const ['total_leeching']);
  copyAlias('todayUploadIncrement', const ['today_upload_increment']);
  copyAlias('todayDownloadIncrement', const ['today_download_increment']);
  copyAlias('totalPublished', const ['total_published']);
  copyAlias('uploadIncrementDataList', const ['upload_increment_data_list']);
  copyAlias('downloadIncrementDataList', const [
    'download_increment_data_list',
  ]);
  copyAlias('uploadMonthIncrementDataList', const [
    'upload_month_increment_data_list',
  ]);
  copyAlias('statusList', const ['status_list']);
  copyAlias('stackChartDataList', const ['stack_chart_data_list']);
  copyAlias('seedDataList', const ['seed_data_list']);
  copyAlias('siteCount', const ['site_count']);
  copyAlias('updatedAt', const ['updated_at']);
  copyAlias('earliestSite', const ['earliest_site']);

  for (final key in const [
    'totalUploaded',
    'totalDownloaded',
    'totalSeedVol',
    'totalSeeding',
    'totalLeeching',
    'todayUploadIncrement',
    'todayDownloadIncrement',
    'totalPublished',
    'siteCount',
  ]) {
    data[key] = _dashboardNum(data[key]);
  }

  for (final key in const [
    'emailCount',
    'usernameCount',
    'uploadIncrementDataList',
    'downloadIncrementDataList',
    'seedDataList',
  ]) {
    data[key] = _normalizeDashboardKvList(data[key]);
  }

  data['uploadMonthIncrementDataList'] = _normalizeDashboardSeriesList(
    data['uploadMonthIncrementDataList'],
    _normalizeDashboardStatusRecord,
  );
  data['statusList'] = _normalizeDashboardStatusList(data['statusList']);
  data['stackChartDataList'] = _normalizeDashboardSeriesList(
    data['stackChartDataList'],
    _normalizeDashboardUploadRecord,
  );

  final earliestSite = data['earliestSite'];
  if (earliestSite is Map) {
    data['earliestSite'] = Map<String, dynamic>.from(earliestSite);
  }

  return data;
}

dynamic _dashboardNum(dynamic value) {
  if (value is String) return num.tryParse(value.trim()) ?? value;
  return value;
}

dynamic _normalizeDashboardKvList(dynamic value) {
  if (value is! List) return value;
  return value.map((item) {
    if (item is! Map) return item;
    final data = Map<String, dynamic>.from(item);
    data['name'] ??= data['key'] ?? data['label'] ?? data['site'];
    data['value'] ??= data['count'] ?? data['total'] ?? data['size'];
    data['value'] = _dashboardNum(data['value']);
    return data;
  }).toList();
}

dynamic _normalizeDashboardSeriesList(
  dynamic value,
  Map<String, dynamic> Function(Map<String, dynamic>) normalizeRecord,
) {
  if (value is! List) return value;
  return value.map((item) {
    if (item is! Map) return item;
    final data = Map<String, dynamic>.from(item);
    final records = data['value'];
    if (records is List) {
      data['value'] = records.map((record) {
        if (record is! Map) return record;
        return normalizeRecord(Map<String, dynamic>.from(record));
      }).toList();
    }
    return data;
  }).toList();
}

dynamic _normalizeDashboardStatusList(dynamic value) {
  if (value is! List) return value;
  return value.map((item) {
    if (item is! Map) return item;
    final data = Map<String, dynamic>.from(item);
    final record = data['value'];
    if (record is Map) {
      data['value'] = _normalizeDashboardStatusRecord(
        Map<String, dynamic>.from(record),
      );
    }
    return data;
  }).toList();
}

Map<String, dynamic> _normalizeDashboardStatusRecord(
  Map<String, dynamic> data,
) {
  data['created_at'] ??= data['createdAt'];
  data['uploaded'] = _dashboardNum(data['uploaded']);
  data['downloaded'] = _dashboardNum(data['downloaded']);
  data['published'] = _dashboardNum(data['published']);
  return data;
}

Map<String, dynamic> _normalizeDashboardUploadRecord(
  Map<String, dynamic> data,
) {
  data['created_at'] ??= data['createdAt'];
  data['uploaded'] = _dashboardNum(data['uploaded']);
  data['downloaded'] = _dashboardNum(data['downloaded']);
  return data;
}
