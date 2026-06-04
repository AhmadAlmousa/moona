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

  /// Loads everything the main screen needs in one round-trip.
  Future<BootstrapData> bootstrap();

  Future<Profile> updatePreferences({
    String? language,
    String? theme,
    String? displayName,
  });

  Future<List<Product>> searchProducts(String query);

  Future<ListItem> addItem(ItemFormData form);

  Future<ListItem> updateItem(String itemId, ItemFormData form);

  Future<void> trashItem(String itemId, {String reason = 'scratch_timer'});

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

  /// Uploads an item image and returns its stable file id, or null on failure.
  Future<String?> uploadImage({
    required Uint8List bytes,
    required String filename,
  });

  /// Builds a displayable URL for a stored image file id, or null when the
  /// backend cannot serve one (e.g. the fake repository).
  String? imageUrl(String fileId);

  /// Realtime change notifications for the signed-in session.
  Stream<RealtimeChange> realtimeChanges();

  void dispose();
}
