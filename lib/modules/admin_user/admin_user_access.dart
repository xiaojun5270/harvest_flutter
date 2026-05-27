const String adminUserAuthorizedEmail = 'ngfchl@126.com';

bool canOpenAdminUsers(Object? authInfo) {
  return _isAuthorizedUsername(_authInfoUsername(authInfo));
}

bool _isAuthorizedUsername(String? value) {
  return value?.trim().toLowerCase() == adminUserAuthorizedEmail;
}

String? _authInfoUsername(Object? authInfo) {
  if (authInfo is Map) {
    final value = authInfo['username'];
    if (value != null) return value.toString();
  }
  return null;
}
