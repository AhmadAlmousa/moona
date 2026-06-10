import 'package:flutter_test/flutter_test.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/features/sharing/contact_picker.dart';

void main() {
  group('buildContactPickerRows', () {
    test('shows local device contacts without backend lookup data', () {
      final rows = buildContactPickerRows(const [
        ContactPickerDeviceContact('Noor saved', '0501112233'),
        ContactPickerDeviceContact('Short code', '123'),
      ], const ContactLookupResult());

      expect(rows.length, 2);
      expect(rows.first.name, 'Noor saved');
      expect(rows.first.phoneDigits, '966501112233');
      expect(rows.first.registered, isFalse);
      expect(rows.last.name, 'Short code');
      expect(rows.last.phoneDigits, '123');
    });

    test('enriches matching rows while preserving local saved names', () {
      final rows = buildContactPickerRows(
        const [
          ContactPickerDeviceContact('Saved Omar', '0507654321'),
          ContactPickerDeviceContact('', '0550000000'),
        ],
        const ContactLookupResult(
          contacts: [
            ContactLookupEntry(
              phone: '+966507654321',
              phoneDigits: '966507654321',
              registered: true,
              displayName: 'Omar',
            ),
          ],
        ),
      );

      expect(rows.length, 2);
      expect(rows.first.name, 'Saved Omar');
      expect(rows.first.registered, isTrue);
      expect(rows.last.phone, '0550000000');
      expect(rows.last.registered, isFalse);
    });

    test('matches contacts saved with a trunk zero after the country code', () {
      final rows = buildContactPickerRows(
        const [ContactPickerDeviceContact('Saved Omar', '+966 050 765 4321')],
        const ContactLookupResult(
          contacts: [
            ContactLookupEntry(
              phone: '+966507654321',
              phoneDigits: '966507654321',
              registered: true,
              displayName: 'Omar',
            ),
          ],
        ),
      );

      expect(rows, hasLength(1));
      expect(rows.single.name, 'Saved Omar');
      expect(rows.single.phoneDigits, '966507654321');
      expect(rows.single.registered, isTrue);
    });

    test(
      'appends registered lookup entries that do not match a device row',
      () {
        final rows = buildContactPickerRows(
          const [ContactPickerDeviceContact('Local', '0550000000')],
          const ContactLookupResult(
            contacts: [
              ContactLookupEntry(
                phone: '+966507654321',
                phoneDigits: '966507654321',
                registered: true,
                displayName: 'Omar',
              ),
            ],
          ),
        );

        expect(rows.length, 2);
        expect(rows.last.name, 'Omar');
        expect(rows.last.registered, isTrue);
      },
    );
  });

  group('contactLookupPhones', () {
    const contacts = [
      ContactPickerDeviceContact(
        'Noor',
        '0501112233',
        normalizedPhone: '+966501112233',
      ),
      ContactPickerDeviceContact('Duplicate Noor', '966501112233'),
      ContactPickerDeviceContact('Short code', '123'),
      ContactPickerDeviceContact('Omar', '0507654321'),
    ];

    test('uses normalized numbers, dedupes, and skips invalid numbers', () {
      expect(contactLookupPhones(contacts), ['+966501112233', '0507654321']);
    });

    test('applies the lookup limit', () {
      expect(contactLookupPhones(contacts, limit: 1), ['+966501112233']);
    });
  });
}
