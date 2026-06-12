import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';
import 'admin_screen.dart';

/// The catalogs an admin can curate through one generic editor.
enum AdminCatalogKind { categories, units, products, brands, stores }

String _kindStr(AdminCatalogKind kind) => switch (kind) {
  AdminCatalogKind.categories => 'categories',
  AdminCatalogKind.units => 'units',
  AdminCatalogKind.products => 'products',
  AdminCatalogKind.brands => 'brands',
  AdminCatalogKind.stores => 'stores',
};

typedef _FieldSpec = ({String key, String label, bool emoji});

List<_FieldSpec> _fieldsFor(AdminCatalogKind kind, AppStrings t) =>
    switch (kind) {
      AdminCatalogKind.categories => [
        (key: 'nameEn', label: t.adminNameEn, emoji: false),
        (key: 'nameAr', label: t.adminNameAr, emoji: false),
        (key: 'emoji', label: t.adminEmoji, emoji: true),
      ],
      AdminCatalogKind.units => [
        (key: 'nameEn', label: t.adminNameEn, emoji: false),
        (key: 'nameAr', label: t.adminNameAr, emoji: false),
      ],
      AdminCatalogKind.products => [
        (key: 'displayName', label: t.adminProductName, emoji: false),
        (key: 'nameEn', label: t.adminNameEn, emoji: false),
        (key: 'nameAr', label: t.adminNameAr, emoji: false),
      ],
      AdminCatalogKind.brands || AdminCatalogKind.stores => [
        (key: 'name', label: t.adminTermName, emoji: false),
      ],
    };

String _titleFor(AdminCatalogKind kind, AppStrings t) => switch (kind) {
  AdminCatalogKind.categories => t.adminCategories,
  AdminCatalogKind.units => t.adminUnits,
  AdminCatalogKind.products => t.adminProducts,
  AdminCatalogKind.brands => t.adminBrands,
  AdminCatalogKind.stores => t.adminStores,
};

String _idOf(Map<String, dynamic> m) =>
    (m[r'$id'] ?? m['stableId'] ?? m['id'] ?? '').toString();

/// Generic list + add/edit/delete screen for a single [AdminCatalogKind].
class AdminCatalogScreen extends ConsumerStatefulWidget {
  const AdminCatalogScreen({super.key, required this.kind});

  final AdminCatalogKind kind;

