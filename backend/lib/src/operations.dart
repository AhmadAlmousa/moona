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
  if (payload.containsKey('activeReceivedListId')) {
    patch['activeReceivedListId'] =
        (payload['activeReceivedListId'] ?? '').toString();
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

  // Resolve the active list for the visible owner.
  // For shared lists, the listId comes from the active accepted share.
  // For own lists, the listId comes from the payload (client tracks it).
  final String? listId;
  if (ownerId != actorId) {
    final activeOwnerId = (profile['activeReceivedOwnerId'] ?? '').toString();
    final activeShare = viewerShares.where((s) =>
        s['ownerId'] == activeOwnerId &&
        s['viewerId'] == actorId &&
        s['status'] == 'accepted').firstOrNull;
    final rawListId = (activeShare?['listId'] ??
            profile['activeReceivedListId'] ??
            '')
        .toString();
    listId = rawListId.isEmpty ? null : rawListId;
  } else {
    final rawListId = (payload['listId'] ?? '').toString();
    listId = rawListId.isEmpty ? null : rawListId;
  }

  await finalizeExpiredScratchesForOwner(repo, ownerId, listId: listId);
  final categories = listOfMaps(await repo.listCategories());
  final units = listOfMaps(await repo.listUnits());
  final products = listOfMaps(await repo.listProducts());
  final brands = listOfMaps(await repo.listCatalogTerms('brands'));
  final stores = listOfMaps(await repo.listCatalogTerms('stores'));

  // Load all of the owner's lists so the client can populate the list picker.
  // For shared views, return only the shared list for display.
  final allLists = ownerId == actorId
      ? listOfMaps(await repo.listUserLists(ownerId))
      : <JsonMap>[];
  // Ensure a default list exists for owners without one yet.
  final resolvedListId =
      await ensureDefaultListId(repo, ownerId, actorId, listId, allLists);

  final items =
      listOfMaps(await repo.listActiveItems(ownerId, listId: resolvedListId));
  // De-dup trash for display: hide rows whose product is active again and
  // collapse same-product duplicates (keep newest). Pure — mutation paths
  // hard-delete the rest, so legacy/dirty data tidies up automatically.
  final trash = dedupeTrashForDisplay(
    listOfMaps(await repo.listTrashItems(ownerId, listId: resolvedListId)),
    items,
  );
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

  // Enrich each list with the shared-list name when applicable.
  final enrichedLists = ownerId == actorId
      ? allLists
      : await _sharedListForBootstrap(repo, ownerId, resolvedListId);

  return {
    'profile': profile,
    'visibleList': {
      'ownerId': ownerId,
      'listId': resolvedListId ?? '',
      'isShared': ownerId != actorId,
      'items': sortListItems(enrichedItems),
      'trash': sortTrashItems(enrichedTrash),
    },
    'lists': enrichedLists,
    'catalogs': {
      'categories': categories,
      'units': units,
      'products': products,
      'brands': brands,
      'stores': stores,
    },
    'sharing': sharingStatus(actorId, profile, enrichedShares),
    'profiles': profiles,
    'shoppingPresence': enrichedPresence,
    'suggestions': {'items': suggestions},
  };
}

Future<String?> ensureDefaultListId(
  dynamic repo,
  String ownerId,
  String actorId,
  String? requestedListId,
  List<JsonMap> allLists,
) async {
  // Viewers don't own lists; use the resolved listId directly.
  if (ownerId != actorId) return requestedListId;

  if (allLists.isEmpty) {
    // First-time owner: create a default list.
    final list = asMap(await repo.createUserList(
      buildUserListDocument(
          ownerId: ownerId, name: 'My List', isDefault: true),
      ownerId,
    ));
    return documentId(list);
  }

  // If a specific list was requested, validate it belongs to the owner.
  if ((requestedListId ?? '').isNotEmpty) {
    final owned = allLists.any((l) => documentId(l) == requestedListId);
    return owned ? requestedListId : documentId(allLists.first);
  }

  // Default to the list marked isDefault, or the first list.
  final defaultList = allLists
      .where((l) => l['isDefault'] == true)
      .firstOrNull ?? allLists.first;
  return documentId(defaultList);
}

