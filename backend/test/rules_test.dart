import 'package:moona_backend/moona_backend.dart';
import 'package:test/test.dart';

Matcher throwsMoonaCode(String code) => throwsA(
      isA<MoonaError>().having((error) => error.code, 'code', code),
    );

void main() {
  test('accepted viewers can mutate an owner list', () {
    final shares = [
      {'ownerId': 'owner', 'viewerId': 'viewer', 'status': 'accepted'},
    ];

    expect(canMutateOwnerList('owner', 'owner', shares), isTrue);
    expect(canMutateOwnerList('viewer', 'owner', shares), isTrue);
    expect(canMutateOwnerList('other', 'owner', shares), isFalse);
  });

  test('duplicate active product is rejected per owner list', () {
    final items = [
      {r'$id': 'i1', 'ownerId': 'owner', 'productId': 'p1', 'status': 'active'},
      {r'$id': 'i2', 'ownerId': 'other', 'productId': 'p1', 'status': 'active'},
      {r'$id': 'i3', 'ownerId': 'owner', 'productId': 'p1', 'status': 'trash'},
    ];

    expect(
      () => assertNoDuplicateActiveItem(items, 'owner', 'p1'),
      throwsMoonaCode(ErrorCodes.duplicateItem),
    );
    expect(() => assertNoDuplicateActiveItem(items, 'owner', 'p2'),
        returnsNormally);
    expect(
      () => assertNoDuplicateActiveItem(items, 'owner', 'p1', 'i1'),
      returnsNormally,
    );
  });

  test('important items sort before normal items', () {
    final items = [
      {
        r'$id': 'normal',
        'important': false,
        'updatedAt': '2026-01-02T00:00:00.000Z'
      },
      {
        r'$id': 'important',
        'important': true,
        'updatedAt': '2026-01-01T00:00:00.000Z'
      },
    ];

    expect(sortListItems(items).map((item) => item[r'$id']),
        ['important', 'normal']);
  });

  test('trash patch records actor, time, and reason', () {
    final patch = trashPatch('viewer', 'scratch_timer');

    expect(patch['status'], 'trash');
    expect(patch['trashedByUserId'], 'viewer');
    expect(patch['trashReason'], 'scratch_timer');
    expect(patch['trashedAt'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
  });

  test(
      'share request validation blocks self, missing, pending, and active receiver',
      () {
    expect(
      () => assertShareCanBeRequested(
        ownerId: 'u1',
        viewerId: 'u1',
        viewerProfile: {'userId': 'u1'},
        existingShares: const [],
      ),
      throwsMoonaCode(ErrorCodes.shareSelf),
    );

    expect(
      () => assertShareCanBeRequested(
        ownerId: 'u1',
        viewerId: null,
        viewerProfile: null,
        existingShares: const [],
      ),
      throwsMoonaCode(ErrorCodes.shareTargetMissing),
    );

    expect(
      () => assertShareCanBeRequested(
        ownerId: 'u1',
        viewerId: 'u2',
        viewerProfile: {'userId': 'u2'},
        existingShares: const [
          {'ownerId': 'u1', 'viewerId': 'u2', 'status': 'pending'},
        ],
      ),
      throwsMoonaCode(ErrorCodes.sharePending),
    );

    expect(
      () => assertShareCanBeRequested(
        ownerId: 'u1',
        viewerId: 'u2',
        viewerProfile: {'userId': 'u2', 'activeReceivedOwnerId': 'u3'},
        existingShares: const [],
      ),
      throwsMoonaCode(ErrorCodes.viewerAlreadyReceiving),
    );
  });

  test('product search is substring-based and requires at least two characters',
      () {
    final products = [
      buildProductDocument(
          {'displayName': 'Olive oil', 'nameAr': 'زيت زيتون'}, 'p1'),
      buildProductDocument({'displayName': 'Milk', 'nameAr': 'حليب'}, 'p2'),
    ];

    expect(searchProducts(products, 'o').map((item) => item['id']), isEmpty);
    expect(searchProducts(products, 'oil').map((item) => item['id']), ['p1']);
    expect(searchProducts(products, 'حلي').map((item) => item['id']), ['p2']);
  });

  test('editing an item clears any in-flight scratch', () {
    final existing = {
      r'$id': 'i1',
      'count': 1,
      'status': 'active',
      'scratchedAt': '2026-06-12T10:00:00.000Z',
      'scratchExpiresAt': '2026-06-12T10:00:10.000Z',
      'scratchedByUserId': 'viewer',
    };

    final patch = patchListItemDocument(existing, {'brand': 'Almarai'}, 'owner', 'p1');

    expect(patch['brand'], 'Almarai');
    expect(patch['scratchedAt'], '');
    expect(patch['scratchExpiresAt'], '');
    expect(patch['scratchedByUserId'], '');
    expect(patch['updatedByUserId'], 'owner');
  });

  test('findDuplicateTrashItems returns every trashed row for a product', () {
    final items = [
      {r'$id': 'i1', 'ownerId': 'owner', 'productId': 'p1', 'status': 'trash'},
      {r'$id': 'i2', 'ownerId': 'owner', 'productId': 'p1', 'status': 'trash'},
      {r'$id': 'i3', 'ownerId': 'owner', 'productId': 'p1', 'status': 'active'},
      {r'$id': 'i4', 'ownerId': 'other', 'productId': 'p1', 'status': 'trash'},
    ];

    expect(
      findDuplicateTrashItems(items, 'owner', 'p1').map((i) => i[r'$id']),
      ['i1', 'i2'],
    );
    expect(
      findDuplicateTrashItems(items, 'owner', 'p1', 'i1').map((i) => i[r'$id']),
      ['i2'],
    );
  });

  test('dedupeTrashForDisplay hides active products and collapses duplicates',
      () {
    final active = [
      {r'$id': 'a1', 'ownerId': 'owner', 'productId': 'p1', 'status': 'active'},
    ];
    final trash = [
      {
        r'$id': 't1',
        'productId': 'p1',
        'status': 'trash',
        'trashedAt': '2026-06-12T10:00:00.000Z'
      },
      {
        r'$id': 't2',
        'productId': 'p2',
        'status': 'trash',
        'trashedAt': '2026-06-12T09:00:00.000Z'
      },
      {
        r'$id': 't3',
        'productId': 'p2',
        'status': 'trash',
        'trashedAt': '2026-06-12T11:00:00.000Z'
      },
    ];

    final visible = dedupeTrashForDisplay(trash, active);

    // p1 is active again → hidden; p2 collapses to the newest (t3).
    expect(visible.map((i) => i[r'$id']), ['t3']);
  });

  test('merge suggestions find near-duplicate product names', () {
    final products = [
      buildProductDocument({'displayName': 'Tomato'}, 'p1'),
      buildProductDocument({'displayName': 'Tomatos'}, 'p2'),
      buildProductDocument({'displayName': 'Milk'}, 'p3'),
    ];

    final suggestions = suggestProductMerges(products);

    expect(suggestions, hasLength(1));
    expect(suggestions[0]['sourceProductId'], 'p2');
    expect(suggestions[0]['targetProductId'], 'p1');
  });
}
