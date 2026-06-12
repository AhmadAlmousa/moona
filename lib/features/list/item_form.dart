import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/widgets.dart';

/// Most items a single paste can add at once (keeps the batch sane).
const int _maxBulkItems = 50;

/// Opens the add/edit item bottom sheet.
Future<void> showItemForm(
  BuildContext context,
  WidgetRef ref, {
  ListItem? editing,
}) {
  final t = ref.read(appControllerProvider).t;
  return showMoonaSheet(
    context: context,
    title: editing == null ? t.addTitle : t.editTitle,
    builder: (_) => _ItemForm(editing: editing),
  );
}

/// Opens the "paste a list" sheet (one item per line, added in bulk). Returns
/// the number of items added, or null if dismissed.
Future<int?> showBulkPasteSheet(BuildContext context, WidgetRef ref) {
  final t = ref.read(appControllerProvider).t;
  return showMoonaSheet<int>(
    context: context,
    title: t.pasteListTitle,
    builder: (_) => const _BulkPasteForm(),
  );
}

class _ItemForm extends ConsumerStatefulWidget {
  const _ItemForm({this.editing});

  final ListItem? editing;

  @override
  ConsumerState<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<_ItemForm> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _seller;
  late final TextEditingController _note;

  double _count = 1;
  String? _unitId;
  String? _categoryId;
  bool _important = false;
  String? _imageFileId;
  Uint8List? _pickedBytes;
  String? _pickedName;

  bool _expanded = false;
  bool _busy = false;
  String? _nameError;

  List<Product> _suggestions = const [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final initialName = editing == null
        ? ''
        : ref.read(appControllerProvider).productName(editing.productId);
    _name = TextEditingController(text: initialName);
    _brand = TextEditingController(text: editing?.brand ?? '');
    _seller = TextEditingController(text: editing?.seller ?? '');
    _note = TextEditingController(text: editing?.note ?? '');
    _count = editing?.count ?? 1;
    _unitId = editing?.unitId;
    _categoryId = editing == null ? _defaultCategoryId() : editing.categoryId;
    _important = editing?.important ?? false;
    _imageFileId = editing?.imageFileId;
    _expanded =
        editing != null &&
        (_count > 1 ||
            _unitId != null ||
            _brand.text.isNotEmpty ||
            _seller.text.isNotEmpty ||
            _note.text.isNotEmpty);
  }

