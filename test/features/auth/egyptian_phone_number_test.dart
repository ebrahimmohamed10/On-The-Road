import 'package:flutter_test/flutter_test.dart';
import 'package:on_the_road/features/auth/services/egyptian_phone_number.dart';

void main() {
  group('normalizeEgyptianPhoneNumber', () {
    test('maps local and international forms to the same unique value', () {
      expect(normalizeEgyptianPhoneNumber('010 1234 5678'), '+201012345678');
      expect(normalizeEgyptianPhoneNumber('+20 1012345678'), '+201012345678');
    });

    test('normalizes Arabic numerals before validating', () {
      expect(normalizeEgyptianPhoneNumber('٠١٠١٢٣٤٥٦٧٨'), '+201012345678');
    });

    test('rejects unsupported Egyptian mobile prefixes', () {
      expect(normalizeEgyptianPhoneNumber('01912345678'), isNull);
    });
  });
}
