import 'dart:async';

import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/encryption/workspace_lock_screen.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Stands in front of one page, table, folder or file while it is protected and
/// the workspace key has not been entered.
///
/// It is placed around the one host every plugin body is built in, so a
/// protected item of any kind is covered by a single wrapper rather than by a
/// check inside each plugin. The child is not built at all while it is closed,
/// so nothing behind it reads the page.
class ProtectedViewGate extends StatefulWidget {
  const ProtectedViewGate({
    super.key,
    required this.viewId,
    required this.child,
  });

  final String viewId;
  final Widget child;

  @override
  State<ProtectedViewGate> createState() => _ProtectedViewGateState();
}

class _ProtectedViewGateState extends State<ProtectedViewGate> {
  EncryptionVault get _vault => EncryptionVault.instance;

  ViewPB? _view;
  bool _protected = false;

  /// Which ancestor is doing the protecting, so unlocking a folder opens the
  /// files in it rather than asking again for each one.
  String? _protectedBy;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
    unawaited(_read());
  }

  @override
  void didUpdateWidget(ProtectedViewGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      _protected = false;
      _protectedBy = null;
      _view = null;
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    if (!mounted) {
      return;
    }
    // The vault only speaks when the key or the policy changes, so re-reading
    // here is cheap — and it is the only way this notices a mark that was
    // cleared when the passphrase was removed.
    unawaited(_read());
    setState(() {});
  }

  Future<void> _read() async {
    await _vault.ensureLoaded();
    if (!_vault.isConfigured || widget.viewId.isEmpty) {
      // Nothing can be protected without a key, so the backend is not asked.
      if (mounted && _protected) {
        setState(() => _protected = false);
      }
      return;
    }

    final result = await ViewBackendService.getView(widget.viewId);
    final view = result.fold((found) => found, (_) => null);
    if (!mounted) {
      return;
    }

    // Marking the tree covers what was inside the folder when it was
    // protected; the ancestor chain covers whatever was put there afterwards.
    var protected = view?.isProtected ?? false;
    String? protectedBy;
    if (view != null) {
      protectedBy =
          await EncryptionMarkService.protectingAncestorOf(widget.viewId);
      protected = protected || protectedBy != null;
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _view = view;
      _protected = protected;
      _protectedBy = protectedBy;
    });
  }

  bool get _open =>
      _vault.isRevealed(widget.viewId) ||
      (_protectedBy != null && _vault.isRevealed(_protectedBy!));

  @override
  Widget build(BuildContext context) {
    if (_protected && !_open) {
      return LockedContentPlacard(
        name: _view?.name ?? '',
        viewId: widget.viewId,
      );
    }
    return widget.child;
  }
}
