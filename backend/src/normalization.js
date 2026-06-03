import { MoonaError, errorCodes } from './errors.js';

export function normalizePhone(input, defaultCountryCode = '966') {
  const raw = String(input || '').trim();
  if (!raw) {
    throw new MoonaError(
      errorCodes.invalidInput,
      'Phone number is required.',
      400,
    );
  }

  let digits = raw.replace(/\D/g, '');
  if (raw.startsWith('+')) {
    digits = digits.replace(/^00/, '');
  } else if (digits.startsWith('00')) {
    digits = digits.slice(2);
  } else if (digits.startsWith('0')) {
    digits = `${defaultCountryCode}${digits.slice(1)}`;
  } else if (!digits.startsWith(defaultCountryCode) && digits.length <= 10) {
    digits = `${defaultCountryCode}${digits}`;
  }

  if (digits.length < 8 || digits.length > 15) {
    throw new MoonaError(
      errorCodes.invalidInput,
      'Phone number must normalize to 8-15 digits.',
      400,
      { digits },
    );
  }

  return {
    digits,
    e164: `+${digits}`,
    aliasEmail: `phone-${digits}@moona.local`,
  };
}

export function normalizeProductName(input) {
  return String(input || '')
    .trim()
    .toLocaleLowerCase('und')
    .normalize('NFKD')
    .replace(/[\u064B-\u065F\u0670]/g, '')
    .replace(/\s+/g, ' ');
}

export function normalizeText(input) {
  return String(input || '').trim().replace(/\s+/g, ' ');
}

export function nowIso() {
  return new Date().toISOString();
}

export function asBoolean(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (value === undefined || value === null || value === '') return fallback;
  if (value === 'true') return true;
  if (value === 'false') return false;
  return Boolean(value);
}
