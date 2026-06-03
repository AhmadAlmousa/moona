import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  Client,
  Functions,
  Permission,
  Role,
  Storage,
  TablesDB,
} from 'node-appwrite';

loadDotEnv();

const { collectionIds, databaseId } = await import('../src/ids.js');
const { defaultCategories, defaultProducts, defaultUnits } = await import(
  '../src/seed-data.js'
);
const { appwriteSchema } = await import('../src/schema.js');
const { buildProductDocument } = await import('../src/rules.js');
const { nowIso } = await import('../src/normalization.js');

const client = new Client()
  .setEndpoint(requireEnv('APPWRITE_ENDPOINT'))
  .setProject(requireEnv('APPWRITE_PROJECT_ID'))
  .setKey(requireEnv('APPWRITE_API_KEY'));

const databases = new ProvisionTablesDB(new TablesDB(client));
const storage = new ProvisionStorage(new Storage(client));
const functions = new ProvisionFunctions(new Functions(client));

await provision();

async function provision() {
  await ensureDatabase();

  for (const collection of appwriteSchema.collections) {
    await ensureCollection(collection);
    await ensureAttributes(collection);
    await sleep(Number(process.env.MOONA_PROVISION_WAIT_MS || 750));
    await ensureIndexes(collection);
  }

  await ensureBucket();
  await seedCatalogs();
  await ensureFunctions();

  console.log('Moona Appwrite backend provisioning complete.');
}

async function ensureDatabase() {
  await ignoreConflict(() =>
    databases.create({
      databaseId: appwriteSchema.database.id,
      name: appwriteSchema.database.name,
    }),
  );
}

async function ensureCollection(collection) {
  await ignoreConflict(() =>
    databases.createCollection({
      databaseId,
      collectionId: collection.id,
      name: collection.name,
      permissions: collection.documentSecurity
        ? []
        : [Permission.read(Role.users())],
      documentSecurity: collection.documentSecurity,
      enabled: true,
    }),
  );
}

async function ensureAttributes(collection) {
  for (const attribute of collection.attributes) {
    await ignoreConflict(() => createAttribute(collection.id, attribute));
  }
}

async function createAttribute(collectionId, attribute) {
  const base = {
    databaseId,
    collectionId,
    key: attribute.key,
    required: attribute.required,
    array: Boolean(attribute.array),
  };

  if (attribute.type === 'string') {
    return databases.createStringAttribute({
      ...base,
      size: attribute.size,
      default: attribute.default,
    });
  }
  if (attribute.type === 'integer') {
    return databases.createIntegerAttribute({
      ...base,
      min: attribute.min,
      max: attribute.max,
      default: attribute.default,
    });
  }
  if (attribute.type === 'float') {
    return databases.createFloatAttribute({
      ...base,
      min: attribute.min,
      max: attribute.max,
      default: attribute.default,
    });
  }
  if (attribute.type === 'boolean') {
    return databases.createBooleanAttribute({
      ...base,
      default: attribute.default,
    });
  }
  if (attribute.type === 'datetime') {
    return databases.createDatetimeAttribute({
      ...base,
      default: attribute.default,
    });
  }
  if (attribute.type === 'enum') {
    return databases.createEnumAttribute({
      ...base,
      elements: attribute.elements,
      default: attribute.default,
    });
  }

  throw new Error(`Unsupported attribute type ${attribute.type}`);
}

async function ensureIndexes(collection) {
  for (const index of collection.indexes) {
    await ignoreConflict(() =>
      databases.createIndex({
        databaseId,
        collectionId: collection.id,
        key: index.key,
        type: index.type,
        attributes: index.attributes,
        orders: index.orders || [],
      }),
    );
  }
}

async function ensureBucket() {
  await ignoreConflict(() =>
    storage.createBucket({
      bucketId: appwriteSchema.bucket.id,
      name: appwriteSchema.bucket.name,
      permissions: [],
      fileSecurity: appwriteSchema.bucket.fileSecurity,
      enabled: appwriteSchema.bucket.enabled,
      maximumFileSize: appwriteSchema.bucket.maximumFileSize,
      allowedFileExtensions: appwriteSchema.bucket.allowedFileExtensions,
    }),
  );
}

async function seedCatalogs() {
  for (const category of defaultCategories) {
    await upsertDocument(collectionIds.categories, category.id, {
      stableId: category.id,
      nameAr: category.nameAr,
      nameEn: category.nameEn,
      emoji: category.emoji,
      sortOrder: category.sortOrder,
      active: category.active,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    });
  }

  for (const unit of defaultUnits) {
    await upsertDocument(collectionIds.units, unit.id, {
      stableId: unit.id,
      nameAr: unit.nameAr,
      nameEn: unit.nameEn,
      sortOrder: unit.sortOrder,
      active: unit.active,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    });
  }

  for (const product of defaultProducts) {
    const document = buildProductDocument(product, product.id);
    await upsertDocument(collectionIds.products, product.id, removeId(document));
  }
}

async function upsertDocument(collectionId, documentId, data) {
  await ignoreConflict(
    () =>
      databases.createDocument({
        databaseId,
        collectionId,
        documentId,
        data,
        permissions: [Permission.read(Role.users())],
      }),
    () =>
      databases.updateDocument({
        databaseId,
        collectionId,
        documentId,
        data: { ...withoutCreatedAt(data), updatedAt: nowIso() },
      }),
  );
}

async function ensureFunctions() {
  for (const spec of appwriteSchema.functions) {
    await ignoreConflict(() =>
      functions.create({
        functionId: spec.functionId,
        name: spec.name,
        runtime: spec.runtime,
        execute: spec.execute,
        events: [],
        schedule: '',
        timeout: spec.timeout,
        enabled: true,
        logging: true,
        entrypoint: spec.entrypoint,
        commands: spec.commands,
        scopes: [
          'databases.read',
          'tables.read',
          'rows.read',
          'rows.write',
          'users.read',
          'users.write',
          'buckets.read',
          'files.read',
          'files.write',
        ],
      }),
    );
    await ensureFunctionVariables(spec);
  }
}

