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
  Future<BootstrapData> bootstrap();

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
  Future<ContactLookupResult> lookupContacts(List<String> phones);

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

  Future<void> clearTrash();

  Future<ShareRequestResult> requestShare(String phone);

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

  /// Realtime change notifications for the signed-in session.
  Stream<RealtimeChange> realtimeChanges();

  void dispose();
}
