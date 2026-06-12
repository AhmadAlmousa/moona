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

  test('editing a scratched item cancels the scratch (no surprise trashing)',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    final id = created['item'][r'$id'];

    await scratchItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': id, 'windowSeconds': 10},
    );
    expect(repo.items[id]!['scratchExpiresAt'], isNotEmpty);

    final edited = await updateItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': id, 'brand': 'Almarai'},
    );

    expect(edited['item']['brand'], 'Almarai');
    expect(edited['item']['status'], 'active');
    expect(edited['item']['scratchExpiresAt'], '');
    expect(edited['item']['scratchedAt'], '');

    // The lazy sweep must no longer trash the freshly edited item.
    await finalizeExpiredScratchesForOwner(repo, 'owner');
    expect(repo.items[id]!['status'], 'active');
  });

  test('re-adding a trashed product purges the stale trash row (Issue 6)',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    await trashItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': created['item'][r'$id'], 'reason': 'deleted'},
    );
    expect(await repo.listTrashItems('owner'), hasLength(1));

    // Adding the same product again must clear the trashed copy.
    await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'milk'},
    );

    expect(await repo.listTrashItems('owner'), isEmpty);
    expect(await repo.listActiveItems('owner'), hasLength(1));
  });

  test(
      'trashing a product keeps one trash row and drops older duplicates '
      '(Issue 5)', () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    final productId = created['item']['productId'];
    // Seed a stale trashed duplicate of the same product AFTER create (create
    // itself purges trash), to exercise trashItem's keep-newest cleanup.
    repo.items['old'] = {
      r'$id': 'old',
      'ownerId': 'owner',
      'productId': productId,
      'status': 'trash',
      'trashedAt': '2026-06-01T00:00:00.000Z',
    };

    await trashItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': created['item'][r'$id'], 'reason': 'scratch_timer'},
    );

    final trash = await repo.listTrashItems('owner');
    expect(trash, hasLength(1));
    expect(trash.single[r'$id'], created['item'][r'$id']);
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

  test('lookupContacts marks registered users and returns them first',
      () async {
    final repo = FakeRepo();

    final result = await lookupContacts(
      repo: repo,
      actorId: 'owner',
      payload: {
        'phones': ['0550000000', '0507654321', '+966501112233'],
      },
    );

    final contacts = result['contacts'] as List<JsonMap>;
    final registered = result['registered'] as List<JsonMap>;
    final unregistered = result['unregistered'] as List<JsonMap>;

    expect(contacts.map((entry) => entry['phoneDigits']), [
      '966507654321',
      '966501112233',
      '966550000000',
    ]);
    expect(registered, hasLength(2));
    expect(registered.first['displayName'], 'Viewer');
    expect(registered.first['isSelf'], isFalse);
    expect(registered.last['displayName'], 'Owner');
    expect(registered.last['isSelf'], isTrue);
    expect(unregistered.single['registered'], isFalse);
  });

  test('lookupContacts matches contacts with Saudi trunk-zero variants',
      () async {
    final repo = FakeRepo();
    repo.profiles['viewer'] = {
      ...repo.profiles['viewer']!,
      'phone': '+9660507654321',
      'phoneDigits': '9660507654321',
    };

    final result = await lookupContacts(
      repo: repo,
      actorId: 'owner',
      payload: {
        'phones': ['+966 050 765 4321'],
      },
    );

    final registered = result['registered'] as List<JsonMap>;
    expect(registered.single['registered'], isTrue);
    expect(registered.single['phoneDigits'], '966507654321');
    expect(registered.single['userId'], 'viewer');
  });

  test('lookupContacts honors a caller-supplied defaultCountryCode', () async {
    final repo = FakeRepo();
    repo.profiles['viewer'] = {
      ...repo.profiles['viewer']!,
      'phone': '+971501112233',
      'phoneDigits': '971501112233',
    };

    final result = await lookupContacts(
      repo: repo,
      actorId: 'owner',
      payload: {
        'phones': ['0501112233'],
        'defaultCountryCode': '971',
      },
    );

    final registered = result['registered'] as List<JsonMap>;
    // The leading-zero local number normalizes against +971, not the +966
    // default, and matches the viewer's UAE registration.
    expect(registered.single['phoneDigits'], '971501112233');
    expect(registered.single['userId'], 'viewer');
  });

  test(
      'lookupContacts deduplicates normalized phones and reports invalid input',
      () async {
    final repo = FakeRepo();

    final result = await lookupContacts(
      repo: repo,
      actorId: 'owner',
      payload: {
        'contacts': [
          {
            'phones': [
              {'number': '0507654321'},
              {'number': '+966507654321'},
              {'number': '12'},
            ],
          },
        ],
      },
    );

    final contacts = result['contacts'] as List<JsonMap>;
    final invalid = result['invalid'] as List<JsonMap>;

    expect(contacts, hasLength(1));
    expect(contacts.single['phoneDigits'], '966507654321');
    expect(contacts.single['registered'], isTrue);
    expect(invalid.single['code'], ErrorCodes.invalidInput);
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

  test('bootstrap includes profile lookup and resolved share/trash names',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    await trashItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': created['item'][r'$id']},
    );

    final result = await getBootstrapData(
      repo: repo,
      actorId: 'owner',
      payload: {},
    );

    final profiles = result['profiles'] as JsonMap;
    expect(profiles['viewer']['displayName'], 'Viewer');
    expect(
      result['visibleList']['trash'].first['trashedByDisplayName'],
      'Viewer',
    );
    expect(
      result['visibleList']['trash'].first['createdByDisplayName'],
      'Owner',
    );
    expect(
      result['visibleList']['trash'].first['updatedByDisplayName'],
      'Viewer',
    );
    expect(
      result['sharing']['outgoing'].first['counterpartyName'],
      'Viewer',
    );
  });

  test('mutations append durable list events and activity enriches actors',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    await trashItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': created['item'][r'$id'], 'reason': 'scratch_timer'},
    );
    await clearTrash(repo: repo, actorId: 'owner', payload: {});

    expect(repo.events.map((event) => event['type']), [
      'added',
      'scratched',
      'cleared',
    ]);
    expect(repo.events.last['clearedCount'], 1);

    final activity = await getActivity(
      repo: repo,
      actorId: 'owner',
      payload: {'limit': 10},
    );
    final events = activity['events'] as List<JsonMap>;
    expect(events.first['type'], 'cleared');
    expect(events.first['actorDisplayName'], 'Owner');
    expect(events[1]['actorDisplayName'], 'Viewer');
  });

  test('suggestItems excludes active products and scores purchase history',
      () async {
    final repo = FakeRepo();
    final milk = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    await trashItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': milk['item'][r'$id'], 'reason': 'scratch_timer'},
    );
    final bread = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Bread'},
    );
    await trashItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': bread['item'][r'$id'], 'reason': 'scratch_timer'},
    );
    await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Bread'},
    );

    final result = await suggestItemsOperation(
      repo: repo,
      actorId: 'owner',
      payload: {'limit': 10},
    );
    final suggestions = result['suggestions'] as List<JsonMap>;

    expect(suggestions.map((item) => item['productName']), ['Milk']);
    expect(suggestions.single['purchaseCount'], 1);
  });

  test('buildInsights emits count keys and Sunday-first day buckets', () {
    final insights = buildInsights(
      events: [
        {
          'type': 'scratched',
          'productId': 'p1',
          'productName': 'Milk',
          'categoryId': 'grocery',
          'createdAt': '2026-06-07T10:00:00.000Z',
        },
        {
          'type': 'scratched',
          'productId': 'p1',
          'productName': 'Milk',
          'categoryId': 'grocery',
          'createdAt': '2026-06-08T10:00:00.000Z',
        },
      ],
      rangeDays: 90,
    );

    final topProducts = insights['topProducts'] as List<JsonMap>;
    expect(topProducts.single['count'], 2);
    expect(topProducts.single.containsKey('purchaseCount'), isFalse);
    expect(insights['byDayOfWeek'], [1, 1, 0, 0, 0, 0, 0]);
  });

  test('scratchItem can be undone and expired scratches finalize to trash',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    final itemId = created['item'][r'$id'];

    final scratched = await scratchItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': itemId, 'windowSeconds': 3},
    );
    expect(scratched['item']['scratchedByUserId'], 'viewer');
    expect(scratched['item']['status'], 'active');

    final undone = await undoScratchItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': itemId},
    );
    expect(undone['item']['scratchedByUserId'], '');

    await scratchItem(
      repo: repo,
      actorId: 'viewer',
      payload: {'itemId': itemId, 'windowSeconds': 3},
    );
    repo.items[itemId]!['scratchExpiresAt'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();

    final finalized = await finalizeScratch(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': itemId},
    );
    expect(finalized['item']['status'], 'trash');
    expect(finalized['item']['trashedByUserId'], 'viewer');
    expect(repo.events.last['type'], 'scratched');
  });

  test('shared list item mutations send push to the other participants',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );

    expect(repo.pushes.single['userIds'], ['viewer']);
    expect(repo.pushes.single['data']['type'], 'item_added');
    expect(repo.pushes.single['body'], 'Owner added Milk.');

    repo.pushes.clear();
    await updateItem(
      repo: repo,
      actorId: 'viewer',
      payload: {
        'itemId': created['item'][r'$id'],
        'productName': 'Milk',
        'count': 2,
      },
    );

    expect(repo.pushes.single['userIds'], ['owner']);
    expect(repo.pushes.single['data']['type'], 'item_edited');
    expect(repo.pushes.single['body'], 'Viewer updated Milk.');
  });

  test('share and presence notifications target counterparties', () async {
    final repo = FakeRepo();
    repo.profiles['newViewer'] = {
      'userId': 'newViewer',
      'displayName': 'New Viewer',
      'phone': '+966531234567',
      'phoneDigits': '966531234567',
      'activeReceivedOwnerId': '',
    };

    final requested = await requestShare(
      repo: repo,
      actorId: 'owner',
      payload: {'phone': '+966531234567'},
    );
    expect(repo.pushes.single['userIds'], ['newViewer']);
    expect(repo.pushes.single['data']['type'], 'share_requested');

    repo.pushes.clear();
    await respondShare(
      repo: repo,
      actorId: 'newViewer',
      payload: {'shareId': requested['share'][r'$id'], 'accepted': true},
    );
    expect(repo.pushes.single['userIds'], ['owner']);
    expect(repo.pushes.single['data']['type'], 'share_accepted');

    repo.pushes.clear();
    await setShoppingPresence(
      repo: repo,
      actorId: 'newViewer',
      payload: {'active': true},
    );
    expect(repo.pushes.single['userIds'], unorderedEquals(['owner', 'viewer']));
    expect(repo.pushes.single['data']['type'], 'shopping_started');

    await setShoppingPresence(
      repo: repo,
      actorId: 'newViewer',
      payload: {'active': true},
    );
    expect(repo.pushes, hasLength(1));

    repo.presence['newViewer']!['activeAt'] = '2026-06-09T05:00:00.000Z';
    repo.presence['newViewer']!['updatedAt'] = '2026-06-09T05:00:00.000Z';
    repo.pushes.clear();
    await setShoppingPresence(
      repo: repo,
      actorId: 'newViewer',
      payload: {'active': true},
    );
    expect(repo.pushes.single['data']['type'], 'shopping_started');
    expect(
      repo.presence['newViewer']!['activeAt'],
      isNot('2026-06-09T05:00:00.000Z'),
    );
  });

  test('setShoppingPresence upserts and clears readable presence', () async {
    final repo = FakeRepo();

    final result = await setShoppingPresence(
      repo: repo,
      actorId: 'viewer',
      payload: {'active': true},
    );

    expect(result['presence']['ownerId'], 'owner');
    expect(result['presence']['actorDisplayName'], 'Viewer');
    expect(repo.presence['viewer']?['actorId'], 'viewer');

    await setShoppingPresence(
      repo: repo,
      actorId: 'viewer',
      payload: {'active': false},
    );
    expect(repo.presence, isEmpty);
  });

  test('createImageViewToken verifies list access and item image ownership',
      () async {
    final repo = FakeRepo();
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk', 'imageFileId': 'file-1'},
    );

    final result = await createImageViewToken(
      repo: repo,
      actorId: 'viewer',
      payload: {
        'itemId': created['item'][r'$id'],
        'fileId': 'file-1',
        'ttlSeconds': 120,
      },
    );

    expect(result['bucketId'], imageBucketId);
    expect(result['fileId'], 'file-1');
    expect(result['token'], 'secret-file-1');
    expect(result['ttlSeconds'], 120);

    await expectLater(
      () => createImageViewToken(
        repo: repo,
        actorId: 'stranger',
        payload: {'itemId': created['item'][r'$id'], 'fileId': 'file-1'},
      ),
      throwsMoonaCode(ErrorCodes.unauthorized),
    );

    await expectLater(
      () => createImageViewToken(
        repo: repo,
        actorId: 'owner',
        payload: {'itemId': created['item'][r'$id'], 'fileId': 'other-file'},
      ),
      throwsMoonaCode(ErrorCodes.notFound),
    );
  });

  test('requireAdmin passes for a profile flagged isAdmin and rejects others',
      () async {
    final repo = FakeRepo();
    repo.profiles['boss'] = {
      'userId': 'boss',
      'displayName': 'Boss',
      'isAdmin': true,
    };

    // Promoted profile is allowed.
    await requireAdmin(repo, 'boss');

    // A regular user (no env entry, isAdmin not set) is rejected.
    await expectLater(
      () => requireAdmin(repo, 'owner'),
      throwsMoonaCode(ErrorCodes.adminOnly),
    );
    // An empty actor fails the actor guard first.
    await expectLater(
      () => requireAdmin(repo, ''),
      throwsMoonaCode(ErrorCodes.unauthorized),
    );
  });

  test('adminResetUser wipes a user\'s data but keeps the profile', () async {
    final repo = FakeRepo();
    repo.profiles['boss'] = {'userId': 'boss', 'isAdmin': true};
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    await trashItem(
      repo: repo,
      actorId: 'owner',
      payload: {'itemId': created['item'][r'$id'], 'reason': 'scratch_timer'},
    );
    await setShoppingPresence(
        repo: repo, actorId: 'owner', payload: {'active': true});
    expect(repo.events, isNotEmpty);

    final result = await adminResetUser(
      repo: repo,
      actorId: 'boss',
      payload: {'id': 'owner'},
    );

    expect(result['result']['items'], greaterThan(0));
    expect(await repo.listActiveItems('owner'), isEmpty);
    expect(await repo.listTrashItems('owner'), isEmpty);
    expect(repo.events.where((e) => e['ownerId'] == 'owner'), isEmpty);
    expect(repo.shares.values.where((s) => s['ownerId'] == 'owner'), isEmpty);
    expect(repo.presence['owner'], isNull);
    // Account survives the reset.
    expect(repo.profiles['owner'], isNotNull);
    expect(repo.deletedAuthUsers, isEmpty);
  });

  test('adminDelete on a user cascades the data purge then removes the account',
      () async {
    final repo = FakeRepo();
    repo.profiles['boss'] = {'userId': 'boss', 'isAdmin': true};
    final created = await createItem(
      repo: repo,
      actorId: 'owner',
      payload: {'productName': 'Milk'},
    );
    expect(repo.items[created['item'][r'$id']], isNotNull);

    await adminDelete(
      repo: repo,
      actorId: 'boss',
      payload: {'kind': 'users', 'id': 'owner'},
    );

    expect(repo.items.values.where((i) => i['ownerId'] == 'owner'), isEmpty);
    expect(repo.shares.values.where((s) => s['ownerId'] == 'owner'), isEmpty);
    expect(repo.profiles['owner'], isNull);
    expect(repo.deletedAuthUsers, contains('owner'));
  });

  test('brands CRUD round-trips through the admin operations', () async {
    final repo = FakeRepo();
    repo.profiles['boss'] = {'userId': 'boss', 'isAdmin': true};

    final created = await adminCreate(
      repo: repo,
      actorId: 'boss',
      payload: {
        'kind': 'brands',
        'data': {'name': 'Almarai'}
      },
    );
    expect(created['item']['name'], 'Almarai');

    final listed = await adminList(
      repo: repo,
      actorId: 'boss',
      payload: {'kind': 'brands'},
    );
    expect((listed['items'] as List), hasLength(1));

    await adminDelete(
      repo: repo,
      actorId: 'boss',
      payload: {'kind': 'brands', 'id': created['item'][r'$id']},
    );
    expect(repo.brands[created['item'][r'$id']]!['active'], isFalse);

    // Non-admins cannot touch the catalog.
    await expectLater(
      () => adminCreate(
        repo: repo,
        actorId: 'owner',
        payload: {
          'kind': 'brands',
          'data': {'name': 'Nadec'}
        },
      ),
      throwsMoonaCode(ErrorCodes.adminOnly),
    );
  });

  test('bootstrap returns brand and store catalogs', () async {
    final repo = FakeRepo();
    repo.brands['b1'] = {r'$id': 'b1', 'name': 'Almarai', 'active': true};
    repo.stores['s1'] = {r'$id': 's1', 'name': 'Danube', 'active': true};

    final result = await getBootstrapData(
      repo: repo,
      actorId: 'owner',
      payload: {},
    );

    final catalogs = result['catalogs'] as JsonMap;
    expect((catalogs['brands'] as List).single['name'], 'Almarai');
    expect((catalogs['stores'] as List).single['name'], 'Danube');
  });
}

