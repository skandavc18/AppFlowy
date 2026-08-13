import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/custom_link_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Things from the workspace, and things from the web.
///
/// A dashboard is at its most useful when it gathers what already exists
/// rather than asking for it to be typed in again, so a page really is the
/// page and a picture really is the file.
void registerDashboardContentWidgets() {
  DashboardWidgetRegistry.register(_page);
  DashboardWidgetRegistry.register(_pageLink);
  DashboardWidgetRegistry.register(_image);
  DashboardWidgetRegistry.register(_bookmark);
  DashboardWidgetRegistry.register(_file);
}

const _keyUrl = 'url';
const _keyFit = 'fit';
const _keyDescription = 'description';
const _keyDisplay = 'display';
const _keyPreview = 'preview';

/// One reading of a page's preview for the whole dashboard.
final _previewCache = FolderGalleryPreviewCache();

bool _isDocument(ViewPB view) => view.layout == ViewLayoutPB.Document;

Future<void> _pickPage(DashboardWidgetContext context) => context.pickSource(
      kind: DashboardSourceKind.page,
      filter: _isDocument,
    );

Future<void> _pickFile(DashboardWidgetContext context) =>
    context.pickSource(kind: DashboardSourceKind.file);

DashboardConfigField _viewField(
  DashboardWidgetContext context, {
  required String label,
  required DashboardSourceKind kind,
  bool Function(ViewPB view)? filter,
}) =>
    DashboardConfigView(
      label: label,
      viewId: context.spec.source.viewId,
      name: context.spec.source.name,
      filter: filter,
      onChanged: (viewId, name) => context.setSource(
        context.spec.source.copyWith(
          kind: viewId.isEmpty ? DashboardSourceKind.none : kind,
          viewId: viewId,
          name: name,
        ),
      ),
    );

// ----------------------------------------------------------------------- page

final _page = DashboardWidgetDefinition(
  type: 'page',
  label: () => LocaleKeys.dashboard_widget_page.tr(),
  description: () => LocaleKeys.dashboard_widget_pageHint.tr(),
  icon: Icons.description_rounded,
  group: DashboardWidgetGroup.content,
  defaultColumnSpan: 6,
  defaultRowSpan: 8,
  showsTitleByDefault: false,
  // Both readings draw their own surface, so the card must not draw one too.
  paintsOwnSurface: true,
  slashName: 'page',
  keywords: const ['page', 'document', 'note', 'embed page', 'doc'],
  builder: (context) {
    final viewId = context.spec.source.viewId;
    if (viewId.isEmpty) {
      return DashboardPlaceholder(
        palette: context.palette,
        icon: Icons.description_outlined,
        message: LocaleKeys.dashboard_widget_pickPage.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickPage(context)),
      );
    }
    final asCard =
        context.spec.setting(_keyDisplay, fallback: 'preview') != 'full';
    return DashboardViewBuilder(
      viewId: viewId,
      revision: context.refreshToken,
      placeholder: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      builder: (_, view) => asCard
          ? PagePreviewCard(
              key: ValueKey('dashboard-preview-${view.id}'),
              view: view,
              userProfile: null,
              previewCache: _previewCache,
              previewMode: ViewPreviewMode.fromValue(
                context.spec.setting(_keyPreview, fallback: 'cover'),
              ),
              onOpen: () => _openPage(context, view.id, view.name),
              onChangePage: () => unawaited(_pickPage(context)),
              onPreviewModeChanged: (mode) =>
                  context.setSettings({_keyPreview: mode.name}),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: context.tone.surface,
                borderRadius:
                    BorderRadius.circular(DashboardMetrics.cardRadius),
              ),
              child: MultiBlocProvider(
                key: ValueKey('dashboard-page-${view.id}'),
                providers: [
                  BlocProvider<ViewInfoBloc>(
                    create: (_) => ViewInfoBloc(view: view)
                      ..add(const ViewInfoEvent.started()),
                  ),
                  BlocProvider<PageAccessLevelBloc>(
                    create: (_) => PageAccessLevelBloc(view: view)
                      ..add(const PageAccessLevelEvent.initial()),
                  ),
                ],
                child: DocumentPage(
                  key: ValueKey('dashboard-document-${view.id}'),
                  view: view,
                  onDeleted: () {},
                  tabs: const [
                    PickerTabType.emoji,
                    PickerTabType.icon,
                    PickerTabType.custom,
                  ],
                ),
              ),
            ),
    );
  },
  configure: (context) => [
    _viewField(
      context,
      label: LocaleKeys.dashboard_config_page.tr(),
      kind: DashboardSourceKind.page,
      filter: _isDocument,
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_display.tr(),
      value: context.spec.setting(_keyDisplay, fallback: 'preview'),
      choices: [
        DashboardChoice(
          value: 'preview',
          label: LocaleKeys.dashboard_display_preview.tr(),
        ),
        DashboardChoice(
          value: 'full',
          label: LocaleKeys.dashboard_display_full.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyDisplay: value}),
    ),
  ],
);

