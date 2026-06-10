import 'dart:io' show Platform;

import 'errors.dart';
import 'ids.dart';
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
  await finalizeExpiredScratchesForOwner(repo, ownerId);
  final categories = listOfMaps(await repo.listCategories());
  final units = listOfMaps(await repo.listUnits());
  final products = listOfMaps(await repo.listProducts());
  final items = listOfMaps(await repo.listActiveItems(ownerId));
  final trash = listOfMaps(await repo.listTrashItems(ownerId));
  final shares = listOfMaps(await repo.listSharesForParticipant(actorId));
  final presence = listOfMaps(await repo.listShoppingPresence(ownerId));
  final profiles = await profileLookup(repo, [
    actorId,
    ownerId,
    ...shareParticipantIds(shares),
    ...presence.map((item) => item['actorId']),
    ...items.expand(
      (item) => [
        item['createdByUserId'],
        item['updatedByUserId'],
        item['scratchedByUserId'],
      ],
    ),
    ...trash.map((item) => item['trashedByUserId']),
    ...trash.expand(
      (item) => [
        item['createdByUserId'],
        item['updatedByUserId'],
        item['scratchedByUserId'],
      ],
    ),
  ]);
  final enrichedShares = shares
      .map((share) => withCounterpartyProfile(actorId, share, profiles))
      .toList();
  final enrichedItems =
      items.map((item) => withActorDisplayNames(item, profiles)).toList();
  final enrichedTrash = trash
      .map((item) => withActorDisplayNames(item, profiles))
      .map((item) => withTrashActorDisplayName(item, profiles))
      .toList();
  final enrichedPresence = presence
      .map((item) => withPresenceActorDisplayName(item, profiles))
      .toList();
  final suggestions = await purchaseSuggestionsForOwner(
    repo,
    ownerId,
    activeItems: items,
    limit: 6,
  );

  return {
    'profile': profile,
    'visibleList': {
      'ownerId': ownerId,
      'isShared': ownerId != actorId,
      'items': sortListItems(enrichedItems),
      'trash': sortTrashItems(enrichedTrash),
    },
    'catalogs': {
      'categories': categories,
      'units': units,
      'products': products,
    },
    'sharing': sharingStatus(actorId, profile, enrichedShares),
    'profiles': profiles,
    'shoppingPresence': enrichedPresence,
    'suggestions': {'items': suggestions},
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

Future<JsonMap> lookupContacts({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final rawPhones = contactLookupPhones(payload);
  final limit = intFrom(payload['limit'], fallback: 250).clamp(1, 500).toInt();

  final normalized = <JsonMap>[];
  final invalid = <JsonMap>[];
  final seenDigits = <String>{};
  for (final raw in rawPhones.take(limit)) {
    final value = (raw ?? '').toString();
    try {
      final phone = normalizePhone(value);
      final digits = phone['digits'].toString();
      if (!seenDigits.add(digits)) continue;
      normalized.add({
        'phone': phone['e164'],
        'phoneDigits': digits,
      });
    } on MoonaError catch (error) {
      invalid.add({
        'phone': value,
        'code': error.code,
        'message': error.message,
      });
    }
  }

  final profiles = listOfMaps(
    await repo.listProfilesByPhoneDigits(
      normalized.expand((entry) {
        return phoneDigitLookupVariants(entry['phoneDigits']);
      }),
    ),
  );
  final profilesByDigits = {
    for (final profile in profiles)
      if (profileLookupDigits(profile) != null)
        profileLookupDigits(profile)!: profile,
  };

  final contacts = normalized.map((entry) {
    final digits = entry['phoneDigits'].toString();
    final profile = asNullableMap(profilesByDigits[digits]);
    return contactLookupResult(actorId, entry, profile);
  }).toList();
  final registered =
      contacts.where((entry) => entry['registered'] == true).toList();
  final unregistered =
      contacts.where((entry) => entry['registered'] != true).toList();

  return {
    'contacts': [...registered, ...unregistered],
    'registered': registered,
    'unregistered': unregistered,
    'invalid': invalid,
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

  await appendListEvent(
    repo,
    ownerId: ownerId,
    actorId: actorId,
    type: 'added',
    item: item,
    product: product,
    ownerShares: ownerShares,
  );
  await sendListMutationPush(
    repo,
    ownerId: ownerId,
    actorId: actorId,
    type: 'item_added',
    item: item,
    product: product,
    ownerShares: ownerShares,
  );

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

  final eventProduct = await productForEvent(repo, productId);
  await appendListEvent(
    repo,
    ownerId: item['ownerId'].toString(),
    actorId: actorId,
    type: 'edited',
    item: updated,
    product: eventProduct,
    ownerShares: ownerShares,
  );
  await sendListMutationPush(
    repo,
    ownerId: item['ownerId'].toString(),
    actorId: actorId,
    type: 'item_edited',
    item: updated,
    product: eventProduct,
    ownerShares: ownerShares,
  );

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

  final reason = (payload['reason'] ?? 'scratch_timer').toString();
  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      trashPatch(actorId, reason),
      item['ownerId'],
    ),
  );

  await appendListEvent(
    repo,
    ownerId: item['ownerId'].toString(),
    actorId: actorId,
    type: reason == 'scratch_timer' ? 'scratched' : 'deleted',
    item: updated,
    product: await productForEvent(repo, item['productId']),
    ownerShares: ownerShares,
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

  await appendListEvent(
    repo,
    ownerId: item['ownerId'].toString(),
    actorId: actorId,
    type: 'restored',
    item: updated,
    product: await productForEvent(repo, item['productId']),
    ownerShares: ownerShares,
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

  await appendListEvent(
    repo,
    ownerId: ownerId,
    actorId: actorId,
    type: 'cleared',
    clearedCount: trash.length,
    ownerShares: ownerShares,
  );

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

  await sendPushSafely(
    repo,
    userIds: [viewerId],
    title: 'Moona',
    body:
        '${displayNameFromProfile(ownerProfile, 'Someone')} shared a list with you.',
    data: {
      'type': 'share_requested',
      'ownerId': actorId,
      'shareId': documentId(share),
    },
  );

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
  JsonMap? viewerProfile;
  if (accepted) {
    viewerProfile = asMap(await repo.getProfile(actorId));
    final viewerShares = listOfMaps(await repo.listSharesForViewer(actorId));
    final acceptedOther = viewerShares.where((item) {
      return item['status'] == 'accepted' &&
          item['ownerId'] != share['ownerId'] &&
          documentId(item) != documentId(share);
    }).firstOrNull;
    if ((viewerProfile['activeReceivedOwnerId'] ?? '').toString().isNotEmpty ||
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
    await appendListEvent(
      repo,
      ownerId: share['ownerId'].toString(),
      actorId: actorId,
      type: 'share_accepted',
      ownerShares: listOfMaps(
        await repo.listAcceptedSharesForOwner(share['ownerId']),
      ),
    );
    await sendPushSafely(
      repo,
      userIds: [share['ownerId'].toString()],
      title: 'Moona',
      body:
          '${displayNameFromProfile(viewerProfile, 'Someone')} accepted your shared list.',
      data: {
        'type': 'share_accepted',
        'ownerId': share['ownerId'].toString(),
        'viewerId': actorId,
        'shareId': documentId(updatedShare),
      },
    );
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
  await appendListEvent(
    repo,
    ownerId: share['ownerId'].toString(),
    actorId: actorId,
    type: 'share_revoked',
    ownerShares: listOfMaps(
      await repo.listAcceptedSharesForOwner(share['ownerId']),
    ),
  );

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
  final profiles = await profileLookup(repo, [
    actorId,
    ...shareParticipantIds(shares),
  ]);
  final enrichedShares = shares
      .map((share) => withCounterpartyProfile(actorId, share, profiles))
      .toList();
  return {
    'sharing': sharingStatus(actorId, profile, enrichedShares),
    'profiles': profiles,
  };
}

Future<JsonMap> createImageViewToken({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final itemId = (payload['itemId'] ?? '').toString();
  final fileId = (payload['fileId'] ?? '').toString();
  if (itemId.isEmpty || fileId.isEmpty) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'itemId and fileId are required.',
    );
  }

  final item = asNullableMap(await repo.getListItem(itemId));
  if (item == null) throw notFound('List item');
  if ((item['imageFileId'] ?? '').toString() != fileId) {
    throw notFound('Image file');
  }

  final ownerId = (item['ownerId'] ?? '').toString();
  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  assertCanReadOwnerList(actorId, ownerId, ownerShares);
  await repo.validateImageFile(fileId);

  final ttlSeconds =
      intFrom(payload['ttlSeconds'], fallback: 900).clamp(60, 3600).toInt();
  final expire = DateTime.now()
      .toUtc()
      .add(Duration(seconds: ttlSeconds))
      .toIso8601String();
  final token = asMap(
    await repo.createImageViewToken(fileId, expire: expire),
  );
  final secret = (token['secret'] ?? '').toString();
  if (secret.isEmpty) {
    throw MoonaError(
      ErrorCodes.invalidImage,
      'Could not create an image access token.',
      status: 500,
      details: {'fileId': fileId},
    );
  }

  return {
    'bucketId': imageBucketId,
    'fileId': fileId,
    'tokenId': token[r'$id'] ?? token['id'] ?? '',
    'token': secret,
    'expire': token['expire'] ?? expire,
    'ttlSeconds': ttlSeconds,
  };
}

Future<JsonMap> getActivity({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerId = await visibleOwnerId(repo, actorId);
  await finalizeExpiredScratchesForOwner(repo, ownerId);
  final limit = intFrom(payload['limit'], fallback: 50).clamp(1, 100).toInt();
  final cursor = (payload['cursor'] ?? '').toString();
  final events = listOfMaps(
    await repo.listEvents(
      ownerId,
      limit: limit,
      cursor: cursor.isEmpty ? null : cursor,
    ),
  );
  final profiles = await profileLookup(repo, events.map((e) => e['actorId']));
  final enriched = events
      .map((event) => withEventActorDisplayName(event, profiles))
      .toList();
  final nextCursor = events.length < limit ? '' : documentId(events.last);
  return {'events': enriched, 'nextCursor': nextCursor, 'profiles': profiles};
}

Future<JsonMap> suggestItemsOperation({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerId = await visibleOwnerId(repo, actorId);
  await finalizeExpiredScratchesForOwner(repo, ownerId);
  final activeItems = listOfMaps(await repo.listActiveItems(ownerId));
  final limit = intFrom(payload['limit'], fallback: 20).clamp(1, 50).toInt();
  return {
    'suggestions': await purchaseSuggestionsForOwner(
      repo,
      ownerId,
      activeItems: activeItems,
      limit: limit,
    ),
  };
}

Future<JsonMap> getInsights({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final ownerId = await visibleOwnerId(repo, actorId);
  await finalizeExpiredScratchesForOwner(repo, ownerId);
  final rangeDays =
      intFrom(payload['rangeDays'], fallback: 90).clamp(7, 365).toInt();
  final since = DateTime.now().toUtc().subtract(Duration(days: rangeDays));
  final events = listOfMaps(
    await repo.listEvents(
      ownerId,
      limit: 1000,
      types: const ['scratched'],
      since: since,
    ),
  );
  return {'insights': buildInsights(events: events, rangeDays: rangeDays)};
}

Future<JsonMap> scratchItem({
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

  if (isScratchExpired(item)) {
    return {
      'item': await finalizeScratchDocument(
        repo,
        item,
        fallbackActorId: actorId,
        ownerShares: ownerShares,
      ),
    };
  }

  final windowSeconds =
      intFrom(payload['windowSeconds'], fallback: 10).clamp(3, 120).toInt();
  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      scratchPatch(actorId, windowSeconds: windowSeconds),
      item['ownerId'],
    ),
  );

  return {'item': updated};
}

Future<JsonMap> undoScratchItem({
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

  if (isScratchExpired(item)) {
    return {
      'item': await finalizeScratchDocument(
        repo,
        item,
        fallbackActorId: actorId,
        ownerShares: ownerShares,
      ),
    };
  }
  if (!hasScratch(item)) return {'item': item};

  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      undoScratchPatch(actorId),
      item['ownerId'],
    ),
  );
  return {'item': updated};
}

Future<JsonMap> finalizeScratch({
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

  return {
    'item': await finalizeScratchDocument(
      repo,
      item,
      fallbackActorId: actorId,
      ownerShares: ownerShares,
      force: payload['force'] == true,
    ),
  };
}

Future<JsonMap> setShoppingPresence({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final active = payload['active'] == true;
  if (!active) {
    await repo.deleteShoppingPresence(actorId);
    return {'presence': null};
  }

  final ownerId = await visibleOwnerId(repo, actorId);
  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  assertCanReadOwnerList(actorId, ownerId, ownerShares);
  final currentPresence = listOfMaps(await repo.listShoppingPresence(ownerId));
  final previousPresence = currentPresence.where((item) {
    return item['actorId'] == actorId;
  }).firstOrNull;
  final now = DateTime.now().toUtc();
  final nowString = now.toIso8601String();
  final notifyStart = shouldNotifyShoppingStart(previousPresence, now);
  final presence = asMap(
    await repo.upsertShoppingPresence(
      actorId,
      {
        'ownerId': ownerId,
        'actorId': actorId,
        'activeAt': notifyStart
            ? nowString
            : previousPresence?['activeAt'] ?? nowString,
        'updatedAt': nowString,
      },
      ownerShares,
    ),
  );
  final profiles = await profileLookup(repo, [actorId]);
  if (notifyStart) {
    await sendPushSafely(
      repo,
      userIds: otherListParticipantIds(
        ownerId: ownerId,
        actorId: actorId,
        ownerShares: ownerShares,
      ),
      title: 'Moona',
      body:
          '${displayNameFromProfile(profiles[actorId], 'Someone')} is shopping now.',
      data: {
        'type': 'shopping_started',
        'ownerId': ownerId,
        'actorId': actorId,
      },
    );
  }
  return {
    'presence': withPresenceActorDisplayName(presence, profiles),
    'profiles': profiles,
  };
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
  'lookupContacts': lookupContacts,
  'createItem': createItem,
  'updateItem': updateItem,
  'trashItem': trashItem,
  'restoreTrashItem': restoreTrashItem,
  'clearTrash': clearTrash,
  'requestShare': requestShare,
  'respondShare': respondShare,
  'unlinkShare': unlinkShare,
  'getSharingStatus': getSharingStatus,
  'createImageViewToken': createImageViewToken,
  'getActivity': getActivity,
  'suggestItems': suggestItemsOperation,
  'getInsights': getInsights,
  'scratchItem': scratchItem,
  'undoScratchItem': undoScratchItem,
  'finalizeScratch': finalizeScratch,
  'setShoppingPresence': setShoppingPresence,
  'adminList': adminList,
  'adminCreate': adminCreate,
  'adminUpdate': adminUpdate,
  'adminDelete': adminDelete,
  'adminMergeSuggestions': adminMergeSuggestions,
  'adminMergeProducts': adminMergeProducts,
};

Future<void> finalizeExpiredScratchesForOwner(
  dynamic repo,
  String ownerId,
) async {
  final activeItems = listOfMaps(await repo.listActiveItems(ownerId));
  final ownerShares =
      listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  for (final item in activeItems) {
    if (!isScratchExpired(item)) continue;
    await finalizeScratchDocument(
      repo,
      item,
      fallbackActorId: (item['updatedByUserId'] ?? ownerId).toString(),
      ownerShares: ownerShares,
    );
  }
}

Future<JsonMap> finalizeScratchDocument(
  dynamic repo,
  JsonMap item, {
  required String fallbackActorId,
  List<JsonMap>? ownerShares,
  bool force = false,
}) async {
  if (!force && !isScratchExpired(item)) return item;
  if (!hasScratch(item)) return item;
  if ((item['status'] ?? '').toString() == 'trash') return item;

  final ownerId = (item['ownerId'] ?? '').toString();
  final shares =
      ownerShares ?? listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
  final actorId = scratchActorId(item, fallbackActorId);
  final updated = asMap(
    await repo.updateListItem(
      documentId(item),
      trashPatch(actorId, 'scratch_timer'),
      ownerId,
    ),
  );
  await appendListEvent(
    repo,
    ownerId: ownerId,
    actorId: actorId,
    type: 'scratched',
    item: updated,
    product: await productForEvent(repo, item['productId']),
    ownerShares: shares,
  );
  return updated;
}

Future<void> appendListEvent(
  dynamic repo, {
  required String ownerId,
  required String actorId,
  required String type,
  JsonMap? item,
  JsonMap? product,
  int? clearedCount,
  List<JsonMap>? ownerShares,
}) async {
  try {
    final shares = ownerShares ??
        listOfMaps(await repo.listAcceptedSharesForOwner(ownerId));
    await repo.createListEvent(
      buildListEventDocument(
        ownerId: ownerId,
        actorId: actorId,
        type: type,
        item: item,
        product: product,
        clearedCount: clearedCount,
      ),
      shares,
    );
  } catch (_) {
    // Activity is durable metadata, but user-facing mutations should not roll
    // back if an event append fails.
  }
}

Future<void> sendListMutationPush(
  dynamic repo, {
  required String ownerId,
  required String actorId,
  required String type,
  required JsonMap item,
  required JsonMap? product,
  required List<JsonMap> ownerShares,
}) async {
  final recipients = otherListParticipantIds(
    ownerId: ownerId,
    actorId: actorId,
    ownerShares: ownerShares,
  );
  if (recipients.isEmpty) return;

  final actorName = await displayNameForPush(repo, actorId);
  final productName = productNameForPush(product, item);
  final verb = type == 'item_added' ? 'added' : 'updated';
  await sendPushSafely(
    repo,
    userIds: recipients,
    title: 'Moona',
    body: '$actorName $verb $productName.',
    data: {
      'type': type,
      'ownerId': ownerId,
      'actorId': actorId,
      'itemId': documentId(item),
      'productId':
          (item['productId'] ?? product?['id'] ?? product?[r'$id']).toString(),
    },
  );
}

Future<void> sendPushSafely(
  dynamic repo, {
  required List<String> userIds,
  String? title,
  String? body,
  JsonMap data = const {},
}) async {
  final recipients =
      userIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  if (recipients.isEmpty) return;
  try {
    await repo.sendPush(
      userIds: recipients.toList(),
      title: title,
      body: body,
      data: data,
    );
  } catch (_) {
    // Push is a side effect layered on top of the mutation; it should not make
    // the user's write fail if Messaging is disabled or temporarily unavailable.
  }
}

List<String> otherListParticipantIds({
  required String ownerId,
  required String actorId,
  required List<JsonMap> ownerShares,
}) {
  final recipients = <String>{};
  if (ownerId != actorId) recipients.add(ownerId);
  recipients.addAll(
    acceptedViewerIdsForOwner(ownerId, ownerShares).where(
      (viewerId) => viewerId != actorId,
    ),
  );
  return recipients.toList();
}

Future<String> displayNameForPush(dynamic repo, String userId) async {
  try {
    return displayNameFromProfile(await repo.getProfile(userId), 'Someone');
  } catch (_) {
    return 'Someone';
  }
}

String displayNameFromProfile(Object? profile, String fallback) {
  if (profile is Map) {
    final displayName = (profile['displayName'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
  }
  return fallback;
}

String productNameForPush(JsonMap? product, JsonMap item) {
  final value = (product?['displayName'] ??
          product?['nameEn'] ??
          product?['nameAr'] ??
          item['productName'] ??
          '')
      .toString()
      .trim();
  return value.isEmpty ? 'an item' : value;
}

bool shouldNotifyShoppingStart(JsonMap? previousPresence, DateTime now) {
  if (previousPresence == null) return true;
  final updatedAt = DateTime.tryParse(
    (previousPresence['updatedAt'] ?? previousPresence['activeAt'] ?? '')
        .toString(),
  );
  if (updatedAt == null) return true;
  return now.difference(updatedAt.toUtc()).inSeconds > 60;
}

Future<JsonMap?> productForEvent(dynamic repo, Object? productId) async {
  final value = (productId ?? '').toString();
  if (value.isEmpty) return null;
  try {
    return asNullableMap(await repo.getProduct(value));
  } catch (_) {
    return null;
  }
}

Future<List<JsonMap>> purchaseSuggestionsForOwner(
  dynamic repo,
  String ownerId, {
  required List<JsonMap> activeItems,
  required int limit,
}) async {
  try {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 365));
    final events = listOfMaps(
      await repo.listEvents(
        ownerId,
        limit: 1000,
        types: const ['scratched'],
        since: since,
      ),
    );
    return suggestPurchaseItems(
      events: events,
      activeProductIds: activeItems
          .map((item) => (item['productId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet(),
      limit: limit,
    );
  } catch (_) {
    return const [];
  }
}

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

Iterable<String> shareParticipantIds(List<JsonMap> shares) sync* {
  for (final share in shares) {
    final ownerId = (share['ownerId'] ?? '').toString();
    final viewerId = (share['viewerId'] ?? '').toString();
    if (ownerId.isNotEmpty) yield ownerId;
    if (viewerId.isNotEmpty) yield viewerId;
  }
}

Future<JsonMap> profileLookup(dynamic repo, Iterable<Object?> ids) async {
  final lookup = <String, dynamic>{};
  final uniqueIds = ids
      .map((id) => (id ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();

  for (final id in uniqueIds) {
    try {
      final profile = asNullableMap(await repo.getProfile(id));
      if (profile == null || profile.isEmpty) continue;
      lookup[id] = profileSummary(id, profile);
    } catch (_) {
      // Missing profile rows should not break bootstrap/sharing responses.
    }
  }

  return lookup;
}

JsonMap profileSummary(String userId, JsonMap profile) => {
      'userId': (profile['userId'] ?? userId).toString(),
      'displayName': (profile['displayName'] ?? '').toString(),
      'phone': (profile['phone'] ?? '').toString(),
      'phoneDigits': profileLookupDigits(profile) ?? '',
    };

String? profileLookupDigits(JsonMap profile) {
  for (final value in [profile['phoneDigits'], profile['phone']]) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) continue;
    try {
      return normalizePhone(raw)['digits'].toString();
    } catch (_) {
      // Try the next stored representation.
    }
  }
  return null;
}

JsonMap withCounterpartyProfile(
  String actorId,
  JsonMap share,
  JsonMap profiles,
) {
  final counterpartyId = share['ownerId'] == actorId
      ? (share['viewerId'] ?? '').toString()
      : (share['ownerId'] ?? '').toString();
  final profile = asNullableMap(profiles[counterpartyId]);
  if (profile == null) return share;

  return {
    ...share,
    'counterpartyId': counterpartyId,
    'counterpartyName': profile['displayName'] ?? '',
    'counterpartyPhone': profile['phone'] ?? '',
  };
}

JsonMap withTrashActorDisplayName(JsonMap item, JsonMap profiles) {
  final userId = (item['trashedByUserId'] ?? '').toString();
  if (userId.isEmpty) return item;
  final profile = asNullableMap(profiles[userId]);
  final displayName = (profile?['displayName'] ?? '').toString();
  if (displayName.isEmpty) return item;

  return {
    ...item,
    'trashedByDisplayName': displayName,
  };
}

List<Object?> contactLookupPhones(JsonMap payload) {
  final values = <Object?>[];
  final phones = payload['phones'];
  if (phones is Iterable) values.addAll(phones);

  final contacts = payload['contacts'];
  if (contacts is Iterable) {
    for (final contact in contacts) {
      if (contact is Map) {
        final map = contact.cast<String, dynamic>();
        final phone = map['phone'] ?? map['number'] ?? map['value'];
        if (phone != null) values.add(phone);
        final nestedPhones = map['phones'];
        if (nestedPhones is Iterable) {
          for (final nested in nestedPhones) {
            if (nested is Map) {
              final nestedMap = nested.cast<String, dynamic>();
              values.add(
                nestedMap['phone'] ?? nestedMap['number'] ?? nestedMap['value'],
              );
            } else {
              values.add(nested);
            }
          }
        }
      } else {
        values.add(contact);
      }
    }
  }

  return values;
}

JsonMap contactLookupResult(
  String actorId,
  JsonMap normalized,
  JsonMap? profile,
) {
  final base = {
    'phone': normalized['phone'],
    'phoneDigits': normalized['phoneDigits'],
  };
  if (profile == null) {
    return {...base, 'registered': false};
  }

  final userId = (profile['userId'] ?? documentId(profile)).toString();
  if (userId.isEmpty) {
    return {...base, 'registered': false};
  }

  return {
    ...base,
    'registered': true,
    'userId': userId,
    'displayName': (profile['displayName'] ?? '').toString(),
    'isSelf': userId == actorId,
  };
}

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
