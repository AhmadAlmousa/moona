import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../sharing/contact_picker.dart';
import '../sharing/presence_banner.dart';
import '../sharing/settings_sheet.dart';
import '../trash/trash_sheet.dart';
import 'item_card.dart';
import 'item_form.dart';
import 'sort_sheet.dart';
import 'store_mode.dart';

/// The working shopping list — the app's primary screen.
class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final items = state.visibleItems;
    final showBadge =
        state.filter == 'all' &&
        !(state.grouped && state.sortKey == SortKey.category);
    final sharingActive =
        state.isShared ||
        state.sharing.acceptedOutgoing != null ||
        state.sharing.pendingIncoming.isNotEmpty;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final entries = <_ListEntry>[];
    if (state.grouped) {
      for (final group in state.groupedVisibleItems) {
        entries.add(_HeaderEntry(group.label, group.items.length));
        for (final item in group.items) {
          entries.add(_ItemEntry(item));
        }
      }
    } else {
      for (final item in items) {
        entries.add(_ItemEntry(item));
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  title: state.isShared
                      ? '${state.ownerName} · ${t.sharedListOf}'
                      : t.myList,
                  ownerLine: state.isShared
                      ? '${t.receivingFrom} ${state.ownerName}'
                      : null,
                  trashCount: state.trash.length,
                  sharingActive: sharingActive,
                  settingsBusy: state.busy,
                  hasItems: state.items.isNotEmpty,
                  shareTooltip: t.shareList,
                  storeModeTooltip: t.storeMode,
                  onStoreMode: () => showStoreMode(context),
                  onTrash: () => showTrashSheet(context),
                  onShare: () => showContactFlow(context, ref),
                  onSettings: () => showSettingsSheet(context),
                ),
                const PresenceBanner(),
                _FilterSortBar(
                  state: state,
                  onCategory: controller.setFilter,
                  onStore: controller.setSellerFilter,
                  onBuyAgainAdd: controller.addSuggestion,
                  onSort: () => showSortSheet(context),
                ),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyState(
                          t: t,
                          filtered: state.filter != 'all',
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            2,
                            16,
                            130 + bottomInset,
                          ),
                          itemCount: entries.length + 1,
                          itemBuilder: (context, index) {
                            if (index == entries.length) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 4,
                                ),
                                child: Center(
                                  child: Opacity(
                                    opacity: 0.7,
                                    child: Text(
                                      t.longPressHint,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: c.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return switch (entries[index]) {
                              _HeaderEntry(:final label, :final count) =>
                                _GroupHeader(
                                  label: label,
                                  count: count,
                                  first: index == 0,
                                ),
                              _ItemEntry(:final item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ItemCard(
                                  item: item,
                                  showBadge: showBadge,
                                  onEdit: () =>
                                      showItemForm(context, ref, editing: item),
                                ),
                              ),
                            };
                          },
                        ),
                ),
              ],
            ),
            // Curved arrow guiding new users to the FAB — shown only on a
            // genuinely empty list (no items at all, no active filter).
            if (state.items.isEmpty && state.filter == 'all')
              PositionedDirectional(
                bottom: 88 + bottomInset,
                end: 14,
                child: const _GuidingArrow(),
              ),
            PositionedDirectional(
              bottom: 22 + bottomInset,
              end: 20,
              child: _AddFab(
                label: t.addItem,
                onTap: () => showItemForm(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in the working list: either a group sub-header or an item.
sealed class _ListEntry {
  const _ListEntry();
}

class _HeaderEntry extends _ListEntry {
  const _HeaderEntry(this.label, this.count);
  final String label;
  final int count;
}

class _ItemEntry extends _ListEntry {
  const _ItemEntry(this.item);
  final ListItem item;
}

/// Sub-header shown above each group when grouping is on.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.first,
  });

  final String label;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 4,
        end: 4,
        top: first ? 4 : 18,
        bottom: 8,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: c.primary,
                letterSpacing: 0.4,
              ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.ownerLine,
    required this.trashCount,
    required this.sharingActive,
    required this.settingsBusy,
    required this.hasItems,
    required this.shareTooltip,
    required this.storeModeTooltip,
    required this.onStoreMode,
    required this.onTrash,
    required this.onShare,
    required this.onSettings,
  });

  final String title;
  final String? ownerLine;
  final int trashCount;
  final bool sharingActive;
  final bool settingsBusy;
  final bool hasItems;
  final String shareTooltip;
  final String storeModeTooltip;
  final VoidCallback onStoreMode;
  final VoidCallback onTrash;
  final VoidCallback onShare;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 10, top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: c.onSurface,
                  ),
                ),
                if (ownerLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoonaIcon('share', size: 13, color: c.primary),
                        const SizedBox(width: 5),
                        Text(
                          ownerLine!,
                          style: TextStyle(
                            fontSize: 12.5,
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
          if (hasItems)
            MoonaIconButton(
              icon: 'store',
              size: 20,
              dim: true,
              tooltip: storeModeTooltip,
              onPressed: onStoreMode,
            ),
          MoonaIconButton(
            icon: 'trash',
            size: 20,
            dim: true,
            badge: trashCount > 0,
            onPressed: onTrash,
          ),
          MoonaIconButton(
            icon: 'person',
            size: 20,
            dim: true,
            badge: sharingActive,
            tooltip: shareTooltip,
            onPressed: onShare,
          ),
          MoonaIconButton(
            icon: 'settings',
            size: 20,
            dim: true,
            loading: settingsBusy,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

// ── Filter + Sort bar ──────────────────────────────────────────────────────

/// Single-row bar containing compact dropdown pills for category, store, and
/// buy-again filters, plus the sort pill on the right. Replaces the separate
/// `_CategoryBar`, `_SellerBar`, `_BuyAgainBar`, and `_SortBar` widgets.
class _FilterSortBar extends StatelessWidget {
  const _FilterSortBar({
    required this.state,
    required this.onCategory,
    required this.onStore,
    required this.onBuyAgainAdd,
    required this.onSort,
  });

  final AppState state;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onStore;
  final ValueChanged<PurchaseSuggestion> onBuyAgainAdd;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final showStore = state.visibleSellers.length >= 2;
    final showBuyAgain = state.filter == 'all' && state.buyAgain.isNotEmpty;
    final showSort = state.items.isNotEmpty;

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 14,
        end: 14,
        top: 4,
        bottom: 8,
      ),
      child: Row(
        children: [
          _CategoryPill(state: state, t: t, onSelect: onCategory),
          if (showStore) ...[
            const SizedBox(width: 8),
            _StorePill(state: state, t: t, onSelect: onStore),
          ],
          if (showBuyAgain) ...[
            const SizedBox(width: 8),
            _BuyAgainPill(state: state, t: t, onAdd: onBuyAgainAdd),
          ],
          const Spacer(),
          if (showSort) ...[
            const SizedBox(width: 8),
            _SortPill(
              label: _sortLabel(t, state.sortKey),
              grouped: state.grouped,
              onTap: onSort,
            ),
          ],
        ],
      ),
    );
  }
}

String _sortLabel(AppStrings t, SortKey key) => switch (key) {
  SortKey.name => t.sortName,
  SortKey.category => t.category,
  SortKey.brand => t.brand,
  SortKey.store => t.seller,
};

/// Returns the position rect anchored just below a widget, for use with
/// [showMenu]. Must be called from the widget's own build context.
RelativeRect _pillMenuRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
  return RelativeRect.fromLTRB(
    offset.dx,
    offset.dy + box.size.height + 6,
    overlay.size.width - (offset.dx + box.size.width),
    0,
  );
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.state,
    required this.t,
    required this.onSelect,
  });

  final AppState state;
  final AppStrings t;
  final ValueChanged<String> onSelect;

  String get _label {
    if (state.filter == 'all') return t.allItems;
    for (final cat in state.visibleCategories) {
      if (cat.id == state.filter) return cat.label(state.lang);
    }
    return t.allItems;
  }

  Future<void> _openMenu(BuildContext context) async {
    final c = context.c;
    final rect = _pillMenuRect(context);
    final picked = await showMenu<String>(
      context: context,
      position: rect,
      color: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        _menuItem(context, 'all', t.allItems, null, state.filter == 'all'),
        for (final cat in state.visibleCategories)
          _menuItem(
            context,
            cat.id,
            cat.label(state.lang),
            cat.emoji,
            state.filter == cat.id,
          ),
      ],
    );
    if (picked != null) onSelect(picked);
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    String label,
    String? emoji,
    bool selected,
  ) {
    final c = context.c;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (emoji != null && emoji.isNotEmpty) ...[
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 9),
          ] else
            const SizedBox(width: 25),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.onSurface,
              ),
            ),
          ),
          if (selected) MoonaIcon('check', size: 18, color: c.primary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMenu(context),
      child: _PillShape(
        icon: 'tag',
        label: _label,
        active: state.filter != 'all',
      ),
    );
  }
}

