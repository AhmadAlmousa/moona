import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Material-style outline icons, ported verbatim from the mockup `icons.jsx`.
///
/// Each entry is one or more SVG sub-paths separated by `|`. Icons are drawn as
/// strokes (no fill) and tinted at render time with a [ColorFilter], so the raw
/// SVG string is built once and reused across colors.
const Map<String, String> _iconPaths = {
  'settings':
      'M12 8a4 4 0 100 8 4 4 0 000-8zm0 6a2 2 0 110-4 2 2 0 010 4z|M19.4 13a7.8 7.8 0 000-2l2-1.6-2-3.4-2.4 1a7.6 7.6 0 00-1.7-1l-.4-2.5h-3.8l-.4 2.5c-.6.2-1.2.6-1.7 1l-2.4-1-2 3.4L4.6 11a7.8 7.8 0 000 2l-2 1.6 2 3.4 2.4-1c.5.4 1.1.8 1.7 1l.4 2.5h3.8l.4-2.5c.6-.2 1.2-.6 1.7-1l2.4 1 2-3.4L19.4 13z',
  'sun':
      'M12 7a5 5 0 100 10 5 5 0 000-10zm0 8a3 3 0 110-6 3 3 0 010 6zM12 1v3M12 20v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M1 12h3M20 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1',
  'moon': 'M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z',
  'globe':
      'M12 3a9 9 0 100 18 9 9 0 000-18zM3.6 9h16.8M3.6 15h16.8M12 3c2.5 2.5 2.5 15.5 0 18M12 3c-2.5 2.5-2.5 15.5 0 18',
  'logout': 'M15 4h3a2 2 0 012 2v12a2 2 0 01-2 2h-3M10 17l-5-5 5-5M5 12h12',
  'plus': 'M12 5v14M5 12h14',
  'search': 'M11 4a7 7 0 105 12 7 7 0 00-5-12zM21 21l-4.3-4.3',
  'close': 'M6 6l12 12M18 6L6 18',
  'check': 'M5 13l4 4 10-10',
  'trash':
      'M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13',
  'edit': 'M16.5 3.5a2.1 2.1 0 013 3L7 19l-4 1 1-4 12.5-12.5z',
  'camera':
      'M3 8a2 2 0 012-2h2l1.5-2h7L18 6h1a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V8z|M12 17a3.5 3.5 0 100-7 3.5 3.5 0 000 7z',
  'imageIcon':
      'M4 5a1 1 0 011-1h14a1 1 0 011 1v14a1 1 0 01-1 1H5a1 1 0 01-1-1V5z|M4 16l4-4 3 3 4-5 5 6M9 9.5a1.2 1.2 0 100-2.4 1.2 1.2 0 000 2.4z',
  'undo': 'M9 7L4 12l5 5M4 12h11a5 5 0 010 10h-3',
  'chevron': 'M9 6l6 6-6 6',
  'back': 'M15 6l-6 6 6 6',
  'share':
      'M8.6 13.5l6.8 4M15.4 6.5l-6.8 4M18 8a3 3 0 100-6 3 3 0 000 6zM6 15a3 3 0 100-6 3 3 0 000 6zM18 22a3 3 0 100-6 3 3 0 000 6z',
  'person': 'M12 12a4 4 0 100-8 4 4 0 000 8zM5 20a7 7 0 0114 0',
  'shield':
      'M12 3l8 3v5c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-3z|M8.5 12l2.5 2.5 4.5-4.5',
  'list': 'M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01',
  'tag': 'M3 11l8-8 9 9-8 8-9-9zM7.5 7.5h.01',
  'store': 'M4 9l1-4h14l1 4M5 9h14v10a1 1 0 01-1 1H6a1 1 0 01-1-1V9zM4 9h16',
  'sort': 'M4 6h13M4 12h8M4 18h4',
};

String _svgFor(String name, double strokeWidth) {
  final raw = _iconPaths[name] ?? '';
  final paths = raw
      .split('|')
      .map(
        (d) =>
            '<path d="$d" stroke="#000000" stroke-width="$strokeWidth" '
            'stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
      )
      .join();
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none">$paths</svg>';
}

/// A single Moona outline icon.
class MoonaIcon extends StatelessWidget {
  const MoonaIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.9,
    this.turns = 0,
  });

  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;

  /// Quarter-turn rotation (used to spin the chevron when expanded).
  final double turns;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurface;
    Widget svg = SvgPicture.string(
      _svgFor(name, strokeWidth),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
    if (turns != 0) {
      svg = Transform.rotate(angle: turns, child: svg);
    }
    return svg;
  }
}
