import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';

/// A device contact reduced to what the share picker needs.
class _ContactEntry {
  const _ContactEntry(this.name, this.phone);
  final String name;
  final String phone;
}

/// Runs the share-via-contacts flow: permission explanation → OS permission →
/// contact picker (with manual phone entry). Tapping a contact requests a share
/// with that phone via the controller.
Future<void> showContactFlow(BuildContext context, WidgetRef ref) async {
  final allowed = await _showPermissionDialog(context, ref);
  if (allowed != true || !context.mounted) return;

  // Best-effort device-contacts load. flutter_contacts 2.x triggers the OS
  // permission as needed; if it is denied or the platform has no contacts
  // (web/desktop/tests) we fall back to manual phone entry below. A dedicated
  // permission_handler pass can refine this later.
  var contacts = <_ContactEntry>[];
  try {
    final raw = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );
    contacts = [
      for (final contact in raw)
        if (contact.phones.isNotEmpty)
          _ContactEntry(contact.displayName ?? '', contact.phones.first.number),
    ];
  } catch (_) {
    // Contacts unavailable or denied — manual entry still works.
  }

  if (!context.mounted) return;
  final t = ref.read(appControllerProvider).t;
  await showMoonaSheet(
    context: context,
    title: t.selectContact,
    builder: (_) => _ContactPicker(contacts: contacts),
  );
}

Future<bool?> _showPermissionDialog(BuildContext context, WidgetRef ref) {
  final t = ref.read(appControllerProvider).t;
  return showMoonaDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: MoonaIcon('person', size: 32, color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            t.contactsPermTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.contactsPermBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          MoonaButton(
            label: t.allow,
            full: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          const SizedBox(height: 8),
          MoonaButton(
            label: t.dontAllow,
            variant: MoonaButtonVariant.text,
            full: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      );
    },
  );
}

class _ContactPicker extends ConsumerStatefulWidget {
  const _ContactPicker({required this.contacts});

  final List<_ContactEntry> contacts;

  @override
  ConsumerState<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends ConsumerState<_ContactPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _share(String phone) {
    Navigator.of(context).pop();
    ref.read(appControllerProvider.notifier).requestShare(phone);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final query = _query.text.trim();
    final filtered = widget.contacts
        .where(
          (entry) => entry.name.contains(query) || entry.phone.contains(query),
        )
        .toList();
    final digits = query.replaceAll(RegExp(r'\D'), '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoonaField(
          controller: _query,
          placeholder: t.searchContacts,
          onChanged: (_) => setState(() {}),
          trailing: MoonaIcon('search', size: 20, color: c.onSurfaceVariant),
        ),
        if (digits.length >= 6 &&
            !widget.contacts.any((e) => e.phone.contains(query))) ...[
          const SizedBox(height: 10),
          MoonaButton(
            label: '${t.shareViaContacts} · $query',
            icon: 'share',
            full: true,
            onPressed: () => _share(query),
          ),
        ],
        const SizedBox(height: 12),
        if (widget.contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              t.enterPhoneManually,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.onSurfaceVariant),
            ),
          )
        else
          ...filtered.map(
            (entry) =>
                _ContactRow(entry: entry, onTap: () => _share(entry.phone)),
          ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.entry, required this.onTap});

  final _ContactEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Avatar(name: entry.name, tint: true),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.onSurface,
                    ),
                  ),
                  Text(
                    entry.phone,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
