import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';

/// Text field matching the mockup `Field`: rounded inset border that turns
/// primary on focus and error-red when [error] is set, with an optional
/// trailing widget and helper/error text.
class MoonaField extends StatefulWidget {
  const MoonaField({
    super.key,
    this.controller,
    this.label,
    this.placeholder,
    this.error,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.focusNode,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? label;
  final String? placeholder;
  final String? error;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final FocusNode? focusNode;
  final int? minLines;
  final int maxLines;

  @override
  State<MoonaField> createState() => _MoonaFieldState();
}

class _MoonaFieldState extends State<MoonaField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _node.hasFocus);

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hasError = widget.error != null;
    final borderColor = hasError
        ? c.error
        : _focused
        ? c.primary
        : c.outlineVariant;
    final multiline = widget.maxLines > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: hasError ? c.error : c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: BoxConstraints(minHeight: multiline ? 88 : 52),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: _focused ? 2 : 1.3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: multiline
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textDirection: widget.textDirection,
                  autofocus: widget.autofocus,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.onSurface,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: multiline ? 14 : 15,
                    ),
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(
                      color: c.onSurfaceVariant.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.error!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.error,
            ),
          ),
        ] else if (widget.hint != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
