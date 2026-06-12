import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';
import 'admin_screen.dart';

/// Admin user management: promote/demote admins, reset a user's data, or delete
/// the account entirely. Destructive actions are disabled on your own row.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = const [];
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
      final users = await ref.read(repositoryProvider).adminList('users');
      if (!mounted) return;
      setState(() {
        _users = users;
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

  String _idOf(Map<String, dynamic> m) =>
      (m['userId'] ?? m[r'$id'] ?? m['id'] ?? '').toString();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openActions(Map<String, dynamic> user) async {
    final t = ref.read(appControllerProvider).t;
    final id = _idOf(user);
    final name = (user['displayName'] ?? '').toString();
    final isAdmin = user['isAdmin'] == true;
    final isSelf = id == ref.read(appControllerProvider).profile?.id;

    await showMoonaSheet<void>(
      context: context,
      title: name,
      builder: (sheetContext) {
        final c = sheetContext.c;
        if (isSelf) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t.adminThisIsYou,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: c.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoonaButton(
              label: isAdmin ? t.adminRemoveAdmin : t.adminMakeAdmin,
              icon: 'shield',
              variant: MoonaButtonVariant.tonal,
              full: true,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _toggleAdmin(id, !isAdmin);
              },
            ),
            const SizedBox(height: 8),
            MoonaButton(
              label: t.adminResetData,
              icon: 'undo',
              variant: MoonaButtonVariant.outlined,
              full: true,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _resetUser(id, name);
              },
            ),
            const SizedBox(height: 8),
            MoonaButton(
              label: t.adminDeleteUser,
              icon: 'trash',
              variant: MoonaButtonVariant.outlined,
              danger: true,
              full: true,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _deleteUser(id, name);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleAdmin(String id, bool makeAdmin) async {
    try {
      await ref.read(repositoryProvider).adminUpdate('users', id, {
        'isAdmin': makeAdmin,
      });
    } catch (_) {
      _snack(ref.read(appControllerProvider).t.genericError);
    }
    await _load();
  }

  Future<void> _resetUser(String id, String name) async {
    final t = ref.read(appControllerProvider).t;
    final ok = await adminConfirm(
      context,
      title: t.adminResetData,
      message: t.adminResetConfirm(name),
      confirmLabel: t.adminResetData,
      cancelLabel: t.cancel,
    );
    if (!ok) return;
    try {
      final res = await ref.read(repositoryProvider).adminResetUser(id);
      final items = (res['items'] as num?)?.toInt() ?? 0;
      _snack(t.adminResetDone(items));
    } catch (_) {
      _snack(t.genericError);
    }
    await _load();
  }

  Future<void> _deleteUser(String id, String name) async {
    final t = ref.read(appControllerProvider).t;
    final ok = await adminConfirm(
      context,
      title: t.adminDeleteUser,
      message: t.adminDeleteUserConfirm(name),
      confirmLabel: t.adminDeleteUser,
      cancelLabel: t.cancel,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).adminDelete('users', id);
    } catch (_) {
      _snack(t.genericError);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = ref.watch(appControllerProvider).t;
    final selfId = ref.watch(appControllerProvider).profile?.id;

    return AdminScaffold(
      title: t.adminUsers,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.adminLoadError,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  MoonaButton(
                    label: t.retry,
                    icon: 'undo',
                    variant: MoonaButtonVariant.outlined,
                    onPressed: _load,
                  ),
                ],
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
                itemCount: _users.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final name = (user['displayName'] ?? '').toString();
                  final phone = (user['phone'] ?? '').toString();
                  final isAdmin = user['isAdmin'] == true;
                  final isSelf = _idOf(user) == selfId;
                  return MoonaRow(
                    onTap: () => _openActions(user),
                    child: Row(
                      children: [
                        Avatar(name: name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name.isEmpty ? phone : name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        color: c.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 8),
                                    _AdminBadge(label: t.adminBadge),
                                  ],
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      t.adminYou,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: c.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (phone.isNotEmpty)
                                Text(
                                  phone,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        MoonaIcon(
                          'chevron',
                          size: 18,
                          color: c.onSurfaceVariant,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: c.onPrimaryContainer,
        ),
      ),
    );
  }
}
