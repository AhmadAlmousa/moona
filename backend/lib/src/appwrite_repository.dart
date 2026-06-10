import 'dart:io' show Platform;

import 'package:dart_appwrite/dart_appwrite.dart';

import 'errors.dart';
import 'ids.dart';
import 'normalization.dart';
import 'rules.dart';
import 'schema.dart';

Client appwriteAdminClient(String apiKey) {
  final endpoint = appwriteEndpoint();
  final project = appwriteProjectId();
  if (apiKey.isEmpty) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Missing Appwrite function API key for backend function.',
      status: 500,
    );
  }
  return Client().setEndpoint(endpoint).setProject(project).setKey(apiKey);
}

Client appwriteJwtClient(String jwt) {
  final endpoint = appwriteEndpoint();
  final project = appwriteProjectId();
  return Client().setEndpoint(endpoint).setProject(project).setJWT(jwt);
}

class AppwriteRepository {
  AppwriteRepository({required Client adminClient, Client? userClient})
      : adminDatabases = TablesDBAdapter(TablesDB(adminClient)),
        adminStorage = StorageAdapter(Storage(adminClient)),
        adminTokens = TokensAdapter(Tokens(adminClient)),
        adminMessaging = MessagingAdapter(Messaging(adminClient)),
        users = UsersAdapter(Users(adminClient)),
        userDatabases =
            userClient == null ? null : TablesDBAdapter(TablesDB(userClient));

  final TablesDBAdapter adminDatabases;
  final StorageAdapter adminStorage;
  final TokensAdapter adminTokens;
  final MessagingAdapter adminMessaging;
  final UsersAdapter users;
  final TablesDBAdapter? userDatabases;

  Future<JsonMap> ensureProfile(JsonMap input) async {
    final normalized = normalizePhone(input['phone']);
    final now = nowIso();
    JsonMap? existing;
    try {
      existing = await getProfile(input['userId']);
    } catch (error) {
      if (!isMissing(error)) rethrow;
    }

    final userId = input['userId'].toString();
    final data = {
      'userId': userId,
      'phone': normalized['e164'],
      'phoneDigits': normalized['digits'],
      'displayName': input['displayName'] ??
          existing?['displayName'] ??
          normalized['e164'],
      'language': input['language'] ??
          existing?['language'] ??
          Platform.environment['MOONA_DEFAULT_LANGUAGE'] ??
          'ar',
      'theme': input['theme'] ??
          existing?['theme'] ??
          Platform.environment['MOONA_DEFAULT_THEME'] ??
          'light',
      'activeReceivedOwnerId': existing?['activeReceivedOwnerId'] ?? '',
      'createdAt': existing?['createdAt'] ?? now,
      'updatedAt': now,
    };

    if (existing != null) {
      return adminDatabases.updateDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.profiles,
        documentId: userId,
        data: data,
        permissions: userDocumentPermissions(userId),
      );
    }

