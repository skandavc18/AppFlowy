import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

@immutable
class BookNoteDraft {
  const BookNoteDraft({
    required this.quote,
    required this.body,
    required this.color,
    this.deleted = false,
  });

  const BookNoteDraft.deleted()
      : quote = '',
        body = '',
        color = BookNoteColor.yellow,
        deleted = true;

  final String quote;
  final String body;
  final BookNoteColor color;
  final bool deleted;
}

/// Writes down a passage worth keeping and what the reader thought of it.
Future<BookNoteDraft?> showBookNoteEditor({
  required BuildContext context,
  required BookReaderPalette palette,
  BookNote? note,
}) {
  return showDialog<BookNoteDraft>(
    context: context,
    barrierColor: palette.shadow.withValues(alpha: 0.34),
    builder: (context) => _BookNoteEditor(palette: palette, note: note),
  );
}

class _BookNoteEditor extends StatefulWidget {
  const _BookNoteEditor({required this.palette, this.note});

  final BookReaderPalette palette;
  final BookNote? note;

  @override
  State<_BookNoteEditor> createState() => _BookNoteEditorState();
}

class _BookNoteEditorState extends State<_BookNoteEditor> {
  late final TextEditingController quote =
      TextEditingController(text: widget.note?.quote ?? '');
  late final TextEditingController body =
      TextEditingController(text: widget.note?.body ?? '');
  late BookNoteColor color = widget.note?.color ?? BookNoteColor.yellow;

  @override
  void dispose() {
    quote.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: palette.chrome,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.rule, width: 0.6),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 34,
              offset: const Offset(0, 16),
              spreadRadius: -10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.note == null
                  ? LocaleKeys.collections_book_addNote.tr()
                  : LocaleKeys.collections_book_editNote.tr(),
              style: TextStyle(
                color: palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _field(
              palette: palette,
              controller: quote,
              hint: LocaleKeys.collections_book_noteQuote.tr(),
              minLines: 2,
              maxLines: 5,
              italic: true,
              wash: bookNoteWash(color, palette),
            ),
            const SizedBox(height: 10),
            _field(
              palette: palette,
              controller: body,
              hint: LocaleKeys.collections_book_noteBody.tr(),
              minLines: 3,
              maxLines: 8,
              autofocus: true,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final value in BookNoteColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ColorDot(
                      color: bookNoteColor(
                        value,
                        isDark: palette.theme.isDark,
                      ),
                      selected: value == color,
                      ring: palette.ink,
                      onTap: () => setState(() => color = value),
                    ),
                  ),
                const Spacer(),
                if (widget.note != null)
                  _DialogButton(
                    palette: palette,
                    label: LocaleKeys.collections_book_deleteNote.tr(),
                    destructive: true,
                    onTap: () => Navigator.of(context)
                        .pop(const BookNoteDraft.deleted()),
                  ),
                const SizedBox(width: 8),
                _DialogButton(
                  palette: palette,
                  label: LocaleKeys.button_cancel.tr(),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _DialogButton(
                  palette: palette,
                  label: LocaleKeys.collections_book_saveNote.tr(),
                  primary: true,
                  onTap: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final draft = BookNoteDraft(
      quote: quote.text.trim(),
      body: body.text.trim(),
      color: color,
    );
    if (draft.quote.isEmpty && draft.body.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(draft);
  }

  Widget _field({
    required BookReaderPalette palette,
    required TextEditingController controller,
    required String hint,
    required int minLines,
    required int maxLines,
    bool italic = false,
    bool autofocus = false,
    Color? wash,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      autofocus: autofocus,
      style: TextStyle(
        color: palette.ink,
        fontSize: 13,
        height: 1.5,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: wash ?? palette.page,
        hoverColor: wash ?? palette.page,
        hintText: hint,
        hintStyle: TextStyle(color: palette.inkFaint, fontSize: 13),
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.rule, width: 0.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.rule, width: 0.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.ring,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? ring : color,
              width: selected ? 2 : 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.palette,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final BookReaderPalette palette;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final foreground = widget.primary
        ? palette.chrome
        : widget.destructive
            ? const Color(0xFFCC5A57)
            : palette.inkMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.primary
                ? palette.accent
                : hovered
                    ? palette.hover
                    : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: foreground,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
