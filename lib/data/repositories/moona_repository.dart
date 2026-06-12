import 'dart:typed_data';

import '../models/models.dart';

/// Backend error surfaced to the UI. [code] matches the backend `error.code`
/// values from `back_to_frontend.md`.
class MoonaException implements Exception {
  const MoonaException(this.code, [this.message]);

  final String code;
  final String? message;

  // Known codes from the contract.
  static const duplicateItem = 'duplicate_item';
  static const shareSelf = 'share_self';
  static const shareTargetMissing = 'share_target_missing';
  static const sharePending = 'share_pending';
  static const viewerAlreadyReceiving = 'viewer_already_receiving';
  static const invalidImage = 'invalid_image';
  static const unauthorized = 'unauthorized';
  static const wrongPassword = 'wrong_password';
  static const invalidInput = 'invalid_input';
  static const notFound = 'not_found';

  /// No HTTP response reached the server (offline / DNS / TLS failure).
  static const networkError = 'network_error';

  /// An error we could not classify; [message] carries the underlying detail.
  static const unknown = 'unknown';

  @override
  String toString() => 'MoonaException($code): ${message ?? ''}';
}

enum RealtimeChangeType { create, update, delete, other }

/// A normalized realtime notification from Appwrite.
class RealtimeChange {
  const RealtimeChange({
    required this.collection,
    required this.type,
    required this.payload,
  });

  final String collection;
  final RealtimeChangeType type;
  final Map<String, dynamic> payload;
}

/// Outcome of a share request, used to drive invite-vs-request UI.
class ShareRequestResult {
  const ShareRequestResult({required this.targetExists, this.share});

  final bool targetExists;
  final Share? share;
}

/// Abstraction over the Moona backend so the UI and tests do not depend on
/// Appwrite directly. Implemented by [AppwriteMoonaRepository] (live) and
/// [FakeMoonaRepository] (in-memory, mirrors the mockup seed data).
abstract class MoonaRepository {
  /// Signs in (creating the account on first use) and ensures the profile.
  /// Returns the resolved [Profile].
  Future<Profile> signIn({required String phone, required String password});

  /// Restores an already persisted client session, if one exists.
  Future<bool> restoreSession();

  Future<void> signOut();

  /// Loads everything the main screen needs in one round-trip. On success the
  /// raw response is cached locally for [cachedBootstrap].
  /// Pass [listId] to show a specific list; omit for the default list.
  Future<BootstrapData> bootstrap({String? listId});

  /// Returns the last locally-cached [bootstrap] result without any network or
  /// session, or null when nothing is cached. Used to render the home screen
  /// instantly on launch while the live session is re-validated in the
  /// background. The fake repository returns null.
  Future<BootstrapData?> cachedBootstrap();

  /// Clears the local bootstrap cache (called on logout, or when a restored
  /// session turns out to be invalid).
  Future<void> clearCache();

  Future<Profile> updatePreferences({
    String? language,
    String? theme,
    String? displayName,
  });

  Future<List<Product>> searchProducts(String query);

  /// Resolves which of [phones] belong to registered Moona users. Only phone
  /// numbers are sent — local contact names stay on device and are rejoined by
  /// `phoneDigits`.
  Future<ContactLookupResult> lookupContacts(
    List<String> phones, {
    String defaultCountryCode = '966',
  });

  Future<ListItem> addItem(ItemFormData form);

  Future<ListItem> updateItem(String itemId, ItemFormData form);

  Future<void> trashItem(String itemId, {String reason = 'scratch_timer'});

  /// Backend-owned scratch (Phase 3). Marks the item scratched with a server
  /// expiry window (`scratchExpiresAt`); the item stays active until finalized.
  Future<void> scratchItem(String itemId, {int? windowSeconds});

  /// Clears a scratch before its window lapses (the Undo tap). If the window has
  /// already expired the backend finalizes it instead.
  Future<void> undoScratchItem(String itemId);

  /// Moves an expired scratch to trash (`scratch_timer`) and writes the purchase
  /// event. Best-effort from the client; the backend also finalizes lazily.
  Future<void> finalizeScratch(String itemId, {bool force = false});

  Future<void> restoreTrashItem(String itemId);

  Future<void> clearTrash({String? listId});

  // --- Named lists -----------------------------------------------------------

  Future<List<UserList>> getLists();

  Future<UserList> createList(String name, {String? emoji});

