import 'package:dio/dio.dart';

import 'api.dart';

const String noToastHeader = 'NoToast';
const String suppressErrorToastExtra = 'suppressErrorToast';

bool isSilentAuthCancel(Object error) {
  return error is DioException &&
      error.type == DioExceptionType.cancel &&
      error.error?.toString() == 'token_expired';
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
