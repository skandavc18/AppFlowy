import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

final _fileKeywords = [
  'file upload',
  'pdf',
  'zip',
  'archive',
  'upload',
  'attachment',
];

final fileSlashMenuItem = _buildFileSlashMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_file.tr(),
  keywords: _fileKeywords,
  icon: FlowySvgs.slash_menu_icon_file_s,
);

final pdfSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'PDF',
  keywords: const ['pdf', 'document', 'annotation'],
);
final wordSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: WorkspaceFileKind.word.label,
  keywords: const ['word', 'doc', 'docx', 'odt', 'rtf', 'document'],
  allowedExtensions: WorkspaceFileKind.word.pickerExtensions,
  materialIcon: WorkspaceFileKind.word.icon,
);
final excelSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: WorkspaceFileKind.excel.label,
  keywords: const ['excel', 'xls', 'xlsx', 'ods', 'spreadsheet', 'workbook'],
  allowedExtensions: WorkspaceFileKind.excel.pickerExtensions,
  materialIcon: WorkspaceFileKind.excel.icon,
);
final powerpointSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: WorkspaceFileKind.powerpoint.label,
  keywords: const [
    'powerpoint',
    'ppt',
    'pptx',
    'odp',
    'presentation',
    'slides',
  ],
  allowedExtensions: WorkspaceFileKind.powerpoint.pickerExtensions,
  materialIcon: WorkspaceFileKind.powerpoint.icon,
);
final htmlSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'HTML',
  keywords: const ['html', 'web page', 'javascript', 'css'],
);
final markdownSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'Markdown / markup',
  keywords: const ['markdown', 'markup', 'md'],
);
final zipSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'ZIP archive',
  keywords: const ['zip', 'archive', 'compressed'],
);
final csvSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'CSV table',
  keywords: const ['csv', 'tsv', 'table'],
);
final jsonSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'JSON',
  keywords: const ['json', 'data'],
);
final codeFileSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'Code file',
  keywords: const ['code', 'source', 'python', 'javascript', 'java', 'cpp'],
);
final textFileSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'Text file',
  keywords: const ['text', 'txt', 'log', 'config'],
);
final notebookSlashMenuItem = _buildPreviewFileSlashMenuItem(
  name: 'Jupyter notebook',
  keywords: const ['jupyter', 'notebook', 'ipynb', 'python'],
);

final audioSlashMenuItem = _buildFileSlashMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_audio.tr(),
  keywords: const ['audio', 'music', 'sound', 'voice', 'recording'],
  icon: FlowySvgs.ft_audio_s,
);

final videoSlashMenuItem = _buildFileSlashMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_video.tr(),
  keywords: const ['video', 'movie', 'clip', 'recording'],
  icon: FlowySvgs.ft_video_s,
);

SelectionMenuItem _buildFileSlashMenuItem({
  required String Function() getName,
  required List<String> keywords,
  required FlowySvgData icon,
}) =>
    SelectionMenuItem(
      getName: getName,
      keywords: keywords,
      handler: (editorState, _, __) async => editorState.insertFileBlock(),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableSvgWidget(
        data: icon,
        isSelected: isSelected,
        style: style,
      ),
    );

SelectionMenuItem _buildPreviewFileSlashMenuItem({
  required String name,
  required List<String> keywords,
  List<String>? allowedExtensions,
  IconData? materialIcon,
}) =>
    SelectionMenuItem(
      getName: () => name,
      keywords: keywords,
      handler: (editorState, _, __) async => editorState.insertFileBlock(
        showPreview: true,
        allowedExtensions: allowedExtensions,
      ),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => materialIcon == null
          ? SelectableSvgWidget(
              data: FlowySvgs.slash_menu_icon_file_s,
              isSelected: isSelected,
              style: style,
            )
          : SelectableIconWidget(
              icon: materialIcon,
              isSelected: isSelected,
              style: style,
            ),
    );

extension on EditorState {
  Future<void> insertFileBlock({
    bool showPreview = false,
    List<String>? allowedExtensions,
  }) async {
    final fileGlobalKey = GlobalKey<FileBlockComponentState>();
    await insertEmptyFileBlock(
      fileGlobalKey,
      showPreview: showPreview,
      allowedExtensions: allowedExtensions,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      fileGlobalKey.currentState?.controller.show();
    });
  }
}
