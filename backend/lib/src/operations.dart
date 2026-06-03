import 'dart:io' show Platform;

import 'errors.dart';
import 'normalization.dart';
import 'rules.dart';

typedef Operation = Future<JsonMap> Function({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
});

Future<JsonMap> ensureProfile({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final profile = await repo.ensureProfile({
    'userId': actorId,
    'phone': payload['phone'],
    'displayName': payload['displayName'],
    'language': validLanguage(payload['language']),
    'theme': validTheme(payload['theme']),
  });

  return {'profile': asMap(profile)};
}

Future<JsonMap> updatePreferences({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final patch = <String, dynamic>{};
  if (payload.containsKey('language')) {
    patch['language'] = validLanguage(payload['language']);
  }
  if (payload.containsKey('theme')) {
    patch['theme'] = validTheme(payload['theme']);
  }
  if (payload.containsKey('displayName')) {
    patch['displayName'] = payload['displayName'].toString().trim();
  }

  final profile = await repo.updatePreferences(actorId, patch);
  return {'profile': asMap(profile)};
}

Future<JsonMap> getBootstrapData({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final profile = asMap(await repo.getProfile(actorId));
  final viewerShares = listOfMaps(await repo.listSharesForViewer(actorId));
  final ownerId = listOwnerForViewer(profile, viewerShares);
  final categories = listOfMaps(await repo.listCategories());
  final units = listOfMaps(await repo.listUnits());
  final products = listOfMaps(await repo.listProducts());
  final items = listOfMaps(await repo.listActiveItems(ownerId));
  final trash = listOfMaps(await repo.listTrashItems(ownerId));
  final shares = listOfMaps(await repo.listSharesForParticipant(actorId));

  return {
    'profile': profile,
    'visibleList': {
      'ownerId': ownerId,
      'isShared': ownerId != actorId,
      'items': sortListItems(items),
      'trash': sortTrashItems(trash),
    },
    'catalogs': {
      'categories': categories,
      'units': units,
      'products': products,
    },
    'sharing': sharingStatus(actorId, profile, shares),
  };
}

Future<JsonMap> searchProductsOperation({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final products = listOfMaps(await repo.listProducts());
  return {
    'suggestions': searchProducts(
      products,
      payload['query'],
      intFrom(payload['limit'], fallback: 20),
    ),
  };
}

Future<JsonMap> createItem({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerId = await visibleOwnerId(repo, actorId);
  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  assertCanMutateOwnerList(actorId, ownerId, ownerShares);

  final product = asMap(await repo.ensureProduct(payload['productName']));
  final productId = documentId(product);
  final activeItems = listOfMaps(await repo.listActiveItems(ownerId));
  assertNoDuplicateActiveItem(activeItems, ownerId, productId);

  final data = buildListItemDocument(payload, ownerId, actorId, productId);
  if ((data['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.validateImageFile(data['imageFileId']);
  }
  final item = asMap(await repo.createListItem(data, ownerShares));

  if ((data['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.updateImagePermissions(
        data['imageFileId'], ownerId, ownerShares);
  }

  return {'item': item};
}

Future<JsonMap> updateItem({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final item = asNullableMap(await repo.getListItem(payload['itemId']));
  if (item == null) throw notFound('List item');

  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(item['ownerId']));
  assertCanMutateOwnerList(actorId, item['ownerId'].toString(), ownerShares);

  final productId =
      await resolveProductId(repo, payload, item['productId'].toString());
  final activeItems = listOfMaps(await repo.listActiveItems(item['ownerId']));
  assertNoDuplicateActiveItem(
    activeItems,
    item['ownerId'].toString(),
    productId,
    documentId(item),
  );

  final patch = patchListItemDocument(item, payload, actorId, productId);
  if ((patch['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.validateImageFile(patch['imageFileId']);
  }
  final updated = asMap(
    await repo.updateListItem(documentId(item), patch, item['ownerId']),
  );

  if ((patch['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.updateImagePermissions(
        patch['imageFileId'], item['ownerId'], ownerShares);
  }

  return {'item': updated};
}

Future<JsonMap> trashItem({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final item = asNullableMap(await repo.getListItem(payload['itemId']));
  if (item == null) throw notFound('List item');

  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(item['ownerId']));
  assertCanMutateOwnerList(actorId, item['ownerId'].toString(), ownerShares);

  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      trashPatch(actorId, (payload['reason'] ?? 'scratch_timer').toString()),
      item['ownerId'],
    ),
  );

  return {'item': updated};
}

Future<JsonMap> restoreTrashItem({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final item = asNullableMap(await repo.getListItem(payload['itemId']));
  if (item == null) throw notFound('List item');

  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(item['ownerId']));
  assertCanMutateOwnerList(actorId, item['ownerId'].toString(), ownerShares);

  final activeItems = listOfMaps(await repo.listActiveItems(item['ownerId']));
  assertNoDuplicateActiveItem(
    activeItems,
    item['ownerId'].toString(),
    item['productId'].toString(),
    documentId(item),
  );

  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      restoreTrashPatch(actorId),
      item['ownerId'],
    ),
  );

  return {'item': updated};
}

Future<JsonMap> clearTrash({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerId = await visibleOwnerId(repo, actorId);
  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  assertCanMutateOwnerList(actorId, ownerId, ownerShares);

  final trash = listOfMaps(await repo.listTrashItems(ownerId));
  for (final item in trash) {
    await repo.deleteListItem(documentId(item));
  }

  return {'deletedCount': trash.length};
}

Future<JsonMap> requestShare({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerProfile = asMap(await repo.getProfile(actorId));
  final viewerProfile =
      asNullableMap(await repo.findProfileByPhone(payload['phone']));
  final viewerId = viewerProfile == null
      ? null
      : (viewerProfile['userId'] ?? documentId(viewerProfile)).toString();
  final existingShares = viewerId == null
      ? listOfMaps(await repo.listSharesForOwner(actorId))
      : [
          ...listOfMaps(await repo.listSharesForViewer(viewerId)),
          ...listOfMaps(await repo.listSharesForOwner(actorId)),
        ];

  assertShareCanBeRequested(
    ownerId: actorId,
    viewerId: viewerId,
    viewerProfile: viewerProfile,
    existingShares: existingShares,
  );

  final existing = asNullableMap(await repo.findShare(actorId, viewerId));
  final data = buildShareDocument(actorId, viewerId!);
  final share = existing != null
      ? asMap(
          await repo.updateShare(
            documentId(existing),
            {...data, 'createdAt': existing['createdAt']},
          ),
        )
      : asMap(await repo.createShare(data));

  return {
    'owner': ownerProfile,
    'viewer': viewerProfile,
    'share': share,
  };
}

Future<JsonMap> respondShare({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final share = asNullableMap(await repo.getShare(payload['shareId']));
  if (share == null) throw notFound('Share');

  final accepted = payload['accepted'] == true;
  if (accepted) {
    final profile = asMap(await repo.getProfile(actorId));
    final viewerShares = listOfMaps(await repo.listSharesForViewer(actorId));
    final acceptedOther = viewerShares.where((item) {
      return item['status'] == 'accepted' &&
          item['ownerId'] != share['ownerId'] &&
          documentId(item) != documentId(share);
    }).firstOrNull;
    if ((profile['activeReceivedOwnerId'] ?? '').toString().isNotEmpty ||
        acceptedOther != null) {
      throw MoonaError(
        ErrorCodes.viewerAlreadyReceiving,
        'The viewer is already receiving another shared owner list.',
        status: 409,
      );
    }
  }

  final updatedShare = asMap(
    await repo.updateShare(
      documentId(share),
      respondSharePatch(share, actorId, accepted),
    ),
  );

  if (accepted) {
    await repo.setActiveReceivedOwner(actorId, share['ownerId']);
    await repo.refreshOwnerPermissions(share['ownerId']);
  }

  return {'share': updatedShare};
}

Future<JsonMap> unlinkShare({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final share = await shareFromPayload(repo, actorId, payload);
  if (share == null) throw notFound('Share');

  final patch = revokeSharePatch(share, actorId);
  final updatedShare = patch == null
      ? share
      : asMap(await repo.updateShare(documentId(share), patch));

  final viewerProfile = asMap(await repo.getProfile(share['viewerId']));
  if (viewerProfile['activeReceivedOwnerId'] == share['ownerId']) {
    await repo.setActiveReceivedOwner(share['viewerId'], '');
  }
  await repo.refreshOwnerPermissions(share['ownerId']);

  return {'share': updatedShare};
}

Future<JsonMap> getSharingStatus({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final profile = asMap(await repo.getProfile(actorId));
  final shares = listOfMaps(await repo.listSharesForParticipant(actorId));
  return {'sharing': sharingStatus(actorId, profile, shares)};
}

Future<JsonMap> adminList({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  return {'items': listOfMaps(await repo.adminList(payload['kind']))};
}

Future<JsonMap> adminCreate({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  return {
    'item': asMap(
      await repo.adminCreate(
        payload['kind'],
        payload['data'] ?? <String, dynamic>{},
      ),
    ),
  };
}

Future<JsonMap> adminUpdate({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  return {
    'item': asMap(
      await repo.adminUpdate(
        payload['kind'],
        payload['id'],
        payload['data'] ?? <String, dynamic>{},
      ),
    ),
  };
}

Future<JsonMap> adminDelete({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  if (payload['kind'] == 'users') {
    final shares =
        listOfMaps(await repo.listSharesForParticipant(payload['id']));
    final now = nowIso();
    for (final share in shares.where((share) => share['status'] != 'revoked')) {
      await repo.updateShare(documentId(share), {
        'status': 'revoked',
        'revokedAt': now,
        'updatedAt': now,
      });
    }
  }

  return {'result': await repo.adminDelete(payload['kind'], payload['id'])};
}

Future<JsonMap> adminMergeSuggestions({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  final products = listOfMaps(await repo.listProducts(activeOnly: false));
  return {
    'suggestions': suggestProductMerges(
      products,
      intFrom(payload['limit'], fallback: 25),
    ),
  };
}

Future<JsonMap> adminMergeProducts({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  assertAdmin(actorId);
  return {
    'result': await repo.mergeProducts(
      payload['sourceProductId'],
      payload['targetProductId'],
    ),
  };
}

final operations = <String, Operation>{
  'ensureProfile': ensureProfile,
  'updatePreferences': updatePreferences,
  'getBootstrapData': getBootstrapData,
  'searchProducts': searchProductsOperation,
  'createItem': createItem,
  'updateItem': updateItem,
  'trashItem': trashItem,
  'restoreTrashItem': restoreTrashItem,
  'clearTrash': clearTrash,
  'requestShare': requestShare,
  'respondShare': respondShare,
  'unlinkShare': unlinkShare,
  'getSharingStatus': getSharingStatus,
  'adminList': adminList,
  'adminCreate': adminCreate,
  'adminUpdate': adminUpdate,
  'adminDelete': adminDelete,
  'adminMergeSuggestions': adminMergeSuggestions,
  'adminMergeProducts': adminMergeProducts,
};

Future<String> visibleOwnerId(dynamic repo, String actorId) async {
  final profile = asMap(await repo.getProfile(actorId));
  final shares = listOfMaps(await repo.listSharesForViewer(actorId));
  return listOwnerForViewer(profile, shares);
}

Future<String> resolveProductId(
  dynamic repo,
  JsonMap payload,
  String fallbackProductId,
) async {
  if ((payload['productName'] ?? '').toString().isNotEmpty) {
    final product = asMap(await repo.ensureProduct(payload['productName']));
    return documentId(product);
  }
  if ((payload['productId'] ?? '').toString().isNotEmpty) {
    await repo.getProduct(payload['productId']);
    return payload['productId'].toString();
  }
  return fallbackProductId;
}

Future<JsonMap?> shareFromPayload(
  dynamic repo,
  String actorId,
  JsonMap payload,
) async {
  if ((payload['shareId'] ?? '').toString().isNotEmpty) {
    return asNullableMap(await repo.getShare(payload['shareId']));
  }
  if ((payload['viewerId'] ?? '').toString().isNotEmpty) {
    return asNullableMap(await repo.findShare(actorId, payload['viewerId']));
  }
  if ((payload['ownerId'] ?? '').toString().isNotEmpty) {
    return asNullableMap(await repo.findShare(payload['ownerId'], actorId));
  }
  throw MoonaError(
    ErrorCodes.invalidInput,
    'shareId, viewerId, or ownerId is required.',
  );
}

JsonMap sharingStatus(
  String actorId,
  JsonMap profile,
  List<JsonMap> shares,
) =>
    {
      'activeReceivedOwnerId': profile['activeReceivedOwnerId'] ?? '',
      'outgoing': shares.where((share) => share['ownerId'] == actorId).toList(),
      'incoming':
          shares.where((share) => share['viewerId'] == actorId).toList(),
    };

void requireActor(String actorId) {
  if (actorId.isEmpty) throw unauthorized();
}

String? validLanguage(Object? language) {
  if (language == null || language == '') return null;
  final value = language.toString();
  if (!['ar', 'en'].contains(value)) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'language must be either ar or en.',
    );
  }
  return value;
}

String? validTheme(Object? theme) {
  if (theme == null || theme == '') return null;
  final value = theme.toString();
  if (!['light', 'dark'].contains(value)) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'theme must be either light or dark.',
    );
  }
  return value;
}

void assertAdmin(String actorId) {
  requireActor(actorId);
  final ids = (Platform.environment['MOONA_ADMIN_USER_IDS'] ?? '')
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (!ids.contains(actorId)) throw adminOnly();
}

JsonMap asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}

JsonMap? asNullableMap(Object? value) {
  if (value == null) return null;
  return asMap(value);
}

List<JsonMap> listOfMaps(Object? value) {
  if (value is Iterable) {
    return value.map(asMap).toList();
  }
  return const [];
}

int intFrom(Object? value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString()) ?? fallback;
}
