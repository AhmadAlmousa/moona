import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/app_state.dart';
import 'package:moona/data/models/models.dart';

ListItem item(String id, {bool important = false, String? category}) =>
    ListItem(
      id: id,
      ownerId: 'me',
      productId: 'p_$id',
      count: 1,
      important: important,
      status: ItemStatus.active,
      categoryId: category,
    );

void main() {
  const categories = [
    ShopCategory(
      id: 'grocery',
      nameAr: 'بقالة',
      nameEn: 'Grocery',
      emoji: '🛒',
    ),
    ShopCategory(id: 'meats', nameAr: 'لحوم', nameEn: 'Meats', emoji: '🥩'),
    ShopCategory(id: 'fish', nameAr: 'أسماك', nameEn: 'Fish', emoji: '🐟'),
  ];

  AppState stateWith(List<ListItem> items, {String filter = 'all'}) => AppState(
    screen: AppScreen.main,
    lang: 'en',
    dark: false,
    items: items,
    categories: categories,
    filter: filter,
  );

  test('important items are pinned to the top, others keep order', () {
    final state = stateWith([
      item('a', category: 'grocery'),
      item('b', category: 'meats'),
      item('c', important: true, category: 'fish'),
    ]);
    expect(state.visibleItems.map((i) => i.id).toList(), ['c', 'a', 'b']);
  });

  test('categoryCounts and visibleCategories ignore empty categories', () {
    final state = stateWith([
      item('a', category: 'grocery'),
      item('b', category: 'grocery'),
      item('c', category: 'meats'),
    ]);
    expect(state.categoryCounts, {'grocery': 2, 'meats': 1});
    // 'fish' has no items, so it must not appear.
    expect(state.visibleCategories.map((c) => c.id).toList(), [
      'grocery',
      'meats',
    ]);
  });

  test('visibleItems honors the selected category filter', () {
    final state = stateWith([
      item('a', category: 'grocery'),
      item('b', category: 'meats'),
    ], filter: 'meats');
    expect(state.visibleItems.map((i) => i.id).toList(), ['b']);
  });

  test('groupedVisibleItems buckets by category with Other last', () {
    final state =
        stateWith([
          item('a', category: 'grocery'),
          item('b', category: 'meats'),
          item('c', category: 'grocery'),
          item('d'),
        ]).copyWith(sortKey: SortKey.category, grouped: true);
    final groups = state.groupedVisibleItems;
    expect(groups.map((g) => g.label).toList(), ['Grocery', 'Meats', 'Other']);
    expect(groups.first.items.map((i) => i.id).toList(), ['a', 'c']);
    expect(groups.last.items.map((i) => i.id).toList(), ['d']);
  });

  test('nameFor falls back to the user id when unknown', () {
    final state = stateWith([]);
    expect(state.nameFor('ghost'), 'ghost');
  });
}
