import 'dart:async';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:flutter/material.dart';

/// The writing on a row's own page.
///
/// A wall of cards would otherwise ask the backend for the same page every
/// time it scrolled past, so each page is read once and remembered for as long
/// as the application runs.
class RowPageText {
  const RowPageText._();

  static final Map<String, String> _read = {};
  static final Map<String, Future<String>> _reading = {};

  /// Bumped whenever a page has been forgotten, so anything showing one reads
  /// it again.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String? peek(String documentId) => _read[documentId];

  static Future<String> read(String documentId) {
    if (documentId.isEmpty) {
      return Future.value('');
    }
    final known = _read[documentId];
    if (known != null) {
      return Future.value(known);
    }
    return _reading[documentId] ??= _load(documentId);
  }

  static Future<String> _load(String documentId) async {
    try {
      final result = await DocumentEventGetDocumentText(
        OpenDocumentPayloadPB(documentId: documentId),
      ).send();
      final text = result.fold((data) => data.text, (_) => '');
      _read[documentId] = text;
      return text;
    } finally {
      _reading.removeWhere((key, _) => key == documentId);
    }
  }

  /// Reads the page again the next time somebody asks for it.
  ///
  /// With no id every page is forgotten, which is what a row whose page has
  /// just been made needs: it had no id to forget.
  static void forget([String? documentId]) {
    if (documentId == null) {
      _read.clear();
    } else {
      _read.remove(documentId);
    }
    revision.value++;
  }
}

/// Hands its builder the row's page as soon as it has been read.
///
/// The text is null while it is still being fetched, so a surface can tell
/// "not read yet" from "this page is empty".
class RowPageTextView extends StatefulWidget {
  const RowPageTextView({
    super.key,
    required this.documentId,
    required this.builder,
  });

  final String documentId;
  final Widget Function(BuildContext context, String? text) builder;

  @override
  State<RowPageTextView> createState() => _RowPageTextViewState();
}

class _RowPageTextViewState extends State<RowPageTextView> {
  String? _text;
  int _revision = RowPageText.revision.value;

  @override
  void initState() {
    super.initState();
    RowPageText.revision.addListener(_onForgotten);
    _adopt();
  }

  @override
  void didUpdateWidget(RowPageTextView old) {
    super.didUpdateWidget(old);
    if (old.documentId != widget.documentId) {
      _adopt();
    }
  }

  @override
  void dispose() {
    RowPageText.revision.removeListener(_onForgotten);
    super.dispose();
  }

  void _onForgotten() {
    if (!mounted || _revision == RowPageText.revision.value) {
      return;
    }
    _revision = RowPageText.revision.value;
    setState(() => _text = null);
    _adopt();
  }

  void _adopt() {
    _text = RowPageText.peek(widget.documentId);
    if (_text != null || widget.documentId.isEmpty) {
      return;
    }
    unawaited(
      RowPageText.read(widget.documentId).then((text) {
        if (mounted && widget.documentId.isNotEmpty) {
          setState(() => _text = text);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _text);
}