  @override
  ConsumerState<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends ConsumerState<AdminCatalogScreen> {
  List<Map<String, dynamic>> _items = const [];
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
    try {
      final items = await ref
          .read(repositoryProvider)
          .adminList(_kindStr(widget.kind));
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor(Map<String, dynamic>? item) async {
    final saved = await showMoonaSheet<bool>(
      context: context,
      title: item == null
          ? ref.read(appControllerProvider).t.adminAdd
          : ref.read(appControllerProvider).t.adminEdit,
      builder: (_) => _CatalogEditor(kind: widget.kind, item: item),
    );
    if (saved == true) _load();
  }

  String _rowTitle(Map<String, dynamic> m) => switch (widget.kind) {
    AdminCatalogKind.products => (m['displayName'] ?? m['nameEn'] ?? '')
        .toString(),
    AdminCatalogKind.brands || AdminCatalogKind.stores => (m['name'] ?? '')
        .toString(),
    _ => (m['nameEn'] ?? m['nameAr'] ?? '').toString(),
  };

  String _rowSubtitle(Map<String, dynamic> m) =>
      widget.kind == AdminCatalogKind.brands ||
          widget.kind == AdminCatalogKind.stores
      ? ''
      : (m['nameAr'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = ref.watch(appControllerProvider).t;

    return AdminScaffold(
      title: _titleFor(widget.kind, t),
      action: MoonaIconButton(
        icon: 'plus',
        tooltip: t.adminAdd,
        onPressed: () => _openEditor(null),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
          ? _ErrorState(
              label: t.adminLoadError,
              retryLabel: t.retry,
              onRetry: _load,
            )
          : _items.isEmpty
          ? Center(
              child: Text(
                t.adminEmpty,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.onSurfaceVariant,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  20 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final active = item['active'] != false;
                  final emoji = widget.kind == AdminCatalogKind.categories
                      ? (item['emoji'] ?? '').toString()
                      : '';
                  final subtitle = _rowSubtitle(item);
                  return MoonaRow(
                    onTap: () => _openEditor(item),
                    child: Row(
                      children: [
                        if (emoji.isNotEmpty) ...[
                          Text(emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _rowTitle(item),
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: active
                                      ? c.onSurface
                                      : c.onSurfaceVariant.withValues(
                                          alpha: 0.6,
                                        ),
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!active)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t.inactive,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        MoonaIcon('edit', size: 18, color: c.onSurfaceVariant),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Add/edit form for one catalog row, shown in a [showMoonaSheet]. Pops `true`
/// when a create/update/delete succeeds so the list reloads.
class _CatalogEditor extends ConsumerStatefulWidget {
  const _CatalogEditor({required this.kind, this.item});

  final AdminCatalogKind kind;
  final Map<String, dynamic>? item;

  @override
  ConsumerState<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends ConsumerState<_CatalogEditor> {
  late final List<_FieldSpec> _fields = _fieldsFor(
    widget.kind,
    ref.read(appControllerProvider).t,
  );
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _fields)
      f.key: TextEditingController(
        text: (widget.item?[f.key] ?? '').toString(),
      ),
  };
  late bool _active = widget.item == null
      ? true
      : widget.item!['active'] != false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _slug(String s) {
    final base = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'c${DateTime.now().millisecondsSinceEpoch}' : base;
  }

  Future<void> _save(AppStrings t) async {
    final first = _controllers[_fields.first.key]!.text.trim();
    if (first.isEmpty) {
      setState(() => _error = t.nameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = <String, dynamic>{
      for (final f in _fields) f.key: _controllers[f.key]!.text.trim(),
      'active': _active,
    };
    try {
      final repo = ref.read(repositoryProvider);
      final kind = _kindStr(widget.kind);
      if (widget.item == null) {
        // Categories and units use a stable document id the backend requires.
        if (widget.kind == AdminCatalogKind.categories ||
            widget.kind == AdminCatalogKind.units) {
          data['id'] = _slug(first);
        }
        await repo.adminCreate(kind, data);
      } else {
        await repo.adminUpdate(kind, _idOf(widget.item!), data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t.genericError;
        });
      }
    }
  }

  Future<void> _delete(AppStrings t) async {
    final ok = await adminConfirm(
      context,
      title: t.adminDelete,
      message: t.adminDeleteItemConfirm(
        _controllers[_fields.first.key]!.text.trim(),
      ),
      confirmLabel: t.adminDelete,
      cancelLabel: t.cancel,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .adminDelete(_kindStr(widget.kind), _idOf(widget.item!));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t.genericError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = ref.watch(appControllerProvider).t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _fields) ...[
          MoonaField(
            controller: _controllers[f.key],
            label: f.label,
            placeholder: f.emoji ? '📦' : null,
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                t.active,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.onSurface,
                ),
              ),
            ),
            MoonaSwitch(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.error,
            ),
          ),
        ],
        const SizedBox(height: 18),
        MoonaButton(
          label: t.save,
          full: true,
          onPressed: _busy ? null : () => _save(t),
        ),
        if (widget.item != null) ...[
          const SizedBox(height: 8),
          MoonaButton(
            label: t.adminDelete,
            icon: 'trash',
            variant: MoonaButtonVariant.outlined,
            danger: true,
            full: true,
            onPressed: _busy ? null : () => _delete(t),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.label,
    required this.retryLabel,
    required this.onRetry,
  });

  final String label;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          MoonaButton(
            label: retryLabel,
            icon: 'undo',
            variant: MoonaButtonVariant.outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
