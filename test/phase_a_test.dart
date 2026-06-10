import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';

ProviderContainer makeContainer() => ProviderContainer(
  overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
);

void main() {
  group('shop by seller', () {
    test('narrows the visible list to one store, with a safe fallback', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw'); // Noor — 7 items, 2 stores

      final base = container.read(appControllerProvider);
      expect(base.visibleSellers.length, 2); // كارفور + سمك اليوم
      expect(base.visibleItems.length, 7); // no seller filter yet

      controller.setSellerFilter('كارفور');
      final filtered = container.read(appControllerProvider);
      expect(filtered.effectiveSellerFilter, 'كارفور');
      expect(filtered.visibleItems.length, 1);
      expect(filtered.visibleItems.single.seller, 'كارفور');

      // A store that's no longer present falls back to "all" rather than
      // leaving the user staring at an empty list.
      controller.setSellerFilter('Ghost Mart');
      final stale = container.read(appControllerProvider);
      expect(stale.effectiveSellerFilter, 'all');
      expect(stale.visibleItems.length, 7);
    });

    test('seller bar reflects the active category filter', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw');

      // produce items are Tomatoes (كارفور) + Bananas (no store) → 1 store.
      controller.setFilter('produce');
      final state = container.read(appControllerProvider);
      expect(state.visibleSellers, ['كارفور']);
      expect(state.categoryFilteredCount, 2);
    });
  });

  test('bulk paste adds distinct items and skips duplicates', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw'); // 7 items incl. Milk

    final added = await controller.addItemsBulk(['Sugar', 'Pasta', 'Milk']);
    expect(added, 2); // Milk already on the list → skipped, batch not aborted
    expect(container.read(appControllerProvider).items.length, 9);
  });

  group('item attribution parsing', () {
    test('parses created/updated display names when present', () {
      final item = ListItem.fromJson({
        r'$id': 'x1',
        'ownerId': 'noor',
        'productId': 'p1',
        'count': 1,
        'important': false,
        'status': 'active',
        'createdByUserId': 'omar',
        'createdByDisplayName': 'Omar',
        'updatedByUserId': 'noor',
        'updatedByDisplayName': 'Noor',
      });
      expect(item.createdByUserId, 'omar');
      expect(item.createdByDisplayName, 'Omar');
      expect(item.updatedByDisplayName, 'Noor');
    });

    test('degrades to null before the backend enrichment lands', () {
      final item = ListItem.fromJson({
        r'$id': 'x2',
        'ownerId': 'noor',
        'productId': 'p1',
        'count': 1,
        'important': false,
        'status': 'active',
      });
      expect(item.createdByDisplayName, isNull);
      expect(item.updatedByDisplayName, isNull);
    });
  });
}
