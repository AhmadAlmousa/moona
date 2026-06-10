import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart'
    as native_picker;
import 'package:flutter_native_contact_picker/model/contact.dart'
    as native_picker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/phone.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// A device contact reduced to what the share picker needs.
@visibleForTesting
class ContactPickerDeviceContact {
  const ContactPickerDeviceContact(
    this.name,
    this.phone, {
    this.normalizedPhone,
  });

  final String name;
  final String phone;
  final String? normalizedPhone;
}

/// A merged picker row: a device contact annotated with its Moona registration
/// status. Device contacts are always the source of rows; the `lookupContacts`
/// response only fills in [registered] / [isSelf] / the profile [displayName].
@visibleForTesting
class ContactPickerRow {
  const ContactPickerRow({
    required this.name,
    required this.phone,
    required this.phoneDigits,
    required this.registered,
    required this.isSelf,
  });

  final String name;
  final String phone;
  final String phoneDigits;
  final bool registered;
  final bool isSelf;
}

@visibleForTesting
List<ContactPickerRow> buildContactPickerRows(
  Iterable<ContactPickerDeviceContact> contacts,
  ContactLookupResult result,
) {
  final localNames = <String, String>{};
  final orderedDigits = <String>[];
  final displayPhone = <String, String>{};
  for (final entry in contacts) {
    final digits = _displayDigitsFor(entry);
    if (digits == null) continue;
    if (!displayPhone.containsKey(digits)) {
      orderedDigits.add(digits);
      displayPhone[digits] = entry.phone;
    }
    final name = entry.name.trim();
    if (name.isNotEmpty) localNames.putIfAbsent(digits, () => name);
  }

  final lookup = {
    for (final e in result.contacts)
      if (e.phoneDigits.isNotEmpty) e.phoneDigits: e,
  };
  final rows = <ContactPickerRow>[];
  final used = <String>{};
  for (final digits in orderedDigits) {
    used.add(digits);
    final e = lookup[digits];
    rows.add(
      ContactPickerRow(
        name: _resolveContactName(localNames[digits], e, displayPhone[digits]!),
        phone: displayPhone[digits]!,
        phoneDigits: digits,
        registered: e?.registered ?? false,
        isSelf: e?.isSelf ?? false,
      ),
    );
  }
  // Defensive: surface any registered entries the backend returned that didn't
  // line up with a device row (e.g. normalization drift), so they aren't lost.
  for (final e in result.registered) {
    if (used.add(e.phoneDigits)) {
      rows.add(
        ContactPickerRow(
          name: _resolveContactName(localNames[e.phoneDigits], e, e.phone),
          phone: e.phone,
          phoneDigits: e.phoneDigits,
          registered: true,
          isSelf: e.isSelf,
        ),
      );
    }
  }
  return rows;
}

@visibleForTesting
List<String> contactLookupPhones(
  Iterable<ContactPickerDeviceContact> contacts, {
  int limit = 250,
}) {
  final seen = <String>{};
  final phones = <String>[];
  for (final entry in contacts) {
    final digits = _normalizedDigitsFor(entry);
    if (digits == null || !seen.add(digits)) continue;
    phones.add(
      entry.normalizedPhone?.trim().isNotEmpty == true
          ? entry.normalizedPhone!.trim()
          : entry.phone,
    );
    if (phones.length >= limit) break;
  }
  return phones;
}

String? _normalizedDigitsFor(ContactPickerDeviceContact entry) {
  for (final candidate in [entry.normalizedPhone, entry.phone]) {
    final value = candidate?.trim();
    if (value == null || value.isEmpty) continue;
    try {
      return normalizePhone(value).digits;
    } catch (_) {
      // Try the next representation.
    }
  }
  return null;
}

String? _displayDigitsFor(ContactPickerDeviceContact entry) {
  final normalized = _normalizedDigitsFor(entry);
  if (normalized != null) return normalized;
  for (final candidate in [entry.normalizedPhone, entry.phone]) {
    final digits = candidate?.replaceAll(RegExp(r'\D'), '');
    if (digits != null && digits.isNotEmpty) return digits;
  }
  return null;
}

