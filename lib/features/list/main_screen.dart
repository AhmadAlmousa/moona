import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../sharing/contact_picker.dart';
import '../sharing/settings_sheet.dart';
import '../trash/trash_sheet.dart';
import 'item_card.dart';
import 'item_form.dart';
import 'sort_sheet.dart';

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
    // Grouping by category already labels each section, so the per-card badge
    // would be redundant there.
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
                  grouped: state.grouped,
                  settingsBusy: state.busy,
                  shareTooltip: t.shareList,
                  onSort: () => showSortSheet(context),
                  onTrash: () => showTrashSheet(context),
                  onShare: () => showContactFlow(context, ref),
                  onSettings: () => showSettingsSheet(context),
                ),
                _CategoryBar(state: state, onSelect: controller.setFilter),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyState(
                          t: t,
                          filtered: state.filter != 'all',
                          onAdd: () => showItemForm(context, ref),
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
    required this.grouped,
    required this.settingsBusy,
    required this.shareTooltip,
    required this.onSort,
    required this.onTrash,
    required this.onShare,
    required this.onSettings,
  });

  final String title;
  final String? ownerLine;
  final int trashCount;
  final bool sharingActive;
  final bool grouped;
  final bool settingsBusy;
  final String shareTooltip;
  final VoidCallback onSort;
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
          MoonaIconButton(
            icon: 'sort',
            size: 20,
            dim: true,
            badge: grouped,
            onPressed: onSort,
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

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.state, required this.onSelect});

  final AppState state;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final counts = state.categoryCounts;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
        children: [
          CategoryChip(
            label: t.allItems,
            count: state.items.length,
            selected: state.filter == 'all',
            onTap: () => onSelect('all'),
          ),
          for (final category in state.visibleCategories) ...[
            const SizedBox(width: 9),
            CategoryChip(
              label: category.label(state.lang),
              emoji: category.emoji,
              count: counts[category.id] ?? 0,
              selected: state.filter == category.id,
              onTap: () => onSelect(category.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.t,
    required this.filtered,
    required this.onAdd,
  });

  final AppStrings t;
  final bool filtered;
  final VoidCallback onAdd;

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
            if (!filtered) ...[
              const SizedBox(height: 14),
              MoonaButton(label: t.addItem, icon: 'plus', onPressed: onAdd),
            ],
          ],
        ),
      ),
    );
  }
}

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
