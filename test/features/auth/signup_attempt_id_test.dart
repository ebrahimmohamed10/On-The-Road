import 'package:flutter_test/flutter_test.dart';
import 'package:on_the_road/features/auth/services/auth_service.dart';

void main() {
  group('createSignupAttemptId', () {
    test('creates UUID v4 values', () {
      final id = createSignupAttemptId();

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('creates a fresh value for every signup attempt', () {
      expect(createSignupAttemptId(), isNot(createSignupAttemptId()));
    });
  });
}