// ------------------------------------------------------------------ page link

final _pageLink = DashboardWidgetDefinition(
  type: 'page_link',
  label: () => LocaleKeys.dashboard_widget_pageLink.tr(),
  description: () => LocaleKeys.dashboard_widget_pageLinkHint.tr(),
  icon: Icons.link_rounded,
  group: DashboardWidgetGroup.content,
  defaultColumnSpan: 3,
  defaultRowSpan: 5,
  showsTitleByDefault: false,
  paintsOwnSurface: true,
  keywords: const ['page link', 'shortcut', 'open', 'go to', 'jump'],
  builder: (context) {
    final source = context.spec.source;
    if (source.viewId.isEmpty) {
      return _PageLinkRow(context: context, name: '');
    }
    return DashboardViewBuilder(
      viewId: source.viewId,
      revision: context.refreshToken,
      placeholder: _PageLinkRow(context: context, name: source.name),
      // Given room, a link is worth showing as the page it points at.
      builder: (_, view) => LayoutBuilder(
        builder: (inner, constraints) => constraints.maxHeight < 170
            ? _PageLinkRow(context: context, name: view.name)
            : PagePreviewCard(
                key: ValueKey('dashboard-link-preview-${view.id}'),
                view: view,
                userProfile: null,
                previewCache: _previewCache,
                onOpen: () => _openPage(context, view.id, view.name),
                onChangePage: () => unawaited(_pickPage(context)),
              ),
      ),
    );
  },
  configure: (context) => [
    _viewField(
      context,
      label: LocaleKeys.dashboard_config_page.tr(),
      kind: DashboardSourceKind.page,
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_description.tr(),
      value: context.spec.setting(_keyDescription),
      onChanged: (value) => context.setSettings({_keyDescription: value}),
    ),
  ],
);

// ---------------------------------------------------------------------- image

final _image = DashboardWidgetDefinition(
  type: 'image',
  label: () => LocaleKeys.dashboard_widget_image.tr(),
  icon: Icons.image_rounded,
  group: DashboardWidgetGroup.content,
  defaultRowSpan: 5,
  showsTitleByDefault: false,
  paintsOwnSurface: true,
  keywords: const ['image', 'picture', 'photo', 'cover', 'banner'],
  builder: (context) {
    final url = context.spec.setting(_keyUrl);
    final viewId = context.spec.source.viewId;
    final fit = switch (context.spec.setting(_keyFit, fallback: 'cover')) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };

    if (url.isNotEmpty) {
      return _paintImage(context, url, fit);
    }
    if (viewId.isEmpty) {
      return _EmptySurface(
        palette: context.palette,
        icon: Icons.image_outlined,
        message: LocaleKeys.dashboard_widget_pickImage.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickFile(context)),
      );
    }
    return DashboardViewBuilder(
      viewId: viewId,
      revision: context.refreshToken,
      builder: (_, view) {
        final path = view.workspaceItem?.storageUrl ?? '';
        return path.isEmpty
            ? _EmptySurface(
                palette: context.palette,
                icon: Icons.broken_image_outlined,
                message: LocaleKeys.dashboard_widget_imageMissing.tr(),
              )
            : _paintImage(context, path, fit);
      },
    );
  },
  configure: (context) => [
    _viewField(
      context,
      label: LocaleKeys.dashboard_config_file.tr(),
      kind: DashboardSourceKind.file,
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_url.tr(),
      hint: LocaleKeys.dashboard_config_urlHint.tr(),
      value: context.spec.setting(_keyUrl),
      placeholder: 'https://',
      onChanged: (value) => context.setSettings({_keyUrl: value}),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_fit.tr(),
      value: context.spec.setting(_keyFit, fallback: 'cover'),
      choices: [
        DashboardChoice(
          value: 'cover',
          label: LocaleKeys.dashboard_fit_cover.tr(),
        ),
        DashboardChoice(
          value: 'contain',
          label: LocaleKeys.dashboard_fit_contain.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyFit: value}),
    ),
  ],
);

