import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_body_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/markdown_preview_fonts.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:appflowy/workspace/application/collections/email/email_html.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One message, opened.
///
/// The body is rendered as the sender wrote it, with scripts, frames and forms
/// stripped out and JavaScript switched off. Pictures the message carries are
/// always shown; pictures it fetches from a server can be turned off, because
/// loading one reports that the message was opened, when, and from where.
class EmailReader extends StatefulWidget {
  const EmailReader({
    super.key,
    required this.message,
    required this.theme,
    this.controller,
    this.body,
  }) : assert(
          controller != null || body != null,
          'A reader needs either a mailbox to read from or a parsed message.',
        );

  final EmailMessage message;
  final EmailTheme theme;

  /// The mailbox this message belongs to, when it is being read inside one.
  final EmailController? controller;

  /// A message that has already been read off disk, for a lone `.eml` file.
  final MimeMessage? body;

  @override
  State<EmailReader> createState() => _EmailReaderState();
}

class _EmailReaderState extends State<EmailReader> {
  /// Pictures the message fetches from a server. Shown by default, and the
  /// head carries a control to turn them off again.
  bool _allowRemote = true;

  /// Whether to show the message as it was written or as plain words.
  bool _asWritten = true;

  @override
  void initState() {
    super.initState();
    // The application's own face is inlined into the document, so a message
    // is set in the same type as the pane around it.
    if (markdownPreviewFontFaces == null) {
      unawaited(
        loadMarkdownPreviewFontFaces().then((_) {
          if (mounted) {
            setState(() {});
          }
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final controller = widget.controller;
    final body = widget.body ?? controller?.bodyOf(widget.message.id);
    if (body == null && controller != null) {
      return FutureBuilder<MimeMessage?>(
        future: controller.loadBody(widget.message.id),
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
          final loaded = snapshot.data;
          if (loaded == null) {
            return EmailEmptyState(
              icon: Icons.report_gmailerrorred_rounded,
              title: LocaleKeys.collections_email_unreadable.tr(),
              theme: theme,
              message: LocaleKeys.collections_email_unreadableHint.tr(),
            );
          }
          return _build(context, loaded);
        },
      );
    }
    if (body == null) {
      return EmailEmptyState(
        icon: Icons.report_gmailerrorred_rounded,
        title: LocaleKeys.collections_email_unreadable.tr(),
        theme: theme,
        message: LocaleKeys.collections_email_unreadableHint.tr(),
      );
    }
    return _build(context, body);
  }

  Widget _build(BuildContext context, MimeMessage body) {
    final theme = widget.theme;
    final hasHtml = (body.htmlBody ?? '').trim().isNotEmpty;
    final rendered = canRenderEmailHtml && _asWritten;

    if (!rendered) {
      return _plain(context, body);
    }

    final document = buildEmailHtmlDocument(
      body,
      palette: emailHtmlPaletteOf(theme),
      allowRemoteContent: _allowRemote,
      fontFaces: markdownPreviewFontFaces ?? '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EmailMetrics.space6,
            EmailMetrics.space5,
            EmailMetrics.space6,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(
                message: widget.message,
                body: body,
                theme: theme,
                asWritten: hasHtml ? _asWritten : null,
                onToggleView: hasHtml
                    ? () => setState(() => _asWritten = !_asWritten)
                    : null,
                showImages: document.hasRemoteContent ? _allowRemote : null,
                onToggleImages: document.hasRemoteContent
                    ? () => setState(() => _allowRemote = !_allowRemote)
                    : null,
              ),
              if (body.attachments.isNotEmpty) ...[
                const SizedBox(height: EmailMetrics.space4),
                _Attachments(parts: body.attachments, theme: theme),
              ],
              const SizedBox(height: EmailMetrics.space4),
              if (document.hasBlockedRemoteContent)
                EmailRemoteContentBar(
                  count: document.blockedRemoteCount,
                  theme: theme,
                  message: LocaleKeys.collections_email_remoteBlocked
                      .tr(args: ['${document.blockedRemoteCount}']),
                  actionLabel: LocaleKeys.collections_email_loadImages.tr(),
                  onLoad: () => setState(() => _allowRemote = true),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EmailMetrics.space5,
              0,
              EmailMetrics.space3,
              EmailMetrics.space3,
            ),
            child: EmailBodyView(html: document.html, theme: theme),
          ),
        ),
      ],
    );
  }

