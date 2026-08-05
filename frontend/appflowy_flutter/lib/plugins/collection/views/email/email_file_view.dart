import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/email/email_reader.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A single `.eml` opened on its own, outside any mailbox.
///
/// A message stored as a plain workspace file is still a message, so it is
/// read with the same parser and shown with the same reader a collection uses.
/// Nothing here belongs to a mailbox: the file is parsed once and handed
/// straight to [EmailReader].
class EmailFileView extends StatefulWidget {
  const EmailFileView({super.key, required this.view, required this.file});

  final ViewPB view;
  final File file;

  @override
  State<EmailFileView> createState() => _EmailFileViewState();
}

class _EmailFileViewState extends State<EmailFileView> {
  Future<MimeMessage?>? _message;

  @override
  void initState() {
    super.initState();
    _message = _read();
  }

  @override
  void didUpdateWidget(covariant EmailFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _message = _read();
    }
  }

  Future<MimeMessage?> _read() async {
    try {
      final length = await widget.file.length();
      final bytes = length <= maxMimeMessageBytes
          ? await widget.file.readAsBytes()
          : await _readHead(maxMimeMessageBytes);
      // An exported archive holds many messages back to back; the first one is
      // what a single-message reader can honestly show.
      final source =
          looksLikeMboxArchive(bytes) ? splitMboxArchive(bytes).first : bytes;
      return parseMimeMessage(source);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readHead(int count) async {
    final handle = await widget.file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = emailThemeOf(context);
    return ColoredBox(
      color: theme.canvas,
      child: FutureBuilder<MimeMessage?>(
        future: _message,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.accent,
                ),
              ),
            );
          }

          final body = snapshot.data;
          if (body == null) {
            return EmailEmptyState(
              icon: Icons.report_gmailerrorred_rounded,
              title: LocaleKeys.collections_email_messageUnreadable.tr(),
              theme: theme,
              message: LocaleKeys.collections_email_unreadableHint.tr(),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(
              EmailMetrics.space5,
              EmailMetrics.space4,
              EmailMetrics.space5,
              EmailMetrics.space5,
            ),
            child: EmailPanel(
              child: EmailReader(
                key: ValueKey(widget.file.path),
                message: EmailMessage(
                  view: widget.view,
                  metadata: EmailMetadata.fromMime(body),
                ),
                body: body,
                theme: theme,
              ),
            ),
          );
        },
      ),
    );
  }
}
