import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
  );
  return container;
}

void main() {
  test('signIn loads the main screen with the owner list', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    await controller.signIn('966501112233', 'pw');

    final state = container.read(appControllerProvider);
    expect(state.screen, AppScreen.main);
    expect(state.items.length, 7);
    expect(state.lang, 'ar');
  });

  test('restores a persisted repository session on startup', () async {
    final repo = FakeMoonaRepository();
    await repo.signIn(phone: '966501112233', password: 'pw');
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    expect(container.read(appControllerProvider).screen, AppScreen.login);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final state = container.read(appControllerProvider);
    expect(state.screen, AppScreen.main);
    expect(state.profile?.phone, '966501112233');
    expect(state.items.length, 7);
  });

  test('addItem appends and rejects duplicates', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw');

    expect(
      await controller.addItem(const ItemFormData(productName: 'Sugar')),
      isTrue,
    );
    expect(container.read(appControllerProvider).items.length, 8);

    // Same product again is rejected.
    expect(
      await controller.addItem(const ItemFormData(productName: 'sugar')),
      isFalse,
    );
    expect(container.read(appControllerProvider).items.length, 8);
  });

  test('deleteItem moves an item to trash; restore brings it back', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw');
    final id = container.read(appControllerProvider).items.first.id;

    await controller.deleteItem(id);
    var state = container.read(appControllerProvider);
    expect(state.items.any((i) => i.id == id), isFalse);
    expect(state.trash.any((i) => i.id == id), isTrue);

    await controller.restoreItem(id);
    state = container.read(appControllerProvider);
    expect(state.items.any((i) => i.id == id), isTrue);
    expect(state.trash.any((i) => i.id == id), isFalse);
  });

  test('clearTrash empties the trash', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw');
    expect(container.read(appControllerProvider).trash, isNotEmpty);

    await controller.clearTrash();
    expect(container.read(appControllerProvider).trash, isEmpty);
  });

  test('toggleLang and toggleTheme update state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw');

    final wasDark = container.read(appControllerProvider).dark;
    controller.toggleLang();
    controller.toggleTheme();
    final state = container.read(appControllerProvider);
    expect(state.lang, 'en');
    expect(state.dark, !wasDark);
  });

  test(
    'requestShare to an existing user creates a pending outgoing share',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966552221133', 'pw'); // Layla, no shares

      await controller.requestShare('966507654321'); // Omar exists
      final outgoing = container.read(appControllerProvider).sharing.outgoing;
      expect(outgoing.any((s) => s.viewerId == 'omar'), isTrue);
    },
  );

  test('lookupContacts marks registered, self, and unknown numbers', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw'); // Noor

    final result = await controller.lookupContacts([
      '966507654321', // Omar — registered
      '0501112233', // Noor herself — registered + self
      '966550000000', // nobody
    ]);

    // Registered entries come first.
    expect(result.contacts.first.registered, isTrue);
    expect(result.registered.length, 2);
    expect(result.unregistered.length, 1);
    final self = result.contacts.firstWhere((e) => e.phoneDigits == '966501112233');
    expect(self.isSelf, isTrue);
    expect(self.displayName, 'Noor');
  });

  test('display-name gate: real name needs no prompt; default does', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    // Unknown number → fake repo seeds displayName == phone digits (a default).
    await controller.signIn('966500000999', 'pw');
    expect(controller.needsDisplayName, isTrue);

    await controller.setDisplayName('  Sara  ');
    expect(container.read(appControllerProvider).profile?.displayName, 'Sara');
    expect(controller.needsDisplayName, isFalse);
  });

  test('scratch commits the item to trash after the 10s window', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(appControllerProvider.notifier);

      controller.signIn('966501112233', 'pw');
      async.elapse(const Duration(seconds: 1));

      final id = container.read(appControllerProvider).items.first.id;
      controller.toggleScratch(id);
      expect(
        container.read(appControllerProvider).scratched.contains(id),
        isTrue,
      );

      async.elapse(const Duration(seconds: 11));
      final state = container.read(appControllerProvider);
      expect(state.scratched.contains(id), isFalse);
      expect(state.items.any((i) => i.id == id), isFalse);
      expect(state.trash.any((i) => i.id == id), isTrue);

      container.dispose();
    });
  });
}