  String? _defaultCategoryId() {
    final categories = ref.read(appControllerProvider).categories;
    for (final category in categories) {
      if (category.id == 'grocery') return category.id;
    }
    return categories.isEmpty ? null : categories.first.id;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _brand.dispose();
    _seller.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    setState(() => _nameError = null);
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _showSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final results = await ref.read(repositoryProvider).searchProducts(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = results.isNotEmpty;
      });
    });
  }

  void _adjustCount(bool increment) {
    setState(() {
      if (increment) {
        _count = (_count + (_count < 2 ? 0.5 : 1));
      } else {
        final step = (_count > 1 && _count <= 2) ? 0.5 : 1;
        _count = (_count - step).clamp(1, double.infinity).toDouble();
      }
      _count = double.parse(_count.toStringAsFixed(2));
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedBytes = bytes;
        _pickedName = file.name;
        _imageFileId = null;
      });
    } catch (_) {
      // Camera/gallery unavailable (e.g. on web) — silently ignore.
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final state = ref.read(appControllerProvider);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = state.t.nameRequired);
      return;
    }
    setState(() => _busy = true);

    var imageFileId = _imageFileId;
    if (_pickedBytes != null) {
      imageFileId = await ref
          .read(repositoryProvider)
          .uploadImage(
            bytes: _pickedBytes!,
            filename: _pickedName ?? 'item.jpg',
          );
    }

    final form = ItemFormData(
      productName: name,
      count: _count,
      unitId: _unitId,
      categoryId: _categoryId,
      brand: _brand.text.trim(),
      seller: _seller.text.trim(),
      imageFileId: imageFileId,
      important: _important,
      note: _note.text.trim(),
    );

    final controller = ref.read(appControllerProvider.notifier);
    final ok = widget.editing == null
        ? await controller.addItem(form)
        : await controller.updateItem(widget.editing!.id, form);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  void _delete() {
    final id = widget.editing!.id;
    Navigator.of(context).pop();
    ref.read(appControllerProvider.notifier).deleteItem(id);
  }

  /// A muted "added by / last edited by" caption shown when editing an item on a
  /// shared list. Returns null (renders nothing) until a real name is available
  /// — e.g. before the Phase-A backend enrichment deploy — so raw ids never leak.
  Widget? _attributionLine(BuildContext context, AppState state) {
    final item = widget.editing;
    if (item == null || !state.isShared) return null;

    String? resolve(String? name, String? userId) {
      if (name != null && name.isNotEmpty) return name;
      if (userId != null) {
        final mapped = state.profileNames[userId];
        if (mapped != null && mapped.isNotEmpty) return mapped;
      }
      return null;
    }

    final added = resolve(item.createdByDisplayName, item.createdByUserId);
    final editor = resolve(item.updatedByDisplayName, item.updatedByUserId);
    final lines = <String>[
      if (added != null) state.t.addedBy(added),
      if (editor != null && item.updatedByUserId != item.createdByUserId)
        state.t.editedBy(editor),
    ];
    if (lines.isEmpty) return null;

    final c = context.c;
    return Row(
      children: [
        MoonaIcon('person', size: 13, color: c.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            lines.join('  ·  '),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;
    final lang = state.lang;
    final attribution = _attributionLine(context, state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.editing == null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MoonaButton(
              label: t.pasteList,
              icon: 'list',
              variant: MoonaButtonVariant.text,
              height: 34,
              onPressed: () async {
                final added = await showBulkPasteSheet(context, ref);
                if (added != null && added > 0 && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
        _NameField(
          controller: _name,
          label: t.productName,
          placeholder: t.productHint,
          error: _nameError,
          autofocus: widget.editing == null,
          onChanged: _onNameChanged,
          suggestions: _showSuggestions ? _suggestions : const [],
          lang: lang,
          onPick: (product) {
            _name.text = product.label(lang);
            setState(() => _showSuggestions = false);
            FocusScope.of(context).unfocus();
          },
        ),
        const SizedBox(height: 18),
        _ImportantToggle(
          value: _important,
          title: t.important,
          description: t.importantDesc,
          onChanged: (v) => setState(() => _important = v),
        ),
        const SizedBox(height: 14),
        _Label(t.category),
        const SizedBox(height: 8),
        MoonaDropdown<String?>(
          value: _categoryId,
          hint: t.none,
          items: [
            MoonaDropdownEntry(value: null, label: t.none),
            for (final category in state.categories)
              MoonaDropdownEntry(
                value: category.id,
                label: category.label(lang),
                emoji: category.emoji,
              ),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              MoonaIcon(
                'chevron',
                size: 18,
                color: c.onSurfaceVariant,
                turns: _expanded ? 1.5708 : 0,
              ),
              const SizedBox(width: 9),
              Text(
                t.moreDetails,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: c.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(t.count),
                  const SizedBox(height: 6),
                  _CountStepper(
                    count: _count,
                    onDecrement: () => _adjustCount(false),
                    onIncrement: () => _adjustCount(true),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(t.unit),
                    const SizedBox(height: 6),
                    MoonaDropdown<String?>(
                      value: _unitId,
                      hint: t.none,
                      items: [
                        MoonaDropdownEntry(value: null, label: t.none),
                        for (final unit in state.units)
                          MoonaDropdownEntry(
                            value: unit.id,
                            label: unit.label(lang),
                          ),
                      ],
                      onChanged: (v) => setState(() => _unitId = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TermField(
                  controller: _brand,
                  label: t.brand,
                  placeholder: t.brandHint,
                  terms: state.brands,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TermField(
                  controller: _seller,
                  label: t.seller,
                  placeholder: t.sellerHint,
                  terms: state.stores,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Label(t.note),
          const SizedBox(height: 6),
          MoonaField(
            controller: _note,
            placeholder: t.noteHint,
            minLines: 3,
            maxLines: 4,
          ),
        ],
        const SizedBox(height: 14),
        _Label(t.image),
        const SizedBox(height: 8),
        _ImagePicker(
          bytes: _pickedBytes,
          hasExisting: _imageFileId != null,
          addLabel: t.addPhoto,
          takeLabel: t.takePhoto,
          removeLabel: t.removePhoto,
          onTake: () => _pickImage(ImageSource.camera),
          onAdd: () => _pickImage(ImageSource.gallery),
          onRemove: () => setState(() {
            _pickedBytes = null;
            _pickedName = null;
            _imageFileId = null;
          }),
        ),
        const SizedBox(height: 22),
        if (attribution != null) ...[
          attribution,
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            if (widget.editing != null) ...[
              MoonaButton(
                label: '',
                icon: 'trash',
                variant: MoonaButtonVariant.outlined,
                danger: true,
                onPressed: _busy ? null : _delete,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: MoonaButton(
                label: widget.editing == null ? t.addItem : t.save,
                full: true,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 14),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

/// The "paste a list" sheet body: a multiline field where each line becomes an
/// item. Parses + dedupes lines, caps at [_maxBulkItems], and adds them in bulk.
class _BulkPasteForm extends ConsumerStatefulWidget {
  const _BulkPasteForm();

  @override
  ConsumerState<_BulkPasteForm> createState() => _BulkPasteFormState();
}

class _BulkPasteFormState extends ConsumerState<_BulkPasteForm> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Distinct, trimmed, non-empty lines (case-insensitive dedupe), capped.
  List<String> _parse() {
    final seen = <String>{};
    final names = <String>[];
    for (final raw in _text.text.split('\n')) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) names.add(name);
      if (names.length >= _maxBulkItems) break;
    }
    return names;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final names = _parse();
    if (names.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }
    setState(() => _busy = true);
    final added = await ref
        .read(appControllerProvider.notifier)
        .addItemsBulk(names);
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = ref.watch(appControllerProvider).t;
    final count = _parse().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.pasteListHint,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: c.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        MoonaField(
          controller: _text,
          placeholder: t.pasteListPlaceholder,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        MoonaButton(
          label: count > 0 ? t.addAllN(count) : t.addAll,
          full: true,
          onPressed: (_busy || count == 0) ? null : _submit,
        ),
        if (_busy) ...[
          const SizedBox(height: 14),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: context.c.onSurfaceVariant,
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.error,
    required this.autofocus,
    required this.onChanged,
    required this.suggestions,
    required this.onPick,
    required this.lang,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final String? error;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final List<Product> suggestions;
  final ValueChanged<Product> onPick;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoonaField(
          controller: controller,
          label: label,
          placeholder: placeholder,
          error: error,
          autofocus: autofocus,
          onChanged: onChanged,
          trailing: MoonaIcon('search', size: 20, color: c.onSurfaceVariant),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: BoxDecoration(
              color: c.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              children: [
                for (final product in suggestions)
                  InkWell(
                    onTap: () => onPick(product),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          product.label(lang),
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: c.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A free-text field that suggests from a curated [terms] list (brand / store
/// autocomplete). The typed value is kept as-is — suggestions never constrain
/// the input, so users can still enter anything.
class _TermField extends StatefulWidget {
  const _TermField({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.terms,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final List<CatalogTerm> terms;

  @override
  State<_TermField> createState() => _TermFieldState();
}

class _TermFieldState extends State<_TermField> {
  final FocusNode _node = FocusNode();
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _show = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  List<CatalogTerm> get _matches {
    final q = widget.controller.text.trim().toLowerCase();
    final active = widget.terms.where((term) => term.active);
    final filtered = q.isEmpty
        ? active
        : active.where((term) => term.name.toLowerCase().contains(q));
    // Drop an exact match so a fully-typed value doesn't show a 1-row menu.
    return filtered
        .where((term) => term.name.toLowerCase() != q)
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final matches = _show ? _matches : const <CatalogTerm>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoonaField(
          controller: widget.controller,
          focusNode: _node,
          label: widget.label,
          placeholder: widget.placeholder,
          onChanged: (_) => setState(() => _show = true),
        ),
        if (matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: c.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              children: [
                for (final term in matches)
                  InkWell(
                    onTap: () {
                      widget.controller.text = term.name;
                      setState(() => _show = false);
                      _node.unfocus();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          term.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ImportantToggle extends StatelessWidget {
  const _ImportantToggle({
    required this.value,
    required this.title,
    required this.description,
    required this.onChanged,
  });

  final bool value;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: value
            ? Color.alphaBlend(c.error.withValues(alpha: 0.12), c.field)
            : c.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? c.error.withValues(alpha: 0.38) : c.outlineVariant,
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? c.error : c.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: MoonaIcon(
              'tag',
              size: 20,
              color: value ? Colors.white : c.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: c.onSurface,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoonaSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.count,
    required this.onDecrement,
    required this.onIncrement,
  });

  final double count;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.outlineVariant, width: 1.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoonaIconButton(
            icon: 'close',
            size: 16,
            dim: true,
            onPressed: onDecrement,
          ),
          SizedBox(
            width: 42,
            child: Text(
              formatCount(count),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: c.onSurface,
              ),
            ),
          ),
          MoonaIconButton(icon: 'plus', size: 18, onPressed: onIncrement),
        ],
      ),
    );
  }
}

class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.bytes,
    required this.hasExisting,
    required this.addLabel,
    required this.takeLabel,
    required this.removeLabel,
    required this.onTake,
    required this.onAdd,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final bool hasExisting;
  final String addLabel;
  final String takeLabel;
  final String removeLabel;
  final VoidCallback onTake;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (bytes != null || hasExisting) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: bytes != null
                ? Image.memory(bytes!, width: 78, height: 78, fit: BoxFit.cover)
                : Container(
                    width: 78,
                    height: 78,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF9FD9B8), Color(0xFF6BBF8E)],
                      ),
                    ),
                    child: const MoonaIcon(
                      'imageIcon',
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          MoonaButton(
            label: removeLabel,
            icon: 'trash',
            variant: MoonaButtonVariant.outlined,
            danger: true,
            onPressed: onRemove,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PhotoButton(label: takeLabel, icon: 'camera', onTap: onTake),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PhotoButton(label: addLabel, icon: 'imageIcon', onTap: onAdd),
        ),
      ],
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: SizedBox(
          height: 78,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MoonaIcon(icon, size: 22, color: c.onSurface),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: c.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A field-colored box with a dashed outline (the mockup's photo buttons).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      painter: _DashedRectPainter(color: c.outlineVariant),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(color: c.field, child: child),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
