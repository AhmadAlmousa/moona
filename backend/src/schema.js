import {
  collectionIds,
  databaseId,
  dispatcherFunctionId,
  imageBucketId,
} from './ids.js';

export const maxImageSizeBytes = 5 * 1024 * 1024;
export const allowedImageExtensions = Object.freeze([
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
]);

export const collections = Object.freeze([
  {
    id: collectionIds.profiles,
    name: 'Profiles',
    documentSecurity: true,
    attributes: [
      { type: 'string', key: 'userId', size: 64, required: true },
      { type: 'string', key: 'phone', size: 32, required: true },
      { type: 'string', key: 'phoneDigits', size: 32, required: true },
      { type: 'string', key: 'displayName', size: 128, required: true },
      { type: 'enum', key: 'language', elements: ['ar', 'en'], required: true },
      { type: 'enum', key: 'theme', elements: ['light', 'dark'], required: true },
      { type: 'string', key: 'activeReceivedOwnerId', size: 64, required: false },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'phoneDigits_unique', type: 'unique', attributes: ['phoneDigits'] },
      { key: 'active_received_owner', type: 'key', attributes: ['activeReceivedOwnerId'] },
    ],
  },
  {
    id: collectionIds.categories,
    name: 'Categories',
    documentSecurity: false,
    attributes: [
      { type: 'string', key: 'stableId', size: 64, required: true },
      { type: 'string', key: 'nameAr', size: 128, required: true },
      { type: 'string', key: 'nameEn', size: 128, required: true },
      { type: 'string', key: 'emoji', size: 16, required: true },
      { type: 'integer', key: 'sortOrder', required: true },
      { type: 'boolean', key: 'active', required: true },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'stable_id_unique', type: 'unique', attributes: ['stableId'] },
      { key: 'active_sort', type: 'key', attributes: ['active', 'sortOrder'] },
    ],
  },
  {
    id: collectionIds.units,
    name: 'Units',
    documentSecurity: false,
    attributes: [
      { type: 'string', key: 'stableId', size: 64, required: true },
      { type: 'string', key: 'nameAr', size: 128, required: true },
      { type: 'string', key: 'nameEn', size: 128, required: true },
      { type: 'integer', key: 'sortOrder', required: true },
      { type: 'boolean', key: 'active', required: true },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'stable_id_unique', type: 'unique', attributes: ['stableId'] },
      { key: 'active_sort', type: 'key', attributes: ['active', 'sortOrder'] },
    ],
  },
  {
    id: collectionIds.products,
    name: 'Products',
    documentSecurity: false,
    attributes: [
      { type: 'string', key: 'nameAr', size: 256, required: false },
      { type: 'string', key: 'nameEn', size: 256, required: false },
      { type: 'string', key: 'displayName', size: 256, required: true },
      { type: 'string', key: 'normalizedName', size: 256, required: true },
      { type: 'string', key: 'normalizedNameAr', size: 256, required: false },
      { type: 'string', key: 'normalizedNameEn', size: 256, required: false },
      { type: 'string', key: 'aliases', size: 256, required: false, array: true },
      { type: 'string', key: 'normalizedAliases', size: 256, required: false, array: true },
      { type: 'string', key: 'mergeTargetProductId', size: 64, required: false },
      { type: 'boolean', key: 'active', required: true },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'normalized_unique', type: 'unique', attributes: ['normalizedName'] },
      { key: 'active_display', type: 'key', attributes: ['active', 'displayName'] },
      { key: 'merge_target', type: 'key', attributes: ['mergeTargetProductId'] },
    ],
  },
  {
    id: collectionIds.listItems,
    name: 'List Items',
    documentSecurity: true,
    attributes: [
      { type: 'string', key: 'ownerId', size: 64, required: true },
      { type: 'string', key: 'productId', size: 64, required: true },
      { type: 'float', key: 'count', required: true },
      { type: 'string', key: 'unitId', size: 64, required: false },
      { type: 'string', key: 'brand', size: 128, required: false },
      { type: 'string', key: 'seller', size: 128, required: false },
      { type: 'string', key: 'categoryId', size: 64, required: false },
      { type: 'string', key: 'imageFileId', size: 128, required: false },
      { type: 'boolean', key: 'important', required: true },
      { type: 'string', key: 'note', size: 2048, required: false },
      { type: 'enum', key: 'status', elements: ['active', 'trash'], required: true },
      { type: 'datetime', key: 'trashedAt', required: false },
      { type: 'string', key: 'trashedByUserId', size: 64, required: false },
      { type: 'string', key: 'trashReason', size: 64, required: false },
      { type: 'string', key: 'createdByUserId', size: 64, required: true },
      { type: 'string', key: 'updatedByUserId', size: 64, required: true },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'owner_status_product', type: 'key', attributes: ['ownerId', 'status', 'productId'] },
      { key: 'owner_status_sort', type: 'key', attributes: ['ownerId', 'status', 'important', 'updatedAt'] },
      { key: 'owner_trash', type: 'key', attributes: ['ownerId', 'status', 'trashedAt'] },
    ],
  },
  {
    id: collectionIds.shares,
    name: 'Shares',
    documentSecurity: true,
    attributes: [
      { type: 'string', key: 'ownerId', size: 64, required: true },
      { type: 'string', key: 'viewerId', size: 64, required: true },
      {
        type: 'enum',
        key: 'status',
        elements: ['pending', 'accepted', 'declined', 'revoked'],
        required: true,
      },
      { type: 'datetime', key: 'requestedAt', required: true },
      { type: 'datetime', key: 'respondedAt', required: false },
      { type: 'datetime', key: 'revokedAt', required: false },
      { type: 'datetime', key: 'createdAt', required: true },
      { type: 'datetime', key: 'updatedAt', required: true },
    ],
    indexes: [
      { key: 'owner_viewer_unique', type: 'unique', attributes: ['ownerId', 'viewerId'] },
      { key: 'viewer_status', type: 'key', attributes: ['viewerId', 'status'] },
      { key: 'owner_status', type: 'key', attributes: ['ownerId', 'status'] },
    ],
  },
]);

export const bucket = Object.freeze({
  id: imageBucketId,
  name: 'Item images',
  fileSecurity: true,
  enabled: true,
  maximumFileSize: maxImageSizeBytes,
  allowedFileExtensions: allowedImageExtensions,
});

export const functions = Object.freeze([
  {
    functionId: dispatcherFunctionId,
    name: 'moonaApi',
    runtime: 'node-22',
    entrypoint: 'functions/moona/main.js',
    commands: 'npm install',
    timeout: 15,
    execute: ['users'],
    environment: {
      MOONA_DATABASE_ID: databaseId,
      MOONA_IMAGE_BUCKET_ID: imageBucketId,
    },
  },
]);

export const appwriteSchema = Object.freeze({
  database: { id: databaseId, name: 'Moona' },
  collections,
  bucket,
  functions,
});