Future<List<JsonMap>> _sharedListForBootstrap(
  dynamic repo,
  String ownerId,
  String? listId,
) async {
  if ((listId ?? '').isEmpty) return [];
  try {
    final list = asNullableMap(await repo.getUserList(listId));
    return list == null ? [] : [list];
  } catch (_) {
    return [];
  }
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
  // Caller's own country code (digits) so a local number like `0567…` resolves
  // to the same digits they registered with. Defaults to Saudi (`966`).
  final ccRaw = (payload['defaultCountryCode'] ?? '')
      .toString()
      .replaceAll(RegExp(r'\D'), '');
  final defaultCc = ccRaw.isEmpty ? '966' : ccRaw;

  final normalized = <JsonMap>[];
  final invalid = <JsonMap>[];
  final seenDigits = <String>{};
  for (final raw in rawPhones.take(limit)) {
    final value = (raw ?? '').toString();
    try {
      final phone = normalizePhone(value, defaultCountryCode: defaultCc);
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
        return phoneDigitLookupVariants(
          entry['phoneDigits'],
          defaultCountryCode: defaultCc,
        );
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

  // Resolve the target list (for own lists, use payload; for shared lists, use
  // the share's listId via the profile).
  final listId = await resolveItemListId(repo, actorId, ownerId, payload);

  final product = asMap(await repo.ensureProduct(payload['productName']));
  final productId = documentId(product);
  final activeItems =
      listOfMaps(await repo.listActiveItems(ownerId, listId: listId));
  assertNoDuplicateActiveItem(activeItems, ownerId, productId);

  final data =
      buildListItemDocument(payload, ownerId, actorId, productId, listId: listId);
  if ((data['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.validateImageFile(data['imageFileId']);
  }
  final item = asMap(await repo.createListItem(data, ownerShares));

  if ((data['imageFileId'] ?? '').toString().isNotEmpty) {
    await repo.updateImagePermissions(
        data['imageFileId'], ownerId, ownerShares);
  }

  // The product is active again, so it shouldn't linger in trash (Issue 6).
  await purgeTrashDuplicates(repo, ownerId, productId);

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

  // Keep only the row just trashed; drop earlier trashed copies of the same
  // product so trash doesn't fill up with duplicates (Issue 5).
  await purgeTrashDuplicates(
    repo,
    item['ownerId'].toString(),
    item['productId'],
    keepItemId: documentId(item),
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

  // The restored row is active now; drop any other trashed copies of the same
  // product so a stale duplicate can't shadow it (Issues 5 & 6).
  await purgeTrashDuplicates(
    repo,
    item['ownerId'].toString(),
    item['productId'],
    keepItemId: documentId(item),
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

  final listId = await resolveItemListId(repo, actorId, ownerId, payload);
  final trash =
      listOfMaps(await repo.listTrashItems(ownerId, listId: listId));
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

  final rawListId = (payload['listId'] ?? '').toString();
  final listId = rawListId.isEmpty ? null : rawListId;

  final existing = asNullableMap(await repo.findShare(actorId, viewerId));
  final data = buildShareDocument(actorId, viewerId!, listId: listId);
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
    final shareListId = (updatedShare['listId'] ?? '').toString();
    await repo.setActiveReceivedOwner(
      actorId,
      share['ownerId'],
      listId: shareListId.isEmpty ? null : shareListId,
    );
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
  await requireAdmin(repo, actorId);
  return {'items': listOfMaps(await repo.adminList(payload['kind']))};
}

Future<JsonMap> adminCreate({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
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
  await requireAdmin(repo, actorId);
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
  await requireAdmin(repo, actorId);
  if (payload['kind'] == 'users') {
    // Full cascade (audit B13): purge the user's data — items, events, shares,
    // presence, images — before removing the profile + auth account.
    await repo.resetUserData(payload['id']);
  }

  return {'result': await repo.adminDelete(payload['kind'], payload['id'])};
}

Future<JsonMap> adminResetUser({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
  final userId = payload['id'] ?? payload['userId'];
  return {'result': await repo.resetUserData(userId)};
}

Future<JsonMap> adminMergeSuggestions({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
  final products = listOfMaps(await repo.listProducts(activeOnly: false));
  return {
    'suggestions': suggestProductMerges(
      products,
      intFrom(payload['limit'], fallback: 25),
    ),
  };
}

// ── Named Lists ──────────────────────────────────────────────────────────────

Future<JsonMap> getLists({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final lists = listOfMaps(await repo.listUserLists(actorId));
  return {'lists': lists};
}

Future<JsonMap> createList({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final existingLists = listOfMaps(await repo.listUserLists(actorId));
  final isFirst = existingLists.isEmpty;
  final doc = buildUserListDocument(
    ownerId: actorId,
    name: (payload['name'] ?? '').toString(),
    emoji: payload['emoji']?.toString(),
    sortOrder: existingLists.length,
    isDefault: isFirst,
  );
  final list = asMap(await repo.createUserList(doc, actorId));
  return {'list': list};
}

Future<JsonMap> updateList({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final listId = (payload['listId'] ?? '').toString();
  if (listId.isEmpty) {
    throw MoonaError(ErrorCodes.invalidInput, 'listId is required.');
  }
  final existing = asMap(await repo.getUserList(listId));
  if ((existing['ownerId'] ?? '') != actorId) {
    throw MoonaError(ErrorCodes.unauthorized, 'Not your list.', status: 403);
  }
  final patch = <String, dynamic>{'updatedAt': nowIso()};
  if (payload.containsKey('name')) {
    final trimmed = payload['name'].toString().trim();
    if (trimmed.isEmpty) {
      throw MoonaError(ErrorCodes.invalidInput, 'List name is required.');
    }
    patch['name'] = trimmed;
  }
  if (payload.containsKey('emoji')) {
    patch['emoji'] = (payload['emoji'] ?? '').toString().trim();
  }
  if (payload.containsKey('sortOrder')) {
    patch['sortOrder'] = intFrom(payload['sortOrder'], fallback: 0);
  }
  final updated = asMap(await repo.updateUserList(listId, patch));
  return {'list': updated};
}

Future<JsonMap> deleteList({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final listId = (payload['listId'] ?? '').toString();
  if (listId.isEmpty) {
    throw MoonaError(ErrorCodes.invalidInput, 'listId is required.');
  }
  final existing = asMap(await repo.getUserList(listId));
  if ((existing['ownerId'] ?? '') != actorId) {
    throw MoonaError(ErrorCodes.unauthorized, 'Not your list.', status: 403);
  }

  final allLists = listOfMaps(await repo.listUserLists(actorId));
  if (allLists.length <= 1) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Cannot delete the last list.',
      status: 409,
    );
  }

  final migrateToListId = (payload['migrateToListId'] ?? '').toString();
  if (migrateToListId.isNotEmpty) {
    // Validate target list belongs to the actor.
    final target = asMap(await repo.getUserList(migrateToListId));
    if ((target['ownerId'] ?? '') != actorId) {
      throw MoonaError(ErrorCodes.unauthorized, 'Invalid target list.', status: 403);
    }
    // Re-assign all items from this list to the target list.
    final allItems = listOfMaps(
      await listAllItemsForList(repo, actorId, listId),
    );
    for (final item in allItems) {
      await repo.updateListItem(
        documentId(item),
        {'listId': migrateToListId, 'updatedAt': nowIso()},
        actorId,
      );
    }
  } else {
    // Hard-delete all items in the list.
    final allItems = listOfMaps(
      await listAllItemsForList(repo, actorId, listId),
    );
    for (final item in allItems) {
      await repo.deleteListItem(documentId(item));
    }
  }

  // If this was the default list, promote the first remaining list.
  if (existing['isDefault'] == true) {
    final remaining = allLists.where((l) => documentId(l) != listId).toList();
    if (remaining.isNotEmpty) {
      await repo.updateUserList(documentId(remaining.first), {
        'isDefault': true,
        'updatedAt': nowIso(),
      });
    }
  }

  await repo.deleteUserList(listId);
  return {'deleted': listId};
}

// ── Barcode Lookup ────────────────────────────────────────────────────────────

Future<JsonMap> lookupBarcode({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  requireActor(actorId);
  final barcode = (payload['barcode'] ?? '').toString().trim();
  if (barcode.isEmpty) {
    throw MoonaError(ErrorCodes.invalidInput, 'barcode is required.');
  }
  final product = asNullableMap(await repo.findProductByBarcode(barcode));
  if (product == null) {
    // Log the unknown barcode for admin review (best-effort).
    try {
      await repo.upsertBarcodeSubmission(barcode, actorId);
    } catch (_) {}
    return {'product': null, 'found': false};
  }
  return {'product': product, 'found': true};
}

Future<JsonMap> adminGetBarcodeQueue({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
  final submissions = listOfMaps(await repo.listUnresolvedBarcodeSubmissions());
  return {'submissions': submissions};
}

Future<JsonMap> adminResolveBarcode({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
  final submissionId = (payload['submissionId'] ?? '').toString();
  final productId = (payload['productId'] ?? '').toString();
  if (submissionId.isEmpty || productId.isEmpty) {
    throw MoonaError(
        ErrorCodes.invalidInput, 'submissionId and productId are required.');
  }

  final submission = asMap(await repo.getBarcodeSubmission(submissionId));
  final barcode = (submission['barcode'] ?? '').toString();

  // Set the barcode on the product.
  final product = asMap(await repo.getProduct(productId));
  await repo.adminUpdate(
    'products',
    productId,
    {...product, 'barcode': barcode},
  );

  await repo.resolveBarcodeSubmission(submissionId, productId);
  return {'resolved': true, 'barcode': barcode, 'productId': productId};
}

Future<JsonMap> adminMergeProducts({
  required dynamic repo,
  required String actorId,
  required JsonMap payload,
}) async {
  await requireAdmin(repo, actorId);
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
  'getLists': getLists,
  'createList': createList,
  'updateList': updateList,
  'deleteList': deleteList,
  'lookupBarcode': lookupBarcode,
  'adminGetBarcodeQueue': adminGetBarcodeQueue,
  'adminResolveBarcode': adminResolveBarcode,
  'adminList': adminList,
  'adminCreate': adminCreate,
  'adminUpdate': adminUpdate,
  'adminDelete': adminDelete,
  'adminMergeSuggestions': adminMergeSuggestions,
  'adminMergeProducts': adminMergeProducts,
  'adminResetUser': adminResetUser,
};

/// Hard-deletes trashed rows for [ownerId]/[productId], keeping [keepItemId]
/// when given. Keeps trash de-duplicated (Issue 5) and clear of products that
/// are active again (Issue 6). Best-effort: a delete failure is swallowed so the
/// user's action still succeeds.
Future<void> purgeTrashDuplicates(
  dynamic repo,
  String ownerId,
  Object? productId, {
  String? keepItemId,
}) async {
  final pid = (productId ?? '').toString();
  if (pid.isEmpty || ownerId.isEmpty) return;
  final trash = listOfMaps(await repo.listTrashItems(ownerId));
  final dupes = findDuplicateTrashItems(trash, ownerId, pid, keepItemId);
  for (final item in dupes) {
    try {
      await repo.deleteListItem(documentId(item));
    } catch (_) {
      // Best-effort cleanup; never block the primary mutation.
    }
  }
}

Future<void> finalizeExpiredScratchesForOwner(
  dynamic repo,
  String ownerId, {
  String? listId,
}) async {
  final activeItems =
      listOfMaps(await repo.listActiveItems(ownerId, listId: listId));
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
  // De-dup trash: keep this finalized row, drop earlier trashed copies (Issue 5).
  await purgeTrashDuplicates(
    repo,
    ownerId,
    item['productId'],
    keepItemId: documentId(item),
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

/// Resolves the listId an item should be created in / cleared from.
/// For shared lists, reads the listId from the active accepted share.
/// For own lists, reads from the payload or falls back to the default list.
/// Creates a default list on demand if the owner has none.
Future<String?> resolveItemListId(
  dynamic repo,
  String actorId,
  String ownerId,
  JsonMap payload,
) async {
  if (ownerId != actorId) {
    // Viewing a shared list — use the share's listId.
    final profile = asMap(await repo.getProfile(actorId));
    final viewerShares = listOfMaps(await repo.listSharesForViewer(actorId));
    final activeOwnerId =
        (profile['activeReceivedOwnerId'] ?? '').toString();
    final share = viewerShares.where((s) =>
        s['ownerId'] == activeOwnerId &&
        s['viewerId'] == actorId &&
        s['status'] == 'accepted').firstOrNull;
    final rawListId = (share?['listId'] ?? '').toString();
    return rawListId.isEmpty ? null : rawListId;
  }

  // Own list: prefer the listId from the payload.
  final rawListId = (payload['listId'] ?? '').toString();
  if (rawListId.isNotEmpty) return rawListId;

  // Fall back to the owner's default list (creating it if necessary).
  final allLists = listOfMaps(await repo.listUserLists(ownerId));
  if (allLists.isEmpty) {
    final list = asMap(await repo.createUserList(
      buildUserListDocument(
          ownerId: ownerId, name: 'My List', isDefault: true),
      ownerId,
    ));
    return documentId(list);
  }
  final defaultList = allLists
      .where((l) => l['isDefault'] == true)
      .firstOrNull ?? allLists.first;
  return documentId(defaultList);
}

/// Lists all items (active + trash) for a given owner+list, used during
/// deleteList migration / deletion.
Future<List<dynamic>> listAllItemsForList(
  dynamic repo,
  String ownerId,
  String listId,
) async {
  final active = await repo.listActiveItems(ownerId, listId: listId);
  final trash = await repo.listTrashItems(ownerId, listId: listId);
  return [...listOfMaps(active), ...listOfMaps(trash)];
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

Set<String> adminEnvUserIds() =>
    (Platform.environment['MOONA_ADMIN_USER_IDS'] ?? '')
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

/// Admin gate. Passes if the actor is in the `MOONA_ADMIN_USER_IDS` env var
/// (the bootstrap-the-first-admin seed) OR their profile has `isAdmin == true`
/// (in-app promotion). Throws [adminOnly] otherwise.
Future<void> requireAdmin(dynamic repo, String actorId) async {
  requireActor(actorId);
  if (adminEnvUserIds().contains(actorId)) return;
  try {
    final profile = await repo.getProfile(actorId);
    if (profile is Map && profile['isAdmin'] == true) return;
  } catch (_) {
    // Missing profile → not an admin.
  }
  throw adminOnly();
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
