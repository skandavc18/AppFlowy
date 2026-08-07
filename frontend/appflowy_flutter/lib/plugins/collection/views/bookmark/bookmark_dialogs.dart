import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Saves one or more addresses into [collection].
///
/// [controller] is the open library, when there is one. The collection's own
/// Add button has no library in scope, so it saves the links and leaves the
/// reading to the host, which picks up new children as they arrive.
Future<void> showAddBookmarkDialog({
  required BuildContext context,
  required CollectionViewContext collection,
  BookmarkController? controller,
  String? initialText,
}) async {
  final theme = bookmarkThemeOf(context);
  await showDialog<void>(
    context: context,
    builder: (context) => _AddBookmarkDialog(
      collection: collection,
      controller: controller,
      theme: theme,
      initialText: initialText,
    ),
  );
}

class _AddBookmarkDialog extends StatefulWidget {
  const _AddBookmarkDialog({
    required this.collection,
    required this.controller,
    required this.theme,
    this.initialText,
  });

  final CollectionViewContext collection;
  final BookmarkController? controller;
  final BookmarkTheme theme;
  final String? initialText;

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialText ?? '');
  final FocusNode _focus = FocusNode();
  late bool _snapshot = widget.controller?.settings.autoSnapshot ?? false;
  List<String> _found = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _found = extractBookmarkUrls(_input.text);
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Paste is bound here rather than through `Shortcuts` because the dialog
  /// opens on its own route: until the caret is in the field, nothing in this
  /// subtree is on the focus chain and the key never arrives.
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        _saving ||
        event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return false;
    }
    unawaited(_paste());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return BookmarkDialogShell(
      theme: theme,
      title: LocaleKeys.collections_bookmark_addLinkTitle.tr(),
      description: LocaleKeys.collections_bookmark_addLinkDescription.tr(),
      actions: [
        BookmarkDialogButton(
          theme: theme,
          label: LocaleKeys.collections_bookmark_cancel.tr(),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        BookmarkDialogButton(
          theme: theme,
          label: _saving
              ? LocaleKeys.collections_bookmark_savingLinks
                  .tr(args: ['${_found.length}'])
              : LocaleKeys.collections_bookmark_add.tr(),
          primary: true,
          onPressed: _found.isEmpty || _saving ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _input,
            focusNode: _focus,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            enabled: !_saving,
            cursorColor: theme.accent,
            style: theme.face(
              fontSize: BookmarkMetrics.bodySize + 1,
              color: theme.textStrong,
              height: 1.45,
            ),
            onChanged: (value) =>
                setState(() => _found = extractBookmarkUrls(value)),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.sunken,
              hoverColor: theme.sunken,
              hintText: LocaleKeys.collections_bookmark_addLinkHint.tr(),
              hintStyle: theme.face(
                fontSize: BookmarkMetrics.bodySize + 1,
                color: theme.textFaint,
              ),
              contentPadding: const EdgeInsets.all(BookmarkMetrics.space3),
              border: _border,
              enabledBorder: _border,
              focusedBorder: _border,
              disabledBorder: _border,
            ),
          ),
          const SizedBox(height: BookmarkMetrics.space3),
          Row(
            children: [
              BookmarkAction(
                icon: Icons.content_paste_rounded,
                tooltip:
                    LocaleKeys.collections_bookmark_pasteFromClipboard.tr(),
                theme: theme,
                label: LocaleKeys.collections_bookmark_pasteFromClipboard.tr(),
                onPressed: _saving ? null : _paste,
              ),
              const Spacer(),
              if (_input.text.trim().isNotEmpty)
                Text(
                  switch (_found.length) {
                    0 => LocaleKeys.collections_bookmark_noLinksFound.tr(),
                    1 => LocaleKeys.collections_bookmark_oneLink.tr(),
                    final count => LocaleKeys.collections_bookmark_linkCount
                        .tr(args: ['$count']),
                  },
                  style: theme.meta,
                ),
            ],
          ),
          const SizedBox(height: BookmarkMetrics.space2),
          // Without an open library there is nothing to read the page with
          // here, so the toggle would promise a snapshot nobody takes; the
          // library's own preference governs when it picks the link up.
          if (widget.controller != null)
            _OfflineToggle(
              theme: theme,
              value: _snapshot,
              onChanged:
                  _saving ? null : (value) => setState(() => _snapshot = value),
            ),
          if (_found.isNotEmpty) ...[
            const SizedBox(height: BookmarkMetrics.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final url in _found)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: BookmarkMetrics.space2 + 2,
                          bottom: 3,
                        ),
                        child: Text(
                          bookmarkDisplayUrl(url, maxLength: 72),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.meta,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      );

  /// Writes the clipboard in at the caret, replacing any selection.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    final value = _input.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    setState(() => _found = extractBookmarkUrls(next));
    _focus.requestFocus();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    const service = BookmarkService();
    final parentId = widget.collection.collectionView.id;
    for (final url in _found) {
      await service.createBookmark(parentViewId: parentId, url: url);
    }
    if (!mounted) {
      return;
    }
    final controller = widget.controller;
    Navigator.of(context).pop();
    if (controller == null) {
      return;
    }
    if (_snapshot != controller.settings.autoSnapshot) {
      controller.updateSettings(
        controller.settings.copyWith(autoSnapshot: _snapshot),
      );
    }
    // The explorer reports the new children, and the host then reads each
    // page; asking for the snapshot here keeps that one pass.
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        () => controller.refreshMissing(snapshot: _snapshot),
      ),
    );
  }
}

