import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_attachments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_block_link.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_html.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_in_app_json.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_plain_text.dart';
import 'package:appflowy/shared/clipboard_state.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/default_extensions.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

/// - support
///   - desktop
///   - web
///   - mobile
///
final CommandShortcutEvent customPasteCommand = CommandShortcutEvent(
  key: 'paste the content',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: _pasteCommandHandler,
);

final CommandShortcutEvent customPastePlainTextCommand = CommandShortcutEvent(
  key: 'paste the plain content',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+shift+v',
  macOSCommand: 'cmd+shift+v',
  handler: _pastePlainCommandHandler,
);

CommandShortcutEventHandler _pasteCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null || editorState.isDisposed || !editorState.editable) {
    return KeyEventResult.ignored;
  }

  doPaste(editorState).then((_) {
    if (editorState.isDisposed) return;
    final context = editorState.document.root.context;
    if (context != null && context.mounted) {
      context.read<ClipboardState?>()?.didPaste();
    }
  });

  return KeyEventResult.handled;
};

CommandShortcutEventHandler _pastePlainCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  doPlainPaste(editorState).then((_) {
    final context = editorState.document.root.context;
    if (context != null && context.mounted) {
      context.read<ClipboardState>().didPaste();
    }
  });

  return KeyEventResult.handled;
};

final _pendingPastes = Expando<bool>();

Future<void> doPaste(
  EditorState editorState, {
  AttachmentPasteService attachments = const AttachmentPasteService(),
}) async {
  if (editorState.isDisposed ||
      !editorState.editable ||
      editorState.selection == null ||
      _pendingPastes[editorState] == true) {
    return;
  }
  final context = editorState.document.root.context;
  final bloc = context?.read<DocumentBloc?>();
  if (bloc?.isClosing == true || bloc?.isClosed == true) return;
  _pendingPastes[editorState] = true;
  final target = AttachmentPasteTarget(
    editorState,
    isActive: () =>
        (bloc == null || (!bloc.isClosing && !bloc.isClosed)) &&
        (context == null ||
            (context.mounted &&
                identical(context.read<DocumentBloc?>(), bloc))),
  );
  try {
    await _doPaste(editorState, target, attachments);
  } catch (_) {
    // Neither source paths, clipboard contents, nor upload credentials belong
    // in paste feedback. Also consume async shortcut failures, not just taps.
    if (target.isCurrent) _showPasteFailure(editorState);
  } finally {
    target.dispose();
    _pendingPastes[editorState] = false;
  }
}

Future<void> _doPaste(
  EditorState editorState,
  AttachmentPasteTarget target,
  AttachmentPasteService attachments,
) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }

  EditorNotification.paste().post();

  // dispatch the paste event
  final data = await getIt<ClipboardService>().getData();
  if (!target.isCurrent) return;
  final inAppJson = data.inAppJson;
  final html = data.html;
  final plainText = data.plainText;
  final image = data.image;

  // dump the length of the data here, don't log the data itself for privacy concerns
  Log.info('paste command: inAppJson: ${inAppJson?.length}');
  Log.info('paste command: html: ${html?.length}');
  Log.info('paste command: plainText: ${plainText?.length}');
  Log.info('paste command: image: ${image?.$2?.length}');

  // Order:
  // 1. in app json format
  // 2. native files (all clipboard items, in order)
  // 3. image bytes, before possibly private/unreachable HTML image URLs
  // 4. links, HTML, plain text

  // try to paste the content in order, if any of them is failed, then try the next one
  if (inAppJson != null && inAppJson.isNotEmpty) {
    if (await editorState.pasteInAppJson(inAppJson)) {
      return Log.info('Pasted in app json');
    }
  }

  if (data.files.isNotEmpty || image?.$2?.isNotEmpty == true) {
    final documentBloc =
        editorState.document.root.context?.read<DocumentBloc?>();
    final documentId = documentBloc?.documentId;
    if (documentId == null || documentId.isEmpty) {
      _showPasteFailure(editorState);
      return;
    }
    final prepared = await attachments.prepare(
      data,
      documentId: documentId,
      isLocalMode: documentBloc!.isLocalMode,
    );
    var inserted = false;
    try {
      if (!target.isCurrent) return;
      inserted = await insertPastedAttachments(editorState, prepared.nodes);
      if (!inserted) _showPasteFailure(editorState);
    } finally {
      if (!inserted) await prepared.discard();
    }
    return;
  }

  if (await editorState.pasteAppFlowySharePageLink(plainText)) {
    return Log.info('Pasted block link');
  }
  if (await _pasteAsLinkPreview(editorState, plainText)) {
    return Log.info('Pasted as link preview');
  }

  if (html != null && html.isNotEmpty) {
    await editorState.deleteSelectionIfNeeded();
    if (await editorState.pasteHtml(html)) {
      return Log.info('Pasted html');
    }
  }

  if (plainText != null && plainText.isNotEmpty) {
    final currentSelection = editorState.selection;
    if (currentSelection == null) {
      await editorState.updateSelectionWithReason(
        selection,
        reason: SelectionUpdateReason.uiEvent,
      );
    }
    await editorState.pasteText(plainText);
    return Log.info('Pasted plain text');
  }

  return Log.info('unable to parse the clipboard content');
}

