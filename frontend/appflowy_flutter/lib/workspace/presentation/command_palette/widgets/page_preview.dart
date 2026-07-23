import 'dart:async';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/document_immersive_cover_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

class PagePreview extends StatelessWidget {
  const PagePreview({
    super.key,
    required this.view,
    required this.onViewOpened,
  });
  final ViewPB view;
  final VoidCallback onViewOpened;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final backgroundColor = EditorSurfaceStyle.previewBackgroundFor(
      Theme.of(context).brightness,
      theme.surfaceColorScheme.layer02,
      isPaper: PaperTheme.isEnabled(context),
    );

    return BlocProvider(
      create: (context) => DocumentImmersiveCoverBloc(view: view)
        ..add(const DocumentImmersiveCoverEvent.initial()),
      child:
          BlocBuilder<DocumentImmersiveCoverBloc, DocumentImmersiveCoverState>(
        builder: (context, state) {
          final cover = buildCover(state, context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 20),
            child: Container(
              key: const ValueKey('page-preview-card'),
              height: double.infinity,
              width: 304,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.borderColorScheme.primary),
                boxShadow: theme.shadow.small,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover != null) cover,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (view.icon.value.isNotEmpty || cover == null) ...[
                          SizedBox.square(
                            dimension: 24,
                            child: Center(
                              child: buildIcon(theme, view, cover != null),
                            ),
                          ),
                          const VSpace(10),
                        ],
                        buildTitle(context, view),
                      ],
                    ),
                  ),
                  const AFDivider(),
                  Expanded(
                    child: _buildPageContent(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageContent() {
    if (view.layout.isDocumentView) {
      return _DocumentPagePreview(
        key: ValueKey('document-preview-${view.id}'),
        viewId: view.id,
      );
    }
    if (view.layout.isDatabaseView) {
      return _DatabasePagePreview(
        key: ValueKey('database-preview-${view.id}'),
        view: view,
      );
    }
    return const _PreviewError();
  }

  Widget? buildCover(DocumentImmersiveCoverState state, BuildContext context) {
    final cover = state.cover;
    final type = state.cover.type;
    const height = 96.0;
    if (type == PageStyleCoverImageType.customImage ||
        type == PageStyleCoverImageType.unsplashImage) {
      final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile;
      if (userProfile == null) return null;

      return SizedBox(
        height: height,
        width: double.infinity,
        child: FlowyNetworkImage(
          url: cover.value,
          userProfilePB: userProfile,
        ),
      );
    }

    if (type == PageStyleCoverImageType.builtInImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    if (type == PageStyleCoverImageType.pureColor) {
      final color = FlowyTint.fromId(cover.value)?.color(context) ??
          cover.value.tryToColor();
      return Container(
        height: height,
        width: double.infinity,
        color: color,
      );
    }

    if (type == PageStyleCoverImageType.gradientColor) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: FlowyGradientColor.fromId(cover.value).linear,
        ),
      );
    }

    if (type == PageStyleCoverImageType.localImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.file(
          File(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    return null;
  }

  Widget buildIcon(AppFlowyThemeData theme, ViewPB view, bool hasCover) {
    final hasIcon = view.icon.value.isNotEmpty;
    if (!hasIcon && hasCover) return const SizedBox.shrink();
    return hasIcon
        ? RawEmojiIconWidget(
            emoji: view.icon.toEmojiIconData(),
            emojiSize: 16.0,
            lineHeight: 20 / 16,
          )
        : FlowySvg(
            view.iconData,
            size: const Size.square(20),
            color: theme.iconColorScheme.secondary,
          );
  }

  Widget buildTitle(BuildContext context, ViewPB view) {
    final theme = AppFlowyTheme.of(context);
    final titleStyle = theme.textStyle.heading4
            .enhanced(color: theme.textColorScheme.primary),
        titleHoverStyle =
            titleStyle.copyWith(decoration: TextDecoration.underline);
    return LayoutBuilder(
      builder: (context, constrains) {
        final maxWidth = constrains.maxWidth;
        String displayText = view.nameOrDefault;
        final painter = TextPainter(
          text: TextSpan(text: displayText, style: titleStyle),
          maxLines: 3,
          textDirection: TextDirection.ltr,
          ellipsis: '...     ',
        );
        painter.layout(maxWidth: maxWidth);
        if (painter.didExceedMaxLines) {
          final lines = painter.computeLineMetrics();
          final lastLine = lines.last;
          final offset = Offset(
            lastLine.left + lastLine.width,
            lines.map((e) => e.height).reduce((a, b) => a + b),
          );
          final range = painter.getPositionForOffset(offset);
          displayText = '${displayText.substring(0, range.offset)}...';
        }
        return AFBaseButton(
          borderColor: (_, __, ___, ____) => Colors.transparent,
          borderRadius: 0,
          onTap: onViewOpened,
          padding: EdgeInsets.zero,
          builder: (context, isHovering, disabled) {
            return RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: displayText,
                    style: isHovering ? titleHoverStyle : titleStyle,
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FlowyTooltip(
                        message: LocaleKeys.settings_files_open.tr(),
                        child: FlowySvg(
                          FlowySvgs.search_open_tab_m,
                          color: theme.iconColorScheme.secondary,
                          size: const Size.square(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DocumentPagePreview extends StatefulWidget {
  const _DocumentPagePreview({
    required this.viewId,
    super.key,
  });

  final String viewId;

  @override
  State<_DocumentPagePreview> createState() => _DocumentPagePreviewState();
}

class _DocumentPagePreviewState extends State<_DocumentPagePreview> {
  static const double _canvasWidth = 520;
  static const double _lineHeight = 1.4;

  EditorState? editorState;
  bool isLoading = true;
  bool hasError = false;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocument());
  }

  @override
  void didUpdateWidget(covariant _DocumentPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      unawaited(_loadDocument());
    }
  }

  @override
  void dispose() {
    requestId++;
    editorState?.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final currentRequestId = ++requestId;
    final previousEditorState = editorState;
    editorState = null;
    previousEditorState?.dispose();

    if (mounted && !isLoading) {
      setState(() {
        isLoading = true;
        hasError = false;
      });
    }

    final result = await DocumentService().getDocument(
      documentId: widget.viewId,
    );
    var requestFailed = false;
    final document = result.fold(
      (data) => data.toDocument(),
      (error) {
        requestFailed = true;
        Log.warn(
          'Unable to load search preview for ${widget.viewId}: $error',
        );
        return null;
      },
    );

    if (!mounted || currentRequestId != requestId) {
      return;
    }

    if (document == null && !requestFailed) {
      Log.warn('Search preview document is invalid: ${widget.viewId}');
    }
    setState(() {
      editorState = document == null ? null : EditorState(document: document);
      hasError = document == null;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final editorState = this.editorState;
    if (hasError || editorState == null) {
      return _PreviewError(onRetry: () => unawaited(_loadDocument()));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final scale = constraints.maxWidth / _canvasWidth;
        final canvasHeight = constraints.maxHeight / scale;
        final styleCustomizer = EditorStyleCustomizer(
          context: context,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          width: _canvasWidth,
          editorState: editorState,
        );
        final baseEditorStyle = styleCustomizer.style();
        final editorStyle = baseEditorStyle.copyWith(
          cursorColor: Colors.transparent,
          cursorWidth: 0,
          textStyleConfiguration: baseEditorStyle.textStyleConfiguration
              .copyWith(lineHeight: _lineHeight),
        );
        final blockBuilders = buildBlockComponentBuilders(
          context: context,
          editorState: editorState,
          styleCustomizer: styleCustomizer,
          editable: false,
          customPadding: (node) => node.type == HeadingBlockKeys.type
              ? const EdgeInsets.only(top: 6, bottom: 2)
              : EdgeInsets.zero,
          alwaysDistributeSimpleTableColumnWidths: true,
        );

        return ClipRect(
          child: FittedBox(
            key: const ValueKey('document-preview-canvas'),
            alignment: Alignment.topLeft,
            fit: BoxFit.fill,
            child: SizedBox(
              width: _canvasWidth,
              height: canvasHeight,
              child: AppFlowyEditor(
                editorState: editorState,
                editorStyle: editorStyle,
                blockComponentBuilders: blockBuilders,
                contextMenuItems: const [],
                disableSelectionService: true,
                disableKeyboardService: true,
                disableAutoScroll: true,
                editable: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DatabasePagePreview extends StatelessWidget {
  const _DatabasePagePreview({
    required this.view,
    super.key,
  });

  static const double _canvasWidth = 720;
  static const double _canvasHeight = 960;

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final scale = constraints.maxWidth / _canvasWidth;
        final renderedHeight = _canvasHeight * scale;
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: renderedHeight,
            child: FittedBox(
              alignment: Alignment.topLeft,
              fit: BoxFit.fill,
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: FocusScope(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: IgnorePointer(
                    child: Provider(
                      create: (_) => const DatabasePluginWidgetBuilderSize(
                        horizontalPadding: 16,
                      ),
                      child: DatabaseTabBarView(
                        view: view,
                        shrinkWrap: false,
                        showActions: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.something_wrong_warning_m,
              color: theme.iconColorScheme.secondary,
              size: const Size.square(24),
            ),
            const VSpace(8),
            Text(
              LocaleKeys.search_somethingWentWrong.tr(),
              textAlign: TextAlign.center,
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.secondary,
              ),
            ),
            if (onRetry != null) ...[
              const VSpace(8),
              TextButton(
                onPressed: onRetry,
                child: Text(LocaleKeys.button_tryAgain.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
