import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Real compiled artwork, gallery leaves and decoration slots. Synthetic views,
/// synchronous previews, no controllers, file reads, backend or preference IO.
class WorkspaceIdentityVisualFixture extends StatelessWidget {
  const WorkspaceIdentityVisualFixture({
    super.key,
    required this.monochrome,
    required this.vivid,
  });

  final ValueListenable<DefaultIconStyle> monochrome;
  final ValueListenable<DefaultIconStyle> vivid;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: WorkspacePalette.of(context).background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final styles in [monochrome, vivid])
                Expanded(
                  child: DefaultIconStyleScope(
                    styles: styles,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _Column(style: styles.value),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Column extends StatelessWidget {
  const _Column({required this.style});
  final DefaultIconStyle style;

  @override
  Widget build(BuildContext context) {
    final chat = ViewPB(
      id: 'visual-chat',
      name: 'AI Chat',
      layout: ViewLayoutPB.Chat,
    );
    final file = ViewPB(
      id: 'archive-visual::Notes.zip',
      name: 'Notes.zip',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
      ).mergeIntoExtra(''),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          style == DefaultIconStyle.monochrome ? 'Monochrome' : 'Vivid',
          style: WorkspaceTypography.style(context, WorkspaceTextRole.section),
        ),
        for (final group in _groups.entries) ...[
          const SizedBox(height: 18),
          Text(
            group.key,
            style: WorkspaceTypography.style(context, WorkspaceTextRole.body),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            children: [
              for (final name in group.value)
                SizedBox(
                  width: 74,
                  height: 78,
                  child: Column(
                    children: [
                      WorkspaceGlyph.named(name, size: 30),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.caption,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            for (final view in [chat, file])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: FolderGalleryPreviewThumbnail(
                    item: WorkspaceExplorerItem.fromView(view),
                    view: view,
                    preview: SynchronousFuture(
                      view == chat
                          ? FolderGalleryPreviewParser.chat(view)
                          : const FolderGalleryPreview(
                              kind: FolderGalleryPreviewKind.file,
                              blocks: [],
                              wordCount: 0,
                              readingMinutes: 0,
                              tags: [],
                              fileTypeLabel: 'ZIP',
                            ),
                    ),
                    userProfile: null,
                    height: 140,
                  ),
                ),
              ),
          ],
        ),
        DatabasePageDecoration(
          view: ViewPB(
            id: 'visual-table',
            name: 'A table without a cover',
            layout: ViewLayoutPB.Grid,
          ),
          userProfile: null,
          horizontalPadding: 20,
        ),
      ],
    );
  }
}

const _groups = {
  'Files': [
    'file',
    'file-text',
    'file-pdf',
    'file-doc',
    'file-xls',
    'file-ppt',
    'file-zip',
    'file-code',
    'file-csv',
    'file-markdown',
    'file-html',
    'file-json',
    'file-notebook',
    'image',
    'film-strip',
    'music-note',
  ],
  'Folders and collections': [
    'folder',
    'folder-open',
    'book-open',
    'images',
    'git-branch',
    'database',
    'link-simple',
    'envelope-simple',
  ],
  'Pages and views': [
    'file-text',
    'ai-chat',
    'table',
    'kanban',
    'calendar-blank',
    'chart-bar',
    'map-trifold',
    'presentation-chart',
    'graph',
    'article',
    'list-checks',
    'squares-four',
    'layout',
    'canvas',
  ],
  'Code toolbar': ['line-numbers', 'line-numbers-off'],
};
