import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harvest/core/storage/hive_manager.dart';

import '../model/notice_history.dart';
import '../service/local_notice_notification_service.dart';
import '../service/notice_service.dart';

final noticeHistoryProvider =
    AsyncNotifierProvider<NoticeHistoryNotifier, List<NoticeHistory>>(
      NoticeHistoryNotifier.new,
    );

final noticeUnreadCountProvider = Provider<int>((ref) {
  final notices =
      ref.watch(noticeHistoryProvider).valueOrNull ?? const <NoticeHistory>[];
  return notices.where((notice) => !notice.isRead).length;
});

class NoticeHistoryNotifier extends AsyncNotifier<List<NoticeHistory>> {
  @override
  Future<List<NoticeHistory>> build() {
    if (!HiveManager.hasAccessToken) {
      _syncBadgeFor(const <NoticeHistory>[]);
      return Future.value(const <NoticeHistory>[]);
    }
    return _fetchNoticeHistoryWithNotification();
  }

  Future<void> refresh() async {
    if (!HiveManager.hasAccessToken) {
      state = const AsyncValue.data(<NoticeHistory>[]);
      _syncBadgeFor(const <NoticeHistory>[]);
      return;
    }

    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncValue.loading();

    final result = await AsyncValue.guard(_fetchNoticeHistoryWithNotification);
    if (result.hasError && previous != null) {
      state = AsyncValue.data(previous);
      return;
    }
    state = result;
  }

  Future<void> markRead(NoticeHistory notice) async {
    if (!HiveManager.hasAccessToken) return;
    if (notice.isRead || notice.id <= 0) return;

    final previous = state.valueOrNull;
    _setReadLocally({notice.id});

    try {
      await NoticeService.markRead(notice.id);
    } catch (_) {
      if (previous != null) {
        state = AsyncValue.data(previous);
        _syncBadgeFor(previous);
      }
      rethrow;
    }
  }

  Future<void> deleteNotice(NoticeHistory notice) async {
    if (!HiveManager.hasAccessToken) return;
    if (notice.id <= 0) return;

    final previous = state.valueOrNull;
    final notices = previous ?? const <NoticeHistory>[];
    state = AsyncValue.data([
      for (final item in notices)
        if (item.id != notice.id) item,
    ]);
    _syncBadgeFor(state.valueOrNull ?? const <NoticeHistory>[]);

    try {
      await NoticeService.deleteNotice(notice.id);
    } catch (_) {
      if (previous != null) {
        state = AsyncValue.data(previous);
        _syncBadgeFor(previous);
      }
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    if (!HiveManager.hasAccessToken) return;

    final notices = state.valueOrNull ?? const <NoticeHistory>[];
    final unreadIds = notices
        .where((notice) => !notice.isRead && notice.id > 0)
        .map((notice) => notice.id)
        .toSet();
    if (unreadIds.isEmpty) return;

    final previous = List<NoticeHistory>.from(notices);
    _setReadLocally(unreadIds);

    try {
      await NoticeService.markAllRead();
    } catch (_) {
      state = AsyncValue.data(previous);
      _syncBadgeFor(previous);
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    if (!HiveManager.hasAccessToken) return;

    final previous = state.valueOrNull;
    final notices = previous ?? const <NoticeHistory>[];
    if (notices.isEmpty) return;

    state = const AsyncValue.data(<NoticeHistory>[]);
    _syncBadgeFor(const <NoticeHistory>[]);

    try {
      await NoticeService.deleteAll();
    } catch (_) {
      if (previous != null) {
        state = AsyncValue.data(previous);
        _syncBadgeFor(previous);
      }
      rethrow;
    }
  }

  void _setReadLocally(Set<int> ids) {
    final notices = state.valueOrNull;
    if (notices == null) return;

    state = AsyncValue.data([
      for (final notice in notices)
        ids.contains(notice.id) ? notice.copyWith(isRead: true) : notice,
    ]);
    _syncBadgeFor(state.valueOrNull ?? const <NoticeHistory>[]);
  }

  Future<List<NoticeHistory>> _fetchNoticeHistoryWithNotification() async {
    final notices = await NoticeService.fetchNoticeHistory();
    try {
      await LocalNoticeNotificationService.instance.showNewNotices(notices);
    } catch (_) {
      // 系统通知失败不应影响站内通知列表刷新。
    }
    return notices;
  }

  void _syncBadgeFor(List<NoticeHistory> notices) {
    final unreadCount = notices.where((notice) => !notice.isRead).length;
    unawaited(
      LocalNoticeNotificationService.instance.syncBadgeCount(unreadCount),
    );
  }
}
