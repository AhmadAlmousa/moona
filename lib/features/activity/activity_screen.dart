import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Pushes the activity feed screen.
void showActivity(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ActivityScreen()));
}

/// A recent-activity feed for the visible owner list: who added, edited,
/// checked off, restored, cleared, or joined/left. Backed by `getActivity`
/// (paginated) and refreshed live via the `activityRevision` signal.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final List<ActivityEvent> _events = [];
  final Map<String, String> _names = {};
  String _cursor = '';
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = false;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final page = await ref
        .read(appControllerProvider.notifier)
        .loadActivity(cursor: reset ? null : _cursor);

    if (!mounted) return;
    setState(() {
      if (page == null) {
        _error = reset;
      } else {
        if (reset) _events.clear();
        _events.addAll(page.events);
        _names.addAll(page.profileNames);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = false;
      }
      _loading = false;
      _loadingMore = false;
    });
  }

  /// Resolves the actor's display name: the snapshot on the event, then the
  /// page's profiles lookup, then the app's shared-name fallback.
  String _actorName(AppState state, ActivityEvent e) {
    final snapshot = e.actorDisplayName;
    if (snapshot != null && snapshot.isNotEmpty) return snapshot;
    final mapped = _names[e.actorId];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    return state.nameFor(e.actorId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;

    // Refetch the first page whenever a list_events realtime change arrives.
    ref.listen(appControllerProvider.select((s) => s.activityRevision), (_, _) {
      if (mounted) _load(reset: true);
    });

    final rows = _events
        .where((e) => e.type != ActivityType.other)
        .toList();

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
                    child: Text(
                      t.activity,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: c.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error
                  ? _ErrorState(t: t, onRetry: () => _load(reset: true))
                  : rows.isEmpty
                  ? _ActivityEmpty(t: t)
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          20 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: rows.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == rows.length) {
                            return _LoadMore(
                              label: t.loadMore,
                              busy: _loadingMore,
                              onTap: () => _load(reset: false),
                            );
                          }
                          final e = rows[index];
                          return _ActivityTile(
                            event: e,
                            text: _lineFor(t, _actorName(state, e), e),
                            time: e.createdAt == null
                                ? ''
                                : t.relTime(e.createdAt!),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _lineFor(AppStrings t, String who, ActivityEvent e) {
    final what = e.label(state.lang);
    return switch (e.type) {
      ActivityType.added => t.actAdded(who, what),
      ActivityType.edited => t.actEdited(who, what),
      ActivityType.scratched => t.actScratched(who, what),
      ActivityType.deleted => t.actDeleted(who, what),
      ActivityType.restored => t.actRestored(who, what),
      ActivityType.cleared => t.actCleared(who, e.clearedCount),
      ActivityType.shareAccepted => t.actShareAccepted(who),
      ActivityType.shareRevoked => t.actShareRevoked(who),
      ActivityType.other => who,
    };
  }

  AppState get state => ref.read(appControllerProvider);
}

String _iconFor(ActivityType type) => switch (type) {
  ActivityType.added => 'plus',
  ActivityType.edited => 'edit',
  ActivityType.scratched => 'check',
  ActivityType.deleted => 'trash',
  ActivityType.restored => 'undo',
  ActivityType.cleared => 'trash',
  ActivityType.shareAccepted => 'person',
  ActivityType.shareRevoked => 'person',
  ActivityType.other => 'list',
};

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.event,
    required this.text,
    required this.time,
  });

  final ActivityEvent event;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: MoonaIcon(
              _iconFor(event.type),
              size: 18,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: c.onSurface,
                ),
              ),
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : MoonaButton(
                label: label,
                variant: MoonaButtonVariant.outlined,
                height: 40,
                onPressed: onTap,
              ),
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({required this.t});

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
              child: MoonaIcon('list', size: 44, color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              t.activityEmpty,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.activityEmptySub,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.t, required this.onRetry});

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
