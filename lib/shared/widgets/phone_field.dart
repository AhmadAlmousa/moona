import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';
import '../../core/util/countries.dart';
import 'fields.dart';
import 'moona_icon.dart';
import 'sheet.dart';

/// A [MoonaField] for phone numbers with a leading country-code selector.
///
/// The selected [country] dial code is shown as a tappable chip (`ISO +code`)
/// that opens a searchable country picker; the text field holds only the local
/// number. Callers combine the two with `composeInternationalPhone` on submit.
class MoonaPhoneField extends StatelessWidget {
  const MoonaPhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    required this.isArabic,
    this.label,
    this.placeholder,
    this.error,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final Country country;
  final ValueChanged<Country> onCountryChanged;
  final bool isArabic;
  final String? label;
  final String? placeholder;
  final String? error;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return MoonaField(
      controller: controller,
      label: label,
      placeholder: placeholder,
      error: error,
      keyboardType: TextInputType.phone,
      // Phone numbers always read left-to-right, even in the Arabic RTL layout.
      textDirection: TextDirection.ltr,
      autofocus: autofocus,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      leading: _CountryCodeButton(
        country: country,
        onTap: () async {
          final picked = await showCountryPicker(
            context: context,
            isArabic: isArabic,
            selected: country,
          );
          if (picked != null) onCountryChanged(picked);
        },
      ),
    );
  }
}

/// The leading ISO + dial-code chip, with a divider separating it from the
/// number input.
class _CountryCodeButton extends StatelessWidget {
  const _CountryCodeButton({required this.country, required this.onTap});

  final Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CountryFlag(country),
          const SizedBox(width: 6),
          Text(
            '+${country.dialCode}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
          const SizedBox(width: 2),
          // Right-pointing chevron rotated a quarter-turn to point down.
          MoonaIcon(
            'chevron',
            size: 16,
            color: c.onSurfaceVariant,
            turns: 1.5708,
          ),
          const SizedBox(width: 10),
          Container(width: 1.2, height: 24, color: c.outlineVariant),
        ],
      ),
    );
  }
}

/// Shows the country picker bottom sheet and resolves to the chosen [Country],
/// or null if dismissed.
Future<Country?> showCountryPicker({
  required BuildContext context,
  required bool isArabic,
  required Country selected,
}) {
  return showMoonaSheet<Country>(
    context: context,
    title: isArabic ? 'اختر الدولة' : 'Select country',
    builder: (_) => _CountryPicker(isArabic: isArabic, selected: selected),
  );
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.isArabic, required this.selected});

  final bool isArabic;
  final Country selected;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final query = _query.text;
    final results = kCountries.where((e) => e.matches(query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoonaField(
          controller: _query,
          placeholder: widget.isArabic ? 'بحث' : 'Search',
          autofocus: true,
          onChanged: (_) => setState(() {}),
          trailing: MoonaIcon('search', size: 20, color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final country in results)
          _CountryRow(
            country: country,
            isArabic: widget.isArabic,
            selected: country.iso == widget.selected.iso,
            onTap: () => Navigator.of(context).pop(country),
          ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              widget.isArabic ? 'لا توجد نتائج' : 'No matches',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.isArabic,
    required this.selected,
    required this.onTap,
  });

  final Country country;
  final bool isArabic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            _CountryFlag(country),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                country.name(isArabic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.onSurface,
                ),
              ),
            ),
            Text(
              '+${country.dialCode}',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.onSurfaceVariant,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 10),
              MoonaIcon('check', size: 20, color: c.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Country flag rendered from the `country_code_picker` bundled PNG assets, in a
/// fixed-width slot so the chip and picker rows stay aligned. Flag emoji are
/// unreliable on Android, so we use real images and fall back to the ISO text
/// badge if an asset is ever missing.
class _CountryFlag extends StatelessWidget {
  const _CountryFlag(this.country);

  final Country country;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        'flags/${country.iso.toLowerCase()}.png',
        package: 'country_code_picker',
        width: 32,
        height: 22,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _CountryIsoBadge(country.iso),
      ),
    );
  }
}

class _CountryIsoBadge extends StatelessWidget {
  const _CountryIsoBadge(this.iso);

  final String iso;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 34,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        iso.toUpperCase(),
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: c.onSurfaceVariant,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
