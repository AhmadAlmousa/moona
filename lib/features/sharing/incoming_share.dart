import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Prompts the current user to accept or decline an incoming list share.
///
/// This flow is not in the prototype: `project.md` requires the target user to
/// permit sharing before being linked, so the request must surface here.
Future<void> showIncomingShareDialog(
  BuildContext context,
  WidgetRef ref,
  Share share,
) {
  final state = ref.read(appControllerProvider);
  final controller = ref.read(appControllerProvider.notifier);
  final t = state.t;
  final who = share.counterpartyName ?? state.nameFor(share.ownerId);

  return showMoonaDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: MoonaIcon('share', size: 30, color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            t.shareRequestTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.shareRequestBody(who),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          MoonaButton(
            label: t.accept,
            full: true,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.respondShare(share.id, accepted: true);
            },
          ),
          const SizedBox(height: 8),
          MoonaButton(
            label: t.decline,
            variant: MoonaButtonVariant.text,
            full: true,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.respondShare(share.id, accepted: false);
            },
          ),
        ],
      );
    },
  );
}
