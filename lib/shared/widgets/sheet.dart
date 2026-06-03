import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';
import 'buttons.dart';

/// Shows a Moona-styled bottom sheet (drag handle, optional title row with a
/// close button, scrollable padded body) that lifts above the keyboard.
Future<T?> showMoonaSheet<T>({
  required BuildContext context,
  String? title,
  required WidgetBuilder builder,
}) {
  final c = context.c;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surfaceLow,
    barrierColor: c.scrim,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.92,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _SheetScaffold(title: title, child: builder(ctx)),
  );
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: c.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 20,
                end: 14,
                top: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  MoonaIconButton(
                    icon: 'close',
                    dim: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a centered Moona dialog.
Future<T?> showMoonaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final c = context.c;
  return showDialog<T>(
    context: context,
    barrierColor: c.scrim,
    builder: (ctx) => Dialog(
      backgroundColor: c.surfaceContainerHigh,
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(padding: const EdgeInsets.all(24), child: builder(ctx)),
    ),
  );
}
