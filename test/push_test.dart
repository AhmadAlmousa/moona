import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/core/l10n/app_strings.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';
import 'package:moona/features/push/push_notifications.dart';

/// Records push-service calls so the controller's lifecycle wiring is observable
/// without any Firebase plugin (the default test provider is already the Noop).
class _RecordingPush implements PushNotifications {
  int registerCount = 0;
  int unregisterCount = 0;
  PushHandler? onForeground;
  PushHandler? onTap;

  @override
  Future<void> init({PushHandler? onForeground, PushHandler? onTap}) async {
    this.onForeground = onForeground;
    this.onTap = onTap;
  }

  @override
  Future<void> registerForSession() async => registerCount++;

  @override
  Future<void> unregister() async => unregisterCount++;
}

/// Counts `bootstrap()` calls so we can assert a push tap refreshes the list.
class _BootstrapCountingRepo extends FakeMoonaRepository {
  int bootstrapCount = 0;

  @override
  Future<BootstrapData> bootstrap() {
    bootstrapCount++;
    return super.bootstrap();
  }
}

void main() {
  test('Noop push service is inert', () async {
    const push = NoopPushNotifications();
    await push.init();
    await push.registerForSession();
    await push.unregister(); // must not throw
  });

  test('fake repo push-target methods are no-ops', () async {
    final repo = FakeMoonaRepository();
    expect(await repo.registerPushTarget('tok'), isNull);
    await repo.removePushTarget(); // must not throw
  });

  test('signIn registers a push target; logout unregisters it', () async {
    final push = _RecordingPush();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(FakeMoonaRepository()),
        pushProvider.overrideWithValue(push),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    await controller.signIn('966501112233', 'pw');
    await Future<void>.delayed(Duration.zero); // let the fire-and-forget run
    expect(push.registerCount, 1);
    expect(push.unregisterCount, 0);

    await controller.logout();
    expect(push.unregisterCount, 1);
  });

  test('restoring a session registers a push target', () async {
    final repo = FakeMoonaRepository();
    await repo.signIn(phone: '966501112233', password: 'pw');
    final push = _RecordingPush();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        pushProvider.overrideWithValue(push),
      ],
    );
    addTearDown(container.dispose);

    // Reading the provider instantiates it; build() kicks off session restore.
    expect(container.read(appControllerProvider).screen, AppScreen.login);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(container.read(appControllerProvider).screen, AppScreen.main);
    expect(push.registerCount, 1);
  });

  test('handlePushTap on the main screen refreshes the visible list', () async {
    final repo = _BootstrapCountingRepo();
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    await controller.signIn('966501112233', 'pw');
    final before = repo.bootstrapCount;
    controller.handlePushTap({'type': 'item_added'});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(repo.bootstrapCount, before + 1);
  });

  test('handlePushTap on the login screen is a no-op', () async {
    final repo = _BootstrapCountingRepo();
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    expect(container.read(appControllerProvider).screen, AppScreen.login);
    final before = repo.bootstrapCount;
    controller.handlePushTap({'type': 'item_added'});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(repo.bootstrapCount, before);
  });

  test('pushToastMessage maps types and falls back to the body', () async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.signIn('966501112233', 'pw'); // profile lang is 'ar'
    final t = AppStrings.of('ar');

    expect(
      controller.pushToastMessage({'type': 'share_requested'}),
      t.pushShareRequested,
    );
    expect(
      controller.pushToastMessage({'type': 'share_accepted'}),
      t.pushShareAccepted,
    );
    expect(controller.pushToastMessage({'type': 'item_added'}), t.pushItemAdded);
    expect(
      controller.pushToastMessage({'type': 'item_edited'}),
      t.pushItemEdited,
    );
    expect(
      controller.pushToastMessage({'type': 'shopping_started'}),
      t.pushShoppingStarted,
    );
    // Unknown type falls back to the notification body, or null when absent.
    expect(controller.pushToastMessage({'type': 'mystery', '_body': 'hi'}), 'hi');
    expect(controller.pushToastMessage({'type': 'mystery'}), isNull);
  });
}