/// Local contact name, falling back to the registered profile name, then the
/// phone number.
String _resolveContactName(String? local, ContactLookupEntry? e, String phone) {
  if (local != null && local.isNotEmpty) return local;
  final display = e?.displayName;
  if (display != null && display.isNotEmpty) return display;
  return phone;
}

/// Why the device-contact load ended the way it did, so the picker can show a
/// meaningful empty state (and we can tell apart "denied" / "none" / "failed"
/// instead of one mystery blank list).
@visibleForTesting
enum ContactLoadStatus {
  /// Contacts were read (the list may still be empty if the device has none).
  ok,

  /// The OS contacts permission was refused.
  denied,

  /// Reading contacts threw — e.g. no contacts backend (web/desktop/tests) or a
  /// platform exception (logged via debugPrint).
  error,
}

/// Outcome of loading device contacts for the picker.
@visibleForTesting
class ContactLoadResult {
  const ContactLoadResult(this.status, this.contacts, {this.rawCount = 0});

  final ContactLoadStatus status;
  final List<ContactPickerDeviceContact> contacts;

  /// Total contacts the OS returned (before flattening to phone numbers). Lets
  /// the empty state tell "device has no contacts" apart from "contacts have no
  /// readable phone number".
  final int rawCount;
}

/// Reads device contacts, capturing *why* it ended up with the contacts it did.
/// Permission is driven by `permission_handler` (`request()` shows the system
/// dialog, or returns the existing grant silently); contacts are read with
/// flutter_contacts 1.x's `getContacts`, with `includeNonVisibleOnAndroid`
/// enabled so contacts outside a "visible group" (common for synced/SIM contacts
/// on Samsung/One UI) aren't silently filtered out — that filter, not any device
/// restriction, was the cause of the earlier empty list, and 2.x can't disable
/// it. On platforms without a contacts backend (web/desktop/tests) the method
/// channel throws — recorded as [ContactLoadStatus.error] rather than swallowed.
Future<ContactLoadResult> loadDeviceContacts() async {
  // Web/PWA has no full address-book read (`flutter_contacts` ships no web impl,
  // and the browser Contact Picker API only returns user-picked entries). Skip
  // the plugin call entirely and fall back to manual phone entry — intentional,
  // not an exception we happen to swallow below.
  if (kIsWeb) {
    debugPrint('Moona[contacts]: web — manual entry only (no address-book read)');
    return const ContactLoadResult(ContactLoadStatus.error, []);
  }
  try {
    final status = await Permission.contacts.request();
    if (!status.isGranted && !status.isLimited) {
      debugPrint('Moona[contacts]: permission not granted ($status)');
      return const ContactLoadResult(ContactLoadStatus.denied, []);
    }
    // By default flutter_contacts adds `IN_VISIBLE_GROUP = 1` to the query, which
    // silently drops every contact not in a "visible group". On Samsung/One UI
    // synced/SIM contacts are routinely flagged out of any visible group, so the
    // query returned an empty cursor (no error) even with permission granted —
    // the real cause of the long "empty picker" saga, NOT a device restriction.
    // Including non-visible contacts mirrors what the system Contacts app shows.
    FlutterContacts.config.includeNonVisibleOnAndroid = true;
    final raw = await FlutterContacts.getContacts(withProperties: true);
    final contacts = [
      for (final contact in raw)
        for (final phone in contact.phones)
          if (phone.number.trim().isNotEmpty)
            ContactPickerDeviceContact(
              contact.displayName,
              phone.number,
              normalizedPhone: phone.normalizedNumber,
            ),
    ];
    debugPrint(
      'Moona[contacts]: getContacts -> ${raw.length} contacts, '
      '${contacts.length} phones.',
    );
    return ContactLoadResult(
      ContactLoadStatus.ok,
      contacts,
      rawCount: raw.length,
    );
  } catch (e) {
    debugPrint('Moona[contacts]: read failed: $e');
    return const ContactLoadResult(ContactLoadStatus.error, []);
  }
}

