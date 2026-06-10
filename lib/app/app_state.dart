import 'package:flutter/widgets.dart';

import '../core/l10n/app_strings.dart';
import '../data/models/models.dart';

enum AppScreen { login, main }

/// How the working list is ordered (and, when grouping is on, what items are
/// bucketed by).
enum SortKey { name, category, brand, store }

/// A labelled bucket of items shown under a sub-header when grouping is on.
@immutable
class ItemGroup {
  const ItemGroup({required this.label, required this.items});
  final String label;
  final List<ListItem> items;
}

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
    this.suggestions = const [],
    this.filter = 'all',
    this.sellerFilter = 'all',
    this.sortKey = SortKey.name,
    this.grouped = false,
    this.presence = const [],
    this.activityRevision = 0,
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

  /// "Buy again" suggestions from bootstrap / `suggestItems` (Phase 2).
  final List<PurchaseSuggestion> suggestions;
  final String filter;

  /// Secondary "shop by store" filter: 'all' or a specific seller name. Applied
  /// on top of the category [filter] so the list can be narrowed to one store.
  final String sellerFilter;
  final SortKey sortKey;
  final bool grouped;

  /// Live "shopping now" presence rows for the visible owner list (Phase 3).
  /// Scratch state is no longer tracked here — it lives on each [ListItem]
  /// (`scratchExpiresAt`), so it survives restarts and propagates via realtime.
  final List<ShoppingPresence> presence;

  /// Monotonic counter bumped on every `list_events` realtime change so an open
  /// activity feed can refetch without holding its own subscription.
  final int activityRevision;

  AppStrings get t => AppStrings.of(lang);

  /// Presence rows for *other* people on the visible owner list — the input to
  /// the "shopping now" banner. Freshness is applied by the banner (it ticks),
  /// so a row lingering here until a realtime delete/refresh is harmless.
  List<ShoppingPresence> get othersShopping {
    final me = profile?.id;
    return presence
        .where((p) => p.actorId != me && (p.ownerId.isEmpty || p.ownerId == ownerId))
        .toList();
  }

  /// Buy-Again suggestions still worth showing: those whose product isn't
  /// already on the active list. (The backend excludes these too, but filtering
  /// here keeps the row correct the instant a suggestion is added or an item
  /// arrives via realtime.) Due staples float to the front.
  List<PurchaseSuggestion> get buyAgain {
    final active = {for (final i in items) i.productId};
    final shown = suggestions
        .where((s) => !active.contains(s.productId))
        .toList();
    shown.sort((a, b) {
      final byDue = (b.isDue ? 1 : 0) - (a.isDue ? 1 : 0);
      if (byDue != 0) return byDue;
      return b.purchaseCount.compareTo(a.purchaseCount);
    });
    return shown;
  }

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

  /// Lower-cased comparison value for the active [sortKey].
  String _sortValue(ListItem item) {
    final raw = switch (sortKey) {
      SortKey.name => productName(item.productId),
      SortKey.category => categoryById(item.categoryId)?.label(lang) ?? '',
      SortKey.brand => item.brand,
      SortKey.store => item.seller,
    };
    return raw.toLowerCase();
  }

  /// Sub-header label an item falls under when grouping by the active [sortKey].
  /// Names group by first letter; missing values fall into [AppStrings.ungrouped].
  String groupLabel(ListItem item) {
    switch (sortKey) {
      case SortKey.name:
        final name = productName(item.productId).trim();
        return name.isEmpty ? t.ungrouped : name.characters.first.toUpperCase();
      case SortKey.category:
        return categoryById(item.categoryId)?.label(lang) ?? t.ungrouped;
      case SortKey.brand:
        return item.brand.trim().isEmpty ? t.ungrouped : item.brand.trim();
      case SortKey.store:
        return item.seller.trim().isEmpty ? t.ungrouped : item.seller.trim();
    }
  }

  /// Important pinned to top, then the active sort key, then name as tiebreak.
  int _compareItems(ListItem a, ListItem b) {
    final byImportant = (b.important ? 1 : 0) - (a.important ? 1 : 0);
    if (byImportant != 0) return byImportant;
    final byKey = _sortValue(a).compareTo(_sortValue(b));
    if (byKey != 0) return byKey;
    return productName(
      a.productId,
    ).toLowerCase().compareTo(productName(b.productId).toLowerCase());
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

  /// Active items honouring the category filter only (before the seller filter
  /// and before sort/group).
  List<ListItem> get _categoryFilteredItems => filter == 'all'
      ? items
      : items.where((i) => i.categoryId == filter).toList();

  /// Item count of the current category view — the "All stores" chip count.
  int get categoryFilteredCount => _categoryFilteredItems.length;

  /// Distinct non-empty sellers in the current category view → item count.
  Map<String, int> get sellerCounts {
    final counts = <String, int>{};
    for (final item in _categoryFilteredItems) {
      final s = item.seller.trim();
      if (s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Stores present in the current category view, alphabetical.
  List<String> get visibleSellers =>
      sellerCounts.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// The active seller filter, ignored when its store is no longer present so a
  /// stale selection never leaves the user staring at an empty list.
  String get effectiveSellerFilter =>
      sellerFilter != 'all' && sellerCounts.containsKey(sellerFilter)
      ? sellerFilter
      : 'all';

  /// Active items honouring both the category and seller filters, before
  /// sort/group is applied.
  List<ListItem> get _filteredItems {
    final byCategory = _categoryFilteredItems;
    final seller = effectiveSellerFilter;
    if (seller == 'all') return byCategory;
    return byCategory.where((i) => i.seller.trim() == seller).toList();
  }

  /// Flat list ordered by the active sort key (important pinned to the top),
  /// with original insertion order as a stable final tiebreak.
  List<ListItem> get visibleItems {
    final base = _filteredItems;
    final indexed = [
      for (var i = 0; i < base.length; i++) (item: base[i], index: i),
    ];
    indexed.sort((a, b) {
      final byCompare = _compareItems(a.item, b.item);
      return byCompare != 0 ? byCompare : a.index - b.index;
    });
    return [for (final e in indexed) e.item];
  }

  /// Visible items bucketed under sub-headers by the active sort key. Groups are
  /// ordered alphabetically with [AppStrings.ungrouped] last; items inside a
  /// group keep important first, then name order.
  List<ItemGroup> get groupedVisibleItems {
    final buckets = <String, List<({ListItem item, int index})>>{};
    final base = _filteredItems;
    for (var i = 0; i < base.length; i++) {
      buckets
          .putIfAbsent(groupLabel(base[i]), () => [])
          .add((item: base[i], index: i));
    }
    final labels = buckets.keys.toList()
      ..sort((a, b) {
        if (a == t.ungrouped) return 1;
        if (b == t.ungrouped) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [
      for (final label in labels)
        ItemGroup(
          label: label,
          items: [
            for (final e in buckets[label]!
              ..sort((a, b) {
                final byImportant =
                    (b.item.important ? 1 : 0) - (a.item.important ? 1 : 0);
                if (byImportant != 0) return byImportant;
                final byName = productName(a.item.productId)
                    .toLowerCase()
                    .compareTo(productName(b.item.productId).toLowerCase());
                return byName != 0 ? byName : a.index - b.index;
              }))
              e.item,
          ],
        ),
    ];
  }

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
    List<PurchaseSuggestion>? suggestions,
    String? filter,
    String? sellerFilter,
    SortKey? sortKey,
    bool? grouped,
    List<ShoppingPresence>? presence,
    int? activityRevision,
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
      suggestions: suggestions ?? this.suggestions,
      filter: filter ?? this.filter,
      sellerFilter: sellerFilter ?? this.sellerFilter,
      sortKey: sortKey ?? this.sortKey,
      grouped: grouped ?? this.grouped,
      presence: presence ?? this.presence,
      activityRevision: activityRevision ?? this.activityRevision,
    );
  }

  static const Object _sentinel = Object();
}
