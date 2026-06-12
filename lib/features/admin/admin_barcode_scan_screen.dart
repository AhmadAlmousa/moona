import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';
import 'admin_screen.dart';

/// Two-tab admin screen: Scan a barcode to define/edit a product, or review
/// the pending submission queue.
class AdminBarcodeScanScreen extends ConsumerStatefulWidget {
  const AdminBarcodeScanScreen({super.key});

  @override
  ConsumerState<AdminBarcodeScanScreen> createState() =>
      _AdminBarcodeScanScreenState();
}

class _AdminBarcodeScanScreenState
    extends ConsumerState<AdminBarcodeScanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    return AdminScaffold(
      title: t.barcodeScanner,
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: [Tab(text: t.scanTab), Tab(text: t.queueTab)],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ScanTab(onSwitchToQueue: () => _tabs.animateTo(1)),
                _QueueTab(onDefine: (barcode) {
                  _tabs.animateTo(0);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan tab ────────────────────────────────────────────────────────────────

class _ScanTab extends ConsumerStatefulWidget {
  const _ScanTab({required this.onSwitchToQueue});

  final VoidCallback onSwitchToQueue;

  @override
  ConsumerState<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends ConsumerState<_ScanTab> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _scanned = false;
  String? _lastBarcode;
  Product? _foundProduct;
  bool _loadingBarcode = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _scanned = true;
    setState(() {
      _lastBarcode = value;
      _loadingBarcode = true;
    });
    final controller = ref.read(appControllerProvider.notifier);
    final product = await controller.lookupBarcode(value);
    if (!mounted) return;
    setState(() {
      _foundProduct = product;
      _loadingBarcode = false;
    });
    await _scanner.stop();
  }

  void _reset() {
    setState(() {
      _scanned = false;
      _lastBarcode = null;
      _foundProduct = null;
      _loadingBarcode = false;
    });
    _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final t = state.t;

    if (kIsWeb) {
      return Center(child: Text(t.scannerNotSupported));
    }

    if (_lastBarcode != null) {
      return _ProductDefineForm(
        barcode: _lastBarcode!,
        initial: _foundProduct,
        loading: _loadingBarcode,
        onSaved: _reset,
        onCancel: _reset,
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (ctx, error, child) =>
              Center(child: Text(t.cameraDenied)),
        ),
        Positioned(
          bottom: 32,
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
      ],
    );
  }
}

// ── Product define form ──────────────────────────────────────────────────────

class _ProductDefineForm extends ConsumerStatefulWidget {
  const _ProductDefineForm({
    required this.barcode,
    required this.initial,
    required this.loading,
    required this.onSaved,
    required this.onCancel,
  });

  final String barcode;
  final Product? initial;
  final bool loading;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<_ProductDefineForm> createState() => _ProductDefineFormState();
}

class _ProductDefineFormState extends ConsumerState<_ProductDefineForm> {
  late final TextEditingController _displayName;
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _defaultBrand;
  String? _defaultUnitId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _displayName = TextEditingController(text: p?.displayName ?? '');
    _nameAr = TextEditingController(text: p?.nameAr ?? '');
    _nameEn = TextEditingController(text: p?.nameEn ?? '');
    _defaultBrand = TextEditingController(text: p?.defaultBrand ?? '');
    _defaultUnitId = p?.defaultUnitId;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _defaultBrand.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = ref.read(appControllerProvider);
    final repo = ref.read(repositoryProvider);
    final data = {
      'displayName': _displayName.text.trim(),
      'nameAr': _nameAr.text.trim(),
      'nameEn': _nameEn.text.trim(),
      'barcode': widget.barcode,
      if (_defaultUnitId != null) 'defaultUnitId': _defaultUnitId,
      if (_defaultBrand.text.trim().isNotEmpty)
        'defaultBrand': _defaultBrand.text.trim(),
    };
    try {
      if (widget.initial != null) {
        await repo.adminUpdate('products', widget.initial!.id, data);
      } else {
        await repo.adminCreate('products', data);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.t.adminDone)),
      );
      widget.onSaved();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.t.genericError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final c = context.c;

    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.barcode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: c.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.initial != null ? t.barcodeFound : t.barcodeNotFound,
                style: TextStyle(
                  color: widget.initial != null ? c.primary : c.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _displayName,
            decoration: InputDecoration(labelText: t.adminProductName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameEn,
            decoration: InputDecoration(labelText: t.adminNameEn),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameAr,
            decoration: InputDecoration(labelText: t.adminNameAr),
          ),
          const SizedBox(height: 12),
          MoonaDropdown<String?>(
            value: _defaultUnitId,
            hint: t.adminDefaultUnit,
            items: [
              MoonaDropdownEntry(value: null, label: t.none),
              for (final u in state.units)
                MoonaDropdownEntry(value: u.id, label: u.label(state.lang)),
            ],
            onChanged: (v) => setState(() => _defaultUnitId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _defaultBrand,
            decoration: InputDecoration(labelText: t.adminDefaultBrand),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              MoonaButton(
                label: t.cancel,
                variant: MoonaButtonVariant.outlined,
                onPressed: _busy ? null : widget.onCancel,
              ),
              const SizedBox(width: 12),
              MoonaButton(
                label: t.save,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Queue tab ────────────────────────────────────────────────────────────────

class _QueueTab extends ConsumerStatefulWidget {
  const _QueueTab({required this.onDefine});

  final void Function(String barcode) onDefine;

  @override
  ConsumerState<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<_QueueTab> {
  List<BarcodeSubmission>? _submissions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final queue = await ref.read(repositoryProvider).adminGetBarcodeQueue();
      if (!mounted) return;
      setState(() {
        _submissions = queue;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _resolve(BarcodeSubmission sub, String productId) async {
    try {
      await ref
          .read(repositoryProvider)
          .adminResolveBarcode(sub.id, productId);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final c = context.c;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final subs = _submissions ?? [];
    if (subs.isEmpty) {
      return Center(
        child: Text(t.barcodeQueueEmpty, style: TextStyle(color: c.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: subs.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final sub = subs[i];
        return ListTile(
          title: Text(
            sub.barcode,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          subtitle: Text('${t.queueTab}: ${sub.count}×'),
          trailing: MoonaButton(
            label: t.barcodeDefine,
            variant: MoonaButtonVariant.tonal,
            height: 36,
            onPressed: () => _showDefineDialog(ctx, sub, state),
          ),
        );
      },
    );
  }

  Future<void> _showDefineDialog(
    BuildContext context,
    BarcodeSubmission sub,
    AppState appState,
  ) async {
    final state = ref.read(appControllerProvider);
    final products = state.products;
    // Show a dialog to either link to an existing product or define a new one.
    final productId = await showDialog<String>(
      context: context,
      builder: (ctx) => _LinkProductDialog(
        barcode: sub.barcode,
        products: products,
        t: state.t,
      ),
    );
    if (productId == null) return;
    await _resolve(sub, productId);
  }
}

class _LinkProductDialog extends StatefulWidget {
  const _LinkProductDialog({
    required this.barcode,
    required this.products,
    required this.t,
  });

  final String barcode;
  final List<Product> products;
  final AppStrings t;

  @override
  State<_LinkProductDialog> createState() => _LinkProductDialogState();
}

class _LinkProductDialogState extends State<_LinkProductDialog> {
  String? _selectedProductId;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final c = context.c;
    final state = ProviderScope.containerOf(context).read(appControllerProvider);

    return AlertDialog(
      title: Text(t.barcodeResolve),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.barcode, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _selectedProductId,
            hint: Text(t.adminProducts),
            items: widget.products
                .map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.label(state.lang)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedProductId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: _selectedProductId == null
              ? null
              : () => Navigator.of(context).pop(_selectedProductId),
          child: Text(t.save, style: TextStyle(color: c.primary)),
        ),
      ],
    );
  }
}