/// Runs the share-via-contacts flow: ensure the user has a real display name →
/// OS contacts permission (requested directly, no custom pre-dialog) → contact
/// picker. Device contacts are the source of rows; `lookupContacts` only
/// enriches/splits them into Registered / Not-registered (phone numbers go on
/// the wire, names stay on device). A backend/network miss therefore degrades to
/// showing the local contacts, never an empty picker.
Future<void> showContactFlow(BuildContext context, WidgetRef ref) async {
  // Gate sharing on a real display name so counterparties never see a raw id.
  final named = await _ensureDisplayName(context, ref);
  if (named != true || !context.mounted) return;

  final loaded = await loadDeviceContacts();

  if (!context.mounted) return;
  final t = ref.read(appControllerProvider).t;
  await showMoonaSheet(
    context: context,
    title: t.selectContact,
    builder: (_) => _ContactPicker(loaded: loaded),
  );
}

/// Ensures the signed-in profile has a real display name before sharing,
/// prompting for one when it is empty or just the phone number. Returns true
/// when the user can proceed.
Future<bool> _ensureDisplayName(BuildContext context, WidgetRef ref) async {
  if (!ref.read(appControllerProvider.notifier).needsDisplayName) return true;
  final saved = await showDisplayNameDialog(context, ref, requiredName: true);
  return saved == true;
}

