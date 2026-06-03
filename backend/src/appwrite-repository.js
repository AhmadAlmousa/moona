import {
  Client,
  ID,
  Permission,
  Query,
  Role,
  Storage,
  TablesDB,
  Users,
} from 'node-appwrite';

import { collectionIds, databaseId, imageBucketId } from './ids.js';
import { MoonaError, errorCodes, notFound } from './errors.js';
import { normalizePhone, normalizeProductName, nowIso } from './normalization.js';
import {
  acceptedViewerIdsForOwner,
  buildProductDocument,
  matchProductByName,
} from './rules.js';
import { allowedImageExtensions, maxImageSizeBytes } from './schema.js';

export function appwriteAdminClient(apiKey) {
  const endpoint = appwriteEndpoint();
  const project = appwriteProjectId();
  if (!apiKey) {
    throw new MoonaError(
      errorCodes.invalidInput,
      'Missing Appwrite function API key for backend function.',
      500,
    );
  }
  return new Client().setEndpoint(endpoint).setProject(project).setKey(apiKey);
}

export function appwriteJwtClient(jwt) {
  const endpoint = appwriteEndpoint();
  const project = appwriteProjectId();
  return new Client().setEndpoint(endpoint).setProject(project).setJWT(jwt);
}

export class AppwriteRepository {
  constructor({ adminClient, userClient = null }) {
    this.adminDatabases = new TablesDBAdapter(new TablesDB(adminClient));
    this.adminStorage = new StorageAdapter(new Storage(adminClient));
    this.users = new UsersAdapter(new Users(adminClient));
    this.userDatabases = userClient
      ? new TablesDBAdapter(new TablesDB(userClient))
      : null;
  }

  async ensureProfile({ userId, phone, displayName, language, theme }) {
    const normalized = normalizePhone(phone);
    const now = nowIso();
    const existing = await this.getProfile(userId).catch((error) => {
      if (isMissing(error)) return null;
      throw error;
    });

    const data = {
      userId,
      phone: normalized.e164,
      phoneDigits: normalized.digits,
      displayName: displayName || normalized.e164,
      language: language || process.env.MOONA_DEFAULT_LANGUAGE || 'ar',
      theme: theme || process.env.MOONA_DEFAULT_THEME || 'light',
      activeReceivedOwnerId: existing?.activeReceivedOwnerId || '',
      createdAt: existing?.createdAt || now,
      updatedAt: now,
    };

    if (existing) {
      return this.adminDatabases.updateDocument({
        databaseId,
        collectionId: collectionIds.profiles,
        documentId: userId,
        data,
        permissions: userDocumentPermissions(userId),
      });
    }

    return this.adminDatabases.createDocument({
      databaseId,
      collectionId: collectionIds.profiles,
      documentId: userId,
      data,
      permissions: userDocumentPermissions(userId),
    });
  }

