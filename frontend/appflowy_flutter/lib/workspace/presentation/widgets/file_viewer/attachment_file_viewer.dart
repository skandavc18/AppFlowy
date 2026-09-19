import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';

typedef AttachmentFileOpener = Future<bool> Function(File file);

/// Only genuine links are handed to a browser. Legacy image links are already
/// resolved by [MediaFileTypeResolution]; known document/media links are files.
/// An HTML link remains a web page, not an attachment to download on opening.
bool isAttachmentWebLink(MediaFilePB file) {
  final uri = Uri.tryParse(file.url);
  if (file.uploadType != FileUploadTypePB.NetworkFile ||
      file.effectiveFileType != MediaFileTypePB.Link ||
      uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https'))) {
    return false;
  }
  for (final name in [file.name, _sourceName(file.url)]) {
    final kind = filePreviewKindFromName(name);
    if ((kind != null && kind != FilePreviewKind.html) ||
        isOfficeFile(name) ||
        fileMediaKind(name, null) != null) {
      return false;
    }
  }
  return true;
}

/// Shared by the cell-editor row and the popup, with credentials snapshotted
/// only for CloudFile. A link can legitimately be copied/shared as a link.
MediaActionSource attachmentMediaSource(
  MediaFilePB file, {
  UserProfilePB? userProfile,
}) =>
    MediaActionSource.file(
      source: file.url,
      name: file.name.isEmpty ? _sourceName(file.url) : file.name,
      uploadType: file.uploadType,
      userProfile: userProfile,
      isImage: file.isImage,
      shareAsLink: isAttachmentWebLink(file),
    );

/// Opens desktop attachments without changing the cell or its stored metadata.
/// IO/platform boundaries are injectable; simply constructing a popup does not
/// download an unsupported file or invoke the native clipboard/share sheet.
Future<void> showAttachmentFileViewer(
  BuildContext context,
  MediaFilePB file, {
  UserProfilePB? userProfile,
  MediaActionService actions = const MediaActionService(),
  MaterializedFileLoader materialize = materializeMediaFile,
  AttachmentFileOpener openFile = _openInSystemApp,
  Future<bool> Function(String) openLink = afLaunchUrlString,
}) async {
  if (isAttachmentWebLink(file)) {
    try {
      if (await openLink(file.url)) return;
    } catch (_) {
      // Never surface a signed URL or platform exception in feedback.
    }
    if (context.mounted) {
      showSnapBar(context, LocaleKeys.openFileMessage_unknownError.tr());
    }
    return;
  }

  final profile = userProfile ??
      context.read<DocumentBloc?>()?.state.userProfilePB ??
      context.read<UserWorkspaceBloc?>()?.state.userProfile;
  await showDialog<void>(
    context: context,
    builder: (_) => file.isImage
        ? InteractiveImageViewer(
            userProfile: profile,
            imageProvider: MediaFileImageProvider(files: [file]),
            actions: actions,
          )
        : AttachmentFileViewer(
            file: file,
            userProfile: profile,
            actions: actions,
            materialize: materialize,
            openFile: openFile,
          ),
  );
}

class AttachmentFileViewer extends StatefulWidget {
  const AttachmentFileViewer({
    super.key,
    required this.file,
    this.userProfile,
    this.actions = const MediaActionService(),
    this.materialize = materializeMediaFile,
    this.openFile = _openInSystemApp,
  });

  final MediaFilePB file;
  final UserProfilePB? userProfile;
  final MediaActionService actions;
  final MaterializedFileLoader materialize;
  final AttachmentFileOpener openFile;

  @override
  State<AttachmentFileViewer> createState() => _AttachmentFileViewerState();
}

class _AttachmentFileViewerState extends State<AttachmentFileViewer> {
  Animation<double>? _routeAnimation;
  bool _previewReady = true;
  bool _opening = false;
  bool _openFailed = false;
  int _retry = 0;

  UserProfilePB? get _profile =>
      widget.userProfile ??
      context.read<DocumentBloc?>()?.state.userProfilePB ??
      context.read<UserWorkspaceBloc?>()?.state.userProfile;

