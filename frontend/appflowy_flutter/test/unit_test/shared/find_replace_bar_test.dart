import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the find bar builds inside an overlay', (tester) async {
    final findController = TextEditingController();
    final replaceController = TextEditingController();
    final findFocusNode = FocusNode();
    final replaceFocusNode = FocusNode();
    addTearDown(findController.dispose);
    addTearDown(replaceController.dispose);
    addTearDown(findFocusNode.dispose);
    addTearDown(replaceFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 52,
                right: 40,
                child: Material(
                  color: Colors.transparent,
                  child: FindReplaceBar(
                    findController: findController,
                    findFocusNode: findFocusNode,
                    options: const FindOptions(),
                    onOptionsChanged: (_) {},
                    matchCount: 3,
                    currentMatch: 1,
                    onPrevious: () {},
                    onNext: () {},
                    onClose: () {},
                    replaceController: replaceController,
                    replaceFocusNode: replaceFocusNode,
                    showReplace: true,
                    onToggleReplace: () {},
                    onReplace: () {},
                    onReplaceAll: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('findTextField')), findsOneWidget);
    expect(find.byKey(const ValueKey('replaceTextField')), findsOneWidget);
    expect(find.byKey(const ValueKey('findNextMatch')), findsOneWidget);
  });
}
