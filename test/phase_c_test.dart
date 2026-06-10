import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';

ProviderContainer makeContainer() => ProviderContainer(
  overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
);

ListItem _active(String id, {DateTime? scratchExpiresAt}) => ListItem(
  id: id,
  ownerId: 'noor',
  productId: 'p_$id',
  count: 1,
  important: false,
  status: ItemStatus.active,
  scratchExpiresAt: scratchExpiresAt,
);

ShoppingPresence _presence(
  String actorId, {
  String ownerId = 'noor',
  String? name,
  Duration age = Duration.zero,
}) => ShoppingPresence(
  ownerId: ownerId,
  actorId: actorId,
  actorDisplayName: name,
  activeAt: DateTime.now().subtract(age),
);

void main() {
  group('backend-owned scratch (model + repo)', () {
    test('isScratched is derived from scratchExpiresAt', () {
      expect(_active('a').isScratched, isFalse);
      expect(
        _active(
          'a',
          scratchExpiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ).isScratched,
        isTrue,
      );
    });

    test('copyWith can set and clear scratch fields independently', () {
      final base = _active('a');
      final now = DateTime.now();
      final scratched = base.copyWith(
        scratchedAt: now,
        scratchExpiresAt: now.add(const Duration(seconds: 10)),
        scratchedByUserId: 'noor',
      );
      expect(scratched.isScratched, isTrue);
      expect(scratched.scratchedByUserId, 'noor');

      // Omitting a field keeps it; passing null clears it.
      final kept = scratched.copyWith(scratchedByUserId: 'omar');
      expect(kept.scratchExpiresAt, isNotNull);
      expect(kept.scratchedByUserId, 'omar');

      final cleared = scratched.copyWith(
        scratchedAt: null,
        scratchExpiresAt: null,
        scratchedByUserId: null,
      );
      expect(cleared.isScratched, isFalse);
      expect(cleared.scratchedByUserId, isNull);
    });

    test('fake repo scratchItem sets the window; finalize trashes it', () async {
      final repo = FakeMoonaRepository();
      await repo.signIn(phone: '966501112233', password: 'pw'); // Noor
      final id = (await repo.bootstrap()).visibleList.items.first.id;

      await repo.scratchItem(id, windowSeconds: 10);
      var item = (await repo.bootstrap()).visibleList.items.firstWhere(
        (i) => i.id == id,
      );
      expect(item.isScratched, isTrue);

      // Undo clears it.
      await repo.undoScratchItem(id);
      item = (await repo.bootstrap()).visibleList.items.firstWhere(
        (i) => i.id == id,
      );
      expect(item.isScratched, isFalse);

      // Re-scratch, then finalize → moved to trash with scratch_timer reason.
      await repo.scratchItem(id);
      await repo.finalizeScratch(id);
      final data = await repo.bootstrap();
      expect(data.visibleList.items.any((i) => i.id == id), isFalse);
      final trashed = data.visibleList.trash.firstWhere((i) => i.id == id);
      expect(trashed.trashReason, 'scratch_timer');
    });

    test('setShoppingPresence is a no-op on the fake repo', () async {
      final repo = FakeMoonaRepository();
      await repo.signIn(phone: '966501112233', password: 'pw');
      await repo.setShoppingPresence(active: true);
      await repo.setShoppingPresence(active: false); // must not throw
    });
  });

  group('presence model + state', () {
    test('ShoppingPresence parses and applies the 60s freshness window', () {
      final fresh = ShoppingPresence.fromJson({
        'ownerId': 'noor',
        'actorId': 'omar',
        'actorDisplayName': 'Omar',
        'activeAt': DateTime.now().toIso8601String(),
      });
      expect(fresh.actorDisplayName, 'Omar');
      expect(fresh.isFresh, isTrue);

      final stale = _presence('omar', age: const Duration(minutes: 5));
      expect(stale.isFresh, isFalse);

      // Falls back to updatedAt / $updatedAt when activeAt is absent.
      final viaUpdated = ShoppingPresence.fromJson({
        'ownerId': 'noor',
        'actorId': 'omar',
        r'$updatedAt': DateTime.now().toIso8601String(),
      });
      expect(viaUpdated.isFresh, isTrue);
    });

    test('othersShopping excludes self and other owner lists', () {
      final state = AppState(
        screen: AppScreen.main,
        lang: 'en',
        dark: false,
        ownerId: 'noor',
        profile: const Profile(
          id: 'noor',
          phone: '966501112233',
          displayName: 'Noor',
          language: 'en',
          theme: 'light',
        ),
        presence: [
          _presence('noor'), // me → excluded
          _presence('omar', name: 'Omar'), // other on my list → shown
          _presence('layla', ownerId: 'someoneElse'), // other list → excluded
        ],
      );
      final others = state.othersShopping.map((p) => p.actorId).toList();
      expect(others, ['omar']);
    });

    test('bootstrap parses shoppingPresence rows', () {
      final data = BootstrapData.fromJson({
        'profile': {'userId': 'noor', 'phone': '966501112233'},
        'visibleList': {
          'ownerId': 'noor',
          'isShared': false,
          'items': [],
          'trash': [],
        },
        'catalogs': {'categories': [], 'units': [], 'products': []},
        'shoppingPresence': [
          {'ownerId': 'noor', 'actorId': 'omar', 'activeAt': '2026-06-09T12:00:00.000Z'},
        ],
      });
      expect(data.shoppingPresence.length, 1);
      expect(data.shoppingPresence.first.actorId, 'omar');
    });
  });
}
