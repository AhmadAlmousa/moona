import 'package:moona_backend/moona_backend.dart';
import 'package:test/test.dart';

void main() {
  test(
      'normalizePhone converts local Saudi mobile numbers to E.164 and alias email',
      () {
    final normalized = normalizePhone('050 111 2233');

    expect(normalized['digits'], '966501112233');
    expect(normalized['e164'], '+966501112233');
    expect(normalized['aliasEmail'], 'phone-966501112233@moona.local');
  });

  test('normalizePhone accepts already international formats', () {
    expect(normalizePhone('+966501112233')['digits'], '966501112233');
    expect(normalizePhone('00966501112233')['digits'], '966501112233');
  });

  test('normalizePhone drops a Saudi trunk zero after country code', () {
    expect(normalizePhone('+966 050 111 2233')['digits'], '966501112233');
    expect(normalizePhone('009660501112233')['digits'], '966501112233');
    expect(normalizePhone('9660501112233')['digits'], '966501112233');
  });

  test('normalizePhone maps Arabic and Persian digit glyphs', () {
    expect(
      normalizePhone(
              '\u0660\u0665\u0660 \u0661\u0661\u0661 \u0662\u0662\u0663\u0663')[
          'digits'],
      '966501112233',
    );
    expect(
      normalizePhone(
              '\u06F0\u06F5\u06F0 \u06F1\u06F1\u06F1 \u06F2\u06F2\u06F3\u06F3')[
          'digits'],
      '966501112233',
    );
  });

  test('normalizeProductName is case-insensitive and whitespace-stable', () {
    expect(normalizeProductName('  Olive   Oil  '), 'olive oil');
    expect(normalizeProductName('حَلِيب'), 'حليب');
  });
}
