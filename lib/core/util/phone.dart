import '../config.dart';
import 'countries.dart';

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
/// (`backend/lib/src/normalization.dart`) so the client and server always derive the
/// same `phoneDigits` and alias email.
///
/// Defaults to the Saudi country code (`966`) when no international prefix is
/// present.
NormalizedPhone normalizePhone(
  String input, {
  String defaultCountryCode = '966',
}) {
  final raw = _asciiDigits(input).trim();
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
  digits = _stripNationalTrunkAfterCountryCode(
    digits,
    defaultCountryCode: defaultCountryCode,
  );

  if (digits.length < 8 || digits.length > 15) {
    throw const InvalidPhoneException();
  }

  return NormalizedPhone(
    digits: digits,
    e164: '+$digits',
    aliasEmail: 'phone-$digits@${MoonaConfig.aliasEmailDomain}',
  );
}

String _stripNationalTrunkAfterCountryCode(
  String digits, {
  required String defaultCountryCode,
}) {
  final trunkPrefix = '${defaultCountryCode}0';
  if (!digits.startsWith(trunkPrefix)) return digits;
  return '$defaultCountryCode${digits.substring(trunkPrefix.length)}';
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

/// Combines a country [dialCode] (digits only, e.g. `966`) chosen from the
/// country-code picker with a locally typed [localNumber] into an international
/// string ready for [normalizePhone].
///
/// A single leading national-trunk `0` is dropped (so `050…` under +966 becomes
/// `+96650…`). If the user already typed an international prefix (`+` or `00`),
/// their input is returned untouched so an explicit country code always wins. If
/// the typed number already begins with the selected dial code (e.g. they pasted
/// the full `966…`), it is not prepended again — mirroring the backend
/// `normalizePhone` heuristic so the two agree.
/// The dial code (digits only, e.g. `966`) of a stored E.164 number, chosen by
/// the longest known-country-code prefix. Returns null when [e164] is empty or
/// matches no known country, so callers can fall back to their own default.
///
/// Used to make contact lookup and manual sharing "smart": a local number a
/// user types (`0567…`) is normalized against *their own* country code rather
/// than a hardcoded default, so it resolves to the same digits they registered.
String? extractDialCode(String e164) {
  final digits = _asciiDigits(e164).replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  String? best;
  for (final country in kCountries) {
    final code = country.dialCode;
    if (digits.startsWith(code) &&
        (best == null || code.length > best.length)) {
      best = code;
    }
  }
  return best;
}

String composeInternationalPhone(String dialCode, String localNumber) {
  final raw = localNumber.trim();
  if (raw.startsWith('+') || raw.startsWith('00')) return raw;
  var local = raw.replaceAll(RegExp(r'\D'), '');
  if (local.startsWith('0')) local = local.substring(1);
  if (!local.startsWith(dialCode)) local = '$dialCode$local';
  return '+$local';
}