  Future<UserList> updateList(
    String listId, {
    String? name,
    String? emoji,
    int? sortOrder,
  });

  /// Deletes a named list. If [migrateToListId] is provided, all items on the
  /// deleted list are moved there first; otherwise items are hard-deleted.
  Future<void> deleteList(String listId, {String? migrateToListId});

  // --- Barcode ---------------------------------------------------------------

  /// Looks up a product by barcode. Returns null when not found. If not found
  /// and the user is authenticated, the barcode is logged to the submission
  /// queue for admin review.
  Future<Product?> lookupBarcode(String barcode);

  /// Admin: returns the list of unresolved barcode submissions sorted by count.
  Future<List<BarcodeSubmission>> adminGetBarcodeQueue();

  /// Admin: maps a submission to an existing product and marks it resolved.
  Future<void> adminResolveBarcode(String submissionId, String productId);

  Future<ShareRequestResult> requestShare(String phone, {String? listId});

  Future<void> respondShare(String shareId, {required bool accepted});

  Future<void> unlinkShare({
    String? shareId,
    String? viewerId,
    String? ownerId,
  });

  Future<SharingStatus> getSharingStatus();

  /// Paginated activity feed for the visible owner list (`list_events`). Pass
  /// the previous page's `nextCursor` to page further back.
  Future<ActivityFeedPage> getActivity({int limit, String? cursor});

  /// "Buy again" suggestions aggregated from finalized scratch history,
  /// excluding products already on the active list (backend-side).
  Future<List<PurchaseSuggestion>> suggestItems({int limit});

  /// Aggregated buying insights over the visible owner list's scratch history.
  Future<Insights> getInsights({int rangeDays});

  /// Sets or clears the caller's "shopping now" presence for the visible owner
  /// list (Phase 3). Best-effort; heartbeated by the client while in Store Mode.
  Future<void> setShoppingPresence({required bool active});

  /// Registers (or updates) this device's FCM token as an Appwrite push target
  /// for the signed-in user, reusing the locally persisted target id across
  /// token refreshes. Returns the target id, or null when registration failed
  /// (best-effort — push is never allowed to block auth). The fake repository
  /// returns null.
  Future<String?> registerPushTarget(String token);

  /// Deletes this device's Appwrite push target (on logout) and clears the local
  /// record. Best-effort; a no-op when nothing is registered.
  Future<void> removePushTarget();

  /// Uploads an item image and returns its stable file id, or null on failure.
  Future<String?> uploadImage({
    required Uint8List bytes,
    required String filename,
  });

  /// Builds a displayable URL for a stored item image, or null when the backend
  /// cannot serve one (e.g. the fake repository).
  ///
  /// The `item_images` bucket uses `fileSecurity`, so a plain view URL carries
  /// no session on mobile and 401s. This requests a short-lived file view token
  /// (`createImageViewToken`) scoped to the owning [itemId] and appends it to
  /// the view URL, which authenticates the read on every platform.
  Future<String?> imageViewUrl({required String itemId, required String fileId});

  // --- Admin (server-gated by isAdmin / MOONA_ADMIN_USER_IDS) --------------

  /// Lists every row (active + inactive) for an admin [kind] — one of
  /// `users`, `categories`, `units`, `products`, `brands`, `stores`. Returns
  /// raw maps; the admin screens parse them with the matching domain model.
  Future<List<Map<String, dynamic>>> adminList(String kind);

  /// Creates a catalog row of [kind] from [data]; returns the created row.
  Future<Map<String, dynamic>> adminCreate(
    String kind,
    Map<String, dynamic> data,
  );

  /// Patches a catalog/profile row of [kind] by [id] from [data]; returns the
  /// updated row. For `users` only `isAdmin`/`displayName` are honoured.
  Future<Map<String, dynamic>> adminUpdate(
    String kind,
    String id,
    Map<String, dynamic> data,
  );

  /// Deletes a row of [kind] — soft (sets `active=false`) for catalogs, a full
  /// cascade + account removal for `users`.
  Future<void> adminDelete(String kind, String id);

  /// Wipes a user's items, history, linked lists, insights and activity while
  /// keeping their account. Returns the backend's deleted-row counts.
  Future<Map<String, dynamic>> adminResetUser(String userId);

  /// Realtime change notifications for the signed-in session.
  Stream<RealtimeChange> realtimeChanges();

  void dispose();
}
