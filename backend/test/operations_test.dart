import 'package:moona_backend/moona_backend.dart';
import 'package:test/test.dart';

Matcher throwsMoonaCode(String code) => throwsA(
      isA<MoonaError>().having((error) => error.code, 'code', code),
    );

void main() {
  test(
      'accepted viewer creates an item on the owner list and duplicates are rejected',
      () async {
    final repo = FakeRepo();

    final result = await createItem(
      repo: repo,
      actorId: 'viewer',
      payload: {
        'productName': 'Bread',
        'count': 2,
        'unitId': 'bag',
        'important': true
      },
    );

    expect(result['item']['ownerId'], 'owner');
    expect(result['item']['createdByUserId'], 'viewer');
    expect(result['item']['important'], isTrue);

    await expectLater(
      () => createItem(
          repo: repo, actorId: 'viewer', payload: {'productName': 'bread'}),
      throwsMoonaCode(ErrorCodes.duplicateItem),
    );
  });

  test('trashItem moves active items to trash with actor metadata', () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );

    final result = await trashItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': created['item'][r'$id'], 'reason': 'scratch_timer'},
    );

    expect(result['item']['status'], 'trash');
    expect(result['item']['trashedByUserId'], 'viewer');
    expect(result['item']['trashReason'], 'scratch_timer');
  });

  test('requestShare rejects unknown target phone numbers', () async {
    final repo = FakeRepo();

    await expectLater(
      () => requestShare(
        repo: repo,
        actorId: 'owner',
        payload: {'phone': '0550000000'},
      ),
      throwsMoonaCode(ErrorCodes.shareTargetMissing),
    );
  });

  test('createItem rejects invalid image file IDs before creating the item',
      () async {
    final repo = FakeRepo();

    await expectLater(
      () => createItem(
        repo: repo,
        actorId: 'owner',
        payload: {'productName': 'Cheese', 'imageFileId': 'missing-file'},
      ),
      throwsMoonaCode(ErrorCodes.invalidImage),
    );

    expect(repo.items, isEmpty);
  });

  test('respondShare accepts a pending share and sets active received owner',
      () async {
    final repo = FakeRepo();
    repo.profiles['newViewer'] = {
      'userId': 'newViewer',
      'phoneDigits': '966531234567',
      'activeReceivedOwnerId': '',
    };
    repo.shares['s2'] = {
      r'$id': 's2',
      'ownerId': 'owner',
      'viewerId': 'newViewer',
      'status': 'pending',
    };

    final result = await respondShare(
      repo: repo,
      actorId: 'newViewer',
      payload: {'shareId': 's2', 'accepted': true},
    );

    expect(result['share']['status'], 'accepted');
    expect(repo.profiles['newViewer']?['activeReceivedOwnerId'], 'owner');
    expect(repo.refreshedOwners.last, 'owner');
  });
}

class FakeRepo {
  final profiles = <String, JsonMap>{
    'owner': {
      'userId': 'owner',
      'phoneDigits': '966501112233',
      'activeReceivedOwnerId': '',
    },
    'viewer': {
      'userId': 'viewer',
      'phoneDigits': '966507654321',
      'activeReceivedOwnerId': 'owner',
    },
  };

  final shares = <String, JsonMap>{
    's1': {
      r'$id': 's1',
      'ownerId': 'owner',
      'viewerId': 'viewer',
      'status': 'accepted',
    },
  };

  final products = <String, JsonMap>{};
  final items = <String, JsonMap>{};
  final updatedImagePermissions = <String>[];
  final refreshedOwners = <String>[];
  var nextItemId = 1;
  var nextProductId = 1;

  Future<JsonMap?> getProfile(Object? userId) async => profiles[userId];

  Future<JsonMap> ensureProfile(JsonMap input) async {
    profiles[input['userId'].toString()] = input;
    return input;
  }

  Future<JsonMap> updatePreferences(String userId, JsonMap patch) async {
    final profile = {...profiles[userId]!, ...patch};
    profiles[userId] = profile;
    return profile;
  }

