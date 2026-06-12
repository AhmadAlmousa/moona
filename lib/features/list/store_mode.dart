import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../sharing/presence_banner.dart';

/// What subset of the list a Shopping-mode session shops: everything, one store,
/// or one category — chosen from the entry picker.
@immutable
class StoreModeFilter {
  const StoreModeFilter({this.categoryId, this.seller});

  final String? categoryId;
  final String? seller;

  bool get isAll => categoryId == null && seller == null;
}

/// Opens Shopping mode. First shows a picker so the user can scope the trip to a
/// store or category (or shop everything), then pushes the focused screen. When
/// there is nothing to scope by, it goes straight in on "all".
Future<void> showStoreMode(BuildContext context, WidgetRef ref) async {
  final state = ref.read(appControllerProvider);
  if (state.items.isEmpty) return;

  final categories = state.visibleCategories;
  final sellers = _allSellers(state);

  // Nothing to scope by → skip the picker.
  if (categories.isEmpty && sellers.isEmpty) {
    _push(context, const StoreModeFilter());
    return;
  }

  await showMoonaSheet<void>(
    context: context,
    title: state.t.storeModePickTitle,
    builder: (sheetContext) => _StoreModePicker(
      state: state,
      categories: categories,
      sellers: sellers,
      onPick: (filter) {
        Navigator.of(sheetContext).pop();
        _push(context, filter);
      },
    ),
  );
}

void _push(BuildContext context, StoreModeFilter filter) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StoreModeScreen(filter: filter)),
  );
}

/// Distinct non-empty sellers across *all* active items (independent of the
/// on-screen category filter), with counts, alphabetical.
List<({String seller, int count})> _allSellers(AppState state) {
  final counts = <String, int>{};
  for (final item in state.items) {
    final s = item.seller.trim();
    if (s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
  }
  final sellers = counts.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final s in sellers) (seller: s, count: counts[s]!)];
}

/// The entry picker: "All items", then By store / By category sections.
class _StoreModePicker extends StatelessWidget {
  const _StoreModePicker({
    required this.state,
    required this.categories,
    required this.sellers,
    required this.onPick,
  });

