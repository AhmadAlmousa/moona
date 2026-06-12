import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/config.dart';
import '../../core/util/phone.dart';
import '../cache/bootstrap_cache.dart';
import '../cache/push_target_store.dart';
import '../models/models.dart';
import 'moona_repository.dart';

/// Live [MoonaRepository] backed by Appwrite (Account, Functions, Storage,
/// Realtime), following the contract in `back_to_frontend.md`.
class AppwriteMoonaRepository implements MoonaRepository {
  AppwriteMoonaRepository({
    Client? client,
    BootstrapCache? cache,
    PushTargetStore? pushTargets,
  }) : _cache = cache ?? const BootstrapCache(),
       _pushTargets = pushTargets ?? const PushTargetStore(),
       _client =
           client ??
           (Client()
             ..setEndpoint(MoonaConfig.endpoint)
             ..setProject(MoonaConfig.projectId)) {
    _account = Account(_client);
    _functions = Functions(_client);
    _storage = Storage(_client);
  }

  final BootstrapCache _cache;
  final PushTargetStore _pushTargets;
  final Client _client;
  late final Account _account;
  late final Functions _functions;
  late final Storage _storage;
  Realtime? _realtime;
  String _userId = '';

  @override
  Future<Profile> signIn({
    required String phone,
    required String password,
  }) async {
    final normalized = normalizePhone(phone);
    await _establishSession(normalized, password);

    final user = await _account.get();
    _userId = user.$id;

    final data = await _call(MoonaFunctions.ensureProfile, {'phone': phone});
    return Profile.fromJson(_asMap(data['profile']));
  }

  @override
  Future<bool> restoreSession() async {
    try {
      final user = await _account.get();
      _userId = user.$id;
      final phone = _phoneFromUser(email: user.email, name: user.name);
      if (phone != null) {
        await _call(MoonaFunctions.ensureProfile, {'phone': phone});
      }
      return true;
    } on AppwriteException catch (e) {
      if (_isUnauthorized(e)) return false;
      throw _mapAuthError(e);
    }
  }