  Widget _plain(BuildContext context, MimeMessage body) {
    final theme = widget.theme;
    final text = _readableBody(body);
    final hasHtml = (body.htmlBody ?? '').trim().isNotEmpty;
    return EmailScrollArea(
      padding: const EdgeInsets.fromLTRB(
        EmailMetrics.space6,
        EmailMetrics.space5,
        EmailMetrics.space6,
        EmailMetrics.space6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: EmailMetrics.readingWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(
                message: widget.message,
                body: body,
                theme: theme,
                asWritten: hasHtml && canRenderEmailHtml ? _asWritten : null,
                onToggleView: hasHtml && canRenderEmailHtml
                    ? () => setState(() => _asWritten = !_asWritten)
                    : null,
              ),
              const SizedBox(height: EmailMetrics.space5),
              if (text.trim().isEmpty)
                Text(
                  LocaleKeys.collections_email_emptyBody.tr(),
                  style: theme.meta,
                )
              else
                SelectableText(text, style: theme.body),
              if (body.attachments.isNotEmpty) ...[
                const SizedBox(height: EmailMetrics.space6),
                _Attachments(parts: body.attachments, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The message palette, taken from the mailbox's own so a body sits on the
/// same surface as the pane around it.
EmailHtmlPalette emailHtmlPaletteOf(EmailTheme theme) => EmailHtmlPalette(
      brightness: theme.brightness,
      background: theme.panel,
      text: theme.textBody,
      muted: theme.textFaint,
      link: theme.accent,
      rule: theme.palette.border,
      quote: theme.palette.border,
      scrollbar: theme.textFaint.withValues(alpha: 0.5),
    );

class _Head extends StatelessWidget {
  const _Head({
    required this.message,
    required this.body,
    required this.theme,
    this.asWritten,
    this.onToggleView,
    this.showImages,
    this.onToggleImages,
  });

  final EmailMessage message;
  final MimeMessage body;
  final EmailTheme theme;

  /// Null when the message has only one form and there is nothing to switch.
  final bool? asWritten;
  final VoidCallback? onToggleView;

  /// Null when nothing in the message reaches out to another server.
  final bool? showImages;
  final VoidCallback? onToggleImages;

  @override
  Widget build(BuildContext context) {
    final to = body.to.map((address) => address.display).join(', ');
    final cc = body.cc.map((address) => address.display).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                body.subject.isEmpty
                    ? LocaleKeys.collections_email_noSubject.tr()
                    : body.subject,
                style: theme.face(
                  fontSize: 19,
                  color: theme.textStrong,
                  axis: 650,
                  weight: FontWeight.w700,
                  height: 1.28,
                ),
              ),
            ),
            if (onToggleImages != null) ...[
              const SizedBox(width: EmailMetrics.space2),
              EmailAction(
                icon: showImages ?? true
                    ? Icons.image_rounded
                    : Icons.hide_image_rounded,
                tooltip: showImages ?? true
                    ? LocaleKeys.collections_email_hideImages.tr()
                    : LocaleKeys.collections_email_loadImages.tr(),
                theme: theme,
                onPressed: onToggleImages,
              ),
            ],
            if (onToggleView != null) ...[
              const SizedBox(width: EmailMetrics.space3),
              EmailAction(
                icon: asWritten ?? true
                    ? Icons.notes_rounded
                    : Icons.article_rounded,
                tooltip: asWritten ?? true
                    ? LocaleKeys.collections_email_showPlainText.tr()
                    : LocaleKeys.collections_email_showAsWritten.tr(),
                theme: theme,
                onPressed: onToggleView,
              ),
            ],
          ],
        ),
        const SizedBox(height: EmailMetrics.space4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmailAvatar(
              name: message.sender,
              seed: message.metadata.fromAddress,
              theme: theme,
              size: 34,
            ),
            const SizedBox(width: EmailMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          body.from?.display ??
                              LocaleKeys.collections_email_unknownSender.tr(),
                          overflow: TextOverflow.ellipsis,
                          style: theme.face(
                            fontSize: EmailMetrics.senderSize + 0.5,
                            color: theme.textStrong,
                            axis: 620,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if ((body.from?.name ?? '').isNotEmpty) ...[
                        const SizedBox(width: EmailMetrics.space2),
                        Flexible(
                          child: Text(
                            body.from!.address,
                            overflow: TextOverflow.ellipsis,
                            style: theme.meta,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (to.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      LocaleKeys.collections_email_toLine.tr(args: [to]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.meta,
                    ),
                  ],
                  if (cc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      LocaleKeys.collections_email_ccLine.tr(args: [cc]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.meta,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: EmailMetrics.space3),
            Text(
              emailFullDateLabel(body.date ?? message.sentAt),
              style: theme.meta,
            ),
          ],
        ),
      ],
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.parts, required this.theme});

  final List<MimePart> parts;
  final EmailTheme theme;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.collections_email_attachments
                .tr(args: ['${parts.length}']),
            style: theme.sectionLabel,
          ),
          const SizedBox(height: EmailMetrics.space2),
          Wrap(
            spacing: EmailMetrics.space2,
            runSpacing: EmailMetrics.space2,
            children: [
              for (final part in parts)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EmailMetrics.space3,
                    vertical: EmailMetrics.space2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.sunken,
                    borderRadius:
                        BorderRadius.circular(EmailMetrics.controlRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconFor(part.mediaType),
                        size: 15,
                        color: theme.iconRest,
                      ),
                      const SizedBox(width: EmailMetrics.space2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          part.filename ??
                              LocaleKeys.collections_email_unnamedPart.tr(),
                          overflow: TextOverflow.ellipsis,
                          style: theme.metaStrong,
                        ),
                      ),
                      const SizedBox(width: EmailMetrics.space2),
                      Text(emailSizeLabel(part.size), style: theme.meta),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );

  IconData _iconFor(String mediaType) {
    if (mediaType.startsWith('image/')) {
      return Icons.image_rounded;
    }
    if (mediaType.startsWith('audio/')) {
      return Icons.audiotrack_rounded;
    }
    if (mediaType.startsWith('video/')) {
      return Icons.movie_rounded;
    }
    if (mediaType == 'application/pdf') {
      return Icons.picture_as_pdf_rounded;
    }
    if (mediaType.startsWith('text/')) {
      return Icons.description_rounded;
    }
    return Icons.attach_file_rounded;
  }
}

/// A whole conversation, read downwards.
class EmailConversationReader extends StatelessWidget {
  const EmailConversationReader({
    super.key,
    required this.controller,
    required this.theme,
  });

  final EmailController controller;
  final EmailTheme theme;

  @override
  Widget build(BuildContext context) {
    final thread = controller.activeThread;
    if (thread == null) {
      return EmailEmptyState(
        icon: Icons.forum_rounded,
        title: LocaleKeys.collections_email_nothingOpen.tr(),
        theme: theme,
        message: LocaleKeys.collections_email_nothingOpenHint.tr(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EmailMetrics.space6,
            EmailMetrics.space5,
            EmailMetrics.space6,
            EmailMetrics.space3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  thread.subject.isEmpty
                      ? LocaleKeys.collections_email_noSubject.tr()
                      : thread.subject,
                  overflow: TextOverflow.ellipsis,
                  style: theme.face(
                    fontSize: 19,
                    color: theme.textStrong,
                    axis: 650,
                    weight: FontWeight.w700,
                    height: 1.28,
                  ),
                ),
              ),
              const SizedBox(width: EmailMetrics.space3),
              EmailChip(
                label: LocaleKeys.collections_email_inThread
                    .tr(args: ['${thread.length}']),
                theme: theme,
                icon: Icons.forum_rounded,
              ),
            ],
          ),
        ),
        Expanded(
          child: EmailScrollArea(
            padding: const EdgeInsets.fromLTRB(
              EmailMetrics.space5,
              0,
              EmailMetrics.space5,
              EmailMetrics.space6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final message in thread.messages)
                  _ConversationEntry(
                    key: ValueKey(message.id),
                    message: message,
                    controller: controller,
                    theme: theme,
                    expanded: message.id == controller.activeId ||
                        thread.isSingle ||
                        !message.read,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationEntry extends StatefulWidget {
  const _ConversationEntry({
    super.key,
    required this.message,
    required this.controller,
    required this.theme,
    required this.expanded,
  });

  final EmailMessage message;
  final EmailController controller;
  final EmailTheme theme;
  final bool expanded;

  @override
  State<_ConversationEntry> createState() => _ConversationEntryState();
}

class _ConversationEntryState extends State<_ConversationEntry> {
  bool? _open;

  bool get _expanded => _open ?? widget.expanded;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final message = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: EmailMetrics.space3),
      child: EmailPanel(
        color: _expanded ? theme.panel : theme.canvas,
        elevation:
            _expanded ? ViewerCardElevation.resting : ViewerCardElevation.flush,
        padding: const EdgeInsets.all(EmailMetrics.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _open = !_expanded),
                child: Row(
                  children: [
                    EmailAvatar(
                      name: message.sender,
                      seed: message.metadata.fromAddress,
                      theme: theme,
                      size: 28,
                    ),
                    const SizedBox(width: EmailMetrics.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.sender.isEmpty
                                ? LocaleKeys.collections_email_unknownSender
                                    .tr()
                                : message.sender,
                            overflow: TextOverflow.ellipsis,
                            style: theme.sender(unread: !message.read),
                          ),
                          if (!_expanded) ...[
                            const SizedBox(height: 2),
                            Text(
                              message.metadata.snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.snippet,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: EmailMetrics.space3),
                    Text(
                      emailDateLabel(message.sentAt),
                      style: theme.meta,
                    ),
                    const SizedBox(width: EmailMetrics.space1),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: theme.textFaint,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: EmailMetrics.space3),
              _ConversationBody(
                message: message,
                controller: widget.controller,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationBody extends StatelessWidget {
  const _ConversationBody({
    required this.message,
    required this.controller,
    required this.theme,
  });

  final EmailMessage message;
  final EmailController controller;
  final EmailTheme theme;

  @override
  Widget build(BuildContext context) {
    final cached = controller.bodyOf(message.id);
    if (cached != null) {
      return _text(cached);
    }
    return FutureBuilder<MimeMessage?>(
      future: controller.loadBody(message.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.accent,
              ),
            ),
          );
        }
        final body = snapshot.data;
        if (body == null) {
          return Text(
            LocaleKeys.collections_email_unreadable.tr(),
            style: theme.meta,
          );
        }
        return _text(body);
      },
    );
  }

  Widget _text(MimeMessage body) {
    final text = _readableBody(body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text.trim().isEmpty)
          Text(LocaleKeys.collections_email_emptyBody.tr(), style: theme.meta)
        else
          SelectableText(text, style: theme.body),
        if (body.attachments.isNotEmpty) ...[
          const SizedBox(height: EmailMetrics.space4),
          _Attachments(parts: body.attachments, theme: theme),
        ],
      ],
    );
  }
}

/// The words of a message, whichever way it was written.
String _readableBody(MimeMessage body) {
  final plain = body.plainBody;
  if (plain != null && plain.trim().isNotEmpty) {
    return plain.trimRight();
  }
  final html = body.htmlBody;
  if (html == null || html.trim().isEmpty) {
    return '';
  }
  return _htmlToText(html).trimRight();
}

String _htmlToText(String html) => html
    .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>'), '')
    .replaceAll(RegExp('<br[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp('</(p|div|tr|li|h[1-6])>', caseSensitive: false), '\n')
    .replaceAll(RegExp('<li[^>]*>', caseSensitive: false), '• ')
    .replaceAll(RegExp('<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ');

/// Copies a message's text, for the reading pane's own action.
Future<void> copyEmailBody(MimeMessage body) =>
    Clipboard.setData(ClipboardData(text: _readableBody(body)));
