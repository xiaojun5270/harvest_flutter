import 'package:dio/dio.dart';

import 'api.dart';

const String noToastHeader = 'NoToast';
const String suppressErrorToastExtra = 'suppressErrorToast';
const String silentAuthCancelReason = 'token_expired';

bool isSilentAuthCancel(Object error) {
  return error is DioException &&
      error.type == DioExceptionType.cancel &&
      error.error?.toString() == silentAuthCancelReason;
}

bool isServerSetupRequiredError(Object error) {
  if (error is DioException) {
    return isServerSetupRequiredResponse(
      error.response?.statusCode,
      error.response?.data,
      fallbackMessage: error.error?.toString(),
    );
  }
  return false;
}

bool isServerSetupRequiredResponse(
  int? status,
  dynamic data, {
  String? fallbackMessage,
}) {
  if (status != 503) return false;
  final message = extractHttpMessage(data) ?? fallbackMessage;
  return _isSetupRequiredMessage(message);
}

String? extractHttpMessage(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is Map) {
    for (final key in const ['message', 'msg', 'info', 'detail', 'error']) {
      final message = extractHttpMessage(value[key]);
      if (message != null) return message;
    }
    return extractHttpMessage(value['data']);
  }
  if (value is Iterable) {
    final messages = value
        .map(extractHttpMessage)
        .whereType<String>()
        .where((message) => message.trim().isNotEmpty)
        .toList();
    return messages.isEmpty ? null : messages.join('\n');
  }
  return null;
}

bool _isSetupRequiredMessage(String? message) {
  final text = message?.trim();
  if (text == null || text.isEmpty) return false;
  return text.contains('尚未初始化') || text.contains('/setup');
}

bool suppressErrorToast(RequestOptions options) {
  return options.extra[suppressErrorToastExtra] == true;
}

void applyNoToastHeader(RequestOptions options) {
  String? matchedKey;
  Object? matchedValue;
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == noToastHeader.toLowerCase()) {
      matchedKey = entry.key;
      matchedValue = entry.value;
      break;
    }
  }

  if (matchedKey == null) return;
  options.headers.remove(matchedKey);
  if (_isNoToastValue(matchedValue)) {
    options.extra[suppressErrorToastExtra] = true;
  }
}

bool _isNoToastValue(Object? value) {
  if (value == null) return true;
  final text = value.toString().trim().toLowerCase();
  return text.isEmpty || text == '1' || text == 'true' || text == 'yes';
}

String requestEndpointLabel(RequestOptions options) {
  return API.describePath(options.path);
}

String requestToastMessage(RequestOptions options, String detail) {
  final trimmed = detail.trim();
  if (trimmed.isEmpty) return requestEndpointLabel(options);
  return '${requestEndpointLabel(options)}：$trimmed';
}
