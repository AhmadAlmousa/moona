import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';

ProviderContainer makeContainer(FakeMoonaRepository repo) =>
    ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);

void main() {
  group('admin models', () {
    test('Profile.isAdmin parses true / false / absent', () {
      expect(
        Profile.fromJson({'userId': 'a', 'isAdmin': true}).isAdmin,
        isTrue,
      );
      expect(
        Profile.fromJson({'userId': 'a', 'isAdmin': false}).isAdmin,
        isFalse,
      );
      expect(Profile.fromJson({'userId': 'a'}).isAdmin, isFalse);
    });

    test('BootstrapData parses brand/store catalogs', () {
      final data = BootstrapData.fromJson({
        'profile': {'userId': 'a', 'language': 'en', 'theme': 'light'},
        'visibleList': {
          'ownerId': 'a',
          'isShared': false,
          'items': [],
          'trash': [],
        },
        'catalogs': {
          'brands': [
            {r'$id': 'b1', 'name': 'Almarai', 'active': true},
          ],
          'stores': [
            {r'$id': 's1', 'name': 'Danube', 'active': true},
          ],
        },
      });
      expect(data.brands.single.name, 'Almarai');
      expect(data.stores.single.name, 'Danube');
    });
  });

  group('FakeMoonaRepository admin', () {
    test('signed-in demo user is admin; bootstrap carries brand/store lists',
        () async {
      final container = makeContainer(FakeMoonaRepository());
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);

      await controller.signIn('966501112233', 'pw'); // noor (demo admin)

      final state = container.read(appControllerProvider);
      expect(state.profile?.isAdmin, isTrue);
      expect(state.brands, isNotEmpty);
      expect(state.stores, isNotEmpty);
    });

    test('adminList(users) reports the admin flag', () async {
      final repo = FakeMoonaRepository();
      await repo.signIn(phone: '966501112233', password: 'pw');

      final users = await repo.adminList('users');
      final noor = users.firstWhere((u) => u['userId'] == 'noor');
      expect(noor['isAdmin'], isTrue);
    });

    test('adminResetUser clears items and shares but keeps the account',
        () async {
      final repo = FakeMoonaRepository();
      await repo.signIn(phone: '966501112233', password: 'pw'); // noor
      expect((await repo.bootstrap()).visibleList.items, isNotEmpty);

      final res = await repo.adminResetUser('noor');
      expect((res['items'] as num) > 0, isTrue);

      expect((await repo.bootstrap()).visibleList.items, isEmpty);
      expect(
        (await repo.adminList('users')).map((u) => u['userId']),
        contains('noor'),
      );
    });

    test('brands create + list + delete round-trip', () async {
      final repo = FakeMoonaRepository();
      final before = (await repo.adminList('brands')).length;

      await repo.adminCreate('brands', {'name': 'Test Brand'});
      final after = await repo.adminList('brands');
      expect(after.length, before + 1);

      final created = after.firstWhere((b) => b['name'] == 'Test Brand');
      await repo.adminDelete('brands', created[r'$id'].toString());
      expect(
        (await repo.adminList('brands')).any((b) => b['name'] == 'Test Brand'),
        isFalse,
      );
    });

    test('promoting a user via adminUpdate flips isAdmin', () async {
      final repo = FakeMoonaRepository();
      await repo.adminUpdate('users', 'omar', {'isAdmin': true});

      final omar = (await repo.adminList('users')).firstWhere(
        (u) => u['userId'] == 'omar',
      );
      expect(omar['isAdmin'], isTrue);
    });
  });
}
