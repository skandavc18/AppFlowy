import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_folder_import.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_attachments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

/// Pasted text this long is not one path anybody copied.
const _maximumPathLength = 4096;

/// How long a pasted path may take to say whether it exists. A network share
/// that is offline can stall for many seconds; the text is pasted as it is.
const localPathPasteLookupTimeout = Duration(milliseconds: 1500);

/// A file or folder on this computer that pasted text named.
@immutable
class PastedLocalPath {
  const PastedLocalPath({
    required this.path,
    required this.isDirectory,
    this.size,
  });

  final String path;
  final bool isDirectory;

  /// Bytes, for a file.
  final int? size;

  /// The file or folder's own name; a drive's root is called by its path.
  String get name {
    final name = p.basename(path);
    return name.isEmpty ? path : name;
  }
}

/// The absolute local path [text] names when it is nothing but one, else
/// null.
///
/// Understood: drive paths (`C:\…`, `C:/…`), network shares (`\\server\…`),
/// `file:` addresses, POSIX paths (`/…`) and the home folder (`~/…`), each
/// optionally quoted the way "Copy as path" quotes it. Relative paths name
/// nothing without a folder to start from, so they stay text.
String? localPathFromPastedText(
  String? text, {
  bool? windows,
  String? home,
}) {
  var value = text?.trim() ?? '';
  if (value.isEmpty ||
      value.length > _maximumPathLength ||
      value.contains('\n') ||
      value.contains('\r') ||
      value.contains('\u0000')) {
    return null;
  }
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }
  if (value.isEmpty) {
    return null;
  }

  final isWindows = windows ?? Platform.isWindows;
  final style = isWindows ? p.windows : p.posix;
  if (value.toLowerCase().startsWith('file:')) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isScheme('file') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    try {
      value = uri.toFilePath(windows: isWindows);
    } catch (_) {
      return null;
    }
  } else if (value == '~' ||
      value.startsWith('~/') ||
      (isWindows && value.startsWith(r'~\'))) {
    final folder =
        home ?? Platform.environment[isWindows ? 'USERPROFILE' : 'HOME'] ?? '';
    if (folder.isEmpty) {
      return null;
    }
    value = value.length < 2 ? folder : style.join(folder, value.substring(2));
  }

  if (isWindows) {
    final drive = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
    final share = RegExp(r'^[\\/]{2}[^\\/]+[\\/][^\\/]+').hasMatch(value);
    // Characters no Windows name may hold; a colon only follows the drive.
    if ((!drive && !share) ||
        RegExp('[<>"|?*]').hasMatch(value) ||
        value.indexOf(':', 2) != -1) {
      return null;
    }
  } else if (!value.startsWith('/')) {
    return null;
  }
  return style.normalize(value);
}

/// The file or folder [text] names, when it is one path that exists here.
Future<PastedLocalPath?> resolvePastedLocalPath(
  String? text, {
  Duration timeout = localPathPasteLookupTimeout,
}) async {
  final path = localPathFromPastedText(text);
  if (path == null) {
    return null;
  }
  try {
    final stat = await FileStat.stat(path).timeout(timeout);
    return switch (stat.type) {
      FileSystemEntityType.file =>
        PastedLocalPath(path: path, isDirectory: false, size: stat.size),
      FileSystemEntityType.directory =>
        PastedLocalPath(path: path, isDirectory: true),
      _ => null,
    };
  } on TimeoutException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// A local path pasted as a link, followed until somebody answers for it.
class PastedLocalLink {
  PastedLocalLink({
    required this.item,
    required this.node,
    required this.offset,
  });

  final PastedLocalPath item;

  /// The block the link was pasted into, followed by identity so that edits
  /// elsewhere on the page do not lose it.
  final Node node;

  /// Where the link began when it was pasted.
  final int offset;

  /// The link reads as the path and points at it.
  String get text => item.path;

  /// Where the link is now, or null once it has been edited away or its
  /// block has left the page. Of several copies, the nearest to where it was
  /// pasted is the one meant.
  Selection? locate() {
    final delta = node.delta;
    if (node.parent == null || delta == null) {
      return null;
    }
    int? found;
    int? runStart;
    final run = StringBuffer();
    void close() {
      if (runStart != null &&
          run.toString() == text &&
          (found == null ||
              (runStart! - offset).abs() < (found! - offset).abs())) {
        found = runStart;
      }
      runStart = null;
      run.clear();
    }

    var index = 0;
    for (final operation in delta) {
      if (operation is TextInsert && operation.attributes?.href == text) {
        runStart ??= index;
        run.write(operation.text);
      } else {
        close();
      }
      index += operation.length;
    }
    close();
    final start = found;
    if (start == null) {
      return null;
    }
    return Selection(
      start: Position(path: node.path, offset: start),
      end: Position(path: node.path, offset: start + text.length),
    );
  }
}

extension PasteLocalPath on EditorState {
  /// Pastes [item] as a link to where it lives, or returns null when the
  /// caret is somewhere a link cannot go and the paste should go on as text.
  Future<PastedLocalLink?> pasteLocalPathLink(PastedLocalPath item) async {
    final caret = selection;
    if (caret == null) {
      return null;
    }
    final at = getNodeAtPath(caret.normalized.start.path);
    if (at == null || at.delta == null || at.type == CodeBlockKeys.type) {
      return null;
    }
    final collapsed = await deleteSelectionIfNeeded();
    if (collapsed == null) {
      return null;
    }
    final start = collapsed.start;
    await pasteSingleLineNode(
      paragraphNode(
        delta: Delta()
          ..insert(
            item.path,
            attributes: {AppFlowyRichTextKeys.href: item.path},
          ),
      ),
    );
    final node = getNodeAtPath(start.path);
    if (node == null) {
      return null;
    }
    final link = PastedLocalLink(item: item, node: node, offset: start.offset);
    return link.locate() == null ? null : link;
  }
}

/// The page a pasted path was pasted into: where a copy of it is kept.
@immutable
class LocalPathPasteDestination {
  const LocalPathPasteDestination({
    required this.documentId,
    required this.isLocalMode,
    this.userProfile,
  });

  final String documentId;
  final bool isLocalMode;
  final UserProfilePB? userProfile;

  static LocalPathPasteDestination? of(EditorState editor) {
    final context = editor.document.root.context;
    if (context == null || !context.mounted) {
      return null;
    }
    final bloc = context.read<DocumentBloc?>();
    if (bloc == null || bloc.documentId.isEmpty) {
      return null;
    }
    return LocalPathPasteDestination(
      documentId: bloc.documentId,
      isLocalMode: bloc.isLocalMode,
      userProfile: bloc.state.userProfilePB,
    );
  }
}

/// How copying a pasted path into AppFlowy went.
enum LocalPathPasteOutcomeKind {
  /// Everything was copied.
  copied,

  /// A folder was copied, but some of what it holds could not be.
  partlyCopied,

  /// A folder holds more files than one copy takes.
  tooManyFiles,

  /// A folder holds more bytes than one copy takes.
  tooLarge,

  /// A folder is nested deeper than one copy goes.
  tooDeep,

  /// The link was edited away before the copy could take its place.
  pageChanged,

  /// It could not be read or stored.
  failed,
}

@immutable
class LocalPathPasteOutcome {
  const LocalPathPasteOutcome(this.kind, this.item, {this.count = 0});

  final LocalPathPasteOutcomeKind kind;
  final PastedLocalPath item;

  /// Files copied, or those that could not be, whichever the kind is about.
  final int count;
}

/// Copies the file or folder behind [link] into AppFlowy and puts it where
/// the link was: a file as an attachment kept in AppFlowy storage, exactly as
/// pasting the file itself does, and a folder as a workspace folder under the
/// page, shown in the page and filled in as its files are copied.
///
/// The link stays when anything stops the copy, so nothing is lost.
Future<void> copyPastedLocalPath(
  EditorState editor,
  PastedLocalLink link, {
  required LocalPathPasteDestination destination,
  AttachmentPasteService attachments = const AttachmentPasteService(),
  LocalFolderDestination? folders,
  LocalFolderLimits limits = const LocalFolderLimits(),
  ValueChanged<LocalPathPasteOutcome> report = showLocalPathPasteOutcome,
}) async {
  LocalPathPasteOutcomeKind kind;
  int count;
  try {
    (kind, count) = link.item.isDirectory
        ? await _copyFolder(
            editor,
            link,
            destination: destination,
            folders: folders ??
                WorkspaceLocalFolderDestination(
                  userProfile: destination.userProfile,
                ),
            limits: limits,
          )
        : await _copyFile(
            editor,
            link,
            destination: destination,
            attachments: attachments,
          );
  } catch (error) {
    // Nobody awaits this copy; it must not end in an unhandled error.
    Log.error('Copying a pasted path into AppFlowy failed: $error');
    (kind, count) = (LocalPathPasteOutcomeKind.failed, 0);
  }
  report(LocalPathPasteOutcome(kind, link.item, count: count));
}

Future<(LocalPathPasteOutcomeKind, int)> _copyFile(
  EditorState editor,
  PastedLocalLink link, {
  required LocalPathPasteDestination destination,
  required AttachmentPasteService attachments,
}) async {
  final PreparedAttachments prepared;
  try {
    prepared = await attachments.prepare(
      ClipboardServiceData(files: [Uri.file(link.item.path)]),
      documentId: destination.documentId,
      isLocalMode: destination.isLocalMode,
    );
  } catch (_) {
    return (LocalPathPasteOutcomeKind.failed, 0);
  }
  var inserted = false;
  try {
    final range = link.locate();
    if (range == null) {
      return (LocalPathPasteOutcomeKind.pageChanged, 0);
    }
    inserted = await insertPastedAttachments(
      editor,
      prepared.nodes,
      replacing: range,
    );
    return inserted
        ? (LocalPathPasteOutcomeKind.copied, 1)
        : (LocalPathPasteOutcomeKind.failed, 0);
  } finally {
    // Only the new copy goes; the original file is never touched.
    if (!inserted) {
      await prepared.discard();
    }
  }
}

Future<(LocalPathPasteOutcomeKind, int)> _copyFolder(
  EditorState editor,
  PastedLocalLink link, {
  required LocalPathPasteDestination destination,
  required LocalFolderDestination folders,
  required LocalFolderLimits limits,
}) async {
  final source = Directory(link.item.path);
  final LocalFolderSurvey survey;
  try {
    survey = await surveyLocalFolder(source, limits: limits);
  } catch (_) {
    return (LocalPathPasteOutcomeKind.failed, 0);
  }
  switch (survey.exceeded) {
    case LocalFolderLimit.files:
      return (LocalPathPasteOutcomeKind.tooManyFiles, limits.maximumFiles);
    case LocalFolderLimit.bytes:
      return (LocalPathPasteOutcomeKind.tooLarge, limits.maximumBytes);
    case LocalFolderLimit.depth:
      return (LocalPathPasteOutcomeKind.tooDeep, limits.maximumDepth);
    case null:
      break;
  }

  String? folderId;
  try {
    folderId = await folders.createFolder(
      parentId: destination.documentId,
      name: link.item.name,
    );
  } catch (_) {
    folderId = null;
  }
  if (folderId == null) {
    return (LocalPathPasteOutcomeKind.failed, 0);
  }
  // The folder takes the link's place before it is filled, so the page shows
  // the copy arriving rather than waiting on it.
  final range = link.locate();
  final inserted = range != null &&
      await insertPastedAttachments(
        editor,
        [folderExplorerNode(folderId: folderId)],
        replacing: range,
      );
  if (!inserted) {
    await folders.remove(folderId);
    return range == null
        ? (LocalPathPasteOutcomeKind.pageChanged, 0)
        : (LocalPathPasteOutcomeKind.failed, 0);
  }
  final copy = await copyLocalFolderContents(
    source: source,
    folderId: folderId,
    destination: folders,
    limits: limits,
  );
  return copy.failed == 0
      ? (LocalPathPasteOutcomeKind.copied, copy.copied)
      : (LocalPathPasteOutcomeKind.partlyCopied, copy.failed);
}

/// Leaves the pasted path as plain words, no longer a link.
Future<void> unlinkPastedLocalPath(
  EditorState editor,
  PastedLocalLink link,
) async {
  final range = link.locate();
  if (range == null || editor.isDisposed || !editor.editable) {
    return;
  }
  final transaction = editor.transaction
    ..formatText(
      link.node,
      range.startIndex,
      range.length,
      {AppFlowyRichTextKeys.href: null},
    );
  await editor.apply(transaction);
}

/// Says how a copy went, where it needs saying: a file copied in is already
/// on the page for all to see, a folder still filling in is not.
void showLocalPathPasteOutcome(LocalPathPasteOutcome outcome) {
  final name = outcome.item.name;
  final (message, type) = switch (outcome.kind) {
    LocalPathPasteOutcomeKind.copied => outcome.item.isDirectory
        ? (
            LocaleKeys.document_plugins_localPathPaste_copied.tr(args: [name]),
            ToastificationType.success,
          )
        : (null, ToastificationType.success),
    LocalPathPasteOutcomeKind.partlyCopied => (
        LocaleKeys.document_plugins_localPathPaste_partlyCopied
            .tr(args: [name, '${outcome.count}']),
        ToastificationType.warning,
      ),
    LocalPathPasteOutcomeKind.tooManyFiles => (
        LocaleKeys.document_plugins_localPathPaste_tooManyFiles.tr(
          args: [name, NumberFormat.decimalPattern().format(outcome.count)],
        ),
        ToastificationType.warning,
      ),
    LocalPathPasteOutcomeKind.tooLarge => (
        LocaleKeys.document_plugins_localPathPaste_tooLarge
            .tr(args: [name, formatArchiveBytes(outcome.count)]),
        ToastificationType.warning,
      ),
    LocalPathPasteOutcomeKind.tooDeep => (
        LocaleKeys.document_plugins_localPathPaste_tooDeep
            .tr(args: [name, '${outcome.count}']),
        ToastificationType.warning,
      ),
    LocalPathPasteOutcomeKind.pageChanged => (
        LocaleKeys.document_plugins_localPathPaste_pageChanged.tr(args: [name]),
        ToastificationType.warning,
      ),
    LocalPathPasteOutcomeKind.failed => (
        LocaleKeys.document_plugins_localPathPaste_failed.tr(args: [name]),
        ToastificationType.error,
      ),
  };
  if (message != null) {
    showToastNotification(message: message, type: type);
  }
}
