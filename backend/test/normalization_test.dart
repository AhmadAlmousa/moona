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

  test('normalizeProductName is case-insensitive and whitespace-stable', () {
    expect(normalizeProductName('  Olive   Oil  '), 'olive oil');
    expect(normalizeProductName('حَلِيب'), 'حليب');
  });
}
