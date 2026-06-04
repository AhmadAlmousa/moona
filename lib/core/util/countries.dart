import 'package:flutter/foundation.dart';

/// A country entry for the phone-number country-code picker: an ISO code (used to
/// derive the flag emoji), the dial code (digits only), and bilingual names.
@immutable
class Country {
  const Country({
    required this.iso,
    required this.dialCode,
    required this.nameEn,
    required this.nameAr,
  });

  /// ISO 3166-1 alpha-2 code, e.g. `SA`.
  final String iso;

  /// Country calling code without the `+`, e.g. `966`.
  final String dialCode;

  final String nameEn;
  final String nameAr;

  /// Flag emoji built from the ISO code's two regional-indicator symbols.
  String get flag => iso.toUpperCase().codeUnits
      .map((unit) => String.fromCharCode(0x1F1E6 + unit - 0x41))
      .join();

  String name(bool isArabic) => isArabic ? nameAr : nameEn;

  /// Whether [query] (typed in either language, with or without a leading `+`)
  /// matches this country by name or dial code.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return nameEn.toLowerCase().contains(q) ||
        nameAr.contains(q) ||
        (digits.isNotEmpty && dialCode.startsWith(digits));
  }
}

/// Default country for new sign-ins — Saudi Arabia, the primary market.
const Country kDefaultCountry = Country(
  iso: 'SA',
  dialCode: '966',
  nameEn: 'Saudi Arabia',
  nameAr: 'السعودية',
);

/// Curated list of countries for the picker: GCC and the wider Arab world first
/// (the core audience), then common expatriate origins and a few majors.
const List<Country> kCountries = [
  kDefaultCountry,
  Country(iso: 'AE', dialCode: '971', nameEn: 'United Arab Emirates', nameAr: 'الإمارات'),
  Country(iso: 'KW', dialCode: '965', nameEn: 'Kuwait', nameAr: 'الكويت'),
  Country(iso: 'QA', dialCode: '974', nameEn: 'Qatar', nameAr: 'قطر'),
  Country(iso: 'BH', dialCode: '973', nameEn: 'Bahrain', nameAr: 'البحرين'),
  Country(iso: 'OM', dialCode: '968', nameEn: 'Oman', nameAr: 'عُمان'),
  Country(iso: 'EG', dialCode: '20', nameEn: 'Egypt', nameAr: 'مصر'),
  Country(iso: 'JO', dialCode: '962', nameEn: 'Jordan', nameAr: 'الأردن'),
  Country(iso: 'LB', dialCode: '961', nameEn: 'Lebanon', nameAr: 'لبنان'),
  Country(iso: 'IQ', dialCode: '964', nameEn: 'Iraq', nameAr: 'العراق'),
  Country(iso: 'SY', dialCode: '963', nameEn: 'Syria', nameAr: 'سوريا'),
  Country(iso: 'YE', dialCode: '967', nameEn: 'Yemen', nameAr: 'اليمن'),
  Country(iso: 'PS', dialCode: '970', nameEn: 'Palestine', nameAr: 'فلسطين'),
  Country(iso: 'SD', dialCode: '249', nameEn: 'Sudan', nameAr: 'السودان'),
  Country(iso: 'MA', dialCode: '212', nameEn: 'Morocco', nameAr: 'المغرب'),
  Country(iso: 'DZ', dialCode: '213', nameEn: 'Algeria', nameAr: 'الجزائر'),
  Country(iso: 'TN', dialCode: '216', nameEn: 'Tunisia', nameAr: 'تونس'),
  Country(iso: 'LY', dialCode: '218', nameEn: 'Libya', nameAr: 'ليبيا'),
  Country(iso: 'TR', dialCode: '90', nameEn: 'Türkiye', nameAr: 'تركيا'),
  Country(iso: 'PK', dialCode: '92', nameEn: 'Pakistan', nameAr: 'باكستان'),
  Country(iso: 'IN', dialCode: '91', nameEn: 'India', nameAr: 'الهند'),
  Country(iso: 'BD', dialCode: '880', nameEn: 'Bangladesh', nameAr: 'بنغلاديش'),
  Country(iso: 'PH', dialCode: '63', nameEn: 'Philippines', nameAr: 'الفلبين'),
  Country(iso: 'ID', dialCode: '62', nameEn: 'Indonesia', nameAr: 'إندونيسيا'),
  Country(iso: 'US', dialCode: '1', nameEn: 'United States', nameAr: 'الولايات المتحدة'),
  Country(iso: 'GB', dialCode: '44', nameEn: 'United Kingdom', nameAr: 'المملكة المتحدة'),
];
