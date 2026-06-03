import { adminOnly, MoonaError, errorCodes, notFound, unauthorized } from './errors.js';
import { normalizePhone } from './normalization.js';
import {
  assertCanMutateOwnerList,
  assertNoDuplicateActiveItem,
  assertShareCanBeRequested,
  buildListItemDocument,
  buildShareDocument,
  listOwnerForViewer,
  patchListItemDocument,
  respondSharePatch,
  restoreTrashPatch,
  revokeSharePatch,
  searchProducts as searchProductDocuments,
  sortListItems,
  sortTrashItems,
  suggestProductMerges,
  trashPatch,
} from './rules.js';

export async function ensureProfile({ repo, actorId, payload }) {
  requireActor(actorId);
  const profile = await repo.ensureProfile({
    userId: actorId,
    phone: payload.phone,
    displayName: payload.displayName,
    language: validLanguage(payload.language),
    theme: validTheme(payload.theme),
  });

  return { profile };
}

export async function updatePreferences({ repo, actorId, payload }) {
  requireActor(actorId);
  const patch = {};
  if (payload.language !== undefined) patch.language = validLanguage(payload.language);
  if (payload.theme !== undefined) patch.theme = validTheme(payload.theme);
  if (payload.displayName !== undefined) patch.displayName = String(payload.displayName).trim();

  const profile = await repo.updatePreferences(actorId, patch);
  return { profile };
}

export async function getBootstrapData({ repo, actorId }) {
  requireActor(actorId);
  const profile = await repo.getProfile(actorId);
  const viewerShares = await repo.listSharesForViewer(actorId);
  const ownerId = listOwnerForViewer(profile, viewerShares);
  const [categories, units, products, items, trash, shares] = await Promise.all([
    repo.listCategories(),
    repo.listUnits(),
    repo.listProducts(),
    repo.listActiveItems(ownerId),
    repo.listTrashItems(ownerId),
    repo.listSharesForParticipant(actorId),
  ]);

  return {
    profile,
    visibleList: {
      ownerId,
      isShared: ownerId !== actorId,
      items: sortListItems(items),
      trash: sortTrashItems(trash),
    },
    catalogs: { categories, units, products },
    sharing: sharingStatus(actorId, profile, shares),
  };
}

export async function searchProducts({ repo, actorId, payload }) {
  requireActor(actorId);
  const products = await repo.listProducts();
  return {
    suggestions: searchProductDocuments(products, payload.query, payload.limit || 20),
  };
}

export async function createItem({ repo, actorId, payload }) {
  requireActor(actorId);
  const ownerId = await visibleOwnerId(repo, actorId);
  const ownerShares = await repo.listAcceptedSharesForOwner(ownerId);
  assertCanMutateOwnerList(actorId, ownerId, ownerShares);

  const product = await repo.ensureProduct(payload.productName);
  const activeItems = await repo.listActiveItems(ownerId);
  assertNoDuplicateActiveItem(activeItems, ownerId, product.$id || product.id);

  const data = buildListItemDocument(
    payload,
    ownerId,
    actorId,
    product.$id || product.id,
  );
  if (data.imageFileId) await repo.validateImageFile(data.imageFileId);
  const item = await repo.createListItem(data, ownerShares);

  if (data.imageFileId) {
    await repo.updateImagePermissions(data.imageFileId, ownerId, ownerShares);
  }

  return { item };
}

export async function updateItem({ repo, actorId, payload }) {
  requireActor(actorId);
  const item = await repo.getListItem(payload.itemId);
  if (!item) throw notFound('List item');

  const ownerShares = await repo.listAcceptedSharesForOwner(item.ownerId);
  assertCanMutateOwnerList(actorId, item.ownerId, ownerShares);

  const productId = await resolveProductId(repo, payload, item.productId);
  const activeItems = await repo.listActiveItems(item.ownerId);
  assertNoDuplicateActiveItem(activeItems, item.ownerId, productId, item.$id || item.id);

  const patch = patchListItemDocument(item, payload, actorId, productId);
  if (patch.imageFileId) await repo.validateImageFile(patch.imageFileId);
  const updated = await repo.updateListItem(item.$id || item.id, patch, item.ownerId);

  if (patch.imageFileId) {
    await repo.updateImagePermissions(patch.imageFileId, item.ownerId, ownerShares);
  }

  return { item: updated };
}

