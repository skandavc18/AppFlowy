import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// The largest PDF a link downloads to show in place; anything bigger opens
/// in the browser instead.
const _maxPdfBytes = 64 * 1024 * 1024;

/// Any PDF on the web, and arXiv papers, shown in AppFlowy's own PDF viewer:
/// a browser's viewer cannot be framed, and a site's page around its PDF is
/// rarely what was linked.
///
/// Registered last: a site that previews its own files, like Dropbox or
/// GitHub, shows them on its own page instead.
class PdfEmbeds extends WebEmbedProvider {
  const PdfEmbeds();

  /// `2101.00001v2` and the older `hep-th/9901001`.
  static final _arxivId = RegExp(
    r'^(?:\d{4}\.\d{4,5}|[a-z-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?$',
  );

  @override
  String get id => 'pdf';

  @override
  String get name => 'PDF';

  @override
  List<String> get keywords =>
      const ['pdf', 'document', 'paper', 'report', 'arxiv', 'research'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Paper' ? Icons.science_rounded : Icons.picture_as_pdf_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFD93025);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'arxiv.org' ||
        host == 'www.arxiv.org' ||
        host == 'export.arxiv.org') {
      return _arxiv(segments);
    }
    if (webEmbedFileExtension(uri) != 'pdf') {
      return null;
    }
    // A signed download link breaks without its query, so it stays.
    final address = uri.removeFragment().toString();
    final file = segments.last;
    final stem = file.substring(0, file.length - '.pdf'.length).trim();
    return WebEmbedLink(
      provider: this,
      kind: 'Document',
      url: address,
      embedUrl: address,
      title: stem.isEmpty ? null : stem.replaceAll('_', ' '),
      defaultWidth: 680,
      defaultHeight: 880,
    );
  }

  WebEmbedLink? _arxiv(List<String> segments) {
    if (segments.length < 2 ||
        (segments.first != 'abs' && segments.first != 'pdf')) {
      return null;
    }
    var paper = segments.skip(1).join('/');
    if (paper.toLowerCase().endsWith('.pdf')) {
      paper = paper.substring(0, paper.length - 4);
    }
    if (!_arxivId.hasMatch(paper)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: 'Paper',
      siteName: 'arXiv',
      url: 'https://arxiv.org/abs/$paper',
      id: paper,
      embedUrl: 'https://arxiv.org/pdf/$paper',
      defaultWidth: 680,
      defaultHeight: 880,
      accent: const Color(0xFFB31B1B),
    );
  }

  /// An arXiv paper's title and abstract, from its abstract page.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.kind != 'Paper') {
      return null;
    }
    return fetchWebEmbedPageDetails(
      link,
      tidyTitle: (title) =>
          title.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').trim(),
    );
  }

  @override
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  ) =>
      _WebPdfView(link: link, options: options);
}

/// Downloads already started or finished, by address, so a card that is
/// drawn again does not download its PDF again.
final _downloads = <String, Future<File?>>{};

/// [uri]'s PDF in the cache, downloaded unless it is there already, or null
/// when it could not be fetched or is not a PDF.
Future<File?> _webPdf(Uri uri, {bool refresh = false}) {
  final key = uri.toString();
  final pending = refresh ? null : _downloads.remove(key);
  if (pending != null) {
    _downloads[key] = pending;
    return pending;
  }
  late final Future<File?> download;
  download = _downloadPdf(uri, refresh: refresh).then((file) {
    // A failure is not kept, so the next look tries again.
    if (file == null && identical(_downloads[key], download)) {
      _downloads.remove(key);
    }
    return file;
  });
  _downloads[key] = download;
  while (_downloads.length > 64) {
    _downloads.remove(_downloads.keys.first);
  }
  return download;
}

Future<File?> _downloadPdf(Uri uri, {required bool refresh}) async {
  final Directory temporary;
  try {
    temporary = await getTemporaryDirectory();
  } on Object {
    return null;
  }
  final folder = p.join(temporary.path, 'appflowy_web_embeds');
  final name = sha1.convert(utf8.encode(uri.toString())).toString();
  final cached = File(p.join(folder, '$name.pdf'));
  if (!refresh && cached.existsSync() && cached.lengthSync() > 0) {
    return cached;
  }
  // The viewer may still hold the old copy open, which Windows will not let
  // anything replace, so a fresh copy gets a name of its own.
  final target = refresh
      ? File(
          p.join(folder, '$name-${DateTime.now().microsecondsSinceEpoch}.pdf'),
        )
      : cached;
  final saved = await downloadWebEmbedFile(
    uri,
    target,
    maxBytes: _maxPdfBytes,
    accept: 'application/pdf,*/*;q=0.8',
    validate: _looksLikePdf,
  );
  return saved ? target : null;
}

/// Whether a download starts the way a PDF does, rather than being a sign-in
/// or an error page served under the PDF's address.
bool _looksLikePdf(List<int> head) =>
    latin1.decode(head, allowInvalid: true).contains('%PDF-');

class _WebPdfView extends StatefulWidget {
  const _WebPdfView({required this.link, required this.options});

  final WebEmbedLink link;
  final WebEmbedViewOptions options;

  @override
  State<_WebPdfView> createState() => _WebPdfViewState();
}

class _WebPdfViewState extends State<_WebPdfView> {
  File? _file;
  bool _failed = false;

  /// Bumped by every load, so only the latest one lands.
  int _attempt = 0;

  String get _address => widget.link.embedUrl ?? widget.link.url;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _WebPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reload = widget.options.reloadToken != oldWidget.options.reloadToken;
    final moved = _address != (oldWidget.link.embedUrl ?? oldWidget.link.url);
    if (reload || moved) {
      setState(() {
        _file = null;
        _failed = false;
      });
      unawaited(_load(refresh: reload && !moved));
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final attempt = ++_attempt;
    final uri = Uri.tryParse(_address);
    final file = uri == null ? null : await _webPdf(uri, refresh: refresh);
    if (!mounted || attempt != _attempt) {
      return;
    }
    setState(() {
      _file = file;
      _failed = file == null;
    });
  }

  void _retry() {
    setState(() => _failed = false);
    unawaited(_load(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return WebEmbedFailure(
        url: widget.link.url,
        message: 'This PDF could not be downloaded to show here.',
        onRetry: _retry,
      );
    }
    final file = _file;
    if (file == null) {
      return WebEmbedLoadingPlaceholder(link: widget.link);
    }
    return IgnorePointer(
      ignoring: !widget.options.interactive,
      child: PdfPreview(
        // A fresh copy is a new document for the viewer to open.
        key: ValueKey(file.path),
        file: file,
        name: widget.link.title ?? 'PDF',
        bare: true,
        editable: false,
        metadata: const {},
        onMetadataChanged: (_) {},
      ),
    );
  }
}
