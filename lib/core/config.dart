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

  /// Appwrite Messaging provider id for Android FCM push (configured + enabled in
  /// the console by the backend; see `back_to_frontend.md`). Passed when creating
  /// a push target so the user's FCM token is sent through this provider.
  static const String fcmProviderId = 'moona_fcm';

  /// FCM Web Push certificate public key (VAPID) for web/PWA push. Required by
  /// `getToken(vapidKey:)` on web — Android/iOS don't use it. It is console-only
  /// (Firebase → Project settings → Cloud Messaging → Web Push certificates →
  /// "Generate key pair") and not exposed via API, so paste the public key here
  /// or pass `--dart-define=FCM_VAPID_KEY=...`. While empty, web push
  /// registration is skipped (no token requested) so nothing breaks.
  static const String fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

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

  // Named lists.
  static const String getLists = 'getLists';
  static const String createList = 'createList';
  static const String updateList = 'updateList';
  static const String deleteList = 'deleteList';

  // Barcode.
  static const String lookupBarcode = 'lookupBarcode';
  static const String adminGetBarcodeQueue = 'adminGetBarcodeQueue';
  static const String adminResolveBarcode = 'adminResolveBarcode';

  // Admin — gated server-side by isAdmin/MOONA_ADMIN_USER_IDS.
  static const String adminList = 'adminList';
  static const String adminCreate = 'adminCreate';
  static const String adminUpdate = 'adminUpdate';
  static const String adminDelete = 'adminDelete';
  static const String adminResetUser = 'adminResetUser';
  static const String adminMergeSuggestions = 'adminMergeSuggestions';
  static const String adminMergeProducts = 'adminMergeProducts';
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
  static const String brands = 'brands';
  static const String stores = 'stores';

  static const String userLists = 'user_lists';

  static const List<String> all = [
    profiles,
    categories,
    units,
    products,
    listItems,
    shares,
    listEvents,
    shoppingPresence,
    brands,
    stores,
    userLists,
  ];
}
