import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/utils/event_join_code.dart';

void main() {
  group('event join code', () {
    test('normalizes copied code', () {
      expect(normalizeEventJoinCode(' ab12cd34ef '), 'AB12CD34EF');
      expect(isValidEventJoinCode('AB12CD34EF'), isTrue);
    });

    test('extracts join code from shared invitation links', () {
      expect(
        normalizeEventJoinCode('https://example.com/#/join/ab12cd34ef'),
        'AB12CD34EF',
      );
      expect(
        normalizeEventJoinCode('https://example.com/join/ab12cd34ef?share=1'),
        'AB12CD34EF',
      );
      expect(
        normalizeEventJoinCode('https://example.com?code=ab12cd34ef'),
        'AB12CD34EF',
      );
    });

    test('rejects incomplete codes and arbitrary URLs', () {
      expect(isValidEventJoinCode(normalizeEventJoinCode('ABCDE')), isFalse);
      expect(
        isValidEventJoinCode(normalizeEventJoinCode('https://example.com')),
        isFalse,
      );
    });
  });
}
