import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';
import 'moona_icon.dart';

/// One entry in a [MoonaDropdown] menu.
class MoonaDropdownEntry<T> {
  const MoonaDropdownEntry({required this.value, required this.label});

  final T value;
  final String label;
}

/// Field-styled dropdown matching [MoonaField]: a rounded outlined box showing
/// the selected entry, that opens an anchored menu of [items] on tap.
class MoonaDropdown<T> extends StatelessWidget {
  const MoonaDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T value;
  final List<MoonaDropdownEntry<T>> items;
  final ValueChanged<T> onChanged;
  final String? hint;

  MoonaDropdownEntry<T>? get _selected {
    for (final e in items) {
      if (e.value == value) return e;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final c = context.c;
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + box.size.height + 6,
      overlay.size.width - (offset.dx + box.size.width),
      0,
    );

    // Key entries by index, not value: a null-valued entry (e.g. "None") would
    // be indistinguishable from a dismissal if values were returned directly.
    final picked = await showMenu<int>(
      context: context,
      position: position,
      color: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
      ),
      items: [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface,
                    ),
                  ),
                ),
                if (items[i].value == value)
                  MoonaIcon('check', size: 18, color: c.primary),
              ],
            ),
          ),
      ],
    );
    if (picked != null) onChanged(items[picked].value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = _selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.outlineVariant, width: 1.3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.label ?? hint ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: selected == null
                      ? c.onSurfaceVariant.withValues(alpha: 0.6)
                      : c.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MoonaIcon(
              'chevron',
              size: 18,
              color: c.onSurfaceVariant,
              turns: 1.5708,
            ),
          ],
        ),
      ),
    );
  }
}