  async updatePreferences(userId, input) {
    const patch = {
      updatedAt: nowIso(),
    };
    if (input.language) patch.language = input.language;
    if (input.theme) patch.theme = input.theme;
    if (input.displayName) patch.displayName = input.displayName;

    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId: collectionIds.profiles,
      documentId: userId,
      data: patch,
    });
  }

  async getProfile(userId) {
    return this.adminDatabases.getDocument({
      databaseId,
      collectionId: collectionIds.profiles,
      documentId: userId,
    });
  }

  async findProfileByPhone(phone) {
    const normalized = normalizePhone(phone);
    const result = await this.adminDatabases.listDocuments({
      databaseId,
      collectionId: collectionIds.profiles,
      queries: [Query.equal('phoneDigits', normalized.digits), Query.limit(1)],
    });
    return result.documents[0] || null;
  }

  async listProfiles() {
    return listAllDocuments(this.adminDatabases, collectionIds.profiles);
  }

  async listCategories({ activeOnly = true } = {}) {
    const queries = [Query.orderAsc('sortOrder')];
    if (activeOnly) queries.unshift(Query.equal('active', true));
    return listAllDocuments(this.adminDatabases, collectionIds.categories, queries);
  }

  async listUnits({ activeOnly = true } = {}) {
    const queries = [Query.orderAsc('sortOrder')];
    if (activeOnly) queries.unshift(Query.equal('active', true));
    return listAllDocuments(this.adminDatabases, collectionIds.units, queries);
  }

  async listProducts({ activeOnly = true } = {}) {
    const queries = [Query.orderAsc('displayName')];
    if (activeOnly) queries.unshift(Query.equal('active', true));
    return listAllDocuments(this.adminDatabases, collectionIds.products, queries);
  }

  async findProductByName(name) {
    const normalized = normalizeProductName(name);
    const byPrimary = await this.adminDatabases.listDocuments({
      databaseId,
      collectionId: collectionIds.products,
      queries: [
        Query.equal('normalizedName', normalized),
        Query.equal('active', true),
        Query.limit(1),
      ],
    });
    if (byPrimary.documents[0]) return byPrimary.documents[0];

    const allProducts = await this.listProducts();
    return matchProductByName(allProducts, name) || null;
  }

  async ensureProduct(nameOrInput) {
    const input =
      typeof nameOrInput === 'string'
        ? { displayName: nameOrInput, nameEn: nameOrInput }
        : nameOrInput;
    const existing = await this.findProductByName(input.displayName || input.name);
    if (existing) return existing;

    const product = buildProductDocument(input);
    return this.adminDatabases.createDocument({
      databaseId,
      collectionId: collectionIds.products,
      documentId: ID.unique(),
      data: withoutId(product),
      permissions: catalogDocumentPermissions(),
    });
  }

  async getProduct(productId) {
    return this.adminDatabases.getDocument({
      databaseId,
      collectionId: collectionIds.products,
      documentId: productId,
    });
  }

  async listSharesForOwner(ownerId) {
    return listAllDocuments(this.adminDatabases, collectionIds.shares, [
      Query.equal('ownerId', ownerId),
    ]);
  }

  async listSharesForViewer(viewerId) {
    return listAllDocuments(this.adminDatabases, collectionIds.shares, [
      Query.equal('viewerId', viewerId),
    ]);
  }

  async listSharesForParticipant(userId) {
    const owned = await this.listSharesForOwner(userId);
    const viewed = await this.listSharesForViewer(userId);
    return uniqueDocuments([...owned, ...viewed]);
  }

  async listAcceptedSharesForOwner(ownerId) {
    return listAllDocuments(this.adminDatabases, collectionIds.shares, [
      Query.equal('ownerId', ownerId),
      Query.equal('status', 'accepted'),
    ]);
  }

  async listActiveItems(ownerId) {
    return listAllDocuments(this.adminDatabases, collectionIds.listItems, [
      Query.equal('ownerId', ownerId),
      Query.equal('status', 'active'),
      Query.orderDesc('important'),
      Query.orderDesc('updatedAt'),
    ]);
  }

  async listTrashItems(ownerId) {
    return listAllDocuments(this.adminDatabases, collectionIds.listItems, [
      Query.equal('ownerId', ownerId),
      Query.equal('status', 'trash'),
      Query.orderDesc('trashedAt'),
    ]);
  }

  async getListItem(itemId) {
    return this.adminDatabases.getDocument({
      databaseId,
      collectionId: collectionIds.listItems,
      documentId: itemId,
    });
  }

  async createListItem(data, ownerShares) {
    return this.adminDatabases.createDocument({
      databaseId,
      collectionId: collectionIds.listItems,
      documentId: ID.unique(),
      data,
      permissions: listItemPermissions(data.ownerId, ownerShares),
    });
  }

  async updateListItem(itemId, data, ownerId) {
    const ownerShares = await this.listAcceptedSharesForOwner(ownerId);
    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId: collectionIds.listItems,
      documentId: itemId,
      data,
      permissions: listItemPermissions(ownerId, ownerShares),
    });
  }

  async deleteListItem(itemId) {
    return this.adminDatabases.deleteDocument({
      databaseId,
      collectionId: collectionIds.listItems,
      documentId: itemId,
    });
  }

  async createShare(data) {
    return this.adminDatabases.createDocument({
      databaseId,
      collectionId: collectionIds.shares,
      documentId: ID.unique(),
      data,
      permissions: sharePermissions(data.ownerId, data.viewerId),
    });
  }

  async updateShare(shareId, data) {
    const existing = await this.getShare(shareId);
    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId: collectionIds.shares,
      documentId: shareId,
      data,
      permissions: sharePermissions(existing.ownerId, existing.viewerId),
    });
  }

  async getShare(shareId) {
    return this.adminDatabases.getDocument({
      databaseId,
      collectionId: collectionIds.shares,
      documentId: shareId,
    });
  }

  async findShare(ownerId, viewerId) {
    const result = await this.adminDatabases.listDocuments({
      databaseId,
      collectionId: collectionIds.shares,
      queries: [
        Query.equal('ownerId', ownerId),
        Query.equal('viewerId', viewerId),
        Query.limit(1),
      ],
    });
    return result.documents[0] || null;
  }

  async setActiveReceivedOwner(viewerId, ownerId) {
    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId: collectionIds.profiles,
      documentId: viewerId,
      data: {
        activeReceivedOwnerId: ownerId || '',
        updatedAt: nowIso(),
      },
    });
  }

  async refreshOwnerPermissions(ownerId) {
    const shares = await this.listAcceptedSharesForOwner(ownerId);
    const items = await listAllDocuments(this.adminDatabases, collectionIds.listItems, [
      Query.equal('ownerId', ownerId),
    ]);

    await Promise.all(
      items.map((item) =>
        this.adminDatabases.updateDocument({
          databaseId,
          collectionId: collectionIds.listItems,
          documentId: item.$id,
          data: {},
          permissions: listItemPermissions(ownerId, shares),
        }),
      ),
    );

    const imageFileIds = [...new Set(items.map((item) => item.imageFileId).filter(Boolean))];
    await Promise.all(
      imageFileIds.map((fileId) => this.updateImagePermissions(fileId, ownerId, shares)),
    );
  }

  async updateImagePermissions(fileId, ownerId, ownerShares = null) {
    if (!fileId) return null;
    const shares = ownerShares || (await this.listAcceptedSharesForOwner(ownerId));
    return this.adminStorage.updateFile({
      bucketId: imageBucketId,
      fileId,
      permissions: filePermissions(ownerId, shares),
    });
  }

  async validateImageFile(fileId) {
    if (!fileId) return null;
    try {
      const file = await this.adminStorage.getFile({
        bucketId: imageBucketId,
        fileId,
      });
      const extension = String(file.name || '').split('.').pop().toLowerCase();
      const size = Number(file.sizeOriginal || 0);
      if (
        extension &&
        !allowedImageExtensions.includes(extension) ||
        size > maxImageSizeBytes
      ) {
        throw new Error('Unsupported image file.');
      }
      return file;
    } catch (error) {
      throw new MoonaError(
        errorCodes.invalidImage,
        'Image file is missing, too large, or uses an unsupported format.',
        400,
        { fileId },
      );
    }
  }

  async adminList(kind) {
    if (kind === 'categories') return this.listCategories({ activeOnly: false });
    if (kind === 'units') return this.listUnits({ activeOnly: false });
    if (kind === 'products') return this.listProducts({ activeOnly: false });
    if (kind === 'users') return this.listProfiles();
    throw new MoonaError(errorCodes.invalidInput, 'Unsupported admin list kind.');
  }

  async adminCreate(kind, input) {
    const now = nowIso();
    if (kind === 'categories') {
      return this.adminDatabases.createDocument({
        databaseId,
        collectionId: collectionIds.categories,
        documentId: input.id || input.stableId,
        data: {
          stableId: input.id || input.stableId,
          nameAr: input.nameAr,
          nameEn: input.nameEn,
          emoji: input.emoji,
          sortOrder: Number(input.sortOrder || 0),
          active: input.active !== false,
          createdAt: now,
          updatedAt: now,
        },
        permissions: catalogDocumentPermissions(),
      });
    }

    if (kind === 'units') {
      return this.adminDatabases.createDocument({
        databaseId,
        collectionId: collectionIds.units,
        documentId: input.id || input.stableId,
        data: {
          stableId: input.id || input.stableId,
          nameAr: input.nameAr,
          nameEn: input.nameEn,
          sortOrder: Number(input.sortOrder || 0),
          active: input.active !== false,
          createdAt: now,
          updatedAt: now,
        },
        permissions: catalogDocumentPermissions(),
      });
    }

    if (kind === 'products') {
      const data = buildProductDocument(input);
      return this.adminDatabases.createDocument({
        databaseId,
        collectionId: collectionIds.products,
        documentId: input.id || ID.unique(),
        data: withoutId(data),
        permissions: catalogDocumentPermissions(),
      });
    }

    throw new MoonaError(errorCodes.invalidInput, 'Unsupported admin create kind.');
  }

  async adminUpdate(kind, id, input) {
    const data = { ...input, updatedAt: nowIso() };
    if (kind === 'products') {
      const existing = await this.getProduct(id);
      Object.assign(data, withoutId(buildProductDocument({ ...existing, ...input })));
      delete data.createdAt;
    }

    const collectionId = adminKindToCollection(kind);
    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId,
      documentId: id,
      data,
    });
  }

  async adminDelete(kind, id) {
    if (kind === 'users') {
      await this.users.delete({ userId: id });
      return this.adminDatabases.deleteDocument({
        databaseId,
        collectionId: collectionIds.profiles,
        documentId: id,
      });
    }

    const collectionId = adminKindToCollection(kind);
    return this.adminDatabases.updateDocument({
      databaseId,
      collectionId,
      documentId: id,
      data: { active: false, updatedAt: nowIso() },
    });
  }

  async mergeProducts(sourceProductId, targetProductId) {
    if (sourceProductId === targetProductId) {
      throw new MoonaError(
        errorCodes.invalidInput,
        'Source and target products must be different.',
      );
    }

    await this.getProduct(targetProductId);
    const source = await this.getProduct(sourceProductId);
    const affectedItems = await listAllDocuments(
      this.adminDatabases,
      collectionIds.listItems,
      [Query.equal('productId', sourceProductId)],
    );

    await Promise.all(
      affectedItems.map((item) =>
        this.adminDatabases.updateDocument({
          databaseId,
          collectionId: collectionIds.listItems,
          documentId: item.$id,
          data: { productId: targetProductId, updatedAt: nowIso() },
        }),
      ),
    );

    await this.adminDatabases.updateDocument({
      databaseId,
      collectionId: collectionIds.products,
      documentId: sourceProductId,
      data: {
        active: false,
        mergeTargetProductId: targetProductId,
        updatedAt: nowIso(),
      },
    });

    return {
      sourceProductId: source.$id,
      targetProductId,
      affectedItemCount: affectedItems.length,
    };
  }
}