    return adminDatabases.createDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.profiles,
      documentId: userId,
      data: data,
      permissions: userDocumentPermissions(userId),
    );
  }

  Future<JsonMap> updatePreferences(String userId, JsonMap input) {
    final patch = <String, dynamic>{'updatedAt': nowIso()};
    if ((input['language'] ?? '').toString().isNotEmpty) {
      patch['language'] = input['language'];
    }
    if ((input['theme'] ?? '').toString().isNotEmpty) {
      patch['theme'] = input['theme'];
    }
    if ((input['displayName'] ?? '').toString().isNotEmpty) {
      patch['displayName'] = input['displayName'];
    }

    return adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.profiles,
      documentId: userId,
      data: patch,
    );
  }

  Future<JsonMap> getProfile(Object? userId) => adminDatabases.getDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.profiles,
        documentId: userId.toString(),
      );

  Future<JsonMap?> findProfileByPhone(Object? phone) async {
    final digits = phoneDigitLookupVariants(phone);
    final result = await adminDatabases.listDocuments(
      databaseId: databaseId,
      collectionId: CollectionIds.profiles,
      queries: [Query.equal('phoneDigits', digits), Query.limit(1)],
    );
    return result.documents.firstOrNull;
  }

  Future<List<JsonMap>> listProfilesByPhoneDigits(
    Iterable<String> phoneDigits,
  ) async {
    final uniqueDigits = phoneDigits
        .expand((value) {
          try {
            return phoneDigitLookupVariants(value);
          } catch (_) {
            final trimmed = value.trim();
            return trimmed.isEmpty ? const <String>[] : [trimmed];
          }
        })
        .toSet()
        .toList();
    if (uniqueDigits.isEmpty) return const [];

    final profiles = <JsonMap>[];
    for (var i = 0; i < uniqueDigits.length; i += 100) {
      final chunk = uniqueDigits.skip(i).take(100).toList();
      profiles.addAll(
        await listAllDocuments(adminDatabases, CollectionIds.profiles, [
          Query.equal('phoneDigits', chunk),
        ]),
      );
    }
    return uniqueDocuments(profiles);
  }

  Future<List<JsonMap>> listProfiles() =>
      listAllDocuments(adminDatabases, CollectionIds.profiles);

  Future<List<JsonMap>> listCategories({bool activeOnly = true}) {
    final queries = [Query.orderAsc('sortOrder')];
    if (activeOnly) queries.insert(0, Query.equal('active', true));
    return listAllDocuments(adminDatabases, CollectionIds.categories, queries);
  }

  Future<List<JsonMap>> listUnits({bool activeOnly = true}) {
    final queries = [Query.orderAsc('sortOrder')];
    if (activeOnly) queries.insert(0, Query.equal('active', true));
    return listAllDocuments(adminDatabases, CollectionIds.units, queries);
  }

  Future<List<JsonMap>> listProducts({bool activeOnly = true}) {
    final queries = [Query.orderAsc('displayName')];
    if (activeOnly) queries.insert(0, Query.equal('active', true));
    return listAllDocuments(adminDatabases, CollectionIds.products, queries);
  }

  Future<JsonMap?> findProductByName(Object? name) async {
    final normalized = normalizeProductName(name);
    final byPrimary = await adminDatabases.listDocuments(
      databaseId: databaseId,
      collectionId: CollectionIds.products,
      queries: [
        Query.equal('normalizedName', normalized),
        Query.equal('active', true),
        Query.limit(1),
      ],
    );
    if (byPrimary.documents.isNotEmpty) return byPrimary.documents.first;

    final allProducts = await listProducts();
    return matchProductByName(allProducts, name);
  }

  Future<JsonMap> ensureProduct(Object? nameOrInput) async {
    final input = nameOrInput is Map
        ? nameOrInput.cast<String, dynamic>()
        : {'displayName': nameOrInput, 'nameEn': nameOrInput};
    final existing =
        await findProductByName(input['displayName'] ?? input['name']);
    if (existing != null) return existing;

    final product = buildProductDocument(input);
    return adminDatabases.createDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.products,
      documentId: ID.unique(),
      data: withoutId(product),
      permissions: catalogDocumentPermissions(),
    );
  }

  Future<JsonMap> getProduct(Object? productId) => adminDatabases.getDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.products,
        documentId: productId.toString(),
      );

  Future<List<JsonMap>> listSharesForOwner(Object? ownerId) =>
      listAllDocuments(adminDatabases, CollectionIds.shares, [
        Query.equal('ownerId', ownerId),
      ]);

  Future<List<JsonMap>> listSharesForViewer(Object? viewerId) =>
      listAllDocuments(adminDatabases, CollectionIds.shares, [
        Query.equal('viewerId', viewerId),
      ]);

  Future<List<JsonMap>> listSharesForParticipant(Object? userId) async {
    final owned = await listSharesForOwner(userId);
    final viewed = await listSharesForViewer(userId);
    return uniqueDocuments([...owned, ...viewed]);
  }

  Future<List<JsonMap>> listAcceptedSharesForOwner(Object? ownerId) =>
      listAllDocuments(adminDatabases, CollectionIds.shares, [
        Query.equal('ownerId', ownerId),
        Query.equal('status', 'accepted'),
      ]);

  Future<List<JsonMap>> listActiveItems(Object? ownerId) =>
      listAllDocuments(adminDatabases, CollectionIds.listItems, [
        Query.equal('ownerId', ownerId),
        Query.equal('status', 'active'),
        Query.orderDesc('important'),
        Query.orderDesc('updatedAt'),
      ]);

  Future<List<JsonMap>> listTrashItems(Object? ownerId) =>
      listAllDocuments(adminDatabases, CollectionIds.listItems, [
        Query.equal('ownerId', ownerId),
        Query.equal('status', 'trash'),
        Query.orderDesc('trashedAt'),
      ]);

  Future<List<JsonMap>> listEvents(
    Object? ownerId, {
    int limit = 50,
    String? cursor,
    List<String>? types,
    DateTime? since,
  }) async {
    final queries = <String>[
      Query.equal('ownerId', ownerId),
      if (types != null && types.isNotEmpty) Query.equal('type', types),
      if (since != null)
        Query.greaterThanEqual('createdAt', since.toIso8601String()),
      Query.orderDesc('createdAt'),
      Query.limit(limit),
      if ((cursor ?? '').isNotEmpty) Query.cursorAfter(cursor!),
    ];
    final page = await adminDatabases.listDocuments(
      databaseId: databaseId,
      collectionId: CollectionIds.listEvents,
      queries: queries,
    );
    return page.documents;
  }

  Future<JsonMap> getListItem(Object? itemId) => adminDatabases.getDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listItems,
        documentId: itemId.toString(),
      );

  Future<JsonMap> createListItem(
    JsonMap data, [
    List<JsonMap> ownerShares = const [],
  ]) =>
      adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listItems,
        documentId: ID.unique(),
        data: data,
        permissions:
            listItemPermissions(data['ownerId'].toString(), ownerShares),
      );

  Future<JsonMap> createListEvent(
    JsonMap data, [
    List<JsonMap> ownerShares = const [],
  ]) =>
      adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listEvents,
        documentId: ID.unique(),
        data: data,
        permissions: eventPermissions(
          data['ownerId'].toString(),
          ownerShares,
        ),
      );

  Future<JsonMap> updateListItem(
      Object? itemId, JsonMap data, Object? ownerId) async {
    final ownerShares = await listAcceptedSharesForOwner(ownerId);
    return adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.listItems,
      documentId: itemId.toString(),
      data: data,
      permissions: listItemPermissions(ownerId.toString(), ownerShares),
    );
  }

  Future<dynamic> deleteListItem(Object? itemId) =>
      adminDatabases.deleteDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listItems,
        documentId: itemId.toString(),
      );

  Future<JsonMap> createShare(JsonMap data) => adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.shares,
        documentId: ID.unique(),
        data: data,
        permissions: sharePermissions(
            data['ownerId'].toString(), data['viewerId'].toString()),
      );

  Future<JsonMap> updateShare(Object? shareId, JsonMap data) async {
    final existing = await getShare(shareId);
    return adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.shares,
      documentId: shareId.toString(),
      data: data,
      permissions: sharePermissions(
        existing['ownerId'].toString(),
        existing['viewerId'].toString(),
      ),
    );
  }

  Future<JsonMap> getShare(Object? shareId) => adminDatabases.getDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.shares,
        documentId: shareId.toString(),
      );

  Future<JsonMap?> findShare(Object? ownerId, Object? viewerId) async {
    final result = await adminDatabases.listDocuments(
      databaseId: databaseId,
      collectionId: CollectionIds.shares,
      queries: [
        Query.equal('ownerId', ownerId),
        Query.equal('viewerId', viewerId),
        Query.limit(1),
      ],
    );
    return result.documents.firstOrNull;
  }

  Future<JsonMap> setActiveReceivedOwner(Object? viewerId, Object? ownerId) =>
      adminDatabases.updateDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.profiles,
        documentId: viewerId.toString(),
        data: {
          'activeReceivedOwnerId': ownerId?.toString() ?? '',
          'updatedAt': nowIso(),
        },
      );

  Future<void> refreshOwnerPermissions(Object? ownerId) async {
    final shares = await listAcceptedSharesForOwner(ownerId);
    final items =
        await listAllDocuments(adminDatabases, CollectionIds.listItems, [
      Query.equal('ownerId', ownerId),
    ]);

    for (final item in items) {
      await adminDatabases.updateDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listItems,
        documentId: documentId(item),
        data: {},
        permissions: listItemPermissions(ownerId.toString(), shares),
      );
    }

    final imageFileIds = items
        .map((item) => (item['imageFileId'] ?? '').toString())
        .where((fileId) => fileId.isNotEmpty)
        .toSet();
    for (final fileId in imageFileIds) {
      await updateImagePermissions(fileId, ownerId, shares);
    }
  }

  Future<List<JsonMap>> listShoppingPresence(Object? ownerId) =>
      listAllDocuments(adminDatabases, CollectionIds.shoppingPresence, [
        Query.equal('ownerId', ownerId),
        Query.orderDesc('activeAt'),
      ]);

  Future<JsonMap> upsertShoppingPresence(
    Object? actorId,
    JsonMap data, [
    List<JsonMap> ownerShares = const [],
  ]) async {
    final id = actorId.toString();
    try {
      await adminDatabases.getDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.shoppingPresence,
        documentId: id,
      );
      return adminDatabases.updateDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.shoppingPresence,
        documentId: id,
        data: data,
        permissions: presencePermissions(
          data['ownerId'].toString(),
          ownerShares,
        ),
      );
    } catch (error) {
      if (!isMissing(error)) rethrow;
    }

    return adminDatabases.createDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.shoppingPresence,
      documentId: id,
      data: data,
      permissions: presencePermissions(
        data['ownerId'].toString(),
        ownerShares,
      ),
    );
  }

  Future<void> deleteShoppingPresence(Object? actorId) async {
    try {
      await adminDatabases.deleteDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.shoppingPresence,
        documentId: actorId.toString(),
      );
    } catch (error) {
      if (!isMissing(error)) rethrow;
    }
  }

  Future<dynamic> updateImagePermissions(
    Object? fileId,
    Object? ownerId, [
    List<JsonMap>? ownerShares,
  ]) async {
    final value = (fileId ?? '').toString();
    if (value.isEmpty) return null;
    final shares = ownerShares ?? await listAcceptedSharesForOwner(ownerId);
    return adminStorage.updateFile(
      bucketId: imageBucketId,
      fileId: value,
      permissions: filePermissions(ownerId.toString(), shares),
    );
  }

  Future<dynamic> validateImageFile(Object? fileId) async {
    final value = (fileId ?? '').toString();
    if (value.isEmpty) return null;
    try {
      final file = await adminStorage.getFile(
        bucketId: imageBucketId,
        fileId: value,
      );
      final name = readDynamic<String>(file, 'name') ?? '';
      final extension = name.split('.').last.toLowerCase();
      final size = readDynamic<num>(file, 'sizeOriginal')?.toInt() ?? 0;
      if ((extension.isNotEmpty &&
              !allowedImageExtensions.contains(extension)) ||
          size > maxImageSizeBytes) {
        throw StateError('Unsupported image file.');
      }
      return file;
    } catch (_) {
      throw MoonaError(
        ErrorCodes.invalidImage,
        'Image file is missing, too large, or uses an unsupported format.',
        details: {'fileId': value},
      );
    }
  }

  Future<JsonMap> createImageViewToken(
    Object? fileId, {
    String? expire,
  }) async {
    final value = (fileId ?? '').toString();
    if (value.isEmpty) {
      throw MoonaError(
        ErrorCodes.invalidInput,
        'fileId is required.',
      );
    }
    final token = await adminTokens.createFileToken(
      bucketId: imageBucketId,
      fileId: value,
      expire: expire,
    );
    return (token.toMap() as Map).cast<String, dynamic>();
  }

  Future<void> sendPush({
    required List<String> userIds,
    String? title,
    String? body,
    JsonMap data = const {},
  }) async {
    if (Platform.environment['MOONA_PUSH_ENABLED'] != 'true') return;
    final users = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (users.isEmpty) return;
    await adminMessaging.createPush(
      messageId: ID.unique(),
      title: title,
      body: body,
      users: users,
      data: data,
    );
  }

  Future<List<JsonMap>> adminList(Object? kind) {
    if (kind == 'categories') return listCategories(activeOnly: false);
    if (kind == 'units') return listUnits(activeOnly: false);
    if (kind == 'products') return listProducts(activeOnly: false);
    if (kind == 'users') return listProfiles();
    throw MoonaError(ErrorCodes.invalidInput, 'Unsupported admin list kind.');
  }

  Future<JsonMap> adminCreate(Object? kind, Object? rawInput) {
    final input = rawInput is Map
        ? rawInput.cast<String, dynamic>()
        : <String, dynamic>{};
    final now = nowIso();
    if (kind == 'categories') {
      return adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.categories,
        documentId: (input['id'] ?? input['stableId']).toString(),
        data: {
          'stableId': input['id'] ?? input['stableId'],
          'nameAr': input['nameAr'],
          'nameEn': input['nameEn'],
          'emoji': input['emoji'],
          'sortOrder': _intFrom(input['sortOrder'], fallback: 0),
          'active': input['active'] != false,
          'createdAt': now,
          'updatedAt': now,
        },
        permissions: catalogDocumentPermissions(),
      );
    }

    if (kind == 'units') {
      return adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.units,
        documentId: (input['id'] ?? input['stableId']).toString(),
        data: {
          'stableId': input['id'] ?? input['stableId'],
          'nameAr': input['nameAr'],
          'nameEn': input['nameEn'],
          'sortOrder': _intFrom(input['sortOrder'], fallback: 0),
          'active': input['active'] != false,
          'createdAt': now,
          'updatedAt': now,
        },
        permissions: catalogDocumentPermissions(),
      );
    }

    if (kind == 'products') {
      final data = buildProductDocument(input);
      return adminDatabases.createDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.products,
        documentId: (input['id'] ?? ID.unique()).toString(),
        data: withoutId(data),
        permissions: catalogDocumentPermissions(),
      );
    }

    throw MoonaError(ErrorCodes.invalidInput, 'Unsupported admin create kind.');
  }

  Future<JsonMap> adminUpdate(
      Object? kind, Object? id, Object? rawInput) async {
    final input = rawInput is Map
        ? rawInput.cast<String, dynamic>()
        : <String, dynamic>{};
    final data = {...input, 'updatedAt': nowIso()};
    if (kind == 'products') {
      final existing = await getProduct(id);
      data.addAll(withoutId(buildProductDocument({...existing, ...input})));
      data.remove('createdAt');
    }

    final collectionId = adminKindToCollection(kind);
    return adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: id.toString(),
      data: data,
    );
  }

  Future<dynamic> adminDelete(Object? kind, Object? id) async {
    if (kind == 'users') {
      await users.delete(userId: id.toString());
      return adminDatabases.deleteDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.profiles,
        documentId: id.toString(),
      );
    }

    final collectionId = adminKindToCollection(kind);
    return adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: id.toString(),
      data: {'active': false, 'updatedAt': nowIso()},
    );
  }

  Future<JsonMap> mergeProducts(
      Object? sourceProductId, Object? targetProductId) async {
    if (sourceProductId == targetProductId) {
      throw MoonaError(
        ErrorCodes.invalidInput,
        'Source and target products must be different.',
      );
    }

    await getProduct(targetProductId);
    final source = await getProduct(sourceProductId);
    final affectedItems = await listAllDocuments(
      adminDatabases,
      CollectionIds.listItems,
      [Query.equal('productId', sourceProductId)],
    );

    for (final item in affectedItems) {
      await adminDatabases.updateDocument(
        databaseId: databaseId,
        collectionId: CollectionIds.listItems,
        documentId: documentId(item),
        data: {'productId': targetProductId, 'updatedAt': nowIso()},
      );
    }

    await adminDatabases.updateDocument(
      databaseId: databaseId,
      collectionId: CollectionIds.products,
      documentId: sourceProductId.toString(),
      data: {
        'active': false,
        'mergeTargetProductId': targetProductId,
        'updatedAt': nowIso(),
      },
    );

    return {
      'sourceProductId': documentId(source),
      'targetProductId': targetProductId,
      'affectedItemCount': affectedItems.length,
    };
  }
}

