import 'dart:convert';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';

import '../../core/config.dart';
import '../../core/util/phone.dart';
import '../models/models.dart';
import 'moona_repository.dart';

/// Live [MoonaRepository] backed by Appwrite (Account, Functions, Storage,
/// Realtime), following the contract in `back_to_frontend.md`.
class AppwriteMoonaRepository implements MoonaRepository {
  AppwriteMoonaRepository({Client? client})
    : _client =
          client ??
          (Client()
            ..setEndpoint(MoonaConfig.endpoint)
            ..setProject(MoonaConfig.projectId)) {
    _account = Account(_client);
    _functions = Functions(_client);
    _storage = Storage(_client);
  }

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
    final email = normalized.aliasEmail;

    try {
      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
    } on AppwriteException catch (signInError) {
      // Appwrite returns the same `user_invalid_credentials` error whether the
      // password is wrong or the account does not exist yet (it won't reveal
      // which). Only then do we try to register: if the account already exists,
      // the password was wrong. Any other failure (network, blocked origin,
      // server error) is real and must be surfaced — not hidden behind a
      // new-user signup attempt that fails the same way.
      if (signInError.type != 'user_invalid_credentials') {
        throw _mapAuthError(signInError);
      }
      try {
        await _account.create(
          userId: ID.unique(),
          email: email,
          password: password,
          name: normalized.digits,
        );
      } on AppwriteException catch (e) {
        if (e.type == 'user_already_exists') {
          throw const MoonaException(MoonaException.wrongPassword);
        }
        throw _mapAuthError(e);
      }
      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
    }

    final user = await _account.get();
    _userId = user.$id;

    final data = await _call(MoonaFunctions.ensureProfile, {'phone': phone});
    return Profile.fromJson(_asMap(data['profile']));
  }

  @override
  Future<void> signOut() async {
    _realtime = null;
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      // Ignore — already signed out.
    }
  }

  @override
  Future<BootstrapData> bootstrap() async {
    final data = await _call(MoonaFunctions.getBootstrapData, {});
    return BootstrapData.fromJson(_asMap(data));
  }

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

  @override
  String? imageUrl(String fileId) =>
      '${MoonaConfig.endpoint}/storage/buckets/${MoonaConfig.imageBucketId}'
      '/files/$fileId/view?project=${MoonaConfig.projectId}';

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