class _StorePill extends StatelessWidget {
  const _StorePill({
    required this.state,
    required this.t,
    required this.onSelect,
  });

  final AppState state;
  final AppStrings t;
  final ValueChanged<String> onSelect;

  String get _label {
    final sel = state.effectiveSellerFilter;
    return sel == 'all' ? t.allStores : sel;
  }

  Future<void> _openMenu(BuildContext context) async {
    final c = context.c;
    final rect = _pillMenuRect(context);
    final sel = state.effectiveSellerFilter;
    final picked = await showMenu<String>(
      context: context,
      position: rect,
      color: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        _menuItem(context, 'all', t.allStores, '🏪', sel == 'all'),
        for (final seller in state.visibleSellers)
          _menuItem(context, seller, seller, null, sel == seller),
      ],
    );
    if (picked != null) onSelect(picked);
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    String label,
    String? emoji,
    bool selected,
  ) {
    final c = context.c;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (emoji != null && emoji.isNotEmpty) ...[
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 9),
          ] else
            const SizedBox(width: 25),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.onSurface,
              ),
            ),
          ),
          if (selected) MoonaIcon('check', size: 18, color: c.primary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMenu(context),
      child: _PillShape(
        icon: 'store',
        label: _label,
        active: state.effectiveSellerFilter != 'all',
      ),
    );
  }
}

