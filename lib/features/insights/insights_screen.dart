import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Pushes the Insights screen.
void showInsights(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const InsightsScreen()));
}

const int _insightsRangeDays = 90;

/// Simple shopping insights over finalized scratch history: totals, most-bought
/// products, a category breakdown, and a day-of-week pattern. Backed by
/// `getInsights` (lazy — only fetched when this screen opens).
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  Insights? _insights;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final insights = await ref
        .read(appControllerProvider.notifier)
        .loadInsights(rangeDays: _insightsRangeDays);
    if (!mounted) return;
    setState(() {
      _insights = insights;
      _error = insights == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final insights = _insights;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 6,
                end: 16,
                top: 6,
                bottom: 6,
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
                          t.insights,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: c.onSurface,
                          ),
                        ),
                        Text(
                          t.insLastDays(_insightsRangeDays),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error
                  ? _InsightsError(t: t, onRetry: _load)
                  : (insights == null || insights.isEmpty)
                  ? _InsightsEmpty(t: t)
                  : _InsightsBody(state: state, insights: insights),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.state, required this.insights});

  final AppState state;
  final Insights insights;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        6,
        18,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '${insights.totalChecked}',
                label: t.insChecked,
                icon: 'check',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                value: '${insights.distinctProducts}',
                label: t.insDistinct,
                icon: 'list',
              ),
            ),
          ],
        ),
        if (insights.topProducts.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel(t.insTopProducts),
          const SizedBox(height: 10),
          _BarList(
            entries: [
              for (final p in insights.topProducts)
                _BarEntry(label: p.label(state.lang), count: p.count),
            ],
            countLabel: t.insTimes,
          ),
        ],
        if (insights.byCategory.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel(t.insByCategory),
          const SizedBox(height: 10),
          _BarList(
            entries: [
              for (final cat in insights.byCategory)
                _BarEntry(
                  label: state.categoryById(cat.categoryId)?.label(state.lang) ??
                      cat.categoryId,
                  emoji: state.categoryById(cat.categoryId)?.emoji,
                  count: cat.count,
                ),
            ],
            countLabel: t.insTimes,
          ),
        ],
        if (insights.byDayOfWeek.any((n) => n > 0)) ...[
          const SizedBox(height: 22),
          _SectionLabel(t.insByDay),
          const SizedBox(height: 12),
          _DayOfWeekChart(counts: insights.byDayOfWeek, labels: t.daysOfWeekShort),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoonaIcon(icon, size: 20, color: c.primary),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: c.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: c.primary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _BarEntry {
  const _BarEntry({required this.label, required this.count, this.emoji});
  final String label;
  final int count;
  final String? emoji;
}

/// A list of labelled horizontal bars, each scaled to the largest count.
class _BarList extends StatelessWidget {
  const _BarList({required this.entries, required this.countLabel});

  final List<_BarEntry> entries;
  final String Function(int) countLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final max = entries.fold<int>(1, (m, e) => e.count > m ? e.count : m);
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      if (e.emoji != null && e.emoji!.isNotEmpty) ...[
                        Text(e.emoji!, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 7),
                      ],
                      Expanded(
                        child: Text(
                          e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: c.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: e.count / max,
                      minHeight: 10,
                      backgroundColor: c.surfaceContainerHighest,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    countLabel(e.count),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A compact 7-column day-of-week bar chart (Sunday-first).
class _DayOfWeekChart extends StatelessWidget {
  const _DayOfWeekChart({required this.counts, required this.labels});

  final List<int> counts;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final max = counts.fold<int>(1, (m, n) => n > m ? n : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7 && i < counts.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (counts[i] > 0)
                    Text(
                      '${counts[i]}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 70 * (counts[i] / max) + 4,
                    decoration: BoxDecoration(
                      color: counts[i] > 0
                          ? c.primary
                          : c.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InsightsEmpty extends StatelessWidget {
  const _InsightsEmpty({required this.t});

  final AppStrings t;

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
              child: MoonaIcon('check', size: 44, color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              t.insEmpty,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.insEmptySub,
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

class _InsightsError extends StatelessWidget {
  const _InsightsError({required this.t, required this.onRetry});

  final AppStrings t;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.genericError,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          MoonaButton(
            label: t.retry,
            icon: 'undo',
            variant: MoonaButtonVariant.outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
