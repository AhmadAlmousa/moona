import 'errors.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap normalizePhone(Object? input, {String defaultCountryCode = '966'}) {
  final raw = _asciiDigits((input ?? '').toString()).trim();
  if (raw.isEmpty) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Phone number is required.',
    );
  }

  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+')) {
    digits = digits.replaceFirst(RegExp('^00'), '');
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '$defaultCountryCode${digits.substring(1)}';
  } else if (!digits.startsWith(defaultCountryCode) && digits.length <= 10) {
    digits = '$defaultCountryCode$digits';
  }
  digits = stripNationalTrunkAfterCountryCode(
    digits,
    defaultCountryCode: defaultCountryCode,
  );

  if (digits.length < 8 || digits.length > 15) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Phone number must normalize to 8-15 digits.',
      details: {'digits': digits},
    );
  }

  return {
    'digits': digits,
    'e164': '+$digits',
    'aliasEmail': 'phone-$digits@moona.local',
  };
}

String stripNationalTrunkAfterCountryCode(
  String digits, {
  String defaultCountryCode = '966',
}) {
  final trunkPrefix = '${defaultCountryCode}0';
  if (!digits.startsWith(trunkPrefix)) return digits;
  return '$defaultCountryCode${digits.substring(trunkPrefix.length)}';
}

List<String> phoneDigitLookupVariants(
  Object? input, {
  String defaultCountryCode = '966',
}) {
  final normalized = normalizePhone(
    input,
    defaultCountryCode: defaultCountryCode,
  )['digits']
      .toString();
  final variants = <String>{normalized};
  if (normalized.startsWith(defaultCountryCode)) {
    final national = normalized.substring(defaultCountryCode.length);
    if (national.isNotEmpty && !national.startsWith('0')) {
      variants.add('${defaultCountryCode}0$national');
    }
  }
  return variants.toList();
}

String _asciiDigits(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

String normalizeProductName(Object? input) => (input ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

String normalizeText(Object? input) =>
    (input ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');

String nowIso() => DateTime.now().toUtc().toIso8601String();

bool asBoolean(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value == null || value == '') return fallback;
  if (value == 'true') return true;
  if (value == 'false') return false;
  return true;
}
