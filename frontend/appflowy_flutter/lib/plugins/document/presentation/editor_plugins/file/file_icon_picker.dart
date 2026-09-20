import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';

import 'file_icon_binding.dart';
import 'file_preview_kind.dart';

/// The file-type symbol remains the fallback for legacy and cleared icons.
class FileIdentityGlyph extends StatelessWidget {
  const FileIdentityGlyph({
    super.key,
    required this.icon,
    required this.name,
    this.size = 19,
    this.color,
  });

  final EmojiIconData icon;
  final String? name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => icon.isEmpty
      ? Icon(fileIconForName(name), size: size, color: color)
      : RawEmojiIconWidget(emoji: icon, emojiSize: size);
}

/// A stable, host-side identity control: never a key or input to the renderer.
class FileBlockIconButton extends StatefulWidget {
  const FileBlockIconButton({
    super.key,
    required this.binding,
    required this.name,
    this.documentId,
    this.color,
    this.buttonSize = 34,
  });

  final FileBlockIconBinding binding;
  final String? name;
  final String? documentId;
  final Color? color;
  final double buttonSize;

  @override
  State<FileBlockIconButton> createState() => FileBlockIconButtonState();
}

class FileBlockIconButtonState extends State<FileBlockIconButton> {
  final _controller = PopoverController();
  VoidCallback? _releaseToolbar;
  bool _open = false;
  bool _saving = false;
  int _session = 0;

  @override
  void initState() {
    super.initState();
    widget.binding.addListener(_bindingChanged);
  }

  @override
  void didUpdateWidget(covariant FileBlockIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.binding != widget.binding) {
      oldWidget.binding.removeListener(_bindingChanged);
      widget.binding.addListener(_bindingChanged);
      _controller.close();
      _closed();
    }
  }

  void _bindingChanged() {
    if (!mounted) return;
    if (_open && !widget.binding.canEdit) {
      _controller.close();
      _closed();
    }
    setState(() {});
  }

  /// Always hold the stable host region. Some renderers (PDF) supply their
  /// detached menu context, which cannot locate that region after dismissal.
  void open({BuildContext? toolbarContext}) {
    if (!mounted || _open || !widget.binding.canEdit) return;
    _open = true;
    _session++;
    final releaseHost = PreviewToolbarRegion.hold(context);
    final releaseOrigin = toolbarContext?.mounted == true
        ? PreviewToolbarRegion.hold(toolbarContext!)
        : null;
    _releaseToolbar = () {
      releaseOrigin?.call();
      releaseHost();
    };
    keepEditorFocusNotifier.increase();
    _controller.show();
  }

  void _closed() {
    if (!_open) return;
    _open = false;
    _session++;
    _releaseToolbar?.call();
    _releaseToolbar = null;
    keepEditorFocusNotifier.decrease();
  }

  @override
  void dispose() {
    widget.binding.removeListener(_bindingChanged);
    _closed();
    super.dispose();
  }

  bool _isCurrent(FileBlockIconBinding binding, int session) =>
      mounted &&
      _open &&
      _session == session &&
      identical(widget.binding, binding) &&
      binding.canEdit;

  Future<void> _select(
    SelectedEmojiIconResult result,
    FileBlockIconBinding binding,
    int session,
  ) async {
    if (!_isCurrent(binding, session) || _saving) return;
    _saving = true;
    try {
      final saved = await binding.save(result.data);
      if (_isCurrent(binding, session) && saved && !result.keepOpen) {
        _controller.close();
      }
    } catch (_) {
      if (mounted && _isCurrent(binding, session)) {
        showSnapBar(context, 'Unable to change this file’s icon. Try again.');
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = LocaleKeys.document_plugins_cover_changeIcon.tr();
    return AppFlowyPopover(
      controller: _controller,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: BoxConstraints.loose(const Size(360, 380)),
      onClose: _closed,
      popupBuilder: (_) {
        final binding = widget.binding;
        final session = _session;
        return FlowyIconEmojiPicker(
          documentId: binding.workspaceFileId ?? widget.documentId,
          initialType: binding.icon.toPickerTabType(),
          tabs: kAllIconPickerTabs,
          onSelectedEmoji: (result) => _select(result, binding, session),
        );
      },
      // A disabled glyph still owns its hit target, rather than bubbling a
      // click to the chip's Open file gesture.
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: () {},
        child: IconButton(
          key: const ValueKey('file-icon-picker-button'),
          tooltip: label,
          onPressed: widget.binding.canEdit ? open : null,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: widget.buttonSize,
            height: widget.buttonSize,
          ),
          hoverColor: EditorSurfaceStyle.calloutBackgroundFor(
            theme.brightness,
            theme.colorScheme.surfaceContainerHighest,
            isPaper: PaperTheme.isEnabled(context),
          ),
          icon: FileIdentityGlyph(
            icon: widget.binding.icon,
            name: widget.name,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
