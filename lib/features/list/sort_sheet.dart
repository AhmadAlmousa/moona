import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';

/// Opens the "Sort by" sheet: pick the sort key and toggle grouping.
Future<void> showSortSheet(BuildContext context) {
  final t = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appControllerProvider).t;
  return showMoonaSheet(
    context: context,
    title: t.sortBy,
    builder: (_) => const _SortContent(),
  );
}

class _SortContent extends ConsumerWidget {
  const _SortContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;

    final options = <(SortKey, String)>[
      (SortKey.name, t.sortName),
      (SortKey.category, t.category),
      (SortKey.brand, t.brand),
      (SortKey.store, t.seller),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              SelectChip(
                label: option.$2,
                selected: state.sortKey == option.$1,
                onTap: () => controller.setSort(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 18),
        MoonaRow(
          onTap: controller.toggleGrouped,
          child: Row(
            children: [
              MoonaIcon('list', size: 22, color: c.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.grouped,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.onSurface,
                      ),
                    ),
                    Text(
                      t.groupedDesc,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MoonaSwitch(
                value: state.grouped,
                onChanged: (_) => controller.toggleGrouped(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
