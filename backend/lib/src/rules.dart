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
    'updatedByUserId': actorId,
    'updatedAt': now,
  };
}

Map<String, dynamic> restoreTrashPatch(String actorId) => {
      'status': 'active',
      'trashedAt': '',
      'trashedByUserId': '',
      'trashReason': '',
      'updatedByUserId': actorId,
      'updatedAt': nowIso(),
    };

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