async function ensureFunctionVariables(spec) {
  const variables = await functions.listVariables(spec.functionId);
  const existingByKey = new Map(
    variables.variables.map((variable) => [variable.key, variable]),
  );

  for (const [key, value] of Object.entries(functionVariables(spec))) {
    const existing = existingByKey.get(key);
    if (existing) {
      await functions.updateVariable({
        functionId: spec.functionId,
        variableId: existing.$id,
        key,
        value,
        secret: false,
      });
    } else {
      await functions.createVariable({
        functionId: spec.functionId,
        key,
        value,
        secret: false,
      });
    }
  }
}

function functionVariables(spec) {
  return {
    ...spec.environment,
    APPWRITE_ENDPOINT: requireEnv('APPWRITE_ENDPOINT'),
    APPWRITE_PROJECT_ID: requireEnv('APPWRITE_PROJECT_ID'),
    MOONA_ADMIN_USER_IDS: process.env.MOONA_ADMIN_USER_IDS || '',
    MOONA_DEFAULT_LANGUAGE: process.env.MOONA_DEFAULT_LANGUAGE || 'ar',
    MOONA_DEFAULT_THEME: process.env.MOONA_DEFAULT_THEME || 'light',
  };
}

async function ignoreConflict(createFn, updateFn = null) {
  try {
    return await createFn();
  } catch (error) {
    if (isConflict(error)) {
      if (updateFn) return updateFn();
      return null;
    }
    throw error;
  }
}

function isConflict(error) {
  return error?.code === 409 || String(error?.type || '').includes('already');
}

function removeId(document) {
  const { id, ...rest } = document;
  return rest;
}

function withoutCreatedAt(document) {
  const { createdAt, ...rest } = document;
  return rest;
}

function loadDotEnv() {
  const file = resolve(process.cwd(), '.env');
  if (!existsSync(file)) return;

  const content = readFileSync(file, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index === -1) continue;
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim();
    process.env[key] ||= value;
  }
}

function requireEnv(key) {
  const value = process.env[key];
  if (!value) throw new Error(`Missing required environment variable ${key}`);
  return value;
}

function sleep(ms) {
  return new Promise((resolveSleep) => {
    setTimeout(resolveSleep, ms);
  });
}

class ProvisionTablesDB {
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

  createStringAttribute({
    databaseId,
    collectionId,
    key,
    size,
    required,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createVarcharColumn({
      databaseId,
      tableId: collectionId,
      key,
      size,
      required,
      xdefault: defaultValue,
      array,
    });
  }

  createIntegerAttribute({
    databaseId,
    collectionId,
    key,
    required,
    min,
    max,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createIntegerColumn({
      databaseId,
      tableId: collectionId,
      key,
      required,
      min,
      max,
      xdefault: defaultValue,
      array,
    });
  }

  createFloatAttribute({
    databaseId,
    collectionId,
    key,
    required,
    min,
    max,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createFloatColumn({
      databaseId,
      tableId: collectionId,
      key,
      required,
      min,
      max,
      xdefault: defaultValue,
      array,
    });
  }

  createBooleanAttribute({
    databaseId,
    collectionId,
    key,
    required,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createBooleanColumn({
      databaseId,
      tableId: collectionId,
      key,
      required,
      xdefault: defaultValue,
      array,
    });
  }

  createDatetimeAttribute({
    databaseId,
    collectionId,
    key,
    required,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createDatetimeColumn({
      databaseId,
      tableId: collectionId,
      key,
      required,
      xdefault: defaultValue,
      array,
    });
  }

  createEnumAttribute({
    databaseId,
    collectionId,
    key,
    elements,
    required,
    default: defaultValue,
    array,
  }) {
    return this.tablesDB.createEnumColumn({
      databaseId,
      tableId: collectionId,
      key,
      elements,
      required,
      xdefault: defaultValue,
      array,
    });
  }

  createIndex({ databaseId, collectionId, key, type, attributes, orders }) {
    return this.tablesDB.createIndex({
      databaseId,
      tableId: collectionId,
      key,
      type,
      columns: attributes,
      orders,
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
}

class ProvisionStorage {
  constructor(storage) {
    this.storage = storage;
  }

  createBucket({
    bucketId,
    name,
    permissions,
    fileSecurity,
    enabled,
    maximumFileSize,
    allowedFileExtensions,
  }) {
    return this.storage.createBucket({
      bucketId,
      name,
      permissions,
      fileSecurity,
      enabled,
      maximumFileSize,
      allowedFileExtensions,
    });
  }
}

class ProvisionFunctions {
  constructor(functions) {
    this.functions = functions;
  }

  create({
    functionId,
    name,
    runtime,
    execute,
    events,
    schedule,
    timeout,
    enabled,
    logging,
    entrypoint,
    commands,
    scopes,
  }) {
    return this.functions.create({
      functionId,
      name,
      runtime,
      execute,
      events,
      schedule,
      timeout,
      enabled,
      logging,
      entrypoint,
      commands,
      scopes,
    });
  }

  listVariables(functionId) {
    return this.functions.listVariables({ functionId });
  }

  createVariable({ functionId, key, value, secret }) {
    return this.functions.createVariable({
      functionId,
      variableId: key,
      key,
      value,
      secret,
    });
  }

  updateVariable({ functionId, variableId, key, value, secret }) {
    return this.functions.updateVariable({
      functionId,
      variableId,
      key,
      value,
      secret,
    });
  }
}
