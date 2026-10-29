import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/external_file/external_file_view.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const _idPrefix = 'external-file:';

/// The tab id for the file at [path]. Opening the same path again finds it.
PluginId externalFilePluginId(String path) => '$_idPrefix$path';

/// A file from outside the workspace, opened from the system file manager or
/// the command line. It is shown where it is: nothing is imported or copied,
/// and it never appears in the folder tree.
class ExternalFilePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is String && data.isNotEmpty) {
      return ExternalFilePlugin(path: data);
    }
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => 'File';

  @override
  FlowySvgData get icon => FlowySvgs.icon_document_s;

  @override
  PluginType get pluginType => PluginType.externalFile;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class ExternalFilePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class ExternalFilePlugin extends Plugin {
  ExternalFilePlugin({required this.path});

  /// An absolute path.
  final String path;

  /// Bumped when the file is opened again, so the tab reads it from disk.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Preview state, such as source editing, kept for as long as the tab is.
  Map<String, dynamic> metadata = const {};

  bool _disposed = false;

  String get name => p.basename(path);

  @override
  late final PluginWidgetBuilder widgetBuilder =
      ExternalFilePluginDisplay(this);

  @override
  PluginId get id => externalFilePluginId(path);

  @override
  PluginType get pluginType => PluginType.externalFile;

  void reload() {
    if (!_disposed) revision.value++;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    revision.dispose();
    super.dispose();
  }
}

class ExternalFilePluginDisplay extends PluginWidgetBuilder {
  ExternalFilePluginDisplay(this.plugin);

  final ExternalFilePlugin plugin;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  String? get viewName => plugin.name;

  @override
  Widget get leftBarItem => _ExternalFileTitle(path: plugin.path);

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      _ExternalFileTabItem(name: plugin.name, shortForm: shortForm);

  @override
  Widget? get rightBarItem => null;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      ExternalFileView(key: ValueKey(plugin.id), plugin: plugin);

  @override
  late final List<NavigationItem> navigationItems = [this];
}

/// Matches a page tab: the file's icon and its name.
class _ExternalFileTabItem extends StatelessWidget {
  const _ExternalFileTabItem({required this.name, required this.shortForm});

  final String name;
  final bool shortForm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          shortForm ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        WorkspaceGlyph.file(name, size: 16),
        if (!shortForm) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 13,
                    height: 1.2,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The file's name, then the folder it lives in, where a page shows its
/// breadcrumbs.
class _ExternalFileTitle extends StatelessWidget {
  const _ExternalFileTitle({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final style = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.metadata,
    ).copyWith(fontSize: 13, height: 1.2);
    final name = p.basename(path);
    return Tooltip(
      message: path,
      excludeFromSemantics: true,
      child: Row(
        children: [
          const SizedBox(width: 6),
          WorkspaceGlyph.file(name, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: palette.primaryText),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 2,
            child: Text(
              displayExternalFileFolder(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: palette.mutedText),
            ),
          ),
        ],
      ),
    );
  }
}

/// The folder holding [path], with the home folder written as `~`.
String displayExternalFileFolder(String path, {String? home}) {
  final folder = p.dirname(path);
  final root = home ??
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (root == null || root.isEmpty) return folder;
  if (p.equals(folder, root)) return '~';
  if (p.isWithin(root, folder)) {
    return p.join('~', p.relative(folder, from: root));
  }
  return folder;
}
