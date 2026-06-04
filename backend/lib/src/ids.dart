import 'dart:io' show Platform;

final String databaseId = Platform.environment['MOONA_DATABASE_ID'] ?? 'moona';
final String imageBucketId =
    Platform.environment['MOONA_IMAGE_BUCKET_ID'] ?? 'item_images';
final String dispatcherFunctionId =
    Platform.environment['MOONA_FUNCTION_ID'] ?? 'moonaApi';

abstract final class CollectionIds {
  static const profiles = 'profiles';
  static const categories = 'categories';
  static const units = 'units';
  static const products = 'products';
  static const listItems = 'list_items';
  static const shares = 'shares';

  static const all = [
    profiles,
    categories,
    units,
    products,
    listItems,
    shares,
  ];
}

abstract final class FunctionIds {
  static const ensureProfile = 'ensureProfile';
  static const updatePreferences = 'updatePreferences';
  static const getBootstrapData = 'getBootstrapData';
  static const searchProducts = 'searchProducts';
  static const lookupContacts = 'lookupContacts';
  static const createItem = 'createItem';
  static const updateItem = 'updateItem';
  static const trashItem = 'trashItem';
  static const restoreTrashItem = 'restoreTrashItem';
  static const clearTrash = 'clearTrash';
  static const requestShare = 'requestShare';
  static const respondShare = 'respondShare';
  static const unlinkShare = 'unlinkShare';
  static const getSharingStatus = 'getSharingStatus';
  static const createImageViewToken = 'createImageViewToken';
  static const adminList = 'adminList';
  static const adminCreate = 'adminCreate';
  static const adminUpdate = 'adminUpdate';
  static const adminDelete = 'adminDelete';
  static const adminMergeSuggestions = 'adminMergeSuggestions';
  static const adminMergeProducts = 'adminMergeProducts';
}

Map<String, String> get realtimeChannels => {
      CollectionIds.profiles:
          'tablesdb.$databaseId.tables.${CollectionIds.profiles}.rows',
      CollectionIds.categories:
          'tablesdb.$databaseId.tables.${CollectionIds.categories}.rows',
      CollectionIds.units:
          'tablesdb.$databaseId.tables.${CollectionIds.units}.rows',
      CollectionIds.products:
          'tablesdb.$databaseId.tables.${CollectionIds.products}.rows',
      CollectionIds.listItems:
          'tablesdb.$databaseId.tables.${CollectionIds.listItems}.rows',
      CollectionIds.shares:
          'tablesdb.$databaseId.tables.${CollectionIds.shares}.rows',
    };
