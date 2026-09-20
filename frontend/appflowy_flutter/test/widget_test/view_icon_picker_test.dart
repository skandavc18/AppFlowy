import 'dart:async';

import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

void main() {
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = true);

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
        '$appearance: shared folder/file picker saves a typed Vivid icon',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, appearance);
      await fixture.open(tester);
      final picker = tester.widget<FlowyIconEmojiPicker>(
        find.byType(FlowyIconEmojiPicker),
      );
      expect(picker.documentId, 'first-view');
      expect(picker.tabs, kAllIconPickerTabs);
      await tester.tap(find.text('Icons'));
      await tester.pumpAndSettle();
      await tester.tap(vividIconStyleButton('Vivid'));
      await settleVividIconPictures(tester);
      await tester.tap(vividIconOption('rocket'));
      await tester.pumpAndSettle();
      expect(fixture.writes.single.$1, 'first-view');
      expect(fixture.writes.single.$2.toViewIcon(), _vivid().toViewIcon());
      expect(fixture.updates.single.icon, _vivid().toViewIcon());
      expect(fixture.updates.single.name, 'Unchanged name');
      expect(fixture.view.icon.value, isEmpty);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });
  }

  for (final invalidation in ['rebound', 'locked', 'dismissed', 'unmounted']) {
    testWidgets('shared view picker rejects callbacks after $invalidation',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, 'paper');
      await fixture.open(tester);
      final oldSelect = tester
          .widget<FlowyIconEmojiPicker>(
            find.byType(FlowyIconEmojiPicker),
          )
          .onSelectedEmoji!;
      switch (invalidation) {
        case 'rebound':
          fixture.rebuild(() => fixture.view = ViewPB(id: 'second-view'));
        case 'locked':
          fixture.rebuild(
            () => fixture.view = ViewPB(
              id: 'first-view',
              isLocked: true,
            ),
          );
        case 'dismissed':
          tester
              .widget<AppFlowyPopover>(
                find
                    .descendant(
                      of: find.byType(ViewIconPicker),
                      matching: find.byType(AppFlowyPopover),
                    )
                    .first,
              )
              .controller!
              .close();
        case 'unmounted':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      oldSelect(_vivid().toSelectedResult());
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      expect(fixture.updates, isEmpty);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });
  }

  testWidgets('pending save remains targeted and never updates a rebound view',
      (tester) async {
    final fixture = _Fixture();
    final completion = Completer<FlowyResult<void, FlowyError>>();
    fixture.pending = completion.future;
    await fixture.mount(tester, 'paper');
    await fixture.open(tester);
    final select = tester
        .widget<FlowyIconEmojiPicker>(
          find.byType(FlowyIconEmojiPicker),
        )
        .onSelectedEmoji!;
    select(_vivid().toSelectedResult());
    select(EmojiIconData.emoji('📘').toSelectedResult());
    expect(fixture.writes, hasLength(1));
    fixture.rebuild(() => fixture.view = ViewPB(id: 'second-view'));
    await tester.pumpAndSettle();
    completion.complete(FlowyResult.success(null));
    await tester.pumpAndSettle();
    expect(fixture.writes.single.$1, 'first-view');
    expect(fixture.updates, isEmpty);
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
  });
}

EmojiIconData _vivid() =>
    IconsData(vividIconTestGroup, 'rocket', null).toEmojiIconData();

class _Fixture {
  ViewPB view = ViewPB(id: 'first-view', name: 'Unchanged name');
  final writes = <(String, EmojiIconData)>[];
  final updates = <ViewPB>[];
  Future<FlowyResult<void, FlowyError>>? pending;
  late StateSetter rebuild;

  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) async {
    writes.add((view.id, viewIcon));
    final result = pending;
    if (result != null) return result;
    return FlowyResult.success(null);
  }

  Future<void> mount(WidgetTester tester, String appearance) async {
    await tester.pumpWidget(
      vividIconTestApp(
        appearance,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ViewIconPicker(
              view: view,
              updateIcon: save,
              onViewChanged: updates.add,
              child: const SizedBox.square(
                dimension: 40,
                child: Icon(Icons.folder_outlined),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(ViewIconPicker));
    await tester.pumpAndSettle();
    expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
  }
}
