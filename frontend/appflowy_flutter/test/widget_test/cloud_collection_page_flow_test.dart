import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_page_flow.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();
  for (final theme in fileControlAppearances) {
    testWidgets(
        '$theme: cloud state transitions retain header draft and vertical owner',
        (tester) async {
      final stage = ValueNotifier('loading');
      final title = TextEditingController(text: 'Unsaved cloud title');
      final provider = _Provider();
      final headerKey = GlobalKey();
      await mountFileControls(
        tester,
        FileBrowserPageHeader(
          header: SizedBox(
            height: 240,
            child: TextField(key: headerKey, controller: title),
          ),
          child: ProviderPageFlow(
            builder: (context) => ValueListenableBuilder<String>(
              valueListenable: stage,
              builder: (context, value, _) {
                if (value == 'loading' || value == 'error') {
                  return FileBrowserScrollView(
                    controller: CollectionPageScrollScope.maybeOf(context),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Text(value),
                      ),
                    ],
                  );
                }
                return ExternalContentView(
                  controller: provider,
                  layout: ExternalLayout.list,
                  palette: CollectionPalette.of(
                    context,
                    CollectionKind.folder,
                  ),
                  header: value == 'stale'
                      ? const Text('Retry cached listing')
                      : null,
                );
              },
            ),
          ),
        ),
        mode: theme,
        width: 800,
        reduced: true,
      );
      final page =
          tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final headerElement = tester.element(find.byKey(headerKey));
      title.selection = const TextSelection(baseOffset: 2, extentOffset: 8);
      for (final state in [
        'populated',
        'stale',
        'error',
        'loading',
        'populated',
      ]) {
        stage.value = state;
        await settleFileControls(tester);
        expect(tester.state(find.byType(NestedScrollView)), same(page));
        expect(tester.element(find.byKey(headerKey)), same(headerElement));
        expect(title.text, 'Unsaved cloud title');
        expect(
          title.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        expect(page.innerController.positions, hasLength(1));
      }
      final viewport = tester.getRect(find.byType(ExternalContentView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: Offset(
            viewport.center.dx,
            tester.getRect(find.byType(ProviderPageFlow)).bottom - 30,
          ),
          scrollDelta: const Offset(0, 320),
        ),
      );
      await tester.pumpAndSettle();
      expect(page.outerController.offset, closeTo(240, .01));
      expect(page.innerController.offset, closeTo(80, .01));
      expect(find.text('Cloud file 0').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await unmountFileControls(tester);
      provider.dispose();
      title.dispose();
      stage.dispose();
    });
  }
}

class _Provider extends ChangeNotifier implements ProviderController {
  @override
  bool get isSearching => false;
  @override
  List<ProviderNode> get nodes => _nodes;
  final _nodes = List.generate(
    400,
    (i) => ProviderNode(
      id: '$i',
      name: 'Cloud file $i',
      kind: ProviderNodeKind.other,
    ),
  );
  @override
  List<ProviderNode> childrenOf(String? id) => _nodes;
  @override
  bool isLoadingContainer(String? id) => false;
  @override
  String? thumbnailFor(String id) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
