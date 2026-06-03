import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Opens the Trash sheet (scratched-off items, sorted newest first, with who
/// scratched them and when, plus restore / clear-all).
Future<void> showTrashSheet(BuildContext context) {
  final t = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appControllerProvider).t;
  return showMoonaSheet(
    context: context,
    title: t.completedTitle,
    builder: (_) => const _TrashList(),
  );
}

class _TrashList extends ConsumerWidget {
  const _TrashList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final items = state.sortedTrash;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: MoonaIcon('check', size: 38, color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              t.noCompleted,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.noCompletedSub,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MoonaButton(
            label: t.clearAll,
            icon: 'trash',
            variant: MoonaButtonVariant.text,
            danger: true,
            height: 38,
            onPressed: controller.clearTrash,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items) ...[
          _TrashRow(item: item),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.item});

  final ListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final lang = state.lang;
    final category = state.categoryById(item.categoryId);
    final unit = state.unitById(item.unitId);

    final who =
        item.trashedByDisplayName ??
        (item.trashedByUserId != null
            ? state.nameFor(item.trashedByUserId!)
            : null);
    final meta = <String>[t.completedAgo];
    if (item.trashedAt != null) meta.add(t.relTime(item.trashedAt!));
    if (who != null && who.isNotEmpty) meta.add(t.scratchedBy(who));
    if (item.count > 1 || unit != null) {
      meta.add(
        '${formatCount(item.count)}'
        '${unit != null ? ' ${unit.label(lang)}' : ''}',
      );
    }

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: 0.85,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                category?.emoji ?? '🛒',
                style: const TextStyle(fontSize: 23),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: 0.85,
                  child: Text(
                    state.productName(item.productId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.onSurface,
                      decoration: TextDecoration.lineThrough,
                      decorationThickness: 2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    meta.join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 10),
          _RestoreButton(
            label: t.restore,
            onTap: () => controller.restoreItem(item.id),
          ),
        ],
      ),
    );
  }
}

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.primaryContainer,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoonaIcon('undo', size: 16, color: c.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: c.onPrimaryContainer,
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