Future<bool?> showDisplayNameDialog(
  BuildContext context,
  WidgetRef ref, {
  bool requiredName = false,
}) {
  final t = ref.read(appControllerProvider).t;
  final controller = ref.read(appControllerProvider.notifier);
  final profile = ref.read(appControllerProvider).profile;
  final current = profile?.displayName.trim() ?? '';
  final field = TextEditingController(
    text: requiredName && controller.needsDisplayName ? '' : current,
  );

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
                requiredName ? t.nameYourselfTitle : t.changeDisplayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: c.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                requiredName ? t.nameYourselfBody : t.changeDisplayNameBody,
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
                label: requiredName ? t.continueLabel : t.save,
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

class _ContactPicker extends ConsumerStatefulWidget {
  const _ContactPicker({required this.loaded});

  final ContactLoadResult loaded;

  @override
  ConsumerState<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends ConsumerState<_ContactPicker> {
  final _query = TextEditingController();

  List<ContactPickerRow> _rows = const [];
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
    final contacts = widget.loaded.contacts;
    final localRows = buildContactPickerRows(
      contacts,
      const ContactLookupResult(),
    );
    setState(() {
      _rows = localRows;
      _loading = false;
    });

    final phones = contactLookupPhones(contacts);
    if (phones.isEmpty) return;

    final result = await ref
        .read(appControllerProvider.notifier)
        .lookupContacts(phones);
    if (!mounted) return;

    setState(() {
      _rows = buildContactPickerRows(contacts, result);
    });
  }

  void _share(String phone) {
    Navigator.of(context).pop();
    ref.read(appControllerProvider.notifier).requestShare(phone);
  }

  /// Convenience path: launch the OS contact picker (`ACTION_PICK`). The system
  /// contacts app does the reading and hands back only the chosen contact via a
  /// temporary URI grant — a one-tap alternative to scrolling the in-app list,
  /// and a safety net if the in-app read ever comes up short on some device. The
  /// picked number is looked up + added as a row so it lands in On Moona / Not
  /// on Moona just like a browsed contact.
  Future<void> _pickFromSystem() async {
    native_picker.Contact? picked;
    try {
      picked = await native_picker.FlutterNativeContactPicker()
          .selectPhoneNumber();
    } catch (e) {
      debugPrint('Moona[contacts]: native pick failed: $e');
    }
    if (!mounted || picked == null) return;
    final number = picked.selectedPhoneNumber?.trim().isNotEmpty == true
        ? picked.selectedPhoneNumber!
        : (picked.phoneNumbers?.isNotEmpty == true
              ? picked.phoneNumbers!.first
              : null);
    if (number == null || number.trim().isEmpty) return;

    final contact = ContactPickerDeviceContact(picked.fullName ?? '', number);
    final phones = contactLookupPhones([contact]);
    var result = const ContactLookupResult();
    if (phones.isNotEmpty) {
      result = await ref
          .read(appControllerProvider.notifier)
          .lookupContacts(phones);
    }
    if (!mounted) return;

    final newRows = buildContactPickerRows([contact], result);
    setState(() {
      final existing = _rows.map((r) => r.phoneDigits).toSet();
      _rows = [
        ...newRows.where((r) => !existing.contains(r.phoneDigits)),
        ..._rows,
      ];
    });
  }

  bool _matches(ContactPickerRow r, String query, String digits) {
    if (query.isEmpty) return true;
    return r.name.toLowerCase().contains(query.toLowerCase()) ||
        (digits.isNotEmpty && r.phoneDigits.contains(digits)) ||
        r.phone.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final query = _query.text.trim();
    final digits = query.replaceAll(RegExp(r'\D'), '');

    final registered = [
      for (final r in _rows)
        if (r.registered && _matches(r, query, digits)) r,
    ];
    final unregistered = [
      for (final r in _rows)
        if (!r.registered && _matches(r, query, digits)) r,
    ];

    // Offer a manual share when a typed number isn't already in the rows.
    final inRows = _rows.any(
      (r) => digits.isNotEmpty && r.phoneDigits.contains(digits),
    );
    final showManual = digits.length >= 6 && !inRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoonaField(
          controller: _query,
          placeholder: t.searchContacts,
          onChanged: (_) => setState(() {}),
          trailing: MoonaIcon('search', size: 20, color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        // Always available: opens the OS contact picker — a one-tap native
        // shortcut alongside the in-app list, and a safety net if that list
        // ever comes up short on some device.
        MoonaButton(
          label: t.pickFromContacts,
          icon: 'person',
          variant: MoonaButtonVariant.tonal,
          full: true,
          onPressed: _pickFromSystem,
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
        else if (registered.isEmpty && unregistered.isEmpty) ...[
          _EmptyHint(
            // When there are no rows at all, say why; if rows exist but the
            // search filtered them out, fall back to the manual-entry hint.
            text: _rows.isEmpty
                ? switch (widget.loaded.status) {
                    ContactLoadStatus.denied => t.contactsDeniedHint,
                    ContactLoadStatus.error => t.contactsLoadError,
                    ContactLoadStatus.ok => widget.loaded.rawCount == 0
                        ? t.noContactsFound
                        : t.contactsNoPhones(widget.loaded.rawCount),
                  }
                : t.enterPhoneManually,
          ),
          if (widget.loaded.status == ContactLoadStatus.denied) ...[
            const SizedBox(height: 8),
            MoonaButton(
              label: t.openContactsSettings,
              variant: MoonaButtonVariant.text,
              full: true,
              onPressed: openAppSettings,
            ),
          ],
        ] else ...[
          if (registered.isNotEmpty) ...[
            _SectionLabel(t.onMoona),
            for (final r in registered)
              _ContactRow(
                name: r.name,
                phone: r.phone,
                registered: true,
                isSelf: r.isSelf,
                onTap: r.isSelf ? null : () => _share(r.phone),
              ),
          ],
          if (unregistered.isNotEmpty) ...[
            if (registered.isNotEmpty) const SizedBox(height: 8),
            _SectionLabel(t.notOnMoona),
            for (final r in unregistered)
              _ContactRow(
                name: r.name,
                phone: r.phone,
                registered: false,
                isSelf: false,
                trailingLabel: t.invite,
                onTap: () => _share(r.phone),
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
