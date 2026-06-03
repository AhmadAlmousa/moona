import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizePhone, normalizeProductName } from '../src/normalization.js';

test('normalizePhone converts local Saudi mobile numbers to E.164 and alias email', () => {
  const normalized = normalizePhone('050 111 2233');

  assert.equal(normalized.digits, '966501112233');
  assert.equal(normalized.e164, '+966501112233');
  assert.equal(normalized.aliasEmail, 'phone-966501112233@moona.local');
});

test('normalizePhone accepts already international formats', () => {
  assert.equal(normalizePhone('+966501112233').digits, '966501112233');
  assert.equal(normalizePhone('00966501112233').digits, '966501112233');
});

test('normalizeProductName is case-insensitive and whitespace-stable', () => {
  assert.equal(normalizeProductName('  Olive   Oil  '), 'olive oil');
  assert.equal(normalizeProductName('حَلِيب'), 'حليب');
});