List<String> userDocumentPermissions(String userId) => [
      Permission.read(Role.user(userId)),
      Permission.update(Role.user(userId)),
      Permission.delete(Role.user(userId)),
    ];

List<String> catalogDocumentPermissions() => [Permission.read(Role.users())];

List<String> sharePermissions(String ownerId, String viewerId) => [
      ...readWritePermissions(ownerId),
      ...readWritePermissions(viewerId),
    ];

List<String> listItemPermissions(
  String ownerId, [
  List<JsonMap> ownerShares = const [],
]) {
  final participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants.expand(readWritePermissions).toList();
}

List<String> eventPermissions(
  String ownerId, [
  List<JsonMap> ownerShares = const [],
]) {
  final participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants
      .map((userId) => Permission.read(Role.user(userId)))
      .toList();
}

List<String> presencePermissions(
  String ownerId, [
  List<JsonMap> ownerShares = const [],
]) {
  final participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants
      .map((userId) => Permission.read(Role.user(userId)))
      .toList();
}

List<String> filePermissions(
  String ownerId, [
  List<JsonMap> ownerShares = const [],
]) {
  final participants = [
    ownerId,
    ...acceptedViewerIdsForOwner(ownerId, ownerShares),
  ];
  return participants
      .expand(
        (userId) => [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      )
      .toList();
}

Future<List<JsonMap>> listAllDocuments(
  TablesDBAdapter databases,
  String collectionId, [
  List<String> queries = const [],
]) async {
  final documents = <JsonMap>[];
  var offset = 0;
  const pageSize = 100;

  while (true) {
    final page = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [...queries, Query.limit(pageSize), Query.offset(offset)],
    );
    documents.addAll(page.documents);
    if (page.documents.length < pageSize) break;
    offset += pageSize;
  }

  return documents;
}