export async function trashItem({ repo, actorId, payload }) {
  requireActor(actorId);
  const item = await repo.getListItem(payload.itemId);
  if (!item) throw notFound('List item');

  const ownerShares = await repo.listAcceptedSharesForOwner(item.ownerId);
  assertCanMutateOwnerList(actorId, item.ownerId, ownerShares);

  const updated = await repo.updateListItem(
    item.$id || item.id,
    trashPatch(actorId, payload.reason),
    item.ownerId,
  );

  return { item: updated };
}

export async function restoreTrashItem({ repo, actorId, payload }) {
  requireActor(actorId);
  const item = await repo.getListItem(payload.itemId);
  if (!item) throw notFound('List item');

  const ownerShares = await repo.listAcceptedSharesForOwner(item.ownerId);
  assertCanMutateOwnerList(actorId, item.ownerId, ownerShares);

  const activeItems = await repo.listActiveItems(item.ownerId);
  assertNoDuplicateActiveItem(activeItems, item.ownerId, item.productId, item.$id || item.id);

  const updated = await repo.updateListItem(
    item.$id || item.id,
    restoreTrashPatch(actorId),
    item.ownerId,
  );

  return { item: updated };
}

export async function clearTrash({ repo, actorId }) {
  requireActor(actorId);
  const ownerId = await visibleOwnerId(repo, actorId);
  const ownerShares = await repo.listAcceptedSharesForOwner(ownerId);
  assertCanMutateOwnerList(actorId, ownerId, ownerShares);

  const trash = await repo.listTrashItems(ownerId);
  await Promise.all(trash.map((item) => repo.deleteListItem(item.$id || item.id)));

  return { deletedCount: trash.length };
}

export async function requestShare({ repo, actorId, payload }) {
  requireActor(actorId);
  const ownerProfile = await repo.getProfile(actorId);
  const viewerProfile = await repo.findProfileByPhone(payload.phone);
  const viewerId = viewerProfile?.userId || viewerProfile?.$id;
  const existingShares = viewerId
    ? [
        ...(await repo.listSharesForViewer(viewerId)),
        ...(await repo.listSharesForOwner(actorId)),
      ]
    : await repo.listSharesForOwner(actorId);

  assertShareCanBeRequested({
    ownerId: actorId,
    viewerId,
    viewerProfile,
    existingShares,
  });

  const existing = await repo.findShare(actorId, viewerId);
  const data = buildShareDocument(actorId, viewerId);
  const share = existing
    ? await repo.updateShare(existing.$id || existing.id, {
        ...data,
        createdAt: existing.createdAt,
      })
    : await repo.createShare(data);

  return {
    owner: ownerProfile,
    viewer: viewerProfile,
    share,
  };
}

export async function respondShare({ repo, actorId, payload }) {
  requireActor(actorId);
  const share = await repo.getShare(payload.shareId);
  if (!share) throw notFound('Share');

  const accepted = Boolean(payload.accepted);
  if (accepted) {
    const profile = await repo.getProfile(actorId);
    const viewerShares = await repo.listSharesForViewer(actorId);
    const acceptedOther = viewerShares.find(
      (item) =>
        item.status === 'accepted' &&
        item.ownerId !== share.ownerId &&
        item.$id !== share.$id,
    );
    if (profile.activeReceivedOwnerId || acceptedOther) {
      throw new MoonaError(
        errorCodes.viewerAlreadyReceiving,
        'The viewer is already receiving another shared owner list.',
        409,
      );
    }
  }

  const updatedShare = await repo.updateShare(
    share.$id || share.id,
    respondSharePatch(share, actorId, accepted),
  );

  if (accepted) {
    await repo.setActiveReceivedOwner(actorId, share.ownerId);
    await repo.refreshOwnerPermissions(share.ownerId);
  }

  return { share: updatedShare };
}

export async function unlinkShare({ repo, actorId, payload }) {
  requireActor(actorId);
  const share = await shareFromPayload(repo, actorId, payload);
  if (!share) throw notFound('Share');

  const patch = revokeSharePatch(share, actorId);
  const updatedShare = patch
    ? await repo.updateShare(share.$id || share.id, patch)
    : share;

  const viewerProfile = await repo.getProfile(share.viewerId);
  if (viewerProfile.activeReceivedOwnerId === share.ownerId) {
    await repo.setActiveReceivedOwner(share.viewerId, '');
  }
  await repo.refreshOwnerPermissions(share.ownerId);

  return { share: updatedShare };
}

