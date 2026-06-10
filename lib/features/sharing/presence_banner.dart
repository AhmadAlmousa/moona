import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';

/// A slim "Noor is shopping now" banner for the visible owner list. Renders
/// nothing unless another participant has a *fresh* shopping-presence heartbeat.
///
/// Presence rows linger in [AppState.presence] until a realtime delete/refresh,
/// so freshness is re-evaluated on a local ticker (the heartbeat refreshes
/// ~every 30s; rows older than 60s are treated as gone).
class PresenceBanner extends ConsumerStatefulWidget {
  const PresenceBanner({super.key});

  @override
  ConsumerState<PresenceBanner> createState() => _PresenceBannerState();
}

class _PresenceBannerState extends ConsumerState<PresenceBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final fresh = state.othersShopping.where((p) => p.isFresh).toList();
    if (fresh.isEmpty) return const SizedBox.shrink();

    final names = <String>{
      for (final p in fresh)
        (p.actorDisplayName != null && p.actorDisplayName!.isNotEmpty)
            ? p.actorDisplayName!
            : state.nameFor(p.actorId),
    }.toList();
    final label = names.length == 1
        ? state.t.someoneShoppingNow(names.first)
        : state.t.peopleShoppingNow(names.length);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _PulsingDot(color: c.primary),
            const SizedBox(width: 10),
            MoonaIcon('store', size: 16, color: c.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small dot that gently pulses to signal live activity.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0.3).animate(_controller),
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
