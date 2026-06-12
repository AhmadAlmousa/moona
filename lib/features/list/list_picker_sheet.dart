import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/moona_colors.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/sheet.dart';

/// Bottom sheet showing all the user's named lists. Tap to switch; long-press
/// to rename or delete.
Future<void> showListPickerSheet(BuildContext context) =>
    showMoonaSheet<void>(
      context: context,
      builder: (ctx) => const _ListPickerSheet(),
    );

class _ListPickerSheet extends ConsumerStatefulWidget {
  const _ListPickerSheet();

  @override
  ConsumerState<_ListPickerSheet> createState() => _ListPickerSheetState();
}

class _ListPickerSheetState extends ConsumerState<_ListPickerSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final c = context.c;
    final lists = state.lists;
    final activeId = state.activeListId ?? state.activeList?.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.myLists,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: c.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        ...lists.map(
          (list) => _ListTile(
            list: list,
            isActive: list.id == activeId,
            onTap: () async {
              Navigator.of(context).pop();
              await controller.switchList(list.id);
            },
            onRename: () => _showRenameDialog(context, list),
            onDelete: lists.length > 1
                ? () => _showDeleteDialog(context, list, lists)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        MoonaButton(
          label: t.newList,
          icon: 'add',
          variant: MoonaButtonVariant.tonal,
          full: true,
          onPressed: _busy ? null : () => _showCreateDialog(context),
        ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final result = await showMoonaDialog<(String, String?)>(
      context: context,
      builder: (ctx) => const _ListNameDialog(isCreate: true),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    final controller = ref.read(appControllerProvider.notifier);
    final newList = await controller.createList(result.$1, emoji: result.$2);
    if (!mounted) return;
    setState(() => _busy = false);
    if (newList != null && mounted) {
      Navigator.of(context).pop();
      await controller.switchList(newList.id);
    }
  }

  Future<void> _showRenameDialog(BuildContext context, UserList list) async {
    final result = await showMoonaDialog<(String, String?)>(
      context: context,
      builder: (ctx) =>
          _ListNameDialog(isCreate: false, initialName: list.name, initialEmoji: list.emoji),
    );
    if (result == null || !mounted) return;
    final controller = ref.read(appControllerProvider.notifier);
    await controller.renameList(list.id, result.$1, emoji: result.$2);
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    UserList list,
    List<UserList> allLists,
  ) async {
    final controller = ref.read(appControllerProvider.notifier);
    final state = ref.read(appControllerProvider);
    // If list has items (we can infer from item count in state), show migration
    // dialog; otherwise just confirm deletion.
    final itemCount = state.items.where((i) => i.listId == list.id).length +
        state.trash.where((i) => i.listId == list.id).length;

    final others = allLists.where((l) => l.id != list.id).toList();
    final t = state.t;

    if (itemCount > 0 && others.isNotEmpty) {
      final result = await showMoonaDialog<_DeleteListResult>(
        context: context,
        builder: (ctx) => _DeleteListDialog(list: list, others: others, t: t),
      );
      if (result == null || !mounted) return;
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await controller.deleteList(list.id, migrateToListId: result.migrateToListId);
    } else {
      final confirmed = await showMoonaDialog<bool>(
        context: context,
        builder: (ctx) {
          final t = state.t;
          final c = ctx.c;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.deleteList,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.onSurface),
              ),
              const SizedBox(height: 12),
              Text(itemCount > 0 ? t.deleteListWithItems : t.deleteList),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MoonaButton(
                    label: t.cancel,
                    variant: MoonaButtonVariant.text,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 8),
                  MoonaButton(
                    label: t.deleteList,
                    danger: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await controller.deleteList(list.id);
    }
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.list,
    required this.isActive,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  final UserList list;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onLongPress: (onRename != null || onDelete != null)
          ? () => _showActions(context)
          : null,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? c.primaryContainer : c.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            list.emoji ?? '📋',
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(
          list.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: c.onSurface,
          ),
        ),
        trailing: isActive
            ? Icon(Icons.check_rounded, color: c.primary, size: 22)
            : null,
      ),
    );
  }

  void _showActions(BuildContext context) {
    final state = ProviderScope.containerOf(context).read(appControllerProvider);
    final t = state.t;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRename != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(t.renameList),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onRename!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: ctx.c.error),
                title: Text(t.deleteList, style: TextStyle(color: ctx.c.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({
    required this.isCreate,
    this.initialName,
    this.initialEmoji,
  });

  final bool isCreate;
  final String? initialName;
  final String? initialEmoji;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emojiCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _emojiCtrl = TextEditingController(text: widget.initialEmoji ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Read t directly from provider
    final state = ProviderScope.containerOf(context).read(appControllerProvider);
    final t = state.t;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isCreate ? t.newList : t.renameList,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.onSurface),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: t.listName),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emojiCtrl,
          decoration: InputDecoration(labelText: t.listEmoji),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MoonaButton(
              label: t.cancel,
              variant: MoonaButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            MoonaButton(
              label: t.save,
              onPressed: () {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) return;
                final emoji = _emojiCtrl.text.trim();
                Navigator.of(context).pop(
                  (name, emoji.isEmpty ? null : emoji),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _DeleteListResult {
  const _DeleteListResult({this.migrateToListId});
  final String? migrateToListId;
}

class _DeleteListDialog extends StatefulWidget {
  const _DeleteListDialog({
    required this.list,
    required this.others,
    required this.t,
  });

  final UserList list;
  final List<UserList> others;
  final AppStrings t;

  @override
  State<_DeleteListDialog> createState() => _DeleteListDialogState();
}

class _DeleteListDialogState extends State<_DeleteListDialog> {
  late String? _selectedMigrateId = widget.others.first.id;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = widget.t;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.deleteList,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.onSurface),
        ),
        const SizedBox(height: 12),
        Text(t.deleteListWithItems),
        const SizedBox(height: 16),
        // Move items radio
        RadioListTile<bool>(
          title: Text(t.moveItemsTo),
          value: true,
          groupValue: _selectedMigrateId != null,
          onChanged: (_) => setState(() => _selectedMigrateId = widget.others.first.id),
          contentPadding: EdgeInsets.zero,
        ),
        if (_selectedMigrateId != null) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedMigrateId,
            items: widget.others
                .map(
                  (l) => DropdownMenuItem(
                    value: l.id,
                    child: Text(l.displayName),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedMigrateId = v),
          ),
          const SizedBox(height: 8),
        ],
        // Delete items radio
        RadioListTile<bool>(
          title: Text(t.deleteItemsToo),
          value: false,
          groupValue: _selectedMigrateId != null,
          onChanged: (_) => setState(() => _selectedMigrateId = null),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MoonaButton(
              label: t.cancel,
              variant: MoonaButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            MoonaButton(
              label: t.deleteList,
              danger: true,
              onPressed: () => Navigator.of(context).pop(
                _DeleteListResult(migrateToListId: _selectedMigrateId),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
