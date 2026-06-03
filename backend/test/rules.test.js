import test from 'node:test';
import assert from 'node:assert/strict';

import { errorCodes } from '../src/errors.js';
import {
  assertNoDuplicateActiveItem,
  assertShareCanBeRequested,
  buildProductDocument,
  canMutateOwnerList,
  searchProducts,
  sortListItems,
  suggestProductMerges,
  trashPatch,
} from '../src/rules.js';

test('accepted viewers can mutate an owner list', () => {
  const shares = [{ ownerId: 'owner', viewerId: 'viewer', status: 'accepted' }];

  assert.equal(canMutateOwnerList('owner', 'owner', shares), true);
  assert.equal(canMutateOwnerList('viewer', 'owner', shares), true);
  assert.equal(canMutateOwnerList('other', 'owner', shares), false);
});

test('duplicate active product is rejected per owner list', () => {
  const items = [
    { $id: 'i1', ownerId: 'owner', productId: 'p1', status: 'active' },
    { $id: 'i2', ownerId: 'other', productId: 'p1', status: 'active' },
    { $id: 'i3', ownerId: 'owner', productId: 'p1', status: 'trash' },
  ];

  assert.throws(
    () => assertNoDuplicateActiveItem(items, 'owner', 'p1'),
    { code: errorCodes.duplicateItem },
  );
  assert.doesNotThrow(() => assertNoDuplicateActiveItem(items, 'owner', 'p2'));
  assert.doesNotThrow(() => assertNoDuplicateActiveItem(items, 'owner', 'p1', 'i1'));
});

test('important items sort before normal items', () => {
  const items = [
    { $id: 'normal', important: false, updatedAt: '2026-01-02T00:00:00.000Z' },
    { $id: 'important', important: true, updatedAt: '2026-01-01T00:00:00.000Z' },
  ];

  assert.deepEqual(
    sortListItems(items).map((item) => item.$id),
    ['important', 'normal'],
  );
});

test('trash patch records actor, time, and reason', () => {
  const patch = trashPatch('viewer', 'scratch_timer');

  assert.equal(patch.status, 'trash');
  assert.equal(patch.trashedByUserId, 'viewer');
  assert.equal(patch.trashReason, 'scratch_timer');
  assert.match(patch.trashedAt, /^\d{4}-\d{2}-\d{2}T/);
});

test('share request validation blocks self, missing, pending, and active receiver', () => {
  assert.throws(
    () =>
      assertShareCanBeRequested({
        ownerId: 'u1',
        viewerId: 'u1',
        viewerProfile: { userId: 'u1' },
        existingShares: [],
      }),
    { code: errorCodes.shareSelf },
  );

  assert.throws(
    () =>
      assertShareCanBeRequested({
        ownerId: 'u1',
        viewerId: undefined,
        viewerProfile: null,
        existingShares: [],
      }),
    { code: errorCodes.shareTargetMissing },
  );

  assert.throws(
    () =>
      assertShareCanBeRequested({
        ownerId: 'u1',
        viewerId: 'u2',
        viewerProfile: { userId: 'u2' },
        existingShares: [{ ownerId: 'u1', viewerId: 'u2', status: 'pending' }],
      }),
    { code: errorCodes.sharePending },
  );

  assert.throws(
    () =>
      assertShareCanBeRequested({
        ownerId: 'u1',
        viewerId: 'u2',
        viewerProfile: { userId: 'u2', activeReceivedOwnerId: 'u3' },
        existingShares: [],
      }),
    { code: errorCodes.viewerAlreadyReceiving },
  );
});

test('product search is substring-based and requires at least two characters', () => {
  const products = [
    buildProductDocument({ displayName: 'Olive oil', nameAr: 'زيت زيتون' }, 'p1'),
    buildProductDocument({ displayName: 'Milk', nameAr: 'حليب' }, 'p2'),
  ];

  assert.deepEqual(searchProducts(products, 'o').map((item) => item.id), []);
  assert.deepEqual(searchProducts(products, 'oil').map((item) => item.id), ['p1']);
  assert.deepEqual(searchProducts(products, 'حلي').map((item) => item.id), ['p2']);
});

test('merge suggestions find near-duplicate product names', () => {
  const products = [
    buildProductDocument({ displayName: 'Tomato' }, 'p1'),
    buildProductDocument({ displayName: 'Tomatos' }, 'p2'),
    buildProductDocument({ displayName: 'Milk' }, 'p3'),
  ];

  const suggestions = suggestProductMerges(products);

  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].sourceProductId, 'p2');
  assert.equal(suggestions[0].targetProductId, 'p1');
});