class _BuyAgainPill extends StatelessWidget {
  const _BuyAgainPill({
    required this.state,
    required this.t,
    required this.onAdd,
  });

  final AppState state;
  final AppStrings t;
  final ValueChanged<PurchaseSuggestion> onAdd;

  Future<void> _openMenu(BuildContext context) async {
    final c = context.c;
    final rect = _pillMenuRect(context);
    final picked = await showMenu<PurchaseSuggestion>(
      context: context,
      position: rect,
      color: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (final s in state.buyAgain)
          PopupMenuItem<PurchaseSuggestion>(
            value: s,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                MoonaIcon('plus', size: 16, color: c.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.label(state.lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface,
                    ),
                  ),
                ),
                if (s.isDue) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      t.dueBadge,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: c.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    if (picked != null) onAdd(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMenu(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: ShapeDecoration(
          color: c.primaryContainer,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoonaIcon('undo', size: 15, color: c.onPrimaryContainer),
            const SizedBox(width: 6),
            Text(
              t.buyAgain,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: c.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${state.buyAgain.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: c.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            MoonaIcon(
              'chevron',
              size: 13,
              color: c.onPrimaryContainer,
              turns: math.pi / 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort pill — no dropdown, taps open the sort sheet.
class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.label,
    required this.grouped,
    required this.onTap,
  });

  final String label;
  final bool grouped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: c.outlineVariant, width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: SizedBox(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoonaIcon('sort', size: 16, color: c.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: c.onSurface,
                  ),
                ),
                if (grouped) ...[
                  const SizedBox(width: 7),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared visual shape for the category and store filter pills.
class _PillShape extends StatelessWidget {
  const _PillShape({
    required this.icon,
    required this.label,
    required this.active,
  });

  final String icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = active ? c.onPrimaryContainer : c.onSurface;
    final iconColor = active ? c.onPrimaryContainer : c.onSurfaceVariant;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: ShapeDecoration(
        color: active ? c.primaryContainer : Colors.transparent,
        shape: StadiumBorder(
          side: active
              ? BorderSide.none
              : BorderSide(color: c.outlineVariant, width: 1.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoonaIcon(icon, size: 15, color: iconColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 5),
          MoonaIcon(
            'chevron',
            size: 13,
            color: iconColor,
            turns: math.pi / 2,
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.t, required this.filtered});

  final AppStrings t;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceContainer,
                borderRadius: BorderRadius.circular(30),
              ),
              child: MoonaIcon(
                filtered ? 'search' : 'list',
                size: 46,
                color: c.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? t.emptyCatTitle : t.emptyTitle,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered ? t.emptyCatSub : t.emptySub,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Guiding arrow ──────────────────────────────────────────────────────────

/// Transparent curved arrow overlaid near the FAB on an empty list, guiding
/// the user toward the "Add item" button without adding a second button.
class _GuidingArrow extends StatelessWidget {
  const _GuidingArrow();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: 0.38,
      child: SizedBox(
        width: 86,
        height: 86,
        child: CustomPaint(painter: _CurvedArrowPainter(color: c.primary)),
      ),
    );
  }
}

class _CurvedArrowPainter extends CustomPainter {
  const _CurvedArrowPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Cubic bezier curving from top area toward bottom-right (FAB corner).
    final p0 = Offset(w * 0.16, h * 0.08);
    final p1 = Offset(w * 0.05, h * 0.65); // pulls curve left-and-down
    final p2 = Offset(w * 0.66, h * 0.84); // approaches the endpoint
    final p3 = Offset(w * 0.86, h * 0.78); // tip of arrow

    canvas.drawPath(
      Path()..moveTo(p0.dx, p0.dy)..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy),
      paint,
    );

    // Arrowhead: two lines at p3, rotated ±145° from the tangent at t=1.
    // Tangent direction at t=1 is proportional to (p3 - p2).
    final tdx = p3.dx - p2.dx;
    final tdy = p3.dy - p2.dy;
    final tlen = math.sqrt(tdx * tdx + tdy * tdy);
    final ux = tdx / tlen;
    final uy = tdy / tlen;

    const arrowLen = 9.0;
    for (final angle in const [-2.53, 2.53]) {
      // ±145° in radians ≈ ±2.53
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      canvas.drawLine(
        p3,
        Offset(p3.dx + arrowLen * (cos * ux - sin * uy), p3.dy + arrowLen * (sin * ux + cos * uy)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvedArrowPainter old) => old.color != color;
}

// ── FAB ───────────────────────────────────────────────────────────────────

class _AddFab extends StatelessWidget {
  const _AddFab({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.primary,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoonaIcon('plus', size: 24, color: c.onPrimary),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: c.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
