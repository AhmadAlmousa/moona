import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';
import 'admin_barcode_scan_screen.dart';
import 'admin_catalog_screen.dart';
import 'admin_users_screen.dart';

/// Admin hub. Reached from Settings only when `profile.isAdmin` is true; the
/// backend independently gates every admin action, so this is UX-only.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    return AdminScaffold(
      title: t.admin,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          _HubRow(
            icon: 'person',
            label: t.adminUsers,
            onTap: () => _push(context, const AdminUsersScreen()),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'list',
            label: t.adminCategories,
            onTap: () => _push(
              context,
              const AdminCatalogScreen(kind: AdminCatalogKind.categories),
            ),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'sort',
            label: t.adminUnits,
            onTap: () => _push(
              context,
              const AdminCatalogScreen(kind: AdminCatalogKind.units),
            ),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'tag',
            label: t.adminProducts,
            onTap: () => _push(
              context,
              const AdminCatalogScreen(kind: AdminCatalogKind.products),
            ),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'tag',
            label: t.adminBrands,
            onTap: () => _push(
              context,
              const AdminCatalogScreen(kind: AdminCatalogKind.brands),
            ),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'store',
            label: t.adminStores,
            onTap: () => _push(
              context,
              const AdminCatalogScreen(kind: AdminCatalogKind.stores),
            ),
          ),
          const SizedBox(height: 9),
          _HubRow(
            icon: 'camera',
            label: t.barcodeScanner,
            onTap: () => _push(context, const AdminBarcodeScanScreen()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _HubRow extends StatelessWidget {
  const _HubRow({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MoonaRow(
      onTap: onTap,
      child: Row(
        children: [
          MoonaIcon(icon, size: 22, color: c.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: c.onSurface,
              ),
            ),
          ),
          MoonaIcon('chevron', size: 18, color: c.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Shared scaffold for the admin screens: a back-button header with an optional
/// trailing action, over an [Expanded] body.
class AdminScaffold extends StatelessWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 6,
                end: 10,
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
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A centered danger/confirm dialog. Returns true when the user confirms.
Future<bool> adminConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool danger = true,
}) async {
  final c = context.c;
  final result = await showMoonaDialog<bool>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: danger ? c.errorContainer : c.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: MoonaIcon(
            danger ? 'trash' : 'check',
            size: 28,
            color: danger ? c.onErrorContainer : c.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: c.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        MoonaButton(
          label: confirmLabel,
          danger: danger,
          full: true,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        const SizedBox(height: 8),
        MoonaButton(
          label: cancelLabel,
          variant: MoonaButtonVariant.text,
          full: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
    ),
  );
  return result ?? false;
}