  Future<JsonMap?> findProfileByPhone(Object? phone) async {
    final digits = phone
        .toString()
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp('^0'), '966');
    return profiles.values
        .where((profile) => profile['phoneDigits'] == digits)
        .firstOrNull;
  }

  Future<List<JsonMap>> listSharesForViewer(Object? viewerId) async =>
      shares.values.where((share) => share['viewerId'] == viewerId).toList();

  Future<List<JsonMap>> listSharesForOwner(Object? ownerId) async =>
      shares.values.where((share) => share['ownerId'] == ownerId).toList();

  Future<List<JsonMap>> listSharesForParticipant(Object? userId) async => shares
      .values
      .where(
          (share) => share['ownerId'] == userId || share['viewerId'] == userId)
      .toList();

  Future<List<JsonMap>> listAcceptedSharesForOwner(Object? ownerId) async =>
      shares.values
          .where((share) =>
              share['ownerId'] == ownerId && share['status'] == 'accepted')
          .toList();

  Future<List<JsonMap>> listProducts({bool activeOnly = true}) async =>
      products.values.toList();

  Future<JsonMap> ensureProduct(Object? name) async {
    final normalized = name.toString().trim().toLowerCase();
    final existing = products.values
        .where((product) => product['normalizedName'] == normalized)
        .firstOrNull;
    if (existing != null) return existing;

    final id = 'p${nextProductId++}';
    final product = {
      ...buildProductDocument({'displayName': name}, id),
      r'$id': id,
    };
    products[id] = product;
    return product;
  }

  Future<JsonMap?> getProduct(Object? productId) async => products[productId];

  Future<List<JsonMap>> listActiveItems(Object? ownerId) async => items.values
      .where((item) => item['ownerId'] == ownerId && item['status'] == 'active')
      .toList();

  Future<List<JsonMap>> listTrashItems(Object? ownerId) async => items.values
      .where((item) => item['ownerId'] == ownerId && item['status'] == 'trash')
      .toList();

  Future<JsonMap> createListItem(JsonMap data,
      [List<JsonMap> ownerShares = const []]) async {
    final id = 'i${nextItemId++}';
    final item = {...data, r'$id': id};
    items[id] = item;
    return item;
  }

  Future<JsonMap?> getListItem(Object? itemId) async => items[itemId];

  Future<JsonMap> updateListItem(Object? itemId, JsonMap patch,
      [Object? ownerId]) async {
    final item = {...items[itemId]!, ...patch};
    items[itemId.toString()] = item;
    return item;
  }

  Future<void> deleteListItem(Object? itemId) async {
    items.remove(itemId);
  }

  Future<void> updateImagePermissions(
    Object? fileId, [
    Object? ownerId,
    List<JsonMap>? ownerShares,
  ]) async {
    updatedImagePermissions.add(fileId.toString());
  }

  Future<JsonMap> validateImageFile(Object? fileId) async {
    if (fileId == 'missing-file') {
      throw MoonaError(ErrorCodes.invalidImage, 'invalid image');
    }
    return {r'$id': fileId};
  }

  Future<JsonMap?> findShare(Object? ownerId, Object? viewerId) async =>
      shares.values
          .where((share) =>
              share['ownerId'] == ownerId && share['viewerId'] == viewerId)
          .firstOrNull;

  Future<JsonMap> createShare(JsonMap data) async {
    final id = 's${shares.length + 1}';
    final share = {...data, r'$id': id};
    shares[id] = share;
    return share;
  }

  Future<JsonMap?> getShare(Object? shareId) async => shares[shareId];

  Future<JsonMap> updateShare(Object? shareId, JsonMap patch) async {
    final share = {...shares[shareId]!, ...patch};
    shares[shareId.toString()] = share;
    return share;
  }

  Future<void> setActiveReceivedOwner(Object? viewerId, Object? ownerId) async {
    final profile = {...profiles[viewerId]!, 'activeReceivedOwnerId': ownerId};
    profiles[viewerId.toString()] = profile;
  }

  Future<void> refreshOwnerPermissions(Object? ownerId) async {
    refreshedOwners.add(ownerId.toString());
  }
}
