import 'package:dio/dio.dart';

import 'api.dart';

bool isSilentAuthCancel(Object error) {
  return error is DioException &&
      error.type == DioExceptionType.cancel &&
      error.error?.toString() == 'token_expired';
}

String requestEndpointLabel(RequestOptions options) {
  return API.describePath(options.path);
}

String requestToastMessage(RequestOptions options, String detail) {
  final trimmed = detail.trim();
  if (trimmed.isEmpty) return requestEndpointLabel(options);
  return '${requestEndpointLabel(options)}：$trimmed';
}
