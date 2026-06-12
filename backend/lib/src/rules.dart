import 'dart:math' as math;

import 'errors.dart';
import 'normalization.dart';

String documentId(Map<String, dynamic> document) =>
    (document[r'$id'] ?? document['id'] ?? '').toString();

String listOwnerForViewer(
  Map<String, dynamic>? profile, [
  List<Map<String, dynamic>> acceptedShares = const [],
]) {
  if (profile == null) throw notFound('Profile');

  final activeOwnerId = (profile['activeReceivedOwnerId'] ?? '').toString();
  if (activeOwnerId.isEmpty) return profile['userId'].toString();

  final share = acceptedShares.where((item) {
    return item['ownerId'] == activeOwnerId &&
        item['viewerId'] == profile['userId'] &&
        item['status'] == 'accepted';
  }).firstOrNull;

  return share == null ? profile['userId'].toString() : activeOwnerId;
}

List<String> acceptedViewerIdsForOwner(
  String ownerId, [
  List<Map<String, dynamic>> shares = const [],
]) =>
    shares
        .where((share) =>
            share['ownerId'] == ownerId && share['status'] == 'accepted')
        .map((share) => share['viewerId'].toString())
        .toList();

bool canMutateOwnerList(
  String actorId,
  String ownerId, [
  List<Map<String, dynamic>> shares = const [],
]) {
  if (actorId == ownerId) return true;
  return shares.any((share) {
    return share['ownerId'] == ownerId &&
        share['viewerId'] == actorId &&
        share['status'] == 'accepted';
  });
}

bool canReadOwnerList(
  String actorId,
  String ownerId, [
  List<Map<String, dynamic>> shares = const [],
]) =>
    canMutateOwnerList(actorId, ownerId, shares);

void assertCanMutateOwnerList(
  String actorId,
  String ownerId, [
  List<Map<String, dynamic>> shares = const [],
]) {
  if (!canMutateOwnerList(actorId, ownerId, shares)) {
    throw MoonaError(
      ErrorCodes.unauthorized,
      'Only the owner or accepted viewers can mutate this list.',
      status: 403,
    );
  }
}

void assertCanReadOwnerList(
  String actorId,
  String ownerId, [
  List<Map<String, dynamic>> shares = const [],
]) {
  if (!canReadOwnerList(actorId, ownerId, shares)) {
    throw MoonaError(
      ErrorCodes.unauthorized,
      'Only the owner or accepted viewers can read this list.',
      status: 403,
    );
  }
}

List<Map<String, dynamic>> sortListItems(List<Map<String, dynamic>> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    if ((a['important'] == true) != (b['important'] == true)) {
      return a['important'] == true ? -1 : 1;
    }
    final aTime =
        DateTime.tryParse((a['updatedAt'] ?? a['createdAt'] ?? '').toString());
    final bTime =
        DateTime.tryParse((b['updatedAt'] ?? b['createdAt'] ?? '').toString());
    return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
      aTime?.millisecondsSinceEpoch ?? 0,
    );
  });
  return sorted;
}

List<Map<String, dynamic>> sortTrashItems(List<Map<String, dynamic>> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    final aTime =
        DateTime.tryParse((a['trashedAt'] ?? a['updatedAt'] ?? '').toString());
    final bTime =
        DateTime.tryParse((b['trashedAt'] ?? b['updatedAt'] ?? '').toString());
    return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
      aTime?.millisecondsSinceEpoch ?? 0,
    );
  });
  return sorted;
}

Map<String, dynamic>? findDuplicateActiveItem(
  List<Map<String, dynamic>> items,
  String ownerId,
  String productId, [
  String? ignoreItemId,
]) =>
    items.where((item) {
      final itemId = documentId(item);
      return item['ownerId'] == ownerId &&
          item['status'] == 'active' &&
          item['productId'] == productId &&
          (ignoreItemId == null || itemId != ignoreItemId);
    }).firstOrNull;

