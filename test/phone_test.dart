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

    test('Saudi trunk zero after country code is dropped', () {
      expect(normalizePhone('+966 050 111 2233').digits, '966501112233');
      expect(normalizePhone('009660501112233').digits, '966501112233');
      expect(normalizePhone('9660501112233').digits, '966501112233');
    });

    test('Arabic and Persian digit glyphs are mapped before normalization', () {
      expect(
        normalizePhone(
          '\u0660\u0665\u0660 \u0661\u0661\u0661 \u0662\u0662\u0663\u0663',
        ).digits,
        '966501112233',
      );
      expect(
        normalizePhone(
          '\u06F0\u06F5\u06F0 \u06F1\u06F1\u06F1 \u06F2\u06F2\u06F3\u06F3',
        ).digits,
        '966501112233',
      );
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

  group('composeInternationalPhone', () {
    test('prepends the dial code to a bare local number', () {
      expect(composeInternationalPhone('966', '501112233'), '+966501112233');
    });

    test('drops a leading national-trunk zero', () {
      expect(composeInternationalPhone('966', '0501112233'), '+966501112233');
    });

    test('does not double the dial code when already typed', () {
      expect(composeInternationalPhone('966', '966501112233'), '+966501112233');
    });

    test('passes an explicit + international number through', () {
      expect(
        composeInternationalPhone('966', '+971501112233'),
        '+971501112233',
      );
    });

    test('passes an explicit 00 international number through', () {
      expect(
        composeInternationalPhone('966', '00971501112233'),
        '00971501112233',
      );
    });

    test('strips spaces and dashes from the local number', () {
      expect(composeInternationalPhone('20', '010 1234 5678'), '+201012345678');
    });

    test('round-trips through normalizePhone to a stable alias', () {
      final composed = composeInternationalPhone('966', '0501112233');
      expect(normalizePhone(composed).digits, '966501112233');
    });
  });
}