  final AppState state;
  final List<ShopCategory> categories;
  final List<({String seller, int count})> sellers;
  final ValueChanged<StoreModeFilter> onPick;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: Text(
            t.storeModePickSub,
            style: TextStyle(fontSize: 13.5, color: context.c.onSurfaceVariant),
          ),
        ),
        _PickerRow(
          emoji: '🛒',
          label: t.allItems,
          count: state.items.length,
          onTap: () => onPick(const StoreModeFilter()),
        ),
        if (sellers.isNotEmpty) ...[
          _PickerSection(label: t.storeModeByStore),
          for (final s in sellers)
            _PickerRow(
              emoji: '🏪',
              label: s.seller,
              count: s.count,
              onTap: () => onPick(StoreModeFilter(seller: s.seller)),
            ),
        ],
        if (categories.isNotEmpty) ...[
          _PickerSection(label: t.storeModeByCategory),
          for (final cat in categories)
            _PickerRow(
              emoji: cat.emoji,
              label: cat.label(state.lang),
              count: state.categoryCounts[cat.id] ?? 0,
              onTap: () => onPick(StoreModeFilter(categoryId: cat.id)),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PickerSection extends StatelessWidget {
  const _PickerSection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 14, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: c.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.emoji,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.onSurface,
                ),
              ),
            ),
            Opacity(
              opacity: 0.6,
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen shopping companion: a compact two-column tile grid scoped to the
/// chosen store/category and ordered exactly like the main list. Tapping a tile
/// moves it into a "Collected" section (undoable for the whole trip); leaving —
/// via Finish or back — commits the collected items as purchased. The status bar
/// is hidden and the screen stays awake while shopping.
class StoreModeScreen extends ConsumerStatefulWidget {
  const StoreModeScreen({super.key, this.filter = const StoreModeFilter()});

  final StoreModeFilter filter;

  @override
  ConsumerState<StoreModeScreen> createState() => _StoreModeScreenState();
}

class _StoreModeScreenState extends ConsumerState<StoreModeScreen> {
  /// Active item ids in scope on entry — the progress denominator, so the bar
  /// advances monotonically. Items added mid-trip still appear and can be
  /// collected, they just don't move the bar.
  late final Set<String> _initialIds;

  /// Items checked off this trip. Local + session-only: they stay visible
  /// (struck-through) and undoable until the user leaves, then commit to trash.
  final Set<String> _collected = {};

  late final AppController _controller;
  Timer? _presenceTimer;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appControllerProvider.notifier);
    _initialIds = {
      for (final i in _scopedItems(ref.read(appControllerProvider))) i.id,
    };
    // Hide the status bar for a focused, edge-to-edge shopping surface.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _controller.setShoppingPresence(true);
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _controller.setShoppingPresence(true),
    );
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _controller.setShoppingPresence(false);
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  List<ListItem> _scopedItems(AppState state) => state.storeModeItems(
        categoryId: widget.filter.categoryId,
        seller: widget.filter.seller,
      );

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_collected.remove(id)) _collected.add(id);
    });
  }

  /// Commits collected items as purchased, then leaves. Guarded so the back
  /// gesture and the Finish button can't double-commit.
  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    final ids = _collected.toList();
    if (ids.isNotEmpty) await _controller.checkoutCollected(ids);
    if (mounted) Navigator.of(context).pop();
  }

  String _filterLabel(AppState state) {
    if (widget.filter.seller != null) return widget.filter.seller!;
    final categoryId = widget.filter.categoryId;
    if (categoryId != null) {
      return state.categoryById(categoryId)?.label(state.lang) ??
          state.t.storeMode;
    }
    return state.t.storeMode;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;

    final groups = state.storeModeGroups(
      categoryId: widget.filter.categoryId,
      seller: widget.filter.seller,
    );
    final collectedItems = [
      for (final i in _scopedItems(state))
        if (_collected.contains(i.id)) i,
    ];

    final total = _initialIds.length;
    final collected = _initialIds.where(_collected.contains).length;
    final progress = total == 0 ? 1.0 : collected / total;
    final done = total > 0 && collected >= total;

    // Build the scrollable body: scoped active tiles (minus collected) under
    // optional group headers, then a Collected section.
    final children = <Widget>[];
    for (final group in groups) {
      final pending = [
        for (final i in group.items)
          if (!_collected.contains(i.id)) i,
      ];
      if (pending.isEmpty) continue;
      if (group.label.isNotEmpty) children.add(_GroupHeader(label: group.label));
      children.addAll(_tileRows(state, pending, collected: false));
    }
    if (collectedItems.isNotEmpty) {
      children.add(_CollectedHeader(count: collectedItems.length, t: t));
      children.addAll(_tileRows(state, collectedItems, collected: true));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 6,
                  end: 16,
                  top: 6,
                  bottom: 4,
                ),
                child: Row(
                  children: [
                    MoonaIconButton(
                      icon: 'back',
                      size: 22,
                      dim: true,
                      onPressed: _exit,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filterLabel(state),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: c.onSurface,
                            ),
                          ),
                          Text(
                            done
                                ? t.storeModeDone
                                : t.storeModeOf(collected, total),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: c.surfaceContainerHighest,
                    color: c.primary,
                  ),
                ),
              ),
              const PresenceBanner(),
              Expanded(
                child: children.isEmpty
                    ? _DoneState(t: t)
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          2,
                          16,
                          24 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        children: [
                          ...children,
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              t.storeModeTapHint,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (_collected.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    6,
                    16,
                    10 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: MoonaButton(
                    label: t.storeModeFinishCount(_collected.length),
                    icon: 'check',
                    full: true,
                    onPressed: _exit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lays [items] out as rows of two equal-width tiles.
  List<Widget> _tileRows(
    AppState state,
    List<ListItem> items, {
    required bool collected,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tile(state, left, collected: collected)),
              const SizedBox(width: 10),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _tile(state, right, collected: collected),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  Widget _tile(AppState state, ListItem item, {required bool collected}) =>
      _StoreTile(
        title: state.productName(item.productId),
        meta: _metaFor(state, item),
        collected: collected,
        important: item.important && !collected,
        onTap: () => _toggle(item.id),
      );

  String _metaFor(AppState state, ListItem item) {
    final unit = state.unitById(item.unitId);
    final parts = <String>[
      if (item.count > 1 || unit != null)
        '${formatCount(item.count)}'
        '${unit != null ? ' ${unit.label(state.lang)}' : ''}',
      if (item.brand.isNotEmpty) item.brand,
      if (item.seller.isNotEmpty) item.seller,
    ];
    return parts.join('  ·  ');
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 8, bottom: 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: c.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CollectedHeader extends StatelessWidget {
  const _CollectedHeader({required this.count, required this.t});

  final int count;
  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 14, bottom: 8),
      child: Row(
        children: [
          MoonaIcon('check', size: 15, color: c.primary),
          const SizedBox(width: 7),
          Text(
            t.storeModeCollected,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: c.primary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: 0.6,
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: c.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact tappable tile. Tap to collect (dim + strike-through), tap again to
/// undo. No check-circle — the whole tile is the target.
class _StoreTile extends StatelessWidget {
  const _StoreTile({
    required this.title,
    required this.meta,
    required this.collected,
    required this.important,
    required this.onTap,
  });

  final String title;
  final String meta;
  final bool collected;
  final bool important;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tile = Material(
      color: important
          ? Color.alphaBlend(c.error.withValues(alpha: 0.12), c.surfaceContainer)
          : c.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: important
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: c.error.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: collected ? c.onSurfaceVariant : c.onSurface,
                  decoration: collected ? TextDecoration.lineThrough : null,
                  decorationThickness: 2,
                ),
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return collected ? Opacity(opacity: 0.55, child: tile) : tile;
  }
}

class _DoneState extends StatelessWidget {
  const _DoneState({required this.t});

  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(30),
            ),
            child: MoonaIcon('check', size: 48, color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Text(
            t.storeModeDone,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.storeModeDoneSub,
            style: TextStyle(fontSize: 14.5, color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
