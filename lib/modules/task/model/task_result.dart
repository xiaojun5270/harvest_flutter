import 'dart:convert';

class TaskResult {
  final String id;
  final String taskId;
  final String name;
  final String status;
  final String summary;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final Map<String, dynamic> raw;

  const TaskResult({
    required this.id,
    required this.taskId,
    required this.name,
    required this.status,
    required this.summary,
    required this.createdAt,
    required this.finishedAt,
    required this.raw,
  });

  factory TaskResult.fromJson(Map<String, dynamic> json) {
    final taskId = _stringValue(json, const [
      'task_id',
      'taskId',
      'celery_task_id',
      'celeryTaskId',
      'uuid',
    ]);
    final id = _stringValue(json, const ['id', 'result_id', 'resultId']);
    final name = _stringValue(json, const [
      'name',
      'task_name',
      'taskName',
      'task',
    ]);
    final status = _stringValue(json, const [
      'status',
      'state',
      'result_status',
      'resultStatus',
    ]);
    final summary = _summary(json);

    return TaskResult(
      id: id.isNotEmpty ? id : taskId,
      taskId: taskId.isNotEmpty ? taskId : id,
      name: name.isNotEmpty ? name : '未命名任务',
      status: status.isNotEmpty ? status : 'UNKNOWN',
      summary: summary,
      createdAt: _dateValue(json, const [
        'created_at',
        'createdAt',
        'date_created',
        'dateCreated',
        'started_at',
        'startedAt',
        'timestamp',
      ]),
      finishedAt: _dateValue(json, const [
        'updated_at',
        'updatedAt',
        'date_done',
        'dateDone',
        'finished_at',
        'finishedAt',
        'completed_at',
        'completedAt',
      ]),
      raw: Map<String, dynamic>.from(json),
    );
  }

  String get displayId => taskId.isNotEmpty ? taskId : id;

  bool get isSuccess {
    final value = status.toLowerCase();
    return value == 'success' || value == 'succeeded' || value == 'done';
  }

  bool get isFailure {
    final value = status.toLowerCase();
    return value == 'failure' ||
        value == 'failed' ||
        value == 'error' ||
        value == 'revoked';
  }

  static String _summary(Map<String, dynamic> json) {
    for (final key in const [
      'summary',
      'message',
      'result',
      'retval',
      'traceback',
      'error',
    ]) {
      if (!json.containsKey(key)) continue;
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is Map || value is List) return jsonEncode(value);
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _stringValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DateTime? _dateValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is DateTime) return value;
      if (value is num) {
        final milliseconds = value > 100000000000
            ? value.toInt()
            : (value * 1000).toInt();
        return DateTime.fromMillisecondsSinceEpoch(milliseconds);
      }
      final text = value.toString().trim();
      if (text.isEmpty || text.startsWith('0001')) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed;
    }
    return null;
  }
}