Widget _paintImage(
  DashboardWidgetContext context,
  String source,
  BoxFit fit,
) {
  final isRemote =
      source.startsWith('http://') || source.startsWith('https://');
  final image = isRemote
      ? Image.network(
          source,
          fit: fit,
          errorBuilder: (_, __, ___) => _EmptySurface(
            palette: context.palette,
            icon: Icons.broken_image_outlined,
            message: LocaleKeys.dashboard_widget_imageMissing.tr(),
          ),
        )
      : Image.file(
          File(source),
          fit: fit,
          errorBuilder: (_, __, ___) => _EmptySurface(
            palette: context.palette,
            icon: Icons.broken_image_outlined,
            message: LocaleKeys.dashboard_widget_imageMissing.tr(),
          ),
        );
  return SizedBox.expand(child: image);
}

// ------------------------------------------------------------------- bookmark

final _bookmark = DashboardWidgetDefinition(
  type: 'bookmark',
  label: () => LocaleKeys.dashboard_widget_bookmark.tr(),
  description: () => LocaleKeys.dashboard_widget_bookmarkHint.tr(),
  icon: Icons.bookmark_rounded,
  group: DashboardWidgetGroup.content,
  defaultColumnSpan: 6,
  minimumColumnSpan: 3,
  showsTitleByDefault: false,
  // It draws the same card a page embed does, and a card inside a card reads
  // as a double border.
  paintsOwnSurface: true,
  keywords: const ['bookmark', 'link', 'web', 'url', 'site', 'embed'],
  builder: (context) => _LinkCard(context: context),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_url.tr(),
      value: context.spec.setting(_keyUrl),
      placeholder: 'https://',
      onChanged: (value) => context.setSettings({_keyUrl: value}),
    ),
  ],
);