export function userDocumentPermissions(userId) {
  return [
    Permission.read(Role.user(userId)),
    Permission.update(Role.user(userId)),
    Permission.delete(Role.user(userId)),
  ];
}

export function catalogDocumentPermissions() {
  return [Permission.read(Role.users())];
}

export function sharePermissions(ownerId, viewerId) {
  return [...readWritePermissions(ownerId), ...readWritePermissions(viewerId)];
}

export function listItemPermissions(ownerId, ownerShares = []) {
  const participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants.flatMap(readWritePermissions);
}

export function filePermissions(ownerId, ownerShares = []) {
  const participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants.flatMap((userId) => [
    Permission.read(Role.user(userId)),
    Permission.update(Role.user(userId)),
    Permission.delete(Role.user(userId)),
  ]);
}

export async function listAllDocuments(databases, collectionId, queries = []) {
  const documents = [];
  let offset = 0;
  const pageSize = 100;

  while (true) {
    const page = await databases.listDocuments({
      databaseId,
      collectionId,
      queries: [...queries, Query.limit(pageSize), Query.offset(offset)],
    });
    documents.push(...page.documents);
    if (page.documents.length < pageSize) break;
    offset += pageSize;
  }

  return documents;
}

function readWritePermissions(userId) {
  return [
    Permission.read(Role.user(userId)),
    Permission.update(Role.user(userId)),
    Permission.delete(Role.user(userId)),
  ];
}

