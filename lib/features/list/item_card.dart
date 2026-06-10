import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Compact, scannable shopping-list card. Tap scratches it (line-through +
/// countdown), long-press / right-click edits it. Important items get a reddish
/// tint and a leading dot. Mirrors the mockup `ItemCard`.
class ItemCard extends ConsumerWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.showBadge,
    required this.onEdit,
  });

  final ListItem item;
  final bool showBadge;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final lang = state.lang;
    final scratched = item.isScratched;
    final important = item.important && !scratched;
    final category = state.categoryById(item.categoryId);
    final unit = state.unitById(item.unitId);

    final meta = <String>[];
    if (item.count > 1 || unit != null) {
      meta.add(
        '${formatCount(item.count)}'
        '${unit != null ? ' ${unit.label(lang)}' : ''}',
      );
    }
    if (item.brand.isNotEmpty) meta.add(item.brand);
    if (item.seller.isNotEmpty) meta.add(item.seller);

    return GestureDetector(
      onTap: () => controller.toggleScratch(item.id),
      onLongPress: onEdit,
      onSecondaryTap: onEdit,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: scratched ? 0.55 : 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: important
                ? Color.alphaBlend(
                    c.error.withValues(alpha: 0.13),
                    c.surfaceContainer,
                  )
                : c.surfaceContainer,
            borderRadius: BorderRadius.circular(15),
            border: important
                ? Border.all(color: c.error.withValues(alpha: 0.3), width: 1.5)
                : null,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // Only real uploaded photos earn a thumbnail; the category
                    // pill already conveys the category, so no placeholder icon.
                    if (item.imageFileId != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: _ItemImage(item: item, size: 42),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (important) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: c.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  state.productName(item.productId),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.onSurface,
                                    decoration: scratched
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (meta.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                meta.join('  ·  '),
                                maxLines: 1,
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
                    const SizedBox(width: 8),
                    if (scratched)
                      _UndoButton(
                        label: state.t.undo,
                        onTap: () => controller.toggleScratch(item.id),
                      )
                    else if (showBadge && category != null)
                      _CategoryBadge(category: category, lang: lang),
                  ],
                ),
              ),
              if (scratched)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _CountdownBar(expiresAt: item.scratchExpiresAt),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a stored item image, resolving a short-lived tokenized view URL via
/// the repository (see [MoonaRepository.imageViewUrl]) so private images load on
/// mobile as well as web. Falls back to a branded icon while loading or on error.
class _ItemImage extends ConsumerStatefulWidget {
  const _ItemImage({required this.item, required this.size});

  final ListItem item;
  final double size;

  @override
  ConsumerState<_ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends ConsumerState<_ItemImage> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolve();
  }

  @override
  void didUpdateWidget(_ItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.imageFileId != widget.item.imageFileId ||
        oldWidget.item.id != widget.item.id) {
      _url = _resolve();
    }
  }

  Future<String?> _resolve() => ref
      .read(repositoryProvider)
      .imageViewUrl(itemId: widget.item.id, fileId: widget.item.imageFileId!);

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final fallback = MoonaIcon(
      'imageIcon',
      size: size * 0.42,
      color: Colors.white,
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9FD9B8), Color(0xFF6BBF8E)],
        ),
      ),
      alignment: Alignment.center,
      child: FutureBuilder<String?>(
        future: _url,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) return fallback;
          return Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
        },
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.lang});

  final ShopCategory category;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(category.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            category.label(lang),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.primary,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoonaIcon('undo', size: 17, color: c.onPrimary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.onPrimary,
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

/// Animated 3px countdown bar shown while an item is scratched. Derives its
/// remaining time from the backend's [expiresAt] so a viewer who joins mid-
/// scratch (or after a restart) sees the correct slice rather than a fresh 10s.
class _CountdownBar extends StatefulWidget {
  const _CountdownBar({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar>
    with SingleTickerProviderStateMixin {
  late final double _startFraction;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    const total = MoonaConfig.scratchWindow;
    final remaining =
        widget.expiresAt?.difference(DateTime.now()) ?? total;
    final clamped = remaining.isNegative ? Duration.zero : remaining;
    _startFraction = (clamped.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    _controller = AnimationController(vsync: this, duration: clamped)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: _startFraction * (1 - _controller.value),
        child: Container(height: 3, color: c.primary),
      ),
    );
  }
}
