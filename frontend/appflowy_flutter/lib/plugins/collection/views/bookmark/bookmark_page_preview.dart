import 'dart:async';

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_view.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/link_bookmark_store.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link written into a page in the bookmark reader.
///
/// It is the same surface a library uses — the live page, the saved copy, the
/// notes and the tags — over a bookmark kept beside its offline copy rather
/// than in the folder tree.
Future<void> openBookmarkPagePreview({
  required BuildContext context,
  required String url,
  String? title,
}) async {
  final target = normalizeBookmarkUrl(url) ?? url;
  if (!canRenderLiveBookmarkPage) {
    final uri = Uri.tryParse(target);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title ?? target,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: BookmarkMetrics.reveal,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _LinkReader(url: target, title: title),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: BookmarkMetrics.curve),
      child: child,
    ),
  );
}

class _LinkReader extends StatefulWidget {
  const _LinkReader({required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<_LinkReader> createState() => _LinkReaderState();
}

class _LinkReaderState extends State<_LinkReader> {
  final LinkBookmarkStore _store = const LinkBookmarkStore();
  BookmarkController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final view = await _store.load(widget.url, title: widget.title);
    if (!mounted) {
      return;
    }
    final controller = BookmarkController(
      service: LinkBookmarkService(url: widget.url, store: _store),
    )..setViews([view]);
    // Nothing is known about a link the first time it is opened, so it reads
    // itself the way a library does when it catches up.
    unawaited(controller.refreshMissing());
    setState(() => _controller = controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return BookmarkReader(
        entryId: LinkBookmarkStore.idFor(widget.url),
        controller: controller,
      );
    }

    final theme = bookmarkThemeOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
      ),
    );
  }
}