List<String> readWritePermissions(String userId) => [
      Permission.read(Role.user(userId)),
      Permission.update(Role.user(userId)),
      Permission.delete(Role.user(userId)),
    ];

String adminKindToCollection(Object? kind) {
  if (kind == 'categories') return CollectionIds.categories;
  if (kind == 'units') return CollectionIds.units;
  if (kind == 'products') return CollectionIds.products;
  if (kind == 'users') return CollectionIds.profiles;
  throw MoonaError(ErrorCodes.invalidInput, 'Unsupported admin kind.');
}

JsonMap withoutId(JsonMap document) {
  final copy = {...document};
  copy.remove('id');
  return copy;
}

List<JsonMap> uniqueDocuments(List<JsonMap> documents) {
  final seen = <String>{};
  return documents.where((document) {
    final id = documentId(document);
    if (seen.contains(id)) return false;
    seen.add(id);
    return true;
  }).toList();
}

bool isMissing(Object error) {
  if (error is AppwriteException) {
    return error.code == 404 ||
        error.type == 'document_not_found' ||
        error.type == 'row_not_found';
  }
  return false;
}

String requireEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Missing required environment variable $name.',
      status: 500,
    );
  }
  return value;
}

String appwriteEndpoint() =>
    Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ??
    Platform.environment['APPWRITE_ENDPOINT'] ??
    requireEnv('APPWRITE_ENDPOINT');

