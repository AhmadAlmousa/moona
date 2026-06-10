import 'dart:async';

import 'package:flutter/material.dart';
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

/// Pushes the focused in-store "Shopping mode" screen.
void showStoreMode(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const StoreModeScreen()));
}

/// A labelled, category-grouped bucket rendered in Shopping mode.
class _StoreGroup {
  const _StoreGroup({required this.label, required this.emoji, required this.items});
  final String label;
  final String emoji;
  final List<ListItem> items;
}

/// Full-screen shopping companion: the working list grouped by category with
/// big tap targets, a check-off-as-you-go flow (reusing the scratch timer), a
/// progress bar, and a screen that stays awake while you shop.
class StoreModeScreen extends ConsumerStatefulWidget {
  const StoreModeScreen({super.key});

  @override
  ConsumerState<StoreModeScreen> createState() => _StoreModeScreenState();
}

class _StoreModeScreenState extends ConsumerState<StoreModeScreen> {
  /// Active item ids captured on entry — the progress denominator, so the bar
  /// counts down monotonically. Items added mid-run still appear and can be
  /// checked, they just don't move the bar.
  late final Set<String> _initialIds;

  late final AppController _controller;

  /// Broadcasts this device's "shopping now" presence while the screen is open,
  /// refreshing it well inside the 60s staleness window other devices apply.
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appControllerProvider.notifier);
    _initialIds = {
      for (final i in ref.read(appControllerProvider).items) i.id,
    };
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
    super.dispose();
  }

  int _compare(AppState state, ListItem a, ListItem b) {
    final byImportant = (b.important ? 1 : 0) - (a.important ? 1 : 0);
    if (byImportant != 0) return byImportant;
    return state
        .productName(a.productId)
        .toLowerCase()
        .compareTo(state.productName(b.productId).toLowerCase());
  }

  List<_StoreGroup> _groups(AppState state) {
    final byCategory = <String?, List<ListItem>>{};
    for (final item in state.items) {
      byCategory.putIfAbsent(item.categoryId, () => []).add(item);
    }
    final known = {for (final c in state.categories) c.id};
    final groups = <_StoreGroup>[];
    for (final category in state.categories) {
      final items = byCategory[category.id];
      if (items == null || items.isEmpty) continue;
      items.sort((a, b) => _compare(state, a, b));
      groups.add(
        _StoreGroup(
          label: category.label(state.lang),
          emoji: category.emoji,
          items: items,
        ),
      );
    }
    final ungrouped = <ListItem>[
      for (final entry in byCategory.entries)
        if (entry.key == null || !known.contains(entry.key)) ...entry.value,
    ]..sort((a, b) => _compare(state, a, b));
    if (ungrouped.isNotEmpty) {
      groups.add(
        _StoreGroup(label: state.t.ungrouped, emoji: '🛒', items: ungrouped),
      );
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final groups = _groups(state);

    final total = _initialIds.length;
    final activeUnscratched = {
      for (final i in state.items)
        if (!i.isScratched) i.id,
    };
    final remaining = _initialIds.where(activeUnscratched.contains).length;
    final collected = total - remaining;
    final progress = total == 0 ? 1.0 : collected / total;
    final done = total > 0 && remaining == 0;

    return Scaffold(
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
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.storeMode,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: c.onSurface,
                          ),
                        ),
                        Text(
                          done ? t.storeModeDone : t.storeModeOf(collected, total),
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
              child: groups.isEmpty
                  ? _DoneState(t: t)
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        2,
                        16,
                        24 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      children: [
                        for (final group in groups) ...[
                          _GroupHeader(group: group),
                          for (final item in group.items)
                            _StoreRow(
                              item: item,
                              checked: item.isScratched,
                              title: state.productName(item.productId),
                              meta: _metaFor(state, item),
                              onTap: () => controller.toggleScratch(item.id),
                            ),
                        ],
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
          ],
        ),
      ),
    );
  }

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
  const _GroupHeader({required this.group});

  final _StoreGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 14, bottom: 8),
      child: Row(
        children: [
          Text(group.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: c.primary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: 0.6,
            child: Text(
              '${group.items.length}',
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

/// A large, tappable store row with a leading check circle. Tap to check off
/// (strike-through + the shared scratch countdown), tap again to undo.
class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.item,
    required this.checked,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final ListItem item;
  final bool checked;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final important = item.important && !checked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: important
            ? Color.alphaBlend(c.error.withValues(alpha: 0.12), c.surfaceContainer)
            : c.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: important
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: c.error.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  )
                : null,
            child: Row(
              children: [
                _CheckCircle(checked: checked),
                const SizedBox(width: 14),
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
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          color: checked ? c.onSurfaceVariant : c.onSurface,
                          decoration: checked ? TextDecoration.lineThrough : null,
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
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? c.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: checked ? null : Border.all(color: c.outline, width: 2),
      ),
      child: checked
          ? MoonaIcon('check', size: 18, color: c.onPrimary)
          : const SizedBox.shrink(),
    );
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