void _showPasteFailure(EditorState editor) {
  if (editor.isDisposed) return;
  final context = editor.document.root.context;
  if (context != null && context.mounted) {
    showToastNotification(
      context: context,
      type: ToastificationType.error,
      message: LocaleKeys.fileDropzone_uploadFailedDescription.tr(),
    );
  }
}

Future<bool> _pasteAsLinkPreview(
  EditorState editorState,
  String? text,
) async {
  final isMobile = UniversalPlatform.isMobile;
  // the url should contain a protocol
  if (text == null || !isURL(text, {'require_protocol': true})) {
    return false;
  }

  final selection = editorState.selection;
  // Apply the update only when the selection is collapsed
  // and at the start of the current line
  if (selection == null ||
      !selection.isCollapsed ||
      selection.startIndex != 0) {
    return false;
  }

  final node = editorState.getNodeAtPath(selection.start.path);
  // Apply the update only when the current node is a paragraph
  // and the paragraph is empty
  if (node == null ||
      node.type != ParagraphBlockKeys.type ||
      node.delta?.toPlainText().isNotEmpty == true) {
    return false;
  }
  if (!isMobile) return false;
  final bool isImageUrl;
  try {
    isImageUrl = await _isImageUrl(text);
  } catch (e) {
    Log.info('unable to get content header');
    return false;
  }

  if (!isImageUrl) return false;

  // insert the text with link format
  final textTransaction = editorState.transaction
    ..insertText(
      node,
      0,
      text,
      attributes: {AppFlowyRichTextKeys.href: text},
    );
  await editorState.apply(
    textTransaction,
    skipHistoryDebounce: true,
  );

  // convert it to image or link preview node
  final replacementInsertedNodes = [
    isImageUrl ? imageNode(url: text) : linkPreviewNode(url: text),
    // if the next node is null, insert a empty paragraph node
    if (node.next == null) paragraphNode(),
  ];

  final replacementTransaction = editorState.transaction
    ..insertNodes(
      selection.start.path,
      replacementInsertedNodes,
    )
    ..deleteNode(node)
    ..afterSelection = Selection.collapsed(
      Position(path: node.path.next),
    );

  await editorState.apply(replacementTransaction);

  return true;
}

Future<void> doPlainPaste(EditorState editorState) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }

  EditorNotification.paste().post();

  // dispatch the paste event
  final data = await getIt<ClipboardService>().getData();
  final plainText = data.plainText;
  if (plainText != null && plainText.isNotEmpty) {
    await editorState.pastePlainText(plainText);
    Log.info('Pasted plain text');
    return;
  }

  Log.info('unable to parse the clipboard content');
  return;
}

Future<bool> _isImageUrl(String text) async {
  if (isNotImageUrl(text)) return false;
  final response = await http.head(Uri.parse(text));

  if (response.statusCode == 200) {
    final contentType = response.headers['content-type'];
    if (contentType != null) {
      return contentType.startsWith('image/') &&
          defaultImageExtensions.any(contentType.contains);
    }
  }

  throw 'bad status code';
}
