import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

typedef MaterializedFileLoader = Future<File> Function({
  required String source,
  required String name,
  required Map<String, String> httpHeaders,
});

/// Retains one future per mounted request; constructing this widget does no I/O.
class MaterializedFileBuilder extends StatefulWidget {
  const MaterializedFileBuilder({
    super.key,
    required this.source,
    required this.name,
    required this.builder,
    this.httpHeaders = const {},
    this.loader = materializeMediaFile,
  });

  final String source;
  final String name;
  final Map<String, String> httpHeaders;
  final AsyncWidgetBuilder<File> builder;
  final MaterializedFileLoader loader;

  @override
  State<MaterializedFileBuilder> createState() =>
      _MaterializedFileBuilderState();
}

class _MaterializedFileBuilderState extends State<MaterializedFileBuilder> {
  late Future<File> _future;
  late Map<String, String> _httpHeaders;
  int _requestRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MaterializedFileBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.name != widget.name ||
        !mapEquals(_httpHeaders, widget.httpHeaders) ||
        !identical(oldWidget.loader, widget.loader)) {
      _load();
    }
  }

  void _load() {
    // Keep both comparison and in-flight credentials safe from caller mutation.
    _httpHeaders = Map<String, String>.unmodifiable(widget.httpHeaders);
    _requestRevision++;
    _future = Future<File>.sync(
      () => widget.loader(
        source: widget.source,
        name: widget.name,
        httpHeaders: _httpHeaders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      // A new request must not retain the previous snapshot's data or error.
      key: ValueKey(_requestRevision),
      future: _future,
      builder: widget.builder,
    );
  }
}
