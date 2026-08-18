import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/application/row/row_document_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/row/row_banner.dart';
import 'package:appflowy/plugins/database/widgets/row/row_comments.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_list.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/widgets/ai_writer_scroll_wrapper.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/transaction_handler/editor_transaction_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show EditorState;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

class RowDocument extends StatelessWidget {
  const RowDocument({
    super.key,
    required this.viewId,
    required this.rowId,
    this.userProfile,
    this.showComments = false,
    this.shrinkWrap = true,
    this.contentInset = rowDetailContentInset,
  });

  final String viewId;
  final String rowId;
  final UserProfilePB? userProfile;

  /// Whether the row's discussion is shown above its page.
  final bool showComments;

  /// Whether the page takes its height from what is written on it. False makes
  /// the editor scroll inside whatever box it is given, which is what a pane
  /// beside a list needs.
  final bool shrinkWrap;

  /// The measure the page is set on.
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RowDocumentBloc>(
      create: (context) => RowDocumentBloc(viewId: viewId, rowId: rowId)
        ..add(const RowDocumentEvent.initial()),
      child: BlocConsumer<RowDocumentBloc, RowDocumentState>(
        listener: (_, state) => state.loadingState.maybeWhen(
          error: (error) => Log.error('RowDocument error: $error'),
          orElse: () => null,
        ),
        builder: (context, state) {
          return state.loadingState.when(
            loading: () => const Center(
              child: CircularProgressIndicator.adaptive(),
            ),
            error: (error) => Center(
              child: AppFlowyErrorPage(
                error: error,
              ),
            ),
            finish: () => _RowEditor(
              view: state.viewPB!,
              row: PageVersionRowContext(tableViewId: viewId, rowId: rowId),
              userProfile: userProfile,
              showComments: showComments,
              shrinkWrap: shrinkWrap,
              contentInset: contentInset,
              onIsEmptyChanged: (isEmpty) => context
                  .read<RowDocumentBloc>()
                  .add(RowDocumentEvent.updateIsEmpty(isEmpty)),
            ),
          );
        },
      ),
    );
  }
}

class _RowEditor extends StatelessWidget {
  const _RowEditor({
    required this.view,
    required this.row,
    this.onIsEmptyChanged,
    this.userProfile,
    this.showComments = false,
    this.shrinkWrap = true,
    this.contentInset = rowDetailContentInset,
  });

  final ViewPB view;
  final PageVersionRowContext row;
  final void Function(bool)? onIsEmptyChanged;
  final UserProfilePB? userProfile;
  final bool showComments;
  final bool shrinkWrap;
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => DocumentBloc(documentId: view.id)
            ..add(const DocumentEvent.initial()),
        ),
        BlocProvider(
          create: (_) => ViewBloc(view: view)..add(const ViewEvent.initial()),
        ),
      ],
      child: BlocConsumer<DocumentBloc, DocumentState>(
        listenWhen: (previous, current) =>
            previous.isDocumentEmpty != current.isDocumentEmpty,
        listener: (_, state) {
          if (state.isDocumentEmpty != null) {
            onIsEmptyChanged?.call(state.isDocumentEmpty!);
          }
          if (state.error != null) {
            Log.error('RowEditor error: ${state.error}');
          }
          if (state.editorState == null) {
            Log.error('RowEditor unable to get editorState');
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          final editorState = state.editorState;
          final error = state.error;
          if (error != null || editorState == null) {
            return Center(
              child: AppFlowyErrorPage(error: error),
            );
          }

          return BlocProvider<ViewInfoBloc>(
            create: (context) => ViewInfoBloc(view: view),
            child: _RowVersionWatcher(
              viewId: view.id,
              row: row,
              editorState: editorState,
              child: Container(
                constraints: const BoxConstraints(minHeight: 300),
                child: Provider(
                  create: (_) {
                    final context = SharedEditorContext();
                    context.isInDatabaseRowPage = true;
                    return context;
                  },
                  dispose: (_, editorContext) => editorContext.dispose(),
                  child: AiWriterScrollWrapper(
                    viewId: view.id,
                    editorState: editorState,
                    child: EditorDropHandler(
                      viewId: view.id,
                      editorState: editorState,
                      isLocalMode: context.read<DocumentBloc>().isLocalMode,
                      // A host that keeps no drop state of its own lets the
                      // handler make one rather than refusing to build.
                      dropManagerState: context.read<EditorDropManagerState?>(),
                      child: EditorTransactionService(
                        viewId: view.id,
                        editorState: editorState,
                        child: Provider(
                          create: (context) => DatabasePluginWidgetBuilderSize(
                            horizontalPadding: 0,
                          ),
                          child: AppFlowyEditorPage(
                            shrinkWrap: shrinkWrap,
                            autoFocus: false,
                            editorState: editorState,
                            // The thread rides in the editor's own header, so
                            // the body stays the single scrollable the row page
                            // scrolls.
                            header: showComments
                                ? Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      contentInset,
                                      0,
                                      contentInset,
                                      18,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        RowCommentSection(
                                          editorState: editorState,
                                          userProfile: userProfile,
                                          padding: EdgeInsets.zero,
                                        ),
                                        const VSpace(18),
                                        const Divider(height: 1.0),
                                      ],
                                    ),
                                  )
                                : null,
                            styleCustomizer: EditorStyleCustomizer(
                              context: context,
                              // The editor lays the + and :: handles out ahead of
                              // each block, so the page starts a gutter early to
                              // put them in the margin and the text on the
                              // measure.
                              padding: EdgeInsets.only(
                                left: math.max(
                                  0,
                                  contentInset - BlockActionList.gutterWidth,
                                ),
                                right: contentInset,
                              ),
                            ),
                            showParagraphPlaceholder: (editorState, _) =>
                                editorState.document.isEmpty,
                            placeholderText: (_) =>
                                LocaleKeys.cardDetails_notesPlaceholder.tr(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Keeps a row's page in its history the way an ordinary page is kept.
///
/// A row page has no plugin of its own, so nothing else is watching it settle.
class _RowVersionWatcher extends StatefulWidget {
  const _RowVersionWatcher({
    required this.viewId,
    required this.row,
    required this.editorState,
    required this.child,
  });

  final String viewId;
  final PageVersionRowContext row;
  final EditorState editorState;
  final Widget child;

  @override
  State<_RowVersionWatcher> createState() => _RowVersionWatcherState();
}

class _RowVersionWatcherState extends State<_RowVersionWatcher> {
  PageVersionRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(_RowVersionWatcher old) {
    super.didUpdateWidget(old);
    if (old.viewId != widget.viewId || old.editorState != widget.editorState) {
      unawaited(_recorder?.stop());
      _watch();
    }
  }

  @override
  void dispose() {
    unawaited(_recorder?.stop());
    super.dispose();
  }

  void _watch() {
    _recorder = PageVersionRecorder(
      viewId: widget.viewId,
      editorState: widget.editorState,
      row: widget.row,
    )..start();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
