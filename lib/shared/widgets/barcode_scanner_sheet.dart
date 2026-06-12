import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import 'buttons.dart';

/// Shows a fullscreen camera sheet that scans a barcode and calls [onScanned]
/// with the first decoded value, then auto-closes. Handles permission denial
/// and web-unsupported gracefully.
Future<void> showBarcodeScannerSheet(
  BuildContext context, {
  required AppStrings t,
  required void Function(String barcode) onScanned,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.black,
    barrierColor: Colors.black87,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _BarcodeScannerSheet(t: t, onScanned: onScanned),
  );
}

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet({required this.t, required this.onScanned});

  final AppStrings t;
  final void Function(String barcode) onScanned;

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _scanned = true;
    Navigator.of(context).pop();
    widget.onScanned(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;

    if (kIsWeb) {
      return _Unsupported(t: t);
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _ctrl,
          onDetect: _onDetect,
          errorBuilder: (ctx, error, child) => _PermissionDenied(t: t),
        ),
        // Tip overlay.
        Positioned(
          bottom: 32 + MediaQuery.viewPaddingOf(context).bottom,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                t.scanTip,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
        // Close button.
        PositionedDirectional(
          top: 12,
          end: 12,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.t});

  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 64, color: c.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            t.scannerNotSupported,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurface, fontSize: 16),
          ),
          const SizedBox(height: 20),
          MoonaButton(
            label: t.cancel,
            variant: MoonaButtonVariant.tonal,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.t});

  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            t.cameraDenied,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
