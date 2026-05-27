import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/modules/admin_user/admin_user_access.dart';

void main() {
  group('canOpenAdminUsers', () {
    test('allows only when auth info username is the authorized account', () {
      expect(canOpenAdminUsers({'username': 'ngfchl@126.com'}), isTrue);
      expect(canOpenAdminUsers({'username': ' NGFCHL@126.COM '}), isTrue);
    });

    test('does not allow roles or other auth info fields', () {
      expect(canOpenAdminUsers({'username': 'other@example.com'}), isFalse);
      expect(
        canOpenAdminUsers({
          'username': 'other@example.com',
          'is_superuser': true,
          'is_staff': true,
        }),
        isFalse,
      );
      expect(canOpenAdminUsers({'email': 'ngfchl@126.com'}), isFalse);
      expect(canOpenAdminUsers({'mail': 'ngfchl@126.com'}), isFalse);
      expect(canOpenAdminUsers(null), isFalse);
    });
  });
}