class FakeRepo {
  final profiles = <String, JsonMap>{
    'owner': {
      'userId': 'owner',
      'displayName': 'Owner',
      'phone': '+966501112233',
      'phoneDigits': '966501112233',
      'activeReceivedOwnerId': '',
    },
    'viewer': {
      'userId': 'viewer',
      'displayName': 'Viewer',
      'phone': '+966507654321',
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
  final brands = <String, JsonMap>{};
  final stores = <String, JsonMap>{};
  final items = <String, JsonMap>{};
  final events = <JsonMap>[];
  final presence = <String, JsonMap>{};
  final userLists = <String, JsonMap>{};
  final barcodeSubmissions = <String, JsonMap>{};
  final pushes = <JsonMap>[];
  final updatedImagePermissions = <String>[];
  final refreshedOwners = <String>[];
  final deletedAuthUsers = <String>[];
  var nextItemId = 1;
  var nextProductId = 1;
  var nextEventId = 1;
  var nextListId = 1;
  var nextBarcodeId = 1;

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

  Future<List<JsonMap>> listProfilesByPhoneDigits(
    Iterable<String> phoneDigits,
  ) async {
    final digits = phoneDigits.toSet();
    return profiles.values
        .where((profile) => digits.contains(profile['phoneDigits']))
        .toList();
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

  Future<List<JsonMap>> listCategories() async => const [];

  Future<List<JsonMap>> listUnits() async => const [];

  Future<List<JsonMap>> listProducts({bool activeOnly = true}) async =>
      products.values.toList();

  Future<List<JsonMap>> listCatalogTerms(
    Object? kind, {
    bool activeOnly = true,
  }) async {
    final map = kind == 'brands' ? brands : stores;
    return map.values
        .where((term) => !activeOnly || term['active'] != false)
        .toList();
  }

  Future<List<JsonMap>> adminList(Object? kind) async {
    if (kind == 'users') return profiles.values.toList();
    if (kind == 'brands') return brands.values.toList();
    if (kind == 'stores') return stores.values.toList();
    if (kind == 'products') return products.values.toList();
    return const [];
  }

  Future<JsonMap> adminCreate(Object? kind, Object? rawInput) async {
    final input = (rawInput as Map).cast<String, dynamic>();
    final map = kind == 'brands' ? brands : stores;
    final id = (input['id'] ?? 't${map.length + 1}').toString();
    final name = input['name'].toString().trim();
    final row = {
      r'$id': id,
      'name': name,
      'normalizedName': name.toLowerCase(),
      'active': input['active'] != false,
    };
    map[id] = row;
    return row;
  }

  Future<JsonMap> adminUpdate(
      Object? kind, Object? id, Object? rawInput) async {
    final input = (rawInput as Map).cast<String, dynamic>();
    if (kind == 'users') {
      final patch = <String, dynamic>{};
      if (input.containsKey('isAdmin')) {
        patch['isAdmin'] = input['isAdmin'] == true;
      }
      if ((input['displayName'] ?? '').toString().trim().isNotEmpty) {
        patch['displayName'] = input['displayName'].toString().trim();
      }
      profiles[id.toString()] = {...profiles[id.toString()]!, ...patch};
      return profiles[id.toString()]!;
    }
    final map = kind == 'brands' ? brands : stores;
    map[id.toString()] = {...map[id.toString()]!, ...input};
    return map[id.toString()]!;
  }

  Future<dynamic> adminDelete(Object? kind, Object? id) async {
    if (kind == 'users') {
      deletedAuthUsers.add(id.toString());
      return profiles.remove(id.toString());
    }
    final map = kind == 'brands' ? brands : stores;
    map[id.toString()] = {...map[id.toString()]!, 'active': false};
    return map[id.toString()];
  }

  Future<JsonMap> resetUserData(Object? userId) async {
    final id = userId.toString();
    final removedItems =
        items.values.where((item) => item['ownerId'] == id).toList();
    for (final item in removedItems) {
      items.remove(item[r'$id']);
    }
    final removedEvents =
        events.where((event) => event['ownerId'] == id).toList();
    events.removeWhere((event) => event['ownerId'] == id);
    final removedShares = shares.values
        .where((share) => share['ownerId'] == id || share['viewerId'] == id)
        .toList();
    for (final share in removedShares) {
      shares.remove(share[r'$id']);
    }
    presence.remove(id);
    final removedLists =
        userLists.values.where((l) => l['ownerId'] == id).toList();
    for (final list in removedLists) {
      userLists.remove(list[r'$id']);
    }
    if (profiles.containsKey(id)) {
      profiles[id] = {...profiles[id]!, 'activeReceivedOwnerId': ''};
    }
    return {
      'items': removedItems.length,
      'events': removedEvents.length,
      'shares': removedShares.length,
      'files': 0,
      'lists': removedLists.length,
    };
  }

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

  Future<List<JsonMap>> listActiveItems(Object? ownerId,
          {String? listId}) async =>
      items.values
          .where((item) =>
              item['ownerId'] == ownerId &&
              item['status'] == 'active' &&
              (listId == null ||
                  listId.isEmpty ||
                  (item['listId'] ?? '') == listId))
          .toList();

  Future<List<JsonMap>> listTrashItems(Object? ownerId,
          {String? listId}) async =>
      items.values
          .where((item) =>
              item['ownerId'] == ownerId &&
              item['status'] == 'trash' &&
              (listId == null ||
                  listId.isEmpty ||
                  (item['listId'] ?? '') == listId))
          .toList();

  Future<List<JsonMap>> listEvents(
    Object? ownerId, {
    int limit = 50,
    String? cursor,
    List<String>? types,
    DateTime? since,
  }) async {
    final filtered = events.where((event) {
      if (event['ownerId'] != ownerId) return false;
      if (types != null && types.isNotEmpty && !types.contains(event['type'])) {
        return false;
      }
      if (since != null) {
        final createdAt = DateTime.tryParse(event['createdAt'].toString());
        if (createdAt == null || createdAt.isBefore(since)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b['createdAt'].toString().compareTo(
            a['createdAt'].toString(),
          ));
    final start = cursor == null || cursor.isEmpty
        ? 0
        : filtered.indexWhere((event) => event[r'$id'] == cursor) + 1;
    return filtered.skip(start < 0 ? 0 : start).take(limit).toList();
  }

  Future<JsonMap> createListItem(JsonMap data,
      [List<JsonMap> ownerShares = const []]) async {
    final id = 'i${nextItemId++}';
    final item = {...data, r'$id': id};
    items[id] = item;
    return item;
  }

  Future<JsonMap> createListEvent(JsonMap data,
      [List<JsonMap> ownerShares = const []]) async {
    final event = {...data, r'$id': 'e${nextEventId++}'};
    events.add(event);
    return event;
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

  Future<JsonMap> createImageViewToken(
    Object? fileId, {
    String? expire,
  }) async =>
      {
        r'$id': 'token-$fileId',
        'secret': 'secret-$fileId',
        'expire': expire,
      };

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

  Future<void> setActiveReceivedOwner(
    Object? viewerId,
    Object? ownerId, {
    String? listId,
  }) async {
    final profile = {
      ...profiles[viewerId]!,
      'activeReceivedOwnerId': ownerId,
      if (listId != null) 'activeReceivedListId': listId,
    };
    profiles[viewerId.toString()] = profile;
  }

  Future<void> refreshOwnerPermissions(Object? ownerId) async {
    refreshedOwners.add(ownerId.toString());
  }

  Future<List<JsonMap>> listShoppingPresence(Object? ownerId) async =>
      presence.values.where((item) => item['ownerId'] == ownerId).toList();

  Future<JsonMap> upsertShoppingPresence(
    Object? actorId,
    JsonMap data, [
    List<JsonMap> ownerShares = const [],
  ]) async {
    final row = {...data, r'$id': actorId.toString()};
    presence[actorId.toString()] = row;
    return row;
  }

  Future<void> deleteShoppingPresence(Object? actorId) async {
    presence.remove(actorId);
  }

  Future<void> sendPush({
    required List<String> userIds,
    String? title,
    String? body,
    JsonMap data = const {},
  }) async {
    pushes.add({
      'userIds': userIds,
      'title': title,
      'body': body,
      'data': data,
    });
  }

  // ── User Lists ──────────────────────────────────────────────────────────────

  Future<List<JsonMap>> listUserLists(Object? ownerId) async => userLists.values
      .where((l) => l['ownerId'] == ownerId)
      .toList()
    ..sort((a, b) => ((a['sortOrder'] ?? 0) as num)
        .compareTo((b['sortOrder'] ?? 0) as num));

  Future<JsonMap?> findDefaultUserList(Object? ownerId) async =>
      userLists.values
          .where((l) => l['ownerId'] == ownerId && l['isDefault'] == true)
          .firstOrNull;

  Future<JsonMap> getUserList(Object? listId) async =>
      userLists[listId.toString()]!;

  Future<JsonMap> createUserList(JsonMap data, String ownerId) async {
    final id = 'l${nextListId++}';
    final list = {...data, r'$id': id};
    userLists[id] = list;
    return list;
  }

  Future<JsonMap> updateUserList(Object? listId, JsonMap data) async {
    final list = {...userLists[listId.toString()]!, ...data};
    userLists[listId.toString()] = list;
    return list;
  }

  Future<void> deleteUserList(Object? listId) async {
    userLists.remove(listId.toString());
  }

  // ── Barcode ─────────────────────────────────────────────────────────────────

  Future<JsonMap?> findProductByBarcode(Object? barcode) async =>
      products.values
          .where((p) => p['barcode'] == normalizeBarcode(barcode))
          .firstOrNull;

  Future<JsonMap?> findBarcodeSubmission(Object? barcode) async =>
      barcodeSubmissions.values
          .where((s) => s['barcode'] == normalizeBarcode(barcode))
          .firstOrNull;

  Future<JsonMap> upsertBarcodeSubmission(
      String barcode, String userId) async {
    final normalized = normalizeBarcode(barcode);
    final existing = barcodeSubmissions.values
        .where((s) => s['barcode'] == normalized)
        .firstOrNull;
    if (existing != null) {
      final id = existing[r'$id'].toString();
      barcodeSubmissions[id] = {
        ...existing,
        'count': ((existing['count'] ?? 1) as num).toInt() + 1,
      };
      return barcodeSubmissions[id]!;
    }
    final id = 'b${nextBarcodeId++}';
    final sub = {
      r'$id': id,
      'barcode': normalized,
      'submittedByUserId': userId,
      'count': 1,
      'resolvedProductId': '',
    };
    barcodeSubmissions[id] = sub;
    return sub;
  }

  Future<List<JsonMap>> listUnresolvedBarcodeSubmissions() async =>
      barcodeSubmissions.values
          .where((s) => (s['resolvedProductId']?.toString() ?? '').isEmpty)
          .toList();

  Future<JsonMap> getBarcodeSubmission(Object? submissionId) async =>
      barcodeSubmissions[submissionId.toString()]!;

  Future<JsonMap> resolveBarcodeSubmission(
      Object? submissionId, Object? productId) async {
    final sub = {
      ...barcodeSubmissions[submissionId.toString()]!,
      'resolvedProductId': productId.toString(),
    };
    barcodeSubmissions[submissionId.toString()] = sub;
    return sub;
  }
}
