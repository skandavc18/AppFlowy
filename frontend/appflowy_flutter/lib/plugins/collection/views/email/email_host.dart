import 'dart:async';

import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:flutter/material.dart';

/// The key a mailbox's settings, filters and open message are stored under,
/// shared by every email view so the three never disagree.
const emailStateKey = 'email';

/// Loads a mailbox once and hands it to whichever view is showing.
class EmailHost extends StatefulWidget {
  const EmailHost({
    super.key,
    required this.collection,
    required this.builder,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    EmailController controller,
    EmailTheme theme,
  ) builder;

  @override
  State<EmailHost> createState() => _EmailHostState();
}

class _EmailHostState extends State<EmailHost> {
  late final EmailController controller;

  @override
  void initState() {
    super.initState();
    controller = EmailController(
      initialState: widget.collection.stateFor(emailStateKey),
      collectionId: widget.collection.collectionView.id,
      onPersist: (state) =>
          widget.collection.onStateChanged(emailStateKey, state),
      // A sync files real files, so the folder has to be read again before
      // the mailbox can see them.
      onSynced: () => widget.collection.explorer.refresh(),
    )..collectionName = widget.collection.collectionView.name;
    // Register the explorer listener and take the first pass before the
    // controller's own listener, or setState runs during initState.
    widget.collection.explorer.addListener(_syncMessages);
    _syncMessages();
    controller.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncMessages);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await widget.collection.explorer
        .ensureLoaded(widget.collection.collectionView.id);
    if (mounted) {
      // A message that has never been opened knows only its file name; read
      // those once so the mailbox fills itself in.
      unawaited(controller.indexPending());
      controller.beginScheduledSync();
    }
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncMessages() {
    controller.setViews(
      widget.collection.explorer
          .childrenOf(widget.collection.collectionView.id),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        controller,
        emailThemeOf(context),
      );
}
