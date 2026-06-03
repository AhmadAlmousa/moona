import 'package:flutter/foundation.dart';

import '../core/l10n/app_strings.dart';
import '../data/models/models.dart';

enum AppScreen { login, main }

/// Single immutable snapshot of everything the signed-in UI renders.
@immutable
class AppState {
  const AppState({
    required this.screen,
    required this.lang,
    required this.dark,
    this.busy = false,
    this.loginError,
    this.profile,
    this.ownerId = '',
    this.isShared = false,
    this.items = const [],
    this.trash = const [],
    this.categories = const [],
    this.units = const [],
    this.products = const [],
    this.sharing = SharingStatus.empty,
    this.profileNames = const {},
    this.filter = 'all',
    this.scratched = const {},
  });

  final AppScreen screen;
  final String lang;
  final bool dark;
  final bool busy;
  final String? loginError;
  final Profile? profile;
  final String ownerId;
  final bool isShared;
  final List<ListItem> items;
  final List<ListItem> trash;
  final List<ShopCategory> categories;
  final List<Unit> units;
  final List<Product> products;
  final SharingStatus sharing;
  final Map<String, String> profileNames;
  final String filter;

  /// Ids currently scratched (line-through with a running countdown).
  final Set<String> scratched;

  AppStrings get t => AppStrings.of(lang);

  /// Resolves a user id to a display name using the bootstrap lookup, sharing
  /// counterparties, then a graceful fallback.
  String nameFor(String userId) {
    final byMap = profileNames[userId];
    if (byMap != null && byMap.isNotEmpty) return byMap;
    for (final share in [...sharing.outgoing, ...sharing.incoming]) {
      if ((share.viewerId == userId || share.ownerId == userId) &&
          (share.counterpartyName?.isNotEmpty ?? false)) {
        return share.counterpartyName!;
      }
    }
    return userId;
  }

  String get ownerName => isShared ? nameFor(ownerId) : '';

  ShopCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Unit? unitById(String? id) {
    if (id == null) return null;
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  String productName(String productId) {
    for (final p in products) {
      if (p.id == productId) return p.label(lang);
    }
    return '—';
  }

  /// Active items with important pinned to the top, otherwise insertion order.
  List<ListItem> get sortedItems {
    final indexed = [
      for (var i = 0; i < items.length; i++) (item: items[i], index: i),
    ];
    indexed.sort((a, b) {
      final byImportant =
          (b.item.important ? 1 : 0) - (a.item.important ? 1 : 0);
      return byImportant != 0 ? byImportant : a.index - b.index;
    });
    return [for (final e in indexed) e.item];
  }

  /// Category id → pending item count.
  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final item in items) {
      final id = item.categoryId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// Categories that currently have pending items, in catalog order.
  List<ShopCategory> get visibleCategories {
    final counts = categoryCounts;
    return categories.where((c) => counts.containsKey(c.id)).toList();
  }

  List<ListItem> get visibleItems => filter == 'all'
      ? sortedItems
      : sortedItems.where((i) => i.categoryId == filter).toList();

  List<ListItem> get sortedTrash {
    final sorted = List.of(trash);
    sorted.sort((a, b) {
      final at = a.trashedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.trashedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return sorted;
  }

  AppState copyWith({
    AppScreen? screen,
    String? lang,
    bool? dark,
    bool? busy,
    Object? loginError = _sentinel,
    Object? profile = _sentinel,
    String? ownerId,
    bool? isShared,
    List<ListItem>? items,
    List<ListItem>? trash,
    List<ShopCategory>? categories,
    List<Unit>? units,
    List<Product>? products,
    SharingStatus? sharing,
    Map<String, String>? profileNames,
    String? filter,
    Set<String>? scratched,
  }) {
    return AppState(
      screen: screen ?? this.screen,
      lang: lang ?? this.lang,
      dark: dark ?? this.dark,
      busy: busy ?? this.busy,
      loginError: loginError == _sentinel
          ? this.loginError
          : loginError as String?,
      profile: profile == _sentinel ? this.profile : profile as Profile?,
      ownerId: ownerId ?? this.ownerId,
      isShared: isShared ?? this.isShared,
      items: items ?? this.items,
      trash: trash ?? this.trash,
      categories: categories ?? this.categories,
      units: units ?? this.units,
      products: products ?? this.products,
      sharing: sharing ?? this.sharing,
      profileNames: profileNames ?? this.profileNames,
      filter: filter ?? this.filter,
      scratched: scratched ?? this.scratched,
    );
  }

  static const Object _sentinel = Object();
}
