import '../config.dart';

/// Result of normalizing a phone number into the canonical alias form.
class NormalizedPhone {
  const NormalizedPhone({
    required this.digits,
    required this.e164,
    required this.aliasEmail,
  });

  final String digits;
  final String e164;
  final String aliasEmail;
}

/// Thrown when a phone number cannot be normalized to 8–15 digits.
class InvalidPhoneException implements Exception {
  const InvalidPhoneException();
}

/// Normalizes a phone number, mirroring the backend `normalizePhone`
/// (`backend/src/normalization.js`) so the client and server always derive the
/// same `phoneDigits` and alias email.
///
/// Defaults to the Saudi country code (`966`) when no international prefix is
/// present.
NormalizedPhone normalizePhone(
  String input, {
  String defaultCountryCode = '966',
}) {
  final raw = input.trim();
  if (raw.isEmpty) throw const InvalidPhoneException();

  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+')) {
    digits = digits.replaceFirst(RegExp(r'^00'), '');
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '$defaultCountryCode${digits.substring(1)}';
  } else if (!digits.startsWith(defaultCountryCode) && digits.length <= 10) {
    digits = '$defaultCountryCode$digits';
  }

  if (digits.length < 8 || digits.length > 15) {
    throw const InvalidPhoneException();
  }

  return NormalizedPhone(
    digits: digits,
    e164: '+$digits',
    aliasEmail: 'phone-$digits@${MoonaConfig.aliasEmailDomain}',
  );
}
