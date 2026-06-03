export const databaseId = process.env.MOONA_DATABASE_ID || 'moona';
export const imageBucketId =
  process.env.MOONA_IMAGE_BUCKET_ID || 'item_images';
export const dispatcherFunctionId =
  process.env.MOONA_FUNCTION_ID || 'moonaApi';

export const collectionIds = Object.freeze({
  profiles: 'profiles',
  categories: 'categories',
  units: 'units',
  products: 'products',
  listItems: 'list_items',
  shares: 'shares',
});

export const functionIds = Object.freeze({
  ensureProfile: 'ensureProfile',
  updatePreferences: 'updatePreferences',
  getBootstrapData: 'getBootstrapData',
  searchProducts: 'searchProducts',
  createItem: 'createItem',
  updateItem: 'updateItem',
  trashItem: 'trashItem',
  restoreTrashItem: 'restoreTrashItem',
  clearTrash: 'clearTrash',
  requestShare: 'requestShare',
  respondShare: 'respondShare',
  unlinkShare: 'unlinkShare',
  getSharingStatus: 'getSharingStatus',
  adminList: 'adminList',
  adminCreate: 'adminCreate',
  adminUpdate: 'adminUpdate',
  adminDelete: 'adminDelete',
  adminMergeSuggestions: 'adminMergeSuggestions',
  adminMergeProducts: 'adminMergeProducts',
});

export const realtimeChannels = Object.freeze({
  profiles: `tablesdb.${databaseId}.tables.${collectionIds.profiles}.rows`,
  categories: `tablesdb.${databaseId}.tables.${collectionIds.categories}.rows`,
  units: `tablesdb.${databaseId}.tables.${collectionIds.units}.rows`,
  products: `tablesdb.${databaseId}.tables.${collectionIds.products}.rows`,
  listItems: `tablesdb.${databaseId}.tables.${collectionIds.listItems}.rows`,
  shares: `tablesdb.${databaseId}.tables.${collectionIds.shares}.rows`,
});