String appwriteProjectId() =>
    Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ??
    Platform.environment['APPWRITE_PROJECT_ID'] ??
    requireEnv('APPWRITE_PROJECT_ID');

class DocumentPage {
  const DocumentPage({required this.documents, required this.total});

  final List<JsonMap> documents;
  final int total;
}

class TablesDBAdapter {
  TablesDBAdapter(this.tablesDB);

  final TablesDB tablesDB;

  Future<dynamic> create({
    required String databaseId,
    required String name,
    bool? enabled,
  }) =>
      tablesDB.create(databaseId: databaseId, name: name, enabled: enabled);

  Future<dynamic> createCollection({
    required String databaseId,
    required String collectionId,
    required String name,
    required List<String> permissions,
    required bool documentSecurity,
    required bool enabled,
  }) =>
      tablesDB.createTable(
        databaseId: databaseId,
        tableId: collectionId,
        name: name,
        permissions: permissions,
        rowSecurity: documentSecurity,
        enabled: enabled,
      );

  Future<DocumentPage> listDocuments({
    required String databaseId,
    required String collectionId,
    List<String> queries = const [],
  }) async {
    final response = await tablesDB.listRows(
      databaseId: databaseId,
      tableId: collectionId,
      queries: queries,
    );
    final rows = readRows(response).map(rowToMap).toList();
    return DocumentPage(
      documents: rows,
      total: readDynamic<num>(response, 'total')?.toInt() ?? rows.length,
    );
  }

