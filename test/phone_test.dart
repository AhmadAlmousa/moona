import 'package:flutter_test/flutter_test.dart';
import 'package:moona/core/util/phone.dart';

void main() {
  group('normalizePhone', () {
    test('Saudi local 05… maps to 966…', () {
      final result = normalizePhone('0501112233');
      expect(result.digits, '966501112233');
      expect(result.aliasEmail, 'phone-966501112233@moona.local');
      expect(result.e164, '+966501112233');
    });

    test('+ international prefix is preserved', () {
      expect(normalizePhone('+966501112233').digits, '966501112233');
    });

    test('00 international prefix is stripped', () {
      expect(normalizePhone('00966501112233').digits, '966501112233');
    });

    test('already-normalized digits pass through', () {
      expect(normalizePhone('966507654321').digits, '966507654321');
    });

    test('too-short input throws', () {
      expect(
        () => normalizePhone('123'),
        throwsA(isA<InvalidPhoneException>()),
      );
    });

    test('empty input throws', () {
      expect(() => normalizePhone('  '), throwsA(isA<InvalidPhoneException>()));
    });
  });
}