  @override
  Future<void> signOut() async {
    _realtime = null;
    await _cache.clear();
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      // Ignore — already signed out.
    }
  }

  @override
  Future<BootstrapData> bootstrap() async {
    final data = await _call(MoonaFunctions.getBootstrapData, {});
    final map = _asMap(data);
    // Cache the raw response so the next launch can hydrate the home screen
    // instantly (offline-first). Best-effort; never blocks the result.
    unawaited(_cache.save(map));
    return BootstrapData.fromJson(map);
  }

  @override
  Future<BootstrapData?> cachedBootstrap() async {
    final raw = await _cache.read();
    if (raw == null) return null;
    try {
      return BootstrapData.fromJson(raw);
    } catch (_) {
      // A schema drift in the cached blob shouldn't wedge startup — drop it.
      await _cache.clear();
      return null;
    }
  }

  @override
  Future<void> clearCache() => _cache.clear();

  @override
  Future<Profile> updatePreferences({
    String? language,
    String? theme,
    String? displayName,
  }) async {
    final data = await _call(MoonaFunctions.updatePreferences, {
      'language': ?language,
      'theme': ?theme,
      'displayName': ?displayName,
    });
    return Profile.fromJson(_asMap(data['profile']));
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final data = await _call(MoonaFunctions.searchProducts, {
      'query': query,
      'limit': 20,
    });
    final suggestions = data['suggestions'];
    if (suggestions is! List) return const [];
    return suggestions
        .whereType<Map>()
        .map((e) => Product.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<ContactLookupResult> lookupContacts(
    List<String> phones, {
    String defaultCountryCode = '966',
  }) async {
    if (phones.isEmpty) return const ContactLookupResult();
    final data = await _call(MoonaFunctions.lookupContacts, {
      'phones': phones,
      'limit': 250,
      'defaultCountryCode': defaultCountryCode,
    });
    return ContactLookupResult.fromJson(_asMap(data));
  }

  @override
  Future<ListItem> addItem(ItemFormData form) async {
    final data = await _call(MoonaFunctions.createItem, form.toPayload());
    return ListItem.fromJson(_asMap(data['item']));
  }

  @override
  Future<ListItem> updateItem(String itemId, ItemFormData form) async {
    final data = await _call(MoonaFunctions.updateItem, {
      'itemId': itemId,
      ...form.toPayload(),
    });
    return ListItem.fromJson(_asMap(data['item']));
  }

  @override
  Future<void> trashItem(String itemId, {String reason = 'scratch_timer'}) =>
      _call(MoonaFunctions.trashItem, {'itemId': itemId, 'reason': reason});

  @override
  Future<void> scratchItem(String itemId, {int? windowSeconds}) => _call(
    MoonaFunctions.scratchItem,
    {'itemId': itemId, 'windowSeconds': ?windowSeconds},
  );

  @override
  Future<void> undoScratchItem(String itemId) =>
      _call(MoonaFunctions.undoScratchItem, {'itemId': itemId});

  @override
  Future<void> finalizeScratch(String itemId, {bool force = false}) => _call(
    MoonaFunctions.finalizeScratch,
    {'itemId': itemId, 'force': force},
  );

  @override
  Future<void> restoreTrashItem(String itemId) =>
      _call(MoonaFunctions.restoreTrashItem, {'itemId': itemId});

  @override
  Future<void> clearTrash() => _call(MoonaFunctions.clearTrash, {});

  @override
  Future<ShareRequestResult> requestShare(String phone) async {
    try {
      final data = await _call(MoonaFunctions.requestShare, {'phone': phone});
      final share = data['share'];
      return ShareRequestResult(
        targetExists: true,
        share: share is Map
            ? Share.fromJson(share.cast<String, dynamic>())
            : null,
      );
    } on MoonaException catch (e) {
      if (e.code == MoonaException.shareTargetMissing) {
        return const ShareRequestResult(targetExists: false);
      }
      rethrow;
    }
  }

  @override
  Future<void> respondShare(String shareId, {required bool accepted}) => _call(
    MoonaFunctions.respondShare,
    {'shareId': shareId, 'accepted': accepted},
  );

  @override
  Future<void> unlinkShare({
    String? shareId,
    String? viewerId,
    String? ownerId,
  }) => _call(MoonaFunctions.unlinkShare, {
    'shareId': ?shareId,
    'viewerId': ?viewerId,
    'ownerId': ?ownerId,
  });

  @override
  Future<SharingStatus> getSharingStatus() async {
    final data = await _call(MoonaFunctions.getSharingStatus, {});
    return SharingStatus.fromJson(_asMap(data['sharing']));
  }

  @override
  Future<ActivityFeedPage> getActivity({int limit = 50, String? cursor}) async {
    final data = await _call(MoonaFunctions.getActivity, {
      'limit': limit,
      'cursor': cursor ?? '',
    });
    return ActivityFeedPage.fromJson(_asMap(data));
  }

  @override
  Future<List<PurchaseSuggestion>> suggestItems({int limit = 20}) async {
    final data = await _call(MoonaFunctions.suggestItems, {'limit': limit});
    final raw = data['suggestions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PurchaseSuggestion.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Insights> getInsights({int rangeDays = 90}) async {
    final data = await _call(MoonaFunctions.getInsights, {
      'rangeDays': rangeDays,
    });
    return Insights.fromJson(_asMap(data['insights']));
  }

  @override
  Future<void> setShoppingPresence({required bool active}) =>
      _call(MoonaFunctions.setShoppingPresence, {'active': active});

  @override
  Future<String?> registerPushTarget(String token) async {
    if (token.isEmpty) return null;
    final stored = await _pushTargets.read();
    try {
      if (stored != null) {
        // Same token already registered — nothing to do.
        if (stored.token == token) return stored.targetId;
        try {
          await _account.updatePushTarget(
            targetId: stored.targetId,
            identifier: token,
          );
          await _pushTargets.save(
            StoredPushTarget(targetId: stored.targetId, token: token),
          );
          return stored.targetId;
        } on AppwriteException catch (e) {
          if (!_isNotFound(e)) rethrow;
          // The stored target vanished server-side — fall through and recreate.
          await _pushTargets.clear();
        }
      }
      final targetId = ID.unique();
      final target = await _account.createPushTarget(
        targetId: targetId,
        identifier: token,
        providerId: MoonaConfig.fcmProviderId,
      );
      await _pushTargets.save(
        StoredPushTarget(targetId: target.$id, token: token),
      );
      return target.$id;
    } on AppwriteException catch (e) {
      debugPrint('Moona push target register failed: ${e.message ?? e.type}');
      return null;
    }
  }

  @override
  Future<void> removePushTarget() async {
    final stored = await _pushTargets.read();
    await _pushTargets.clear();
    if (stored == null) return;
    try {
      await _account.deletePushTarget(targetId: stored.targetId);
    } on AppwriteException {
      // Already gone (or session expired) — the local record is cleared either way.
    }
  }

  @override
  Future<String?> uploadImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final file = await _storage.createFile(
        bucketId: MoonaConfig.imageBucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: bytes, filename: filename),
        permissions: _userId.isEmpty
            ? null
            : [
                Permission.read(Role.user(_userId)),
                Permission.update(Role.user(_userId)),
                Permission.delete(Role.user(_userId)),
              ],
      );
      return file.$id;
    } on AppwriteException {
      throw const MoonaException(MoonaException.invalidImage);
    }
  }

  /// Cached file view tokens keyed by `itemId|fileId`, reused until shortly
  /// before they expire to avoid a function round-trip on every thumbnail build.
  final Map<String, _ImageViewToken> _imageTokens = {};

  @override
  Future<String?> imageViewUrl({
    required String itemId,
    required String fileId,
  }) async {
    final base =
        '${MoonaConfig.endpoint}/storage/buckets/${MoonaConfig.imageBucketId}'
        '/files/$fileId/view?project=${MoonaConfig.projectId}';

    final cacheKey = '$itemId|$fileId';
    final cached = _imageTokens[cacheKey];
    if (cached != null && cached.isFresh) {
      return '$base&token=${Uri.encodeComponent(cached.token)}';
    }

    try {
      final data = await _call(MoonaFunctions.createImageViewToken, {
        'itemId': itemId,
        'fileId': fileId,
      });
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) return base;
      final expire =
          _date(data['expire']) ??
          DateTime.now().add(const Duration(minutes: 15));
      _imageTokens[cacheKey] = _ImageViewToken(token, expire);
      return '$base&token=${Uri.encodeComponent(token)}';
    } on MoonaException {
      // Fall back to the bare view URL — web sessions still authenticate via
      // the cookie; mobile will surface the image error builder.
      return base;
    }
  }

  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  @override
  Future<List<Map<String, dynamic>>> adminList(String kind) async {
    final data = await _call(MoonaFunctions.adminList, {'kind': kind});
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<Map<String, dynamic>> adminCreate(
    String kind,
    Map<String, dynamic> data,
  ) async {
    final res = await _call(MoonaFunctions.adminCreate, {
      'kind': kind,
      'data': data,
    });
    return _asMap(res['item']);
  }

  @override
  Future<Map<String, dynamic>> adminUpdate(
    String kind,
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _call(MoonaFunctions.adminUpdate, {
      'kind': kind,
      'id': id,
      'data': data,
    });
    return _asMap(res['item']);
  }

  @override
  Future<void> adminDelete(String kind, String id) async {
    await _call(MoonaFunctions.adminDelete, {'kind': kind, 'id': id});
  }

  @override
  Future<Map<String, dynamic>> adminResetUser(String userId) async {
    final res = await _call(MoonaFunctions.adminResetUser, {'id': userId});
    return _asMap(res['result']);
  }

  @override
  Stream<RealtimeChange> realtimeChanges() {
    final realtime = _realtime ??= Realtime(_client);
    final channels = MoonaCollections.all
        .map((id) => 'tablesdb.${MoonaConfig.databaseId}.tables.$id.rows')
        .toList();
    return realtime.subscribe(channels).stream.map(_mapChange);
  }

  RealtimeChange _mapChange(RealtimeMessage message) {
    final collection = MoonaCollections.all.firstWhere(
      (id) => message.events.any((e) => e.contains('.tables.$id.')),
      orElse: () => '',
    );
    final type = message.events.any((e) => e.endsWith('.create'))
        ? RealtimeChangeType.create
        : message.events.any((e) => e.endsWith('.update'))
        ? RealtimeChangeType.update
        : message.events.any((e) => e.endsWith('.delete'))
        ? RealtimeChangeType.delete
        : RealtimeChangeType.other;
    return RealtimeChange(
      collection: collection,
      type: type,
      payload: message.payload,
    );
  }

  @override
  void dispose() {
    _realtime = null;
  }

  /// Invokes a Moona function and unwraps the `{ok, data}` envelope.
  Future<Map<String, dynamic>> _call(
    String functionId,
    Map<String, dynamic> payload,
  ) async {
    final execution = await _functions.createExecution(
      functionId: MoonaFunctions.dispatcher,
      body: jsonEncode({...payload, 'action': functionId}),
      xasync: false,
    );
    final body = execution.responseBody;
    if (body.isEmpty) {
      throw const MoonaException(MoonaException.invalidInput, 'Empty response');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const MoonaException(MoonaException.invalidInput);
    }
    if (decoded['ok'] == true) {
      return _asMap(decoded['data']);
    }
    final error = decoded['error'];
    if (error is Map) {
      throw MoonaException(
        error['code']?.toString() ?? MoonaException.invalidInput,
        error['message']?.toString(),
      );
    }
    throw const MoonaException(MoonaException.invalidInput);
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  Future<void> _establishSession(
    NormalizedPhone normalized,
    String password,
  ) async {
    try {
      await _createEmailSession(normalized.aliasEmail, password);
      return;
    } on AppwriteException catch (e) {
      if (_isSessionAlreadyActive(e)) {
        if (await _currentSessionMatches(normalized.aliasEmail)) return;
        await signOut();
        await _createSessionOrAccount(normalized, password);
        return;
      }
      if (!_isInvalidCredentials(e)) throw _mapAuthError(e);
    }

    await _createSessionOrAccount(normalized, password);
  }

  Future<void> _createSessionOrAccount(
    NormalizedPhone normalized,
    String password,
  ) async {
    try {
      await _account.create(
        userId: ID.unique(),
        email: normalized.aliasEmail,
        password: password,
        name: normalized.digits,
      );
    } on AppwriteException catch (e) {
      if (_isExistingUser(e)) {
        throw const MoonaException(MoonaException.wrongPassword);
      }
      throw _mapAuthError(e);
    }

    try {
      await _createEmailSession(normalized.aliasEmail, password);
    } on AppwriteException catch (e) {
      throw _mapAuthError(e);
    }
  }

  Future<void> _createEmailSession(String email, String password) =>
      _account.createEmailPasswordSession(email: email, password: password);

  Future<bool> _currentSessionMatches(String email) async {
    try {
      final user = await _account.get();
      return user.email.toLowerCase() == email.toLowerCase();
    } on AppwriteException {
      return false;
    }
  }

  String? _phoneFromUser({required String email, required String name}) {
    final alias = RegExp(
      '^phone-(\\d+)@${RegExp.escape(MoonaConfig.aliasEmailDomain)}\$',
    ).firstMatch(email.toLowerCase());
    if (alias != null) return '+${alias.group(1)}';

    final digits = name.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8 && digits.length <= 15) return '+$digits';
    return null;
  }

  bool _isInvalidCredentials(AppwriteException e) =>
      e.type == 'user_invalid_credentials';

  bool _isSessionAlreadyActive(AppwriteException e) =>
      e.type == 'user_session_already_exists' ||
      (e.message ?? '').toLowerCase().contains('session') &&
          (e.message ?? '').toLowerCase().contains('active');

  bool _isExistingUser(AppwriteException e) =>
      e.code == 409 || (e.type ?? '').contains('already_exists');

  bool _isUnauthorized(AppwriteException e) =>
      e.code == 401 ||
      e.type == 'user_unauthorized' ||
      e.type == 'general_unauthorized_scope';

  bool _isNotFound(AppwriteException e) =>
      e.code == 404 || (e.type ?? '').contains('not_found');

  /// Translates a raw [AppwriteException] from the auth flow into a
  /// [MoonaException] the UI can act on. A null/zero HTTP status means no
  /// response reached the server (offline / DNS / TLS), which is by far the most
  /// common cause of a generic "something went wrong" on a fresh device.
  MoonaException _mapAuthError(AppwriteException e) {
    if (e.code == null || e.code == 0) {
      return const MoonaException(MoonaException.networkError);
    }
    return MoonaException(MoonaException.unknown, e.message ?? e.type);
  }
}

/// A cached Appwrite file view token with its server-reported expiry.
class _ImageViewToken {
  _ImageViewToken(this.token, this.expiresAt);

  final String token;
  final DateTime expiresAt;

  /// Whether the token is still valid with a safety margin to cover render +
  /// network latency before it lapses.
  bool get isFresh =>
      expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)));
}