class _OfflineToggle extends StatelessWidget {
  const _OfflineToggle({
    required this.theme,
    required this.value,
    this.onChanged,
  });

  final BookmarkTheme theme;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor:
            onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          // Matches BookmarkAction's box so the checkbox and the paste button
          // share one left edge.
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BookmarkMetrics.space2 + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    value
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 16,
                    color: value ? theme.accent : theme.textFaint,
                  ),
                  const SizedBox(width: BookmarkMetrics.space1 + 2),
                  Text(
                    LocaleKeys.collections_bookmark_keepOfflineCopy.tr(),
                    style: theme.face(
                      fontSize: BookmarkMetrics.metaSize + 0.5,
                      color: theme.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Renames a bookmark.
Future<void> showRenameBookmarkDialog({
  required BuildContext context,
  required BookmarkEntry entry,
}) async {
  final theme = bookmarkThemeOf(context);
  final controller = TextEditingController(text: entry.view.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => BookmarkDialogShell(
      theme: theme,
      title: LocaleKeys.collections_bookmark_renameTitle.tr(),
      actions: [
        BookmarkDialogButton(
          theme: theme,
          label: LocaleKeys.collections_bookmark_cancel.tr(),
          onPressed: () => Navigator.of(context).pop(),
        ),
        BookmarkDialogButton(
          theme: theme,
          label: LocaleKeys.collections_bookmark_save.tr(),
          primary: true,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
      child: TextField(
        controller: controller,
        autofocus: true,
        cursorColor: theme.accent,
        style: theme.face(
          fontSize: BookmarkMetrics.bodySize + 1,
          color: theme.textStrong,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        decoration: InputDecoration(
          filled: true,
          fillColor: theme.sunken,
          hoverColor: theme.sunken,
          hintText: LocaleKeys.collections_bookmark_renameHint.tr(),
          hintStyle: theme.face(
            fontSize: BookmarkMetrics.bodySize + 1,
            color: theme.textFaint,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BookmarkMetrics.space3,
            vertical: BookmarkMetrics.space3,
          ),
          border: _plainBorder,
          enabledBorder: _plainBorder,
          focusedBorder: _plainBorder,
        ),
      ),
    ),
  );
  controller.dispose();
  if (name != null && name.isNotEmpty && name != entry.view.name) {
    await const BookmarkService().rename(viewId: entry.id, name: name);
  }
}

/// Confirms deleting a bookmark.
Future<bool> confirmDeleteBookmark({
  required BuildContext context,
  required BookmarkEntry entry,
}) async {
  final theme = bookmarkThemeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => BookmarkDialogShell(
      theme: theme,
      title: LocaleKeys.collections_bookmark_deleteTitle.tr(),
      description: LocaleKeys.collections_bookmark_deleteDescription.tr(),
      actions: [
        BookmarkDialogButton(
          theme: theme,
          label: LocaleKeys.collections_bookmark_cancel.tr(),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BookmarkDialogButton(
          theme: theme,
          label: LocaleKeys.collections_bookmark_delete.tr(),
          primary: true,
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: Text(entry.title, style: theme.body),
    ),
  );
  return confirmed ?? false;
}

final OutlineInputBorder _plainBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(10),
  borderSide: BorderSide.none,
);

/// The card every bookmark dialog is drawn on.
class BookmarkDialogShell extends StatelessWidget {
  const BookmarkDialogShell({
    super.key,
    required this.theme,
    required this.title,
    required this.child,
    required this.actions,
    this.description,
    this.width = 460,
  });

  final BookmarkTheme theme;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final String? description;
  final double width;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: BookmarkPanel(
            color: theme.raised,
            padding: const EdgeInsets.all(BookmarkMetrics.space5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.face(
                    fontSize: 16,
                    color: theme.textStrong,
                    axis: BookmarkMetrics.strongWeightAxis,
                    weight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: BookmarkMetrics.space2),
                  Text(description!, style: theme.body),
                ],
                const SizedBox(height: BookmarkMetrics.space4),
                child,
                const SizedBox(height: BookmarkMetrics.space5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final action in actions) ...[
                      action,
                      const SizedBox(width: BookmarkMetrics.space2),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

/// A dialog button: a soft wash, never a saturated block.
class BookmarkDialogButton extends StatelessWidget {
  const BookmarkDialogButton({
    super.key,
    required this.theme,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final BookmarkTheme theme;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tint = destructive
        ? (theme.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
        : theme.accent;
    final enabled = onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(
              horizontal: BookmarkMetrics.space4,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary
                  ? tint.withValues(alpha: theme.isDark ? 0.2 : 0.12)
                  : theme.sunken,
              borderRadius:
                  BorderRadius.circular(BookmarkMetrics.controlRadius),
            ),
            child: Text(
              label,
              style: theme.face(
                fontSize: BookmarkMetrics.bodySize + 0.5,
                color: primary ? tint : theme.textBody,
                axis: BookmarkMetrics.strongWeightAxis,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
