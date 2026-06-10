import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/data/models/models.dart';
import 'package:moona/features/widget/widget_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildWidgetPayload', () {
    const products = [
      Product(id: 'p_milk', displayName: 'Milk', nameAr: 'حليب', nameEn: 'Milk'),
      Product(id: 'p_apple', displayName: 'Apple', nameAr: 'تفاح', nameEn: 'Apple'),
      Product(id: 'p_bread', displayName: 'Bread', nameAr: 'خبز', nameEn: 'Bread'),
    ];
    const units = [Unit(id: 'u_btl', nameAr: 'زجاجة', nameEn: 'bottle')];

    ListItem item(
      String id,
      String productId, {
      bool important = false,
      double count = 1,
      String? unitId,
      String brand = '',
      String seller = '',
    }) => ListItem(
      id: id,
      ownerId: 'o',
      productId: productId,
      count: count,
      important: important,
      status: ItemStatus.active,
      unitId: unitId,
      brand: brand,
      seller: seller,
    );

    AppState state({
      String lang = 'en',
      bool dark = false,
      Set<String> scratched = const {},
      String filter = 'all',
    }) {
      final expiry = DateTime.now().add(const Duration(seconds: 10));
      ListItem mark(ListItem it) =>
          scratched.contains(it.id) ? it.copyWith(scratchExpiresAt: expiry) : it;
      return AppState(
        screen: AppScreen.main,
        lang: lang,
        dark: dark,
        products: products,
        units: units,
        items: [
          mark(item('i1', 'p_bread')),
          mark(item('i2', 'p_apple',
              important: true, count: 2, brand: 'Acme', seller: 'Mart')),
          mark(item('i3', 'p_milk', count: 1.5, unitId: 'u_btl')),
        ],
        filter: filter,
      );
    }

    test('pins important first, then alphabetical, with localized fields', () {
      final p = buildWidgetPayload(state());
      expect(p['lang'], 'en');
      expect(p['rtl'], false);
      expect(p['dark'], false);
      expect(p['title'], 'My list');

      final strings = p['strings'] as Map;
      expect(strings['undo'], 'Undo');
      expect(strings['empty'], 'Your list is empty');
      expect(strings['add'], 'Add item');
      expect(strings['details'], 'More details');

      final items = (p['items'] as List).cast<Map<String, dynamic>>();
      // Apple (important) pinned first, then Bread, then Milk.
      expect(items.map((e) => e['id']), ['i2', 'i1', 'i3']);
      expect(items[0]['important'], true);
      expect(items[0]['name'], 'Apple');
      expect(items[0]['brand'], 'Acme');
      expect(items[0]['store'], 'Mart');
      expect(items[0]['count'], '2');
      expect(items[2]['count'], '1.5 bottle');
    });

    test('marks scratched items', () {
      final items = (buildWidgetPayload(state(scratched: {'i3'}))['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(items.firstWhere((e) => e['id'] == 'i3')['scratched'], true);
      expect(items.firstWhere((e) => e['id'] == 'i1')['scratched'], false);
    });

    test('ignores the in-app category filter (always the full list)', () {
      final items = buildWidgetPayload(state(filter: 'some_category'))['items'] as List;
      expect(items.length, 3);
    });

    test('dark flag is carried for theming', () {
      expect(buildWidgetPayload(state(dark: true))['dark'], true);
    });

    test('arabic switches direction, title and names', () {
      final p = buildWidgetPayload(state(lang: 'ar'));
      expect(p['rtl'], true);
      expect(p['title'], 'قائمتي');
      final items = (p['items'] as List).cast<Map<String, dynamic>>();
      expect(items.first['important'], true); // تفاح still pinned to the top
      expect(items.map((e) => e['name']), containsAll(['تفاح', 'خبز', 'حليب']));
    });
  });

  group('moonaWidgetInteraction', () {
    const channel = MethodChannel('home_widget');
    late Map<String, Object?> store;
    late int updates;
    late bool repoCalled;

    setUp(() {
      store = {};
      updates = 0;
      repoCalled = false;
      // Keep the background-isolate path network-free: stub the repo runner so
      // it never instantiates a live Appwrite client during tests.
      debugWidgetRepoRunner = (_) async {
        repoCalled = true;
        return true;
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map?;
            switch (call.method) {
              case 'saveWidgetData':
                store[args!['id'] as String] = args['data'];
                return true;
              case 'getWidgetData':
                return store[args!['id'] as String] ?? args['defaultValue'];
              case 'updateWidget':
                updates++;
                return true;
            }
            return null;
          });
    });

    tearDown(() {
      debugWidgetRepoRunner = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('toggleDetail flips the stored flag and refreshes', () async {
      await moonaWidgetInteraction(Uri.parse('moona://toggledetail'));
      expect(store[MoonaWidget.detailKey], true);
      await moonaWidgetInteraction(Uri.parse('moona://toggledetail'));
      expect(store[MoonaWidget.detailKey], false);
      expect(updates, 2);
    });

    test('undo clears the scratched flag and commits undo server-side', () async {
      store[MoonaWidget.payloadKey] = jsonEncode({
        'items': [
          {'id': 'i1', 'name': 'Bread', 'scratched': true, 'scratchedAt': 123},
          {'id': 'i2', 'name': 'Milk', 'scratched': false},
        ],
      });

      await moonaWidgetInteraction(Uri.parse('moona://undo?id=i1'));

      final saved =
          jsonDecode(store[MoonaWidget.payloadKey] as String) as Map<String, dynamic>;
      final i1 = (saved['items'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['id'] == 'i1');
      expect(i1['scratched'], false);
      expect(i1.containsKey('scratchedAt'), false);
      expect(updates, greaterThanOrEqualTo(1));
      // Backend-owned scratch: undo must clear it server-side, not just locally.
      expect(repoCalled, isTrue);
    });
  });
}
