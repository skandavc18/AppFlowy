import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_preview_dialog.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_rail.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Whatever is open, with its previous states alongside it.
///
/// This wraps EVERY page the workspace shows — a written page, a table, a
/// folder, a collection, a file — so history is one feature rather than one
/// per plugin. The rail slides in from the right rather than floating over the
/// content: comparing a version with what is there now is the whole point.
class PageVersionHost extends StatefulWidget {
  const PageVersionHost({
    super.key,
    required this.viewId,
    required this.child,
    this.row,
  });

  final String viewId;
  final Widget child;

  /// Set when what is hosted is a row's page rather than a page of its own.
  final PageVersionRowContext? row;

  @override
  State<PageVersionHost> createState() => _PageVersionHostState();
}

class _PageVersionHostState extends State<PageVersionHost> {
  late ValueNotifier<bool> _open;
  ViewVersionRecorder? _recorder;
  ViewPB? _view;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(PageVersionHost old) {
    super.didUpdateWidget(old);
    if (old.viewId != widget.viewId) {
      _release();
      _adopt();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _adopt() {
    _open = PageVersionPanel.instance.notifierFor(widget.viewId);
    _view = null;
    if (widget.viewId.isEmpty) {
      return;
    }
    // A written page is watched by its own editor, so the recorder here steps
    // aside for it; it works out which it is once the view is read.
    _recorder = ViewVersionRecorder(viewId: widget.viewId, row: widget.row)
      ..start();
    unawaited(_readView());
  }

  void _release() {
    unawaited(_recorder?.stop());
    _recorder = null;
    PageVersionPanel.instance.close(widget.viewId);
  }

  Future<void> _readView() async {
    final view = await PageVersionService.instance.readView(widget.viewId);
    if (mounted) {
      setState(() => _view = view);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viewId.isEmpty) {
      return widget.child;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _open,
      builder: (context, open, child) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: child!),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: open
                  ? PageVersionRail(
                      viewId: widget.viewId,
                      editable: _isEditable,
                      onPreview: (version) => unawaited(_preview(version)),
                      onRestore: (version) => unawaited(_restore(version)),
                      onCaptureNow: () => unawaited(_captureNow()),
                      onClose: () =>
                          PageVersionPanel.instance.close(widget.viewId),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }

  bool get _isEditable {
    final editor = openEditorFor(widget.viewId);
    return editor?.editable ?? true;
  }

  Future<ViewPB?> _currentView() async {
    final view = await PageVersionService.instance.readView(widget.viewId);
    if (view != null && mounted) {
      setState(() => _view = view);
    }
    return view ?? _view;
  }

  Future<void> _preview(PageVersion version) async {
    final versions = await PageVersionService.instance.versions(widget.viewId);
    if (!mounted) {
      return;
    }
    final chosen = await showPageVersionPreview(
      context,
      versions: versions.isEmpty ? [version] : versions,
      selected: version,
      pageName: _view?.name ?? '',
      editable: _isEditable,
    );
    if (chosen != null && mounted) {
      await _restore(chosen);
    }
  }

  Future<void> _captureNow() async {
    final name = await showPageVersionNameDialog(context);
    if (name == null) {
      return;
    }
    final view = await _currentView();
    if (!mounted) {
      return;
    }
    if (view == null) {
      showToastNotification(
        message: LocaleKeys.pageVersions_saveFailed.tr(),
        type: ToastificationType.error,
      );
      return;
    }

    final PageVersion? captured;
    try {
      captured = await PageVersionService.instance.capture(
        view: view,
        openDocument: openEditorFor(widget.viewId)?.document,
        kind: PageVersionKind.manual,
        name: name,
        row: widget.row,
      );
    } on Object catch (error) {
      Log.warn('The page ${widget.viewId} could not be remembered: $error');
      if (mounted) {
        showToastNotification(
          message: LocaleKeys.pageVersions_saveFailed.tr(),
          type: ToastificationType.error,
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    showToastNotification(
      message: captured == null
          ? LocaleKeys.pageVersions_unchanged.tr()
          : LocaleKeys.pageVersions_saved.tr(),
      type: captured == null
          ? ToastificationType.warning
          : ToastificationType.success,
    );
  }

  Future<void> _restore(PageVersion version) async {
    final confirmed = await _confirmRestore(version);
    if (!confirmed || !mounted) {
      return;
    }

    final view = await _currentView();
    if (view == null) {
      return;
    }

    final outcome = await PageVersionService.instance.restore(
      view: view,
      version: version,
      editorState: openEditorFor(widget.viewId),
    );
    if (!mounted) {
      return;
    }

    showToastNotification(
      message: _messageFor(outcome),
      type: outcome.isSuccess
          ? ToastificationType.success
          : ToastificationType.error,
    );
  }

  String _messageFor(PageVersionRestoreOutcome outcome) {
    switch (outcome.result) {
      case PageVersionRestoreResult.restored:
        if (outcome.missingCount > 0) {
          return LocaleKeys.pageVersions_restoredPartly.tr(
            args: ['${outcome.restoredCount}', '${outcome.missingCount}'],
          );
        }
        return LocaleKeys.pageVersions_restored.tr();
      case PageVersionRestoreResult.restoredAsCopy:
        return LocaleKeys.pageVersions_restoredAsTable.tr(
          args: [outcome.createdView?.name ?? '', '${outcome.restoredCount}'],
        );
      case PageVersionRestoreResult.missing:
        return LocaleKeys.pageVersions_unavailable.tr();
      case PageVersionRestoreResult.readOnly:
        return LocaleKeys.pageVersions_readOnly.tr();
      case PageVersionRestoreResult.needsOpenPage:
        return LocaleKeys.pageVersions_needsOpenPage.tr();
      case PageVersionRestoreResult.failed:
        return LocaleKeys.pageVersions_restoreFailed.tr();
    }
  }

  Future<bool> _confirmRestore(PageVersion version) async {
    final when = pageVersionMoment(version.createdAt, now: DateTime.now());
    final body = switch (version.shape) {
      PageVersionShape.database =>
        LocaleKeys.pageVersions_restoreTableBody.tr(args: [when]),
      PageVersionShape.file =>
        LocaleKeys.pageVersions_restoreFileBody.tr(args: [when]),
      PageVersionShape.container =>
        LocaleKeys.pageVersions_restoreFolderBody.tr(args: [when]),
      _ => LocaleKeys.pageVersions_restoreBody.tr(args: [when]),
    };

    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(LocaleKeys.pageVersions_restoreTitle.tr()),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.pageVersions_restore.tr()),
          ),
        ],
      ),
    );
    return answer ?? false;
  }
}