  Future<JsonMap> getDocument({
    required String databaseId,
    required String collectionId,
    required String documentId,
    List<String> queries = const [],
  }) async {
    final row = await tablesDB.getRow(
      databaseId: databaseId,
      tableId: collectionId,
      rowId: documentId,
      queries: queries,
    );
    return rowToMap(row);
  }

  Future<JsonMap> createDocument({
    required String databaseId,
    required String collectionId,
    required String documentId,
    required JsonMap data,
    List<String>? permissions,
  }) async {
    final row = await tablesDB.createRow(
      databaseId: databaseId,
      tableId: collectionId,
      rowId: documentId,
      data: data,
      permissions: permissions,
    );
    return rowToMap(row);
  }

  Future<JsonMap> updateDocument({
    required String databaseId,
    required String collectionId,
    required String documentId,
    required JsonMap data,
    List<String>? permissions,
  }) async {
    final row = await tablesDB.updateRow(
      databaseId: databaseId,
      tableId: collectionId,
      rowId: documentId,
      data: data,
      permissions: permissions,
    );
    return rowToMap(row);
  }

  Future<dynamic> deleteDocument({
    required String databaseId,
    required String collectionId,
    required String documentId,
  }) =>
      tablesDB.deleteRow(
        databaseId: databaseId,
        tableId: collectionId,
        rowId: documentId,
      );
}

