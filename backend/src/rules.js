import { MoonaError, errorCodes, notFound } from './errors.js';
import { normalizeProductName, normalizeText, nowIso } from './normalization.js';

export function listOwnerForViewer(profile, acceptedShares = []) {
  if (!profile) throw notFound('Profile');

  const activeOwnerId = profile.activeReceivedOwnerId;
  if (!activeOwnerId) return profile.userId;

  const share = acceptedShares.find(
    (item) =>
      item.ownerId === activeOwnerId &&
      item.viewerId === profile.userId &&
      item.status === 'accepted',
  );

  return share ? activeOwnerId : profile.userId;
}

export function acceptedViewerIdsForOwner(ownerId, shares = []) {
  return shares
    .filter((share) => share.ownerId === ownerId && share.status === 'accepted')
    .map((share) => share.viewerId);
}

export function canMutateOwnerList(actorId, ownerId, shares = []) {
  if (actorId === ownerId) return true;
  return shares.some(
    (share) =>
      share.ownerId === ownerId &&
      share.viewerId === actorId &&
      share.status === 'accepted',
  );
}

export function assertCanMutateOwnerList(actorId, ownerId, shares = []) {
  if (!canMutateOwnerList(actorId, ownerId, shares)) {
    throw new MoonaError(
      errorCodes.unauthorized,
      'Only the owner or accepted viewers can mutate this list.',
      403,
    );
  }
}

export function sortListItems(items) {
  return [...items].sort((a, b) => {
    if (Boolean(a.important) !== Boolean(b.important)) {
      return a.important ? -1 : 1;
    }

    const aTime = Date.parse(a.updatedAt || a.createdAt || 0);
    const bTime = Date.parse(b.updatedAt || b.createdAt || 0);
    return bTime - aTime;
  });
}

export function sortTrashItems(items) {
  return [...items].sort((a, b) => {
    const aTime = Date.parse(a.trashedAt || a.updatedAt || 0);
    const bTime = Date.parse(b.trashedAt || b.updatedAt || 0);
    return bTime - aTime;
  });
}

export function findDuplicateActiveItem(items, ownerId, productId, ignoreItemId) {
  return items.find(
    (item) => {
      const itemId = item.$id || item.id;
      return (
        item.ownerId === ownerId &&
        item.status === 'active' &&
        item.productId === productId &&
        (!ignoreItemId || itemId !== ignoreItemId)
      );
    },
  );
}

export function assertNoDuplicateActiveItem(
  items,
  ownerId,
  productId,
  ignoreItemId,
) {
  const duplicate = findDuplicateActiveItem(
    items,
    ownerId,
    productId,
    ignoreItemId,
  );

  if (duplicate) {
    throw new MoonaError(
      errorCodes.duplicateItem,
      'This product is already active in the visible list.',
      409,
      { duplicateItemId: duplicate.$id || duplicate.id, productId },
    );
  }
}

export function buildProductDocument(input, id) {
  const displayName = normalizeText(input.displayName || input.name || input.nameEn);
  if (!displayName) {
    throw new MoonaError(errorCodes.productMissing, 'Product name is required.');
  }

  const nameAr = normalizeText(input.nameAr);
  const nameEn = normalizeText(input.nameEn || displayName);
  const aliases = [
    displayName,
    nameAr,
    nameEn,
    ...(Array.isArray(input.aliases) ? input.aliases : []),
  ].filter(Boolean);
  const normalizedAliases = [...new Set(aliases.map(normalizeProductName))];
  const now = nowIso();

  return {
    id,
    nameAr,
    nameEn,
    displayName,
    normalizedName: normalizeProductName(displayName),
    normalizedNameAr: nameAr ? normalizeProductName(nameAr) : '',
    normalizedNameEn: nameEn ? normalizeProductName(nameEn) : '',
    aliases: [...new Set(aliases)],
    normalizedAliases,
    mergeTargetProductId: input.mergeTargetProductId || '',
    active: input.active !== false,
    createdAt: input.createdAt || now,
    updatedAt: now,
  };
}

export function matchProductByName(products, name) {
  const normalized = normalizeProductName(name);
  return products.find((product) => {
    if (!product.active) return false;
    const values = [
      product.normalizedName,
      product.normalizedNameAr,
      product.normalizedNameEn,
      ...(product.normalizedAliases || []),
    ];
    return values.filter(Boolean).includes(normalized);
  });
}

export function searchProducts(products, query, limit = 20) {
  const normalized = normalizeProductName(query);
  if (normalized.length < 2) return [];

  return products
    .filter((product) => {
      if (!product.active) return false;
      const haystack = [
        product.normalizedName,
        product.normalizedNameAr,
        product.normalizedNameEn,
        ...(product.normalizedAliases || []),
      ].join(' ');
      return haystack.includes(normalized);
    })
    .sort((a, b) => a.displayName.localeCompare(b.displayName))
    .slice(0, limit);
}

export function buildListItemDocument(input, ownerId, actorId, productId) {
  const now = nowIso();
  return {
    ownerId,
    productId,
    count: Number(input.count || 1),
    unitId: input.unitId || '',
    brand: normalizeText(input.brand),
    seller: normalizeText(input.seller),
    categoryId: input.categoryId || '',
    imageFileId: input.imageFileId || '',
    important: Boolean(input.important),
    note: normalizeText(input.note),
    status: 'active',
    trashedAt: '',
    trashedByUserId: '',
    trashReason: '',
    createdByUserId: actorId,
    updatedByUserId: actorId,
    createdAt: now,
    updatedAt: now,
  };
}