export async function getSharingStatus({ repo, actorId }) {
  requireActor(actorId);
  const [profile, shares] = await Promise.all([
    repo.getProfile(actorId),
    repo.listSharesForParticipant(actorId),
  ]);
  return { sharing: sharingStatus(actorId, profile, shares) };
}

export async function adminList({ repo, actorId, payload }) {
  assertAdmin(actorId);
  return { items: await repo.adminList(payload.kind) };
}

export async function adminCreate({ repo, actorId, payload }) {
  assertAdmin(actorId);
  return { item: await repo.adminCreate(payload.kind, payload.data || {}) };
}

export async function adminUpdate({ repo, actorId, payload }) {
  assertAdmin(actorId);
  return {
    item: await repo.adminUpdate(payload.kind, payload.id, payload.data || {}),
  };
}

export async function adminDelete({ repo, actorId, payload }) {
  assertAdmin(actorId);
  if (payload.kind === 'users') {
    const shares = await repo.listSharesForParticipant(payload.id);
    const now = new Date().toISOString();
    await Promise.all(
      shares
        .filter((share) => share.status !== 'revoked')
        .map((share) =>
          repo.updateShare(share.$id || share.id, {
            status: 'revoked',
            revokedAt: now,
            updatedAt: now,
          }),
        ),
    );
  }

  return { result: await repo.adminDelete(payload.kind, payload.id) };
}

export async function adminMergeSuggestions({ repo, actorId, payload }) {
  assertAdmin(actorId);
  const products = await repo.listProducts({ activeOnly: false });
  return { suggestions: suggestProductMerges(products, payload.limit || 25) };
}

export async function adminMergeProducts({ repo, actorId, payload }) {
  assertAdmin(actorId);
  return {
    result: await repo.mergeProducts(
      payload.sourceProductId,
      payload.targetProductId,
    ),
  };
}

export const operations = Object.freeze({
  ensureProfile,
  updatePreferences,
  getBootstrapData,
  searchProducts,
  createItem,
  updateItem,
  trashItem,
  restoreTrashItem,
  clearTrash,
  requestShare,
  respondShare,
  unlinkShare,
  getSharingStatus,
  adminList,
  adminCreate,
  adminUpdate,
  adminDelete,
  adminMergeSuggestions,
  adminMergeProducts,
});

async function visibleOwnerId(repo, actorId) {
  const profile = await repo.getProfile(actorId);
  const shares = await repo.listSharesForViewer(actorId);
  return listOwnerForViewer(profile, shares);
}

async function resolveProductId(repo, payload, fallbackProductId) {
  if (payload.productName) {
    const product = await repo.ensureProduct(payload.productName);
    return product.$id || product.id;
  }
  if (payload.productId) {
    await repo.getProduct(payload.productId);
    return payload.productId;
  }
  return fallbackProductId;
}

async function shareFromPayload(repo, actorId, payload) {
  if (payload.shareId) return repo.getShare(payload.shareId);
  if (payload.viewerId) return repo.findShare(actorId, payload.viewerId);
  if (payload.ownerId) return repo.findShare(payload.ownerId, actorId);
  throw new MoonaError(
    errorCodes.invalidInput,
    'shareId, viewerId, or ownerId is required.',
  );
}

function sharingStatus(actorId, profile, shares) {
  return {
    activeReceivedOwnerId: profile.activeReceivedOwnerId || '',
    outgoing: shares.filter((share) => share.ownerId === actorId),
    incoming: shares.filter((share) => share.viewerId === actorId),
  };
}

function requireActor(actorId) {
  if (!actorId) throw unauthorized();
}

function validLanguage(language) {
  if (!language) return undefined;
  if (!['ar', 'en'].includes(language)) {
    throw new MoonaError(
      errorCodes.invalidInput,
      'language must be either ar or en.',
    );
  }
  return language;
}

function validTheme(theme) {
  if (!theme) return undefined;
  if (!['light', 'dark'].includes(theme)) {
    throw new MoonaError(
      errorCodes.invalidInput,
      'theme must be either light or dark.',
    );
  }
  return theme;
}

function assertAdmin(actorId) {
  requireActor(actorId);
  const ids = String(process.env.MOONA_ADMIN_USER_IDS || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);
  if (!ids.includes(actorId)) throw adminOnly();
}