class StorageAdapter {
  StorageAdapter(this.storage);

  final Storage storage;

  Future<dynamic> updateFile({
    required String bucketId,
    required String fileId,
    String? name,
    List<String>? permissions,
  }) =>
      storage.updateFile(
        bucketId: bucketId,
        fileId: fileId,
        name: name,
        permissions: permissions,
      );

  Future<dynamic> getFile({
    required String bucketId,
    required String fileId,
  }) =>
      storage.getFile(bucketId: bucketId, fileId: fileId);
}

class TokensAdapter {
  TokensAdapter(this.tokens);

  final Tokens tokens;

  Future<dynamic> createFileToken({
    required String bucketId,
    required String fileId,
    String? expire,
  }) =>
      tokens.createFileToken(
        bucketId: bucketId,
        fileId: fileId,
        expire: expire,
      );
}

class MessagingAdapter {
  MessagingAdapter(this.messaging);

  final Messaging messaging;

  Future<dynamic> createPush({
    required String messageId,
    String? title,
    String? body,
    List<String>? users,
    JsonMap data = const {},
  }) =>
      messaging.createPush(
        messageId: messageId,
        title: title,
        body: body,
        users: users,
        data: data,
      );
}

class UsersAdapter {
  UsersAdapter(this.users);

  final Users users;

  Future<dynamic> delete({required String userId}) =>
      users.delete(userId: userId);
}

List<dynamic> readRows(dynamic response) {
  final rows = readDynamic<List<dynamic>>(response, 'rows');
  if (rows != null) return rows;
  final documents = readDynamic<List<dynamic>>(response, 'documents');
  return documents ?? const [];
}

JsonMap rowToMap(dynamic row) {
  if (row is Map<String, dynamic>) return row;
  if (row is Map) return row.cast<String, dynamic>();

  final data = readDynamic<Map<dynamic, dynamic>>(row, 'data');
  final map = data == null ? <String, dynamic>{} : data.cast<String, dynamic>();
  final id = readDynamic<Object>(row, r'$id');
  if (id != null) map[r'$id'] = id;
  final permissions = readDynamic<Object>(row, r'$permissions');
  if (permissions != null) map[r'$permissions'] = permissions;
  final createdAt = readDynamic<Object>(row, r'$createdAt');
  if (createdAt != null) map[r'$createdAt'] = createdAt;
  final updatedAt = readDynamic<Object>(row, r'$updatedAt');
  if (updatedAt != null) map[r'$updatedAt'] = updatedAt;
  return map;
}

T? readDynamic<T>(dynamic object, String field) {
  try {
    final value = switch (field) {
      'name' => object.name,
      'sizeOriginal' => object.sizeOriginal,
      'rows' => object.rows,
      'documents' => object.documents,
      'total' => object.total,
      'data' => object.data,
      r'$id' => object.$id,
      r'$permissions' => object.$permissions,
      r'$createdAt' => object.$createdAt,
      r'$updatedAt' => object.$updatedAt,
      _ => null,
    };
    if (value is T) return value;
    return null;
  } catch (_) {
    return null;
  }
}

int _intFrom(Object? value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString()) ?? fallback;
}
