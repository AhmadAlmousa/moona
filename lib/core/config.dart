/// Backend configuration and Appwrite identifiers.
///
/// These defaults point at the Appwrite Cloud MVP project. `--dart-define`
/// values are still supported for alternate environments, but the app does not
/// require manual configuration to use the live backend.
library;

class MoonaConfig {
  const MoonaConfig._();

  /// Appwrite Cloud API endpoint for the MVP project.
  static const String endpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://nyc.cloud.appwrite.io/v1',
  );

  /// Appwrite project id for the MVP project.
  static const String projectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: '6a20305f000a1a0251d2',
  );

  static const String databaseId = 'moona';
  static const String imageBucketId = 'item_images';

  /// Email-alias domain used for the deterministic phone-alias auth scheme.
  static const String aliasEmailDomain = 'moona.local';

  /// Frontend-owned scratch-to-delete window (spec + backend: 10 seconds).
  static const Duration scratchWindow = Duration(seconds: 10);

  /// Whether the app has enough configuration to use the live Appwrite backend.
  static bool get hasLiveBackend => endpoint.isNotEmpty && projectId.isNotEmpty;
}

/// Appwrite Function ids (one per operation) from the backend contract.
class MoonaFunctions {
  const MoonaFunctions._();

  /// Single deployed Appwrite Function used by the free-plan MVP. Operation
  /// names below are sent as the `action` payload field.
  static const String dispatcher = 'moonaApi';

  static const String ensureProfile = 'ensureProfile';
  static const String updatePreferences = 'updatePreferences';
  static const String getBootstrapData = 'getBootstrapData';
  static const String searchProducts = 'searchProducts';
  static const String lookupContacts = 'lookupContacts';
  static const String createItem = 'createItem';
  static const String updateItem = 'updateItem';
  static const String trashItem = 'trashItem';
  static const String restoreTrashItem = 'restoreTrashItem';
  static const String clearTrash = 'clearTrash';
  static const String requestShare = 'requestShare';
  static const String respondShare = 'respondShare';
  static const String unlinkShare = 'unlinkShare';
  static const String getSharingStatus = 'getSharingStatus';
  static const String createImageViewToken = 'createImageViewToken';

  // Phase 2 — event backbone + history features.
  static const String getActivity = 'getActivity';
  static const String suggestItems = 'suggestItems';
  static const String getInsights = 'getInsights';

  // Phase 3 — backend-owned scratch undo + presence.
  static const String scratchItem = 'scratchItem';
  static const String undoScratchItem = 'undoScratchItem';
  static const String finalizeScratch = 'finalizeScratch';
  static const String setShoppingPresence = 'setShoppingPresence';
}

/// Appwrite collection ids, used to build realtime channel names.
class MoonaCollections {
  const MoonaCollections._();

  static const String profiles = 'profiles';
  static const String categories = 'categories';
  static const String units = 'units';
  static const String products = 'products';
  static const String listItems = 'list_items';
  static const String shares = 'shares';
  static const String listEvents = 'list_events';
  static const String shoppingPresence = 'shopping_presence';

  static const List<String> all = [
    profiles,
    categories,
    units,
    products,
    listItems,
    shares,
    listEvents,
    shoppingPresence,
  ];
}