function adminKindToCollection(kind) {
  if (kind === 'categories') return collectionIds.categories;
  if (kind === 'units') return collectionIds.units;
  if (kind === 'products') return collectionIds.products;
  if (kind === 'users') return collectionIds.profiles;
  throw new MoonaError(errorCodes.invalidInput, 'Unsupported admin kind.');
}

function withoutId(document) {
  const { id, ...rest } = document;
  return rest;
}

function uniqueDocuments(documents) {
  const seen = new Set();
  return documents.filter((document) => {
    const id = document.$id || document.id;
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

function isMissing(error) {
  return (
    error?.code === 404 ||
    error?.type === 'document_not_found' ||
    error?.type === 'row_not_found'
  );
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new MoonaError(
      errorCodes.invalidInput,
      `Missing required environment variable ${name}.`,
      500,
    );
  }
  return value;
}

function appwriteEndpoint() {
  return (
    process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
    process.env.APPWRITE_ENDPOINT ||
    requireEnv('APPWRITE_ENDPOINT')
  );
}

function appwriteProjectId() {
  return (
    process.env.APPWRITE_FUNCTION_PROJECT_ID ||
    process.env.APPWRITE_PROJECT_ID ||
    requireEnv('APPWRITE_PROJECT_ID')
  );
}

class TablesDBAdapter {
  constructor(tablesDB) {
    this.tablesDB = tablesDB;
  }

  create({ databaseId, name, enabled }) {
    return this.tablesDB.create({ databaseId, name, enabled });
  }

  createCollection({
    databaseId,
    collectionId,
    name,
    permissions,
    documentSecurity,
    enabled,
  }) {
    return this.tablesDB.createTable({
      databaseId,
      tableId: collectionId,
      name,
      permissions,
      rowSecurity: documentSecurity,
      enabled,
    });
  }

  listDocuments({ databaseId, collectionId, queries }) {
    return this.tablesDB
      .listRows({ databaseId, tableId: collectionId, queries })
      .then((response) => ({
        ...response,
        documents: response.rows,
      }));
  }

  getDocument({ databaseId, collectionId, documentId, queries }) {
    return this.tablesDB.getRow({
      databaseId,
      tableId: collectionId,
      rowId: documentId,
      queries,
    });
  }

  createDocument({ databaseId, collectionId, documentId, data, permissions }) {
    return this.tablesDB.createRow({
      databaseId,
      tableId: collectionId,
      rowId: documentId,
      data,
      permissions,
    });
  }

  updateDocument({ databaseId, collectionId, documentId, data, permissions }) {
    return this.tablesDB.updateRow({
      databaseId,
      tableId: collectionId,
      rowId: documentId,
      data,
      permissions,
    });
  }

  deleteDocument({ databaseId, collectionId, documentId }) {
    return this.tablesDB.deleteRow({
      databaseId,
      tableId: collectionId,
      rowId: documentId,
    });
  }
}

class StorageAdapter {
  constructor(storage) {
    this.storage = storage;
  }

  updateFile({ bucketId, fileId, name, permissions }) {
    return this.storage.updateFile({ bucketId, fileId, name, permissions });
  }

  getFile({ bucketId, fileId }) {
    return this.storage.getFile({ bucketId, fileId });
  }
}

class UsersAdapter {
  constructor(users) {
    this.users = users;
  }

  delete({ userId }) {
    return this.users.delete({ userId });
  }
}
