import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/phone.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// A device contact reduced to what the share picker needs.
class _ContactEntry {
  const _ContactEntry(this.name, this.phone);
  final String name;
  final String phone;
}

/// Runs the share-via-contacts flow: ensure the user has a real display name →
/// permission explanation → OS permission → contact picker. Device contacts are
/// matched against registered Moona users via `lookupContacts` (phone numbers
/// only; names stay on device), then split into Registered / Not-registered.
Future<void> showContactFlow(BuildContext context, WidgetRef ref) async {
  // Gate sharing on a real display name so counterparties never see a raw id.
  final named = await _ensureDisplayName(context, ref);
  if (named != true || !context.mounted) return;

  final allowed = await _showPermissionDialog(context, ref);
  if (allowed != true || !context.mounted) return;

  // Best-effort device-contacts load. flutter_contacts 2.x triggers the OS
  // permission as needed; if it is denied or the platform has no contacts
  // (web/desktop/tests) we fall back to manual phone entry below.
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

/// Ensures the signed-in profile has a real display name before sharing,
/// prompting for one when it is empty or just the phone number. Returns true
/// when the user can proceed.
Future<bool> _ensureDisplayName(BuildContext context, WidgetRef ref) async {
  if (!ref.read(appControllerProvider.notifier).needsDisplayName) return true;
  final saved = await _showNameDialog(context, ref);
  return saved == true;
}

Future<bool?> _showNameDialog(BuildContext context, WidgetRef ref) {
  final t = ref.read(appControllerProvider).t;
  final controller = ref.read(appControllerProvider.notifier);
  final field = TextEditingController();

  return showMoonaDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return StatefulBuilder(
        builder: (statefulContext, setState) {
          final canSave = field.text.trim().isNotEmpty;
          void save() {
            if (!canSave) return;
            controller.setDisplayName(field.text);
            Navigator.of(dialogContext).pop(true);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: MoonaIcon(
                    'person',
                    size: 32,
                    color: c.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                t.nameYourselfTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: c.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.nameYourselfBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: c.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              MoonaField(
                controller: field,
                label: t.yourName,
                placeholder: t.yourNameHint,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => save(),
              ),
              const SizedBox(height: 18),
              MoonaButton(
                label: t.continueLabel,
                full: true,
                onPressed: canSave ? save : null,
              ),
              const SizedBox(height: 8),
              MoonaButton(
                label: t.cancel,
                variant: MoonaButtonVariant.text,
                full: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(field.dispose);
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

  /// `phoneDigits` → on-device contact name, so registered users keep the name
  /// the owner saved them under rather than their profile name.
  Map<String, String> _localNames = const {};
  ContactLookupResult _result = const ContactLookupResult();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = <String, String>{};
    final phones = <String>[];
    for (final entry in widget.contacts) {
      phones.add(entry.phone);
      final name = entry.name.trim();
      try {
        final digits = normalizePhone(entry.phone).digits;
        if (name.isNotEmpty) names.putIfAbsent(digits, () => name);
      } catch (_) {
        // Unparseable locally; the backend still classifies/ignores it.
      }
    }
    final result = phones.isEmpty
        ? const ContactLookupResult()
        : await ref.read(appControllerProvider.notifier).lookupContacts(phones);
    if (!mounted) return;
    setState(() {
      _localNames = names;
      _result = result;
      _loading = false;
    });
  }

  void _share(String phone) {
    Navigator.of(context).pop();
    ref.read(appControllerProvider.notifier).requestShare(phone);
  }

  /// Local contact name, falling back to the registered profile name, then the
  /// phone number.
  String _nameFor(ContactLookupEntry e) {
    final local = _localNames[e.phoneDigits];
    if (local != null && local.isNotEmpty) return local;
    final display = e.displayName;
    if (display != null && display.isNotEmpty) return display;
    return e.phone;
  }

  bool _matches(ContactLookupEntry e, String query, String digits) {
    if (query.isEmpty) return true;
    return _nameFor(e).toLowerCase().contains(query.toLowerCase()) ||
        (digits.isNotEmpty && e.phoneDigits.contains(digits)) ||
        e.phone.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final query = _query.text.trim();
    final digits = query.replaceAll(RegExp(r'\D'), '');

    final registered = [
      for (final e in _result.registered)
        if (_matches(e, query, digits)) e,
    ];
    final unregistered = [
      for (final e in _result.unregistered)
        if (_matches(e, query, digits)) e,
    ];

    // Offer a manual share when a typed number isn't already in the lists.
    final inLists = _result.contacts.any(
      (e) => (digits.isNotEmpty && e.phoneDigits.contains(digits)),
    );
    final showManual = digits.length >= 6 && !inLists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoonaField(
          controller: _query,
          placeholder: t.searchContacts,
          onChanged: (_) => setState(() {}),
          trailing: MoonaIcon('search', size: 20, color: c.onSurfaceVariant),
        ),
        if (showManual) ...[
          const SizedBox(height: 10),
          MoonaButton(
            label: '${t.shareViaContacts} · $query',
            icon: 'share',
            full: true,
            onPressed: () => _share(query),
          ),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_result.contacts.isEmpty)
          _EmptyHint(text: t.enterPhoneManually)
        else if (registered.isEmpty && unregistered.isEmpty)
          _EmptyHint(text: t.enterPhoneManually)
        else ...[
          if (registered.isNotEmpty) ...[
            _SectionLabel(t.onMoona),
            for (final e in registered)
              _ContactRow(
                name: _nameFor(e),
                phone: e.phone,
                registered: true,
                isSelf: e.isSelf,
                onTap: e.isSelf ? null : () => _share(e.phone),
              ),
          ],
          if (unregistered.isNotEmpty) ...[
            if (registered.isNotEmpty) const SizedBox(height: 8),
            _SectionLabel(t.notOnMoona),
            for (final e in unregistered)
              _ContactRow(
                name: _nameFor(e),
                phone: e.phone,
                registered: false,
                isSelf: false,
                trailingLabel: t.invite,
                onTap: () => _share(e.phone),
              ),
          ],
        ],
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: c.onSurfaceVariant),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 6, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: c.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.name,
    required this.phone,
    required this.registered,
    required this.isSelf,
    required this.onTap,
    this.trailingLabel,
  });

  final String name;
  final String phone;
  final bool registered;
  final bool isSelf;
  final VoidCallback? onTap;

  /// Optional trailing pill (e.g. "Invite" for unregistered contacts).
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: isSelf ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Avatar(name: name, tint: registered),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.onSurface,
                      ),
                    ),
                    Text(
                      phone,
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
              if (trailingLabel != null) _Pill(text: trailingLabel!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: c.onPrimaryContainer,
        ),
      ),
    );
  }
}
