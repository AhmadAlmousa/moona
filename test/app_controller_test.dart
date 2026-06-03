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