void assertNoDuplicateActiveItem(
  List<Map<String, dynamic>> items,
  String ownerId,
  String productId, [
  String? ignoreItemId,
]) {
  final duplicate = findDuplicateActiveItem(
    items,
    ownerId,
    productId,
    ignoreItemId,
  );

  if (duplicate != null) {
    throw MoonaError(
      ErrorCodes.duplicateItem,
      'This product is already active in the visible list.',
      status: 409,
      details: {
        'duplicateItemId': documentId(duplicate),
        'productId': productId,
      },
    );
  }
}

/// Every trashed row for [ownerId]/[productId] (optionally excluding
/// [ignoreItemId]). Mirrors [findDuplicateActiveItem] but returns all matches —
/// used to keep trash free of duplicates (Issue 5) and of products that are
/// active again (Issue 6).
List<Map<String, dynamic>> findDuplicateTrashItems(
  List<Map<String, dynamic>> items,
  String ownerId,
  String productId, [
  String? ignoreItemId,
]) =>
    items.where((item) {
      final itemId = documentId(item);
      return item['ownerId'] == ownerId &&
          item['status'] == 'trash' &&
          item['productId'] == productId &&
          (ignoreItemId == null || itemId != ignoreItemId);
    }).toList();

/// Collapses trash for display (no writes): drops rows whose product is active
/// again, and keeps only the newest trashed row per product. The mutation paths
/// hard-delete the rest; this keeps even legacy/dirty data tidy on read.
List<Map<String, dynamic>> dedupeTrashForDisplay(
  List<Map<String, dynamic>> trash,
  List<Map<String, dynamic>> activeItems,
) {
  final activeProductIds = <String>{
    for (final item in activeItems)
      if ((item['productId'] ?? '').toString().isNotEmpty)
        item['productId'].toString(),
  };
  final newestByProduct = <String, Map<String, dynamic>>{};
  final withoutProduct = <Map<String, dynamic>>[];
  for (final item in trash) {
    final productId = (item['productId'] ?? '').toString();
    if (productId.isEmpty) {
      withoutProduct.add(item);
      continue;
    }
    if (activeProductIds.contains(productId)) continue;
    final existing = newestByProduct[productId];
    if (existing == null ||
        _trashedAtMillis(item) >= _trashedAtMillis(existing)) {
      newestByProduct[productId] = item;
    }
  }
  return [...newestByProduct.values, ...withoutProduct];
}

int _trashedAtMillis(Map<String, dynamic> item) =>
    DateTime.tryParse((item['trashedAt'] ?? '').toString())
        ?.millisecondsSinceEpoch ??
    0;

Map<String, dynamic> buildProductDocument(
  Map<String, dynamic> input, [
  String? id,
]) {
  final displayName = normalizeText(
    input['displayName'] ?? input['name'] ?? input['nameEn'],
  );
  if (displayName.isEmpty) {
    throw MoonaError(ErrorCodes.productMissing, 'Product name is required.');
  }

  final nameAr = normalizeText(input['nameAr']);
  final nameEn = normalizeText(input['nameEn'] ?? displayName);
  final aliases = <String>[
    displayName,
    nameAr,
    nameEn,
    if (input['aliases'] is List)
      for (final alias in input['aliases'] as List) normalizeText(alias),
  ].where((value) => value.isNotEmpty).toSet().toList();
  final normalizedAliases = aliases.map(normalizeProductName).toSet().toList();
  final now = nowIso();

  return {
    'id': id,
    'nameAr': nameAr,
    'nameEn': nameEn,
    'displayName': displayName,
    'normalizedName': normalizeProductName(displayName),
    'normalizedNameAr': nameAr.isEmpty ? '' : normalizeProductName(nameAr),
    'normalizedNameEn': nameEn.isEmpty ? '' : normalizeProductName(nameEn),
    'aliases': aliases,
    'normalizedAliases': normalizedAliases,
    'mergeTargetProductId': input['mergeTargetProductId'] ?? '',
    'active': input['active'] != false,
    'createdAt': input['createdAt'] ?? now,
    'updatedAt': now,
  };
}

