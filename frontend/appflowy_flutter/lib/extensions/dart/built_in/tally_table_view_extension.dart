import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_boundary.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/table_view_host.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// A table view supplied entirely by an extension.
///
/// This is the worked example for the table-view tier, and it is the honest
/// limit of what Dart can add: `ViewLayoutPB` belongs to the Rust backend, so a
/// genuinely new *page type* is impossible from here. A table view is the seam
/// that is available — it rides on a Grid and lives in the view's `extra` JSON,
/// which the backend never interprets. Timeline, feed, form, gallery and
/// mailbox are all built this way; the only difference is that those are
/// compiled into the enum and this one is not.
class TallyTableViewExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'tally',
        name: 'Tally',
        description: 'Shows a table as a running count of its rows.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;

    ctx.tableViews.add(
      id: 'tally',
      name: 'Tally',
      icon: Icons.numbers_rounded,
      buildTabBar: TallyTabBarBuilder.new,
    );
  }
}

class TallyTabBarBuilder extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      ExtensionBoundary(
        extensionId: 'tally',
        child: _TallyPage(view: view, databaseController: controller),
      );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class _TallyPage extends StatefulWidget {
  const _TallyPage({required this.view, required this.databaseController});

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<_TallyPage> createState() => _TallyPageState();
}

class _TallyPageState extends State<_TallyPage>
    with TableViewHostPlumbing<_TallyPage> {
  var _rows = 0;

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => widget.databaseController;

  @override
  String get hostEnvelopeKey => 'ext.tally.tally';

  @override
  void onRowsChanged() {
    if (mounted) {
      setState(() => _rows = hostController.rowCache.rowInfos.length);
    }
  }

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_rows', style: theme.textTheme.displayLarge),
          const SizedBox(height: 8),
          Text(widget.view.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: addRow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a row'),
          ),
        ],
      ),
    );
  }
}
