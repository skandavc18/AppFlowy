import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:flutter/widgets.dart';

/// Keep the real collection identity above provider loading/error/content
/// branches. Only the audited primary list borrows the nested controller;
/// secondary panes and horizontal shelves never inherit it automatically.
class ProviderPageFlow extends StatelessWidget {
  const ProviderPageFlow({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final header = FileBrowserPageHeader.maybeOf(context);
    if (header == null) return builder(context);
    return StandaloneFilePage(
      header: header,
      body: Builder(
        builder: (context) => CollectionPageScrollScope(
          controller: PrimaryScrollController.of(context),
          child: FileBrowserPageHeader(
            header: const SizedBox.shrink(),
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }
}