  MediaActionSource get _source =>
      attachmentMediaSource(widget.file, userProfile: _profile);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_routeStatusChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatusChanged);
    }
    _previewReady =
        animation == null || animation.status == AnimationStatus.completed;
  }

  void _routeStatusChanged(AnimationStatus status) {
    final ready = status == AnimationStatus.completed;
    if (mounted && ready != _previewReady) {
      // Platform preview surfaces must not be created during the opening
      // transition or remain alive through its reverse. Header/actions stay.
      setState(() => _previewReady = ready);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.select<DocumentBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfilePB,
    );
    context.select<UserWorkspaceBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfile,
    );
    final source = _source;
    final theme = Theme.of(context);
    final surface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      theme.colorScheme.surface,
      isPaper: PaperTheme.isEnabled(context),
    );

    return Dialog(
      key: const ValueKey('attachment-file-viewer'),
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 900,
        height: 650,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.delete ||
                event.logicalKey == LogicalKeyboardKey.backspace) {
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              unawaited(Navigator.of(context).maybePop());
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MediaHoverRegion(
            builder: (context, hovered) => Column(
              children: [
                Padding(
                  // Space for the tiny Copied badge, not an overlay over the
                  // document. The header's geometry never changes on hover.
                  padding: const EdgeInsets.fromLTRB(16, 28, 12, 12),
                  child: Row(
                    children: [
                      Icon(fileIconForName(source.name), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          source.name.isEmpty
                              ? LocaleKeys.document_plugins_file_name.tr()
                              : source.name,
                          key: const ValueKey('attachment-file-name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      MediaActionReveal(
                        visible: hovered,
                        child: MediaActionButtons(
                          source: source,
                          actions: widget.actions,
                          decorated: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const ValueKey('attachment-viewer-close'),
                        tooltip: LocaleKeys.button_close.tr(),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(28),
                          maximumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: ClipRect(child: _buildBody(source))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(MediaActionSource source) {
    if (source.requireAuthentication && source.httpHeaders.isEmpty) {
      return _fallback(
        source,
        message: LocaleKeys.openFileMessage_permissionDenied.tr(),
      );
    }
    final name = _previewName(widget.file);
    final kind = filePreviewKindFromName(name);
    final mediaKind = fileMediaKind(name, null);
    if (kind == null && mediaKind == null && !isOfficeFile(name)) {
      // Unsupported attachments are not fetched just to show their icon.
      return _fallback(source);
    }
    if (!_previewReady) return const SizedBox.expand();

    return MaterializedFileBuilder(
      key: ValueKey(_retry),
      source: source.source,
      name: source.name,
      httpHeaders: source.httpHeaders,
      loader: widget.materialize,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _fallback(
            source,
            message: LocaleKeys.openFileMessage_unknownError.tr(),
            canRetry: true,
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (mediaKind != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: FileMediaPlayer(
                key: ValueKey((file.path, mediaKind)),
                url: file.uri.toString(),
                name: source.name,
                kind: mediaKind,
              ),
            ),
          );
        }
        if (kind != null) {
          return FilePreview(
            file: file,
            name: source.name,
            kind: kind,
            metadata: const {},
            onMetadataChanged: (_) {},
            editable: false,
            bare: true,
          );
        }
        return OfficeDocumentView(
          key: ValueKey((file.path, source)),
          file: file,
          name: name,
          source: source.source,
          editable: false,
          cloudService: _AttachmentOfficeSessionService(
            source.requireAuthentication ? _profile : null,
          ),
          fallbackBuilder: (_) => _fallback(source, localFile: file),
        );
      },
    );
  }

  Widget _fallback(
    MediaActionSource source, {
    String? message,
    File? localFile,
    bool canRetry = false,
  }) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                fileIconForName(source.name),
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(source.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (message != null || _openFailed) ...[
                const SizedBox(height: 8),
                Text(
                  message ?? LocaleKeys.openFileMessage_unknownError.tr(),
                  key: const ValueKey('attachment-file-unavailable'),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('attachment-file-open'),
                    onPressed: _opening
                        ? null
                        : () => unawaited(_open(source, localFile)),
                    icon: _opening
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(LocaleKeys.workspaceFolderExplorer_open.tr()),
                  ),
                  if (canRetry)
                    TextButton(
                      onPressed: () => setState(() => _retry++),
                      child: Text(LocaleKeys.button_retry.tr()),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _open(MediaActionSource source, File? localFile) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    try {
      if (source.source.trim().isEmpty ||
          (source.requireAuthentication && source.httpHeaders.isEmpty)) {
        throw StateError('The attachment is unavailable.');
      }
      final file = localFile ??
          await widget.materialize(
            source: source.source,
            name: source.name,
            httpHeaders: source.httpHeaders,
          );
      if (!mounted || source != _source || !_previewReady) return;
      if (!await widget.openFile(file)) {
        throw StateError('The attachment could not be opened.');
      }
    } catch (_) {
      if (mounted && source == _source) {
        setState(() => _openFailed = true);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

/// A local/external attachment must not become a managed cloud document just
/// because the current account is signed in. The popup already has its profile.
class _AttachmentOfficeSessionService
    extends AppFlowyCloudOfficeSessionService {
  const _AttachmentOfficeSessionService(this.profile);

  final UserProfilePB? profile;

  @override
  Future<UserProfilePB?> connectedCloudProfile() async => profile;
}

Future<bool> _openInSystemApp(File file) async =>
    (await OpenFilex.open(file.path)).type == ResultType.done;

String _sourceName(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null &&
      (uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('file'))) {
    try {
      return uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    } on FormatException {
      return '';
    }
  }
  return source.split(RegExp(r'[/\\]')).last;
}

String _previewName(MediaFilePB file) {
  for (final name in [file.name, _sourceName(file.url)]) {
    if (supportsEmbeddedFilePreview(name) ||
        fileMediaKind(name, null) != null) {
      return name;
    }
  }
  return file.name;
}