Map<String, dynamic>? matchProductByName(
  List<Map<String, dynamic>> products,
  Object? name,
) {
  final normalized = normalizeProductName(name);
  return products.where((product) {
    if (product['active'] == false) return false;
    final values = [
      product['normalizedName'],
      product['normalizedNameAr'],
      product['normalizedNameEn'],
      if (product['normalizedAliases'] is List)
        ...product['normalizedAliases'] as List,
    ];
    return values
        .where((value) => value != null && value != '')
        .contains(normalized);
  }).firstOrNull;
}

List<Map<String, dynamic>> searchProducts(
  List<Map<String, dynamic>> products,
  Object? query, [
  int limit = 20,
]) {
  final normalized = normalizeProductName(query);
  if (normalized.length < 2) return [];

  final matches = products.where((product) {
    if (product['active'] == false) return false;
    final haystack = [
      product['normalizedName'],
      product['normalizedNameAr'],
      product['normalizedNameEn'],
      if (product['normalizedAliases'] is List)
        ...product['normalizedAliases'] as List,
    ].join(' ');
    return haystack.contains(normalized);
  }).toList();
  matches.sort(
    (a, b) => (a['displayName'] ?? '').toString().compareTo(
          (b['displayName'] ?? '').toString(),
        ),
  );
  return matches.take(limit).toList();
}

