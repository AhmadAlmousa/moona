import test from 'node:test';
import assert from 'node:assert/strict';

import { errorCodes } from '../src/errors.js';
import { createItem, requestShare, respondShare, trashItem } from '../src/operations.js';
import { buildProductDocument } from '../src/rules.js';

test('accepted viewer creates an item on the owner list and duplicates are rejected', async () => {
  const repo = new FakeRepo();

  const result = await createItem({
    repo,
    actorId: 'viewer',
    payload: { productName: 'Bread', count: 2, unitId: 'bag', important: true },
  });

  assert.equal(result.item.ownerId, 'owner');
  assert.equal(result.item.createdByUserId, 'viewer');
  assert.equal(result.item.important, true);

  await assert.rejects(
    () =>
      createItem({
        repo,
        actorId: 'viewer',
        payload: { productName: 'bread' },
      }),
    { code: errorCodes.duplicateItem },
  );
});

test('trashItem moves active items to trash with actor metadata', async () => {
  const repo = new FakeRepo();
  const created = await createItem({
    repo,
    actorId: 'owner',
    payload: { productName: 'Milk' },
  });

  const result = await trashItem({
    repo,
    actorId: 'viewer',
    payload: { itemId: created.item.$id, reason: 'scratch_timer' },
  });

  assert.equal(result.item.status, 'trash');
  assert.equal(result.item.trashedByUserId, 'viewer');
  assert.equal(result.item.trashReason, 'scratch_timer');
});

test('requestShare rejects unknown target phone numbers', async () => {
  const repo = new FakeRepo();

  await assert.rejects(
    () =>
      requestShare({
        repo,
        actorId: 'owner',
        payload: { phone: '0550000000' },
      }),
    { code: errorCodes.shareTargetMissing },
  );
});

test('createItem rejects invalid image file IDs before creating the item', async () => {
  const repo = new FakeRepo();

  await assert.rejects(
    () =>
      createItem({
        repo,
        actorId: 'owner',
        payload: { productName: 'Cheese', imageFileId: 'missing-file' },
      }),
    { code: errorCodes.invalidImage },
  );

  assert.equal(repo.items.size, 0);
});


test('respondShare accepts a pending share and sets active received owner', async () => {
  const repo = new FakeRepo();
  repo.profiles.set('newViewer', {
    userId: 'newViewer',
    phoneDigits: '966531234567',
    activeReceivedOwnerId: '',
  });
  repo.shares.set('s2', {
    $id: 's2',
    ownerId: 'owner',
    viewerId: 'newViewer',
    status: 'pending',
  });

  const result = await respondShare({
    repo,
    actorId: 'newViewer',
    payload: { shareId: 's2', accepted: true },
  });

  assert.equal(result.share.status, 'accepted');
  assert.equal(repo.profiles.get('newViewer').activeReceivedOwnerId, 'owner');
  assert.equal(repo.refreshedOwners.at(-1), 'owner');
});

class FakeRepo {
  constructor() {
    this.profiles = new Map([
      [
        'owner',
        {
          userId: 'owner',
          phoneDigits: '966501112233',
          activeReceivedOwnerId: '',
        },
      ],
      [
        'viewer',
        {
          userId: 'viewer',
          phoneDigits: '966507654321',
          activeReceivedOwnerId: 'owner',
        },
      ],
    ]);
    this.shares = new Map([
      [
        's1',
        {
          $id: 's1',
          ownerId: 'owner',
          viewerId: 'viewer',
          status: 'accepted',
        },
      ],
    ]);
    this.products = new Map();
    this.items = new Map();
    this.updatedImagePermissions = [];
    this.refreshedOwners = [];
    this.nextItemId = 1;
    this.nextProductId = 1;
  }

  async getProfile(userId) {
    return this.profiles.get(userId);
  }

  async ensureProfile(input) {
    this.profiles.set(input.userId, input);
    return input;
  }

  async updatePreferences(userId, patch) {
    const profile = { ...this.profiles.get(userId), ...patch };
    this.profiles.set(userId, profile);
    return profile;
  }

  async findProfileByPhone(phone) {
    const digits = phone.replace(/\D/g, '').replace(/^0/, '966');
    return [...this.profiles.values()].find((profile) => profile.phoneDigits === digits) || null;
  }

  async listSharesForViewer(viewerId) {
    return [...this.shares.values()].filter((share) => share.viewerId === viewerId);
  }

  async listSharesForOwner(ownerId) {
    return [...this.shares.values()].filter((share) => share.ownerId === ownerId);
  }

  async listSharesForParticipant(userId) {
    return [...this.shares.values()].filter(
      (share) => share.ownerId === userId || share.viewerId === userId,
    );
  }

  async listAcceptedSharesForOwner(ownerId) {
    return [...this.shares.values()].filter(
      (share) => share.ownerId === ownerId && share.status === 'accepted',
    );
  }

  async listProducts() {
    return [...this.products.values()];
  }

  async ensureProduct(name) {
    const normalized = String(name).trim().toLowerCase();
    const existing = [...this.products.values()].find(
      (product) => product.normalizedName === normalized,
    );
    if (existing) return existing;

    const id = `p${this.nextProductId++}`;
    const product = { ...buildProductDocument({ displayName: name }, id), $id: id };
    this.products.set(id, product);
    return product;
  }

  async getProduct(productId) {
    return this.products.get(productId);
  }

  async listActiveItems(ownerId) {
    return [...this.items.values()].filter(
      (item) => item.ownerId === ownerId && item.status === 'active',
    );
  }

  async listTrashItems(ownerId) {
    return [...this.items.values()].filter(
      (item) => item.ownerId === ownerId && item.status === 'trash',
    );
  }

  async createListItem(data) {
    const id = `i${this.nextItemId++}`;
    const item = { ...data, $id: id };
    this.items.set(id, item);
    return item;
  }

  async getListItem(itemId) {
    return this.items.get(itemId);
  }

  async updateListItem(itemId, patch) {
    const item = { ...this.items.get(itemId), ...patch };
    this.items.set(itemId, item);
    return item;
  }

  async deleteListItem(itemId) {
    this.items.delete(itemId);
  }

  async updateImagePermissions(fileId) {
    this.updatedImagePermissions.push(fileId);
  }

  async validateImageFile(fileId) {
    if (fileId === 'missing-file') {
      const error = new Error('invalid image');
      error.code = errorCodes.invalidImage;
      throw error;
    }
    return { $id: fileId };
  }

  async findShare(ownerId, viewerId) {
    return (
      [...this.shares.values()].find(
        (share) => share.ownerId === ownerId && share.viewerId === viewerId,
      ) || null
    );
  }

  async createShare(data) {
    const id = `s${this.shares.size + 1}`;
    const share = { ...data, $id: id };
    this.shares.set(id, share);
    return share;
  }

  async getShare(shareId) {
    return this.shares.get(shareId);
  }

  async updateShare(shareId, patch) {
    const share = { ...this.shares.get(shareId), ...patch };
    this.shares.set(shareId, share);
    return share;
  }

  async setActiveReceivedOwner(viewerId, ownerId) {
    const profile = { ...this.profiles.get(viewerId), activeReceivedOwnerId: ownerId };
    this.profiles.set(viewerId, profile);
    return profile;
  }

  async refreshOwnerPermissions(ownerId) {
    this.refreshedOwners.push(ownerId);
  }
}