export function patchListItemDocument(existing, input, actorId, productId) {
  return {
    productId,
    count: Number(input.count ?? existing.count ?? 1),
    unitId: input.unitId ?? existing.unitId ?? '',
    brand: normalizeText(input.brand ?? existing.brand),
    seller: normalizeText(input.seller ?? existing.seller),
    categoryId: input.categoryId ?? existing.categoryId ?? '',
    imageFileId: input.imageFileId ?? existing.imageFileId ?? '',
    important: Boolean(input.important ?? existing.important),
    note: normalizeText(input.note ?? existing.note),
    updatedByUserId: actorId,
    updatedAt: nowIso(),
  };
}

export function trashPatch(actorId, reason = 'scratch_timer') {
  return {
    status: 'trash',
    trashedAt: nowIso(),
    trashedByUserId: actorId,
    trashReason: reason,
    updatedByUserId: actorId,
    updatedAt: nowIso(),
  };
}

export function restoreTrashPatch(actorId) {
  return {
    status: 'active',
    trashedAt: '',
    trashedByUserId: '',
    trashReason: '',
    updatedByUserId: actorId,
    updatedAt: nowIso(),
  };
}

export function buildShareDocument(ownerId, viewerId) {
  if (ownerId === viewerId) {
    throw new MoonaError(
      errorCodes.shareSelf,
      'A user cannot share their own list with themselves.',
      409,
    );
  }

  const now = nowIso();
  return {
    ownerId,
    viewerId,
    status: 'pending',
    requestedAt: now,
    respondedAt: '',
    revokedAt: '',
    createdAt: now,
    updatedAt: now,
  };
}

export function assertShareCanBeRequested({
  ownerId,
  viewerId,
  viewerProfile,
  existingShares,
}) {
  if (ownerId === viewerId) {
    throw new MoonaError(
      errorCodes.shareSelf,
      'A user cannot share their own list with themselves.',
      409,
    );
  }

  if (!viewerProfile) {
    throw new MoonaError(
      errorCodes.shareTargetMissing,
      'The target phone number does not belong to a Moona user.',
      404,
    );
  }

  const pending = existingShares.find(
    (share) =>
      share.ownerId === ownerId &&
      share.viewerId === viewerId &&
      share.status === 'pending',
  );
  if (pending) {
    throw new MoonaError(
      errorCodes.sharePending,
      'A pending share already exists for this viewer.',
      409,
      { shareId: pending.$id || pending.id },
    );
  }

  const receiving = existingShares.find(
    (share) =>
      share.viewerId === viewerId &&
      share.status === 'accepted' &&
      share.ownerId !== ownerId,
  );
  if (receiving || viewerProfile.activeReceivedOwnerId) {
    throw new MoonaError(
      errorCodes.viewerAlreadyReceiving,
      'The viewer is already receiving another shared owner list.',
      409,
      {
        activeReceivedOwnerId:
          receiving?.ownerId || viewerProfile.activeReceivedOwnerId,
      },
    );
  }
}

export function respondSharePatch(share, actorId, accepted) {
  if (share.viewerId !== actorId) {
    throw new MoonaError(
      errorCodes.unauthorized,
      'Only the target viewer can respond to a share.',
      403,
    );
  }
  if (share.status !== 'pending') {
    throw new MoonaError(
      errorCodes.invalidInput,
      'Only pending shares can be accepted or declined.',
      409,
    );
  }

  return {
    status: accepted ? 'accepted' : 'declined',
    respondedAt: nowIso(),
    updatedAt: nowIso(),
  };
}

export function revokeSharePatch(share, actorId) {
  if (![share.ownerId, share.viewerId].includes(actorId)) {
    throw new MoonaError(
      errorCodes.unauthorized,
      'Only the owner or viewer can unlink this share.',
      403,
    );
  }
  if (share.status === 'revoked') return null;

  return {
    status: 'revoked',
    revokedAt: nowIso(),
    updatedAt: nowIso(),
  };
}

export function suggestProductMerges(products, limit = 25) {
  const activeProducts = products.filter((product) => product.active);
  const suggestions = [];

  for (let i = 0; i < activeProducts.length; i += 1) {
    for (let j = i + 1; j < activeProducts.length; j += 1) {
      const first = activeProducts[i];
      const second = activeProducts[j];
      const score = similarityScore(
        first.normalizedName || normalizeProductName(first.displayName),
        second.normalizedName || normalizeProductName(second.displayName),
      );
      if (score >= 0.82) {
        suggestions.push({
          sourceProductId: second.$id || second.id,
          targetProductId: first.$id || first.id,
          sourceName: second.displayName,
          targetName: first.displayName,
          score,
        });
      }
    }
  }

  return suggestions.sort((a, b) => b.score - a.score).slice(0, limit);
}

export function similarityScore(first, second) {
  if (!first || !second) return 0;
  if (first === second) return 1;

  const distance = levenshteinDistance(first, second);
  const maxLength = Math.max(first.length, second.length);
  return maxLength === 0 ? 1 : 1 - distance / maxLength;
}

function levenshteinDistance(first, second) {
  const rows = first.length + 1;
  const cols = second.length + 1;
  const matrix = Array.from({ length: rows }, () => Array(cols).fill(0));

  for (let i = 0; i < rows; i += 1) matrix[i][0] = i;
  for (let j = 0; j < cols; j += 1) matrix[0][j] = j;

  for (let i = 1; i < rows; i += 1) {
    for (let j = 1; j < cols; j += 1) {
      const cost = first[i - 1] === second[j - 1] ? 0 : 1;
      matrix[i][j] = Math.min(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      );
    }
  }

  return matrix[first.length][second.length];
}