Map<String, dynamic> buildListItemDocument(
  Map<String, dynamic> input,
  String ownerId,
  String actorId,
  String productId,
) {
  final now = nowIso();
  return {
    'ownerId': ownerId,
    'productId': productId,
    'count': NumberLike(input['count']).toDouble(defaultValue: 1),
    'unitId': input['unitId'] ?? '',
    'brand': normalizeText(input['brand']),
    'seller': normalizeText(input['seller']),
    'categoryId': input['categoryId'] ?? '',
    'imageFileId': input['imageFileId'] ?? '',
    'important': input['important'] == true,
    'note': normalizeText(input['note']),
    'status': 'active',
    'trashedAt': '',
    'trashedByUserId': '',
    'trashReason': '',
    'scratchedAt': '',
    'scratchExpiresAt': '',
    'scratchedByUserId': '',
    'createdByUserId': actorId,
    'updatedByUserId': actorId,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> patchListItemDocument(
  Map<String, dynamic> existing,
  Map<String, dynamic> input,
  String actorId,
  String productId,
) =>
    {
      'productId': productId,
      'count': NumberLike(
              input.containsKey('count') ? input['count'] : existing['count'])
          .toDouble(defaultValue: 1),
      'unitId': input.containsKey('unitId')
          ? input['unitId'] ?? ''
          : existing['unitId'] ?? '',
      'brand': normalizeText(
          input.containsKey('brand') ? input['brand'] : existing['brand']),
      'seller': normalizeText(
          input.containsKey('seller') ? input['seller'] : existing['seller']),
      'categoryId': input.containsKey('categoryId')
          ? input['categoryId'] ?? ''
          : existing['categoryId'] ?? '',
      'imageFileId': input.containsKey('imageFileId')
          ? input['imageFileId'] ?? ''
          : existing['imageFileId'] ?? '',
      'important': input.containsKey('important')
          ? input['important'] == true
          : existing['important'] == true,
      'note': normalizeText(
          input.containsKey('note') ? input['note'] : existing['note']),
      // Editing an item is an explicit "keep this" signal, so it cancels any
      // in-flight scratch. Without clearing these, a mid-scratch edit preserves
      // `scratchExpiresAt`, and the lazy finalize sweep later trashes the item
      // (the "adding a brand/store removes the item" bug on shared lists).
      'scratchedAt': '',
      'scratchExpiresAt': '',
      'scratchedByUserId': '',
      'updatedByUserId': actorId,
      'updatedAt': nowIso(),
    };

Map<String, dynamic> trashPatch(String actorId,
    [String reason = 'scratch_timer']) {
  final now = nowIso();
  return {
    'status': 'trash',
    'trashedAt': now,
    'trashedByUserId': actorId,
    'trashReason': reason,
    'scratchedAt': '',
    'scratchExpiresAt': '',
    'scratchedByUserId': '',
    'updatedByUserId': actorId,
    'updatedAt': now,
  };
}

Map<String, dynamic> restoreTrashPatch(String actorId) => {
      'status': 'active',
      'trashedAt': '',
      'trashedByUserId': '',
      'trashReason': '',
      'scratchedAt': '',
      'scratchExpiresAt': '',
      'scratchedByUserId': '',
      'updatedByUserId': actorId,
      'updatedAt': nowIso(),
    };

Map<String, dynamic> scratchPatch(
  String actorId, {
  int windowSeconds = 10,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  return {
    'scratchedAt': timestamp.toIso8601String(),
    'scratchExpiresAt':
        timestamp.add(Duration(seconds: windowSeconds)).toIso8601String(),
    'scratchedByUserId': actorId,
    'updatedByUserId': actorId,
    'updatedAt': timestamp.toIso8601String(),
  };
}

Map<String, dynamic> undoScratchPatch(String actorId) => {
      'scratchedAt': '',
      'scratchExpiresAt': '',
      'scratchedByUserId': '',
      'updatedByUserId': actorId,
      'updatedAt': nowIso(),
    };

bool hasScratch(Map<String, dynamic> item) =>
    (item['scratchedAt'] ?? '').toString().isNotEmpty ||
    (item['scratchExpiresAt'] ?? '').toString().isNotEmpty ||
    (item['scratchedByUserId'] ?? '').toString().isNotEmpty;

bool isScratchExpired(
  Map<String, dynamic> item, [
  DateTime? now,
]) {
  final expiresAt =
      DateTime.tryParse((item['scratchExpiresAt'] ?? '').toString());
  if (expiresAt == null) return false;
  final timestamp = now ?? DateTime.now().toUtc();
  return !expiresAt.toUtc().isAfter(timestamp);
}

String scratchActorId(Map<String, dynamic> item, String fallbackActorId) {
  final value = (item['scratchedByUserId'] ?? '').toString();
  return value.isEmpty ? fallbackActorId : value;
}

Map<String, dynamic> buildListEventDocument({
  required String ownerId,
  required String actorId,
  required String type,
  Map<String, dynamic>? item,
  Map<String, dynamic>? product,
  int? clearedCount,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final productId =
      (item?['productId'] ?? product?['id'] ?? product?[r'$id'])?.toString();
  return {
    'ownerId': ownerId,
    'actorId': actorId,
    'type': type,
    'itemId': item == null ? '' : documentId(item),
    'productId': productId ?? '',
    'productName':
        (product?['displayName'] ?? product?['nameEn'] ?? productId ?? '')
            .toString(),
    'productNameAr': (product?['nameAr'] ?? '').toString(),
    'productNameEn':
        (product?['nameEn'] ?? product?['displayName'] ?? '').toString(),
    'count': item?['count'] ?? 0,
    'unitId': (item?['unitId'] ?? '').toString(),
    'categoryId': (item?['categoryId'] ?? '').toString(),
    'brand': (item?['brand'] ?? '').toString(),
    'seller': (item?['seller'] ?? '').toString(),
    'important': item?['important'] == true,
    'clearedCount': clearedCount ?? 0,
    'createdAt': timestamp.toIso8601String(),
  };
}

Map<String, dynamic> withActorDisplayNames(
  Map<String, dynamic> item,
  Map<String, dynamic> profiles,
) {
  final createdBy = (item['createdByUserId'] ?? '').toString();
  final updatedBy = (item['updatedByUserId'] ?? '').toString();
  return {
    ...item,
    if (createdBy.isNotEmpty &&
        profiles[createdBy] is Map &&
        ((profiles[createdBy] as Map)['displayName'] ?? '')
            .toString()
            .isNotEmpty)
      'createdByDisplayName': (profiles[createdBy] as Map)['displayName'],
    if (updatedBy.isNotEmpty &&
        profiles[updatedBy] is Map &&
        ((profiles[updatedBy] as Map)['displayName'] ?? '')
            .toString()
            .isNotEmpty)
      'updatedByDisplayName': (profiles[updatedBy] as Map)['displayName'],
  };
}

Map<String, dynamic> withEventActorDisplayName(
  Map<String, dynamic> event,
  Map<String, dynamic> profiles,
) {
  final actorId = (event['actorId'] ?? '').toString();
  final profile = profiles[actorId];
  final displayName = profile is Map ? profile['displayName']?.toString() : '';
  return {
    ...event,
    if (displayName != null && displayName.isNotEmpty)
      'actorDisplayName': displayName,
  };
}

Map<String, dynamic> withPresenceActorDisplayName(
  Map<String, dynamic> presence,
  Map<String, dynamic> profiles,
) {
  final actorId = (presence['actorId'] ?? '').toString();
  final profile = profiles[actorId];
  final displayName = profile is Map ? profile['displayName']?.toString() : '';
  return {
    ...presence,
    if (displayName != null && displayName.isNotEmpty)
      'actorDisplayName': displayName,
  };
}

List<Map<String, dynamic>> suggestPurchaseItems({
  required List<Map<String, dynamic>> events,
  required Set<String> activeProductIds,
  required int limit,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final byProduct = <String, List<Map<String, dynamic>>>{};
  for (final event in events) {
    if (event['type'] != 'scratched') continue;
    final productId = (event['productId'] ?? '').toString();
    if (productId.isEmpty || activeProductIds.contains(productId)) continue;
    byProduct.putIfAbsent(productId, () => []).add(event);
  }

  final suggestions = <Map<String, dynamic>>[];
  for (final entry in byProduct.entries) {
    final productEvents = entry.value
      ..sort((a, b) => eventTime(a).compareTo(eventTime(b)));
    final latest = productEvents.last;
    final intervals = <int>[];
    for (var i = 1; i < productEvents.length; i += 1) {
      final previous = eventTime(productEvents[i - 1]);
      final current = eventTime(productEvents[i]);
      final days = current.difference(previous).inDays.abs();
      if (days > 0) intervals.add(days);
    }
    final avgIntervalDays = intervals.isEmpty
        ? 0.0
        : intervals.reduce((a, b) => a + b) / intervals.length;
    final lastPurchasedAt = eventTime(latest);
    final daysSince = timestamp.difference(lastPurchasedAt).inHours / 24;
    final cadenceScore =
        avgIntervalDays <= 0 ? 0.0 : daysSince / avgIntervalDays;
    final frequencyScore = math.min(productEvents.length, 10) / 10;
    final recencyScore = math.max(0, 1 - daysSince / 365);
    final dueScore = cadenceScore + frequencyScore + recencyScore;

    suggestions.add({
      'productId': entry.key,
      'productName': latest['productName'] ?? '',
      'productNameAr': latest['productNameAr'] ?? '',
      'productNameEn': latest['productNameEn'] ?? '',
      'unitId': latest['unitId'] ?? '',
      'categoryId': latest['categoryId'] ?? '',
      'brand': latest['brand'] ?? '',
      'seller': latest['seller'] ?? '',
      'purchaseCount': productEvents.length,
      'lastPurchasedAt': lastPurchasedAt.toIso8601String(),
      'avgIntervalDays': avgIntervalDays,
      'dueScore': dueScore,
    });
  }

  suggestions.sort((a, b) {
    final byScore = (b['dueScore'] as num).compareTo(a['dueScore'] as num);
    if (byScore != 0) return byScore;
    return (b['lastPurchasedAt'] ?? '')
        .toString()
        .compareTo((a['lastPurchasedAt'] ?? '').toString());
  });
  return suggestions.take(limit).toList();
}

Map<String, dynamic> buildInsights({
  required List<Map<String, dynamic>> events,
  required int rangeDays,
}) {
  final scratched = events.where((event) => event['type'] == 'scratched');
  final productIds = <String>{};
  final byProduct = <String, Map<String, dynamic>>{};
  final byCategory = <String, Map<String, dynamic>>{};
  final byDayOfWeek = List<int>.filled(7, 0);
  final byWeek = <String, int>{};

  for (final event in scratched) {
    final productId = (event['productId'] ?? '').toString();
    if (productId.isNotEmpty) productIds.add(productId);
    final product = byProduct.putIfAbsent(productId, () {
      return {
        'productId': productId,
        'productName': event['productName'] ?? '',
        'productNameAr': event['productNameAr'] ?? '',
        'productNameEn': event['productNameEn'] ?? '',
        'count': 0,
        'lastPurchasedAt': '',
      };
    });
    product['count'] = (product['count'] as int) + 1;
    final eventTimestamp = eventTime(event);
    final currentLast = DateTime.tryParse(
      (product['lastPurchasedAt'] ?? '').toString(),
    );
    if (currentLast == null || eventTimestamp.isAfter(currentLast)) {
      product['lastPurchasedAt'] = eventTimestamp.toIso8601String();
    }

    final categoryId = (event['categoryId'] ?? '').toString();
    final category = byCategory.putIfAbsent(categoryId, () {
      return {'categoryId': categoryId, 'count': 0};
    });
    category['count'] = (category['count'] as int) + 1;

    byDayOfWeek[eventTimestamp.weekday % 7] += 1;
    final weekStart =
        eventTimestamp.subtract(Duration(days: eventTimestamp.weekday - 1));
    final key = DateTime.utc(weekStart.year, weekStart.month, weekStart.day)
        .toIso8601String();
    byWeek[key] = (byWeek[key] ?? 0) + 1;
  }

  final topProducts = byProduct.values.toList()
    ..sort((a, b) {
      final byCount = (b['count'] as int).compareTo(a['count'] as int);
      if (byCount != 0) return byCount;
      return (b['lastPurchasedAt'] ?? '')
          .toString()
          .compareTo((a['lastPurchasedAt'] ?? '').toString());
    });
  final categories = byCategory.values.toList()
    ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  final weeks = byWeek.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  return {
    'rangeDays': rangeDays,
    'totalChecked': scratched.length,
    'distinctProducts': productIds.length,
    'topProducts': topProducts.take(10).toList(),
    'byCategory': categories,
    'byDayOfWeek': byDayOfWeek,
    'byWeek': [
      for (final entry in weeks) {'weekStart': entry.key, 'count': entry.value},
    ],
  };
}

DateTime eventTime(Map<String, dynamic> event) =>
    DateTime.tryParse((event['createdAt'] ?? '').toString())?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Map<String, dynamic> buildShareDocument(String ownerId, String viewerId) {
  if (ownerId == viewerId) {
    throw MoonaError(
      ErrorCodes.shareSelf,
      'A user cannot share their own list with themselves.',
      status: 409,
    );
  }

  final now = nowIso();
  return {
    'ownerId': ownerId,
    'viewerId': viewerId,
    'status': 'pending',
    'requestedAt': now,
    'respondedAt': '',
    'revokedAt': '',
    'createdAt': now,
    'updatedAt': now,
  };
}

void assertShareCanBeRequested({
  required String ownerId,
  required String? viewerId,
  required Map<String, dynamic>? viewerProfile,
  required List<Map<String, dynamic>> existingShares,
}) {
  if (ownerId == viewerId) {
    throw MoonaError(
      ErrorCodes.shareSelf,
      'A user cannot share their own list with themselves.',
      status: 409,
    );
  }

  if (viewerProfile == null || viewerId == null || viewerId.isEmpty) {
    throw MoonaError(
      ErrorCodes.shareTargetMissing,
      'The target phone number does not belong to a Moona user.',
      status: 404,
    );
  }

  final pending = existingShares.where((share) {
    return share['ownerId'] == ownerId &&
        share['viewerId'] == viewerId &&
        share['status'] == 'pending';
  }).firstOrNull;
  if (pending != null) {
    throw MoonaError(
      ErrorCodes.sharePending,
      'A pending share already exists for this viewer.',
      status: 409,
      details: {'shareId': documentId(pending)},
    );
  }

  final receiving = existingShares.where((share) {
    return share['viewerId'] == viewerId &&
        share['status'] == 'accepted' &&
        share['ownerId'] != ownerId;
  }).firstOrNull;
  final activeReceivedOwnerId =
      (viewerProfile['activeReceivedOwnerId'] ?? '').toString();
  if (receiving != null || activeReceivedOwnerId.isNotEmpty) {
    throw MoonaError(
      ErrorCodes.viewerAlreadyReceiving,
      'The viewer is already receiving another shared owner list.',
      status: 409,
      details: {
        'activeReceivedOwnerId': receiving?['ownerId'] ?? activeReceivedOwnerId,
      },
    );
  }
}

Map<String, dynamic> respondSharePatch(
  Map<String, dynamic> share,
  String actorId,
  bool accepted,
) {
  if (share['viewerId'] != actorId) {
    throw MoonaError(
      ErrorCodes.unauthorized,
      'Only the target viewer can respond to a share.',
      status: 403,
    );
  }
  if (share['status'] != 'pending') {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Only pending shares can be accepted or declined.',
      status: 409,
    );
  }

  final now = nowIso();
  return {
    'status': accepted ? 'accepted' : 'declined',
    'respondedAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic>? revokeSharePatch(
  Map<String, dynamic> share,
  String actorId,
) {
  if (![share['ownerId'], share['viewerId']].contains(actorId)) {
    throw MoonaError(
      ErrorCodes.unauthorized,
      'Only the owner or viewer can unlink this share.',
      status: 403,
    );
  }
  if (share['status'] == 'revoked') return null;

  final now = nowIso();
  return {
    'status': 'revoked',
    'revokedAt': now,
    'updatedAt': now,
  };
}

List<Map<String, dynamic>> suggestProductMerges(
  List<Map<String, dynamic>> products, [
  int limit = 25,
]) {
  final activeProducts =
      products.where((product) => product['active'] != false).toList();
  final suggestions = <Map<String, dynamic>>[];

  for (var i = 0; i < activeProducts.length; i += 1) {
    for (var j = i + 1; j < activeProducts.length; j += 1) {
      final first = activeProducts[i];
      final second = activeProducts[j];
      final score = similarityScore(
        (first['normalizedName'] ?? normalizeProductName(first['displayName']))
            .toString(),
        (second['normalizedName'] ??
                normalizeProductName(second['displayName']))
            .toString(),
      );
      if (score >= 0.82) {
        suggestions.add({
          'sourceProductId': documentId(second),
          'targetProductId': documentId(first),
          'sourceName': second['displayName'],
          'targetName': first['displayName'],
          'score': score,
        });
      }
    }
  }

  suggestions.sort(
    (a, b) => (b['score'] as num).compareTo(a['score'] as num),
  );
  return suggestions.take(limit).toList();
}

double similarityScore(String first, String second) {
  if (first.isEmpty || second.isEmpty) return 0;
  if (first == second) return 1;

  final distance = _levenshteinDistance(first, second);
  final maxLength = math.max(first.length, second.length);
  return maxLength == 0 ? 1 : 1 - distance / maxLength;
}

int _levenshteinDistance(String first, String second) {
  final rows = first.length + 1;
  final cols = second.length + 1;
  final matrix = List.generate(rows, (_) => List<int>.filled(cols, 0));

  for (var i = 0; i < rows; i += 1) {
    matrix[i][0] = i;
  }
  for (var j = 0; j < cols; j += 1) {
    matrix[0][j] = j;
  }

  for (var i = 1; i < rows; i += 1) {
    for (var j = 1; j < cols; j += 1) {
      final cost = first[i - 1] == second[j - 1] ? 0 : 1;
      matrix[i][j] = math.min(
        math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
        matrix[i - 1][j - 1] + cost,
      );
    }
  }

  return matrix[first.length][second.length];
}

class NumberLike {
  NumberLike(this.value);

  final Object? value;

  double toDouble({required double defaultValue}) {
    if (value is num) return (value! as num).toDouble();
    return double.tryParse((value ?? '').toString()) ?? defaultValue;
  }
}