/// A link as the web itself describes it: its picture, its title, the sentence
/// underneath and the address it really goes to.
///
/// The reading comes from the same [LinkParser] a link preview block uses, so
/// a link saved on a dashboard and a link written into a page agree.
class _LinkCard extends StatefulWidget {
  const _LinkCard({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  final LinkParser _parser = LinkParser();
  LinkInfo? _info;
  String _resolving = '';
  bool _hovered = false;

  String get _url => widget.context.spec.setting(_keyUrl).trim();

  @override
  void initState() {
    super.initState();
    _parser.addLinkInfoListener(_onInfo);
    _resolve();
  }

  @override
  void didUpdateWidget(_LinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  @override
  void dispose() {
    _parser.dispose();
    super.dispose();
  }

  void _onInfo(LinkInfo info) {
    if (mounted) {
      setState(() => _info = info);
    }
  }

  void _resolve() {
    final url = _url;
    if (url.isEmpty || url == _resolving) {
      return;
    }
    _resolving = url;
    _info = null;
    unawaited(_parser.start(url));
  }

  @override
  Widget build(BuildContext build) {
    final context = widget.context;
    final palette = context.palette;
    final url = _url;

    if (url.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.link_rounded,
        message: LocaleKeys.dashboard_widget_bookmarkHint.tr(),
        action: LocaleKeys.dashboard_link_add.tr(),
        onAction: () => unawaited(_askForUrl(context)),
      );
    }

    final info = _info;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    final title = context.spec.title.isNotEmpty
        ? context.spec.title
        : (info?.title?.trim().isNotEmpty ?? false)
            ? info!.title!.trim()
            : (host.isEmpty ? url : host);
    final description = info?.description?.trim() ?? '';
    final image = info?.imageUrl;
    final address =
        uri == null ? url : '${uri.host}${uri.path == '/' ? '' : uri.path}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(
          context.run(
            DashboardAction(kind: DashboardActionKind.openUrl, target: url),
          ),
        ),
        onSecondaryTap:
            context.isTypable ? () => unawaited(_askForUrl(context)) : null,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          decoration: BoxDecoration(
            color: _hovered
                ? Color.alphaBlend(palette.hover, context.tone.surface)
                : context.tone.surface,
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            boxShadow: palette.cardShadow(raised: _hovered),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth >= 320;
              return Row(
                children: [
                  if (image != null && image.isNotEmpty && wide)
                    SizedBox(
                      width: (constraints.maxWidth * 0.34).clamp(120.0, 220.0),
                      height: double.infinity,
                      child: ColoredBox(
                        color: palette.sunken,
                        child: FlowyNetworkImage(
                          url: image,
                          errorWidgetBuilder: (_, __, ___) => Icon(
                            Icons.public_rounded,
                            size: 24,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardType.cardTitle(
                              palette,
                              color: palette.textPrimary,
                            ).copyWith(fontSize: 15.5),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Flexible(
                              child: Text(
                                description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: DashboardType.body(palette)
                                    .copyWith(fontSize: 13),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox.square(
                                dimension: 15,
                                child: info?.buildIconWidget(
                                      size: const Size.square(15),
                                    ) ??
                                    Icon(
                                      Icons.public_rounded,
                                      size: 15,
                                      color: palette.textMuted,
                                    ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashboardType.caption(palette),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 15,
                                color: palette.textMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------- file

final _file = DashboardWidgetDefinition(
  type: 'file',
  label: () => LocaleKeys.dashboard_widget_file.tr(),
  icon: Icons.insert_drive_file_rounded,
  group: DashboardWidgetGroup.content,
  defaultRowSpan: 6,
  showsTitleByDefault: false,
  keywords: const ['file', 'attachment', 'pdf', 'document', 'download'],
  builder: (context) {
    final source = context.spec.source;
    if (source.viewId.isEmpty) {
      return DashboardPlaceholder(
        palette: context.palette,
        icon: Icons.attach_file_rounded,
        message: LocaleKeys.dashboard_widget_pickFile.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickFile(context)),
      );
    }
    final preview = context.spec.flag(_keyPreview, fallback: true);
    return DashboardViewBuilder(
      viewId: source.viewId,
      revision: context.refreshToken,
      // The name is read from the file itself, not from the copy taken when
      // it was chosen, so renaming it anywhere shows here.
      placeholder: _FileRow(context: context, name: source.name),
      builder: (_, view) => preview
          ? WorkspaceFileView(
              key: ValueKey('dashboard-file-${view.id}'),
              view: view,
            )
          : _FileRow(context: context, name: view.name),
    );
  },
  configure: (context) => [
    _viewField(
      context,
      label: LocaleKeys.dashboard_config_file.tr(),
      kind: DashboardSourceKind.file,
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_preview.tr(),
      value: context.spec.flag(_keyPreview, fallback: true),
      onChanged: (value) => context.setSettings({_keyPreview: value}),
    ),
  ],
);

/// A file as one line: what it is called, and a way in.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.context, required this.name});

  final DashboardWidgetContext context;
  final String name;

  @override
  Widget build(BuildContext build) => _Tappable(
        palette: context.palette,
        onTap: () => unawaited(
          context.run(
            DashboardAction(
              kind: DashboardActionKind.openPage,
              target: context.spec.source.viewId,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.strong.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.insert_drive_file_rounded,
                size: 17,
                color: context.strong,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                name.isEmpty ? LocaleKeys.dashboard_widget_pickFile.tr() : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.cardTitle(
                  context.palette,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------- surfaces

void _openPage(DashboardWidgetContext context, String viewId, String name) =>
    unawaited(
      context.run(
        DashboardAction(
          kind: DashboardActionKind.openPage,
          target: viewId,
          targetName: name,
        ),
      ),
    );

/// A page as one line: its icon, its name, and a way in.
class _PageLinkRow extends StatelessWidget {
  const _PageLinkRow({required this.context, required this.name});

  final DashboardWidgetContext context;
  final String name;

  @override
  Widget build(BuildContext build) {
    final source = context.spec.source;
    // The widget paints its own surface, so the compact form has to carry one.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.tone.surface,
        borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
        boxShadow: context.palette.cardShadow(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _Tappable(
          palette: context.palette,
          onTap: source.viewId.isEmpty
              ? () => unawaited(_pickPage(context))
              : () => _openPage(context, source.viewId, name),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.strong.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.description_rounded,
                  size: 17,
                  color: context.strong,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name.isEmpty
                          ? LocaleKeys.dashboard_widget_pickPage.tr()
                          : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        context.palette,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    if (context.spec.setting(_keyDescription).isNotEmpty)
                      Text(
                        context.spec.setting(_keyDescription),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(context.palette),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _askForUrl(DashboardWidgetContext context) async {
  final url = await askForDashboardLink(
    context.context,
    palette: context.palette,
    initialValue: context.spec.setting(_keyUrl),
  );
  if (url == null || url.trim().isEmpty) {
    return;
  }
  context.setSettings({_keyUrl: url.trim()});
}

/// Ask for a web address.
///
/// It is its own dialog rather than the shared text prompt because a link is
/// almost always pasted: the field restates the editing keys (several
/// ancestors in this application claim Backspace and Ctrl+V before a field
/// sees them) and offers a paste button, which needs no key binding at all.
Future<String?> askForDashboardLink(
  BuildContext context, {
  required DashboardPalette palette,
  String initialValue = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _LinkDialog(palette: palette, initialValue: initialValue),
    );

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.palette, required this.initialValue});

  final DashboardPalette palette;
  final String initialValue;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focus.requestFocus();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Dialog(
      backgroundColor: palette.raised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                LocaleKeys.dashboard_config_url.tr(),
                style: DashboardType.cardTitle(
                  palette,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: palette.sunken,
                        borderRadius: BorderRadius.circular(
                          DashboardMetrics.controlRadius,
                        ),
                      ),
                      child: Center(
                        child: TextEntryShortcuts(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            onSubmitted: (_) => _submit(),
                            style: DashboardType.body(palette),
                            cursorColor: palette.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              hintText: 'https://',
                              hintStyle: DashboardType.body(palette)
                                  .copyWith(color: palette.textMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DashboardIconButton(
                    icon: Icons.content_paste_rounded,
                    palette: palette,
                    size: 34,
                    tooltip: LocaleKeys.dashboard_link_paste.tr(),
                    onPressed: () => unawaited(_paste()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DashboardButton(
                    label: LocaleKeys.button_cancel.tr(),
                    palette: palette,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  DashboardButton(
                    label: LocaleKeys.button_save.tr(),
                    palette: palette,
                    primary: true,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tappable extends StatefulWidget {
  const _Tappable({
    required this.child,
    required this.palette,
    required this.onTap,
  });

  final Widget child;
  final DashboardPalette palette;
  final VoidCallback? onTap;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            curve: DashboardMetrics.curve,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: _hovered && widget.onTap != null
                  ? widget.palette.hover
                  : widget.palette.hoverBase,
              borderRadius: BorderRadius.circular(11),
            ),
            child: widget.child,
          ),
        ),
      );
}

class _EmptySurface extends StatelessWidget {
  const _EmptySurface({
    required this.palette,
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final DashboardPalette palette;
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: palette.sunken,
        child: DashboardPlaceholder(
          palette: palette,
          icon: icon,
          message: message,
          action: action,
          onAction: onAction,
        ),
      );
}
