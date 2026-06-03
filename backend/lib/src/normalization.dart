import 'errors.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap normalizePhone(Object? input, {String defaultCountryCode = '966'}) {
  final raw = (input ?? '').toString().trim();
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
