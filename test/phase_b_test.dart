import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';

ProviderContainer makeContainer() => ProviderContainer(
  overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
);

ListItem _active(String id, String productId) => ListItem(
  id: id,
  ownerId: 'me',
  productId: productId,
  count: 1,
  important: false,
  status: ItemStatus.active,
);

PurchaseSuggestion _suggestion(
  String productId, {
  int count = 1,
  double dueScore = 0,
}) => PurchaseSuggestion(
  productId: productId,
  productName: productId,
  purchaseCount: count,
  dueScore: dueScore,
);

void main() {
  group('Buy Again', () {
    test('bootstrap embeds suggestions excluding active products', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw'); // Noor

      final state = container.read(appControllerProvider);
      // Noor's trash holds Eggs, Yogurt, Apples, Salt — none currently active.
      expect(state.buyAgain.length, 4);
      // None of the suggestions is a product already on the active list.
      final activeProducts = {for (final i in state.items) i.productId};
      expect(
        state.buyAgain.every((s) => !activeProducts.contains(s.productId)),
        isTrue,
      );
    });

    test('addSuggestion adds the item and drops the suggestion', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw');

      final before = container.read(appControllerProvider);
      final itemsBefore = before.items.length;
      final eggs = before.buyAgain.firstWhere((s) => s.productName == 'Eggs');

      final ok = await controller.addSuggestion(eggs);
      expect(ok, isTrue);

      final after = container.read(appControllerProvider);
      expect(after.items.length, itemsBefore + 1);
      expect(after.buyAgain.any((s) => s.productId == eggs.productId), isFalse);
      expect(after.buyAgain.length, 3);
    });

    test('buyAgain floats due staples first and excludes active', () {
      final state = AppState(
        screen: AppScreen.main,
        lang: 'en',
        dark: false,
        items: [_active('i1', 'b')],
        suggestions: [
          _suggestion('a', count: 1, dueScore: 2), // due
          _suggestion('b', count: 9), // active → excluded
          _suggestion('c', count: 5), // not due, higher count
        ],
      );
      // 'b' is filtered out (already active); the due one ('a') leads.
      expect(state.buyAgain.map((s) => s.productId).toList(), ['a', 'c']);
    });
  });

  group('activity + insights repo', () {
    test('getActivity returns scratched events for the owner', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw');

      final page = await controller.loadActivity();
      expect(page, isNotNull);
      expect(page!.events.length, 4); // four trashed (scratched) rows
      expect(page.events.every((e) => e.type == ActivityType.scratched), isTrue);
      // Most recent first (Eggs was removed 4 minutes ago).
      expect(page.events.first.productName, 'Eggs');
      expect(page.events.first.actorDisplayName, 'Noor');
    });

    test('getInsights aggregates the scratch history', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw');

      final insights = await controller.loadInsights();
      expect(insights, isNotNull);
      expect(insights!.totalChecked, 4);
      expect(insights.distinctProducts, 4);
      // Eggs, Yogurt, Salt are grocery; Apples is produce.
      final grocery = insights.byCategory.firstWhere(
        (c) => c.categoryId == 'grocery',
      );
      expect(grocery.count, 3);
      expect(insights.byDayOfWeek.length, 7);
    });

    test('refreshSuggestions repopulates from the backend', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.signIn('966501112233', 'pw');

      await controller.refreshSuggestions();
      expect(container.read(appControllerProvider).suggestions, isNotEmpty);
    });
  });

  group('model parsing', () {
    test('PurchaseSuggestion parses names and cadence fields', () {
      final s = PurchaseSuggestion.fromJson({
        'productId': 'p1',
        'productName': 'Milk',
        'productNameAr': 'حليب',
        'productNameEn': 'Milk',
        'unitId': 'bottle',
        'categoryId': 'grocery',
        'purchaseCount': 4,
        'avgIntervalDays': 7,
        'lastPurchasedAt': '2026-06-01T12:00:00.000Z',
        'dueScore': 1.8,
      });
      expect(s.label('ar'), 'حليب');
      expect(s.label('en'), 'Milk');
      expect(s.purchaseCount, 4);
      expect(s.isDue, isTrue); // dueScore >= 1
    });

    test('isDue falls back to interval vs last purchase', () {
      final overdue = PurchaseSuggestion(
        productId: 'p',
        productName: 'Milk',
        avgIntervalDays: 5,
        lastPurchasedAt: DateTime.now().subtract(const Duration(days: 6)),
      );
      final fresh = PurchaseSuggestion(
        productId: 'p',
        productName: 'Milk',
        avgIntervalDays: 5,
        lastPurchasedAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(overdue.isDue, isTrue);
      expect(fresh.isDue, isFalse);
    });

    test('ActivityEvent maps known and unknown types', () {
      expect(
        ActivityEvent.fromJson({'type': 'share_accepted'}).type,
        ActivityType.shareAccepted,
      );
      expect(
        ActivityEvent.fromJson({'type': 'mystery'}).type,
        ActivityType.other,
      );
    });

    test('Insights normalizes byDayOfWeek to length 7', () {
      final short = Insights.fromJson({
        'totalChecked': 3,
        'byDayOfWeek': [1, 2],
      });
      expect(short.byDayOfWeek.length, 7);
      expect(short.byDayOfWeek[0], 1);
      expect(short.byDayOfWeek[2], 0);
      expect(short.isEmpty, isFalse);

      expect(const Insights().isEmpty, isTrue);
    });

    test('BootstrapData parses embedded suggestions.items', () {
      final data = BootstrapData.fromJson({
        'profile': {'userId': 'u1', 'phone': '966500000000'},
        'visibleList': {'ownerId': 'u1', 'isShared': false, 'items': [], 'trash': []},
        'catalogs': {'categories': [], 'units': [], 'products': []},
        'suggestions': {
          'items': [
            {'productId': 'p1', 'productName': 'Milk', 'purchaseCount': 2},
          ],
        },
      });
      expect(data.suggestions.length, 1);
      expect(data.suggestions.first.productName, 'Milk');
    });
  });
}
