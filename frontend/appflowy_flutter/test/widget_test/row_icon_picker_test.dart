import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_banner_bloc.dart';
import 'package:appflowy/plugins/database/application/row/row_cache.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/desktop_grid_text_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/mobile_grid/mobile_grid_text_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/database/widgets/row/row_banner.dart';
import 'package:appflowy/plugins/database_document/presentation/database_document_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/emoji_picker_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_color_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_search_bar.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_uploader.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _viewId = 'row-icon-test-view';
const _rowId = 'row-icon-test-row';
const _documentId = 'row-icon-test-document';
const _title = 'A row title';
const _cell = CellContext(fieldId: 'primary', rowId: _rowId);

enum _Entry { banner, rename }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousDisableLog = Log.shared.disableLog;
  final previousRecents = RecentIcons.enable;
  const dropChannel = MethodChannel('desktop_drop');

  setUpAll(() async {
    Log.shared.disableLog = true;
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(() async {
    await resetVividIconTestPacks();
    // The upload tab is real; OS drag/drop registration is not part of a row
    // identity test and must not require a desktop application.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dropChannel, (_) async => null);
  });
  tearDownAll(() {
    RecentIcons.enable = previousRecents;
    Log.shared.disableLog = previousDisableLog;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dropChannel, null);
  });

  for (final legacy in ['', '📘', '👩🏽‍💻', '🇮🇳']) {
    test('row metadata keeps legacy emoji/empty bytes unchanged: $legacy', () {
      final original = _row(legacy);
      final decoded = EmojiIconData.fromStorageString(original.icon);
      expect(decoded.toStorageString(), legacy);
      final restored = RowMetaPB.fromBuffer(original.writeToBuffer());
      expect(restored.icon, legacy);
      expect(
        EmojiIconData.fromStorageString(restored.icon).toStorageString(),
        legacy,
      );
      if (legacy.isNotEmpty) expect(decoded.type, FlowyIconType.emoji);
    });
  }

  test('typed row icons retain group, name, tint and custom path metadata', () {
    final choices = [
      IconsData('appflowy_default_collections', 'book', '4278255360')
          .toEmojiIconData(),
      IconsData(vividIconTestGroup, 'rocket', null).toEmojiIconData(),
      IconsData('phosphor_regular_objects', 'coffee', '4294901760')
          .toEmojiIconData(),
      EmojiIconData.custom(r'C:\owned test images\a # b.svg'),
      EmojiIconData.custom('https://example.invalid/icon.png?version=2#crop'),
    ];
    for (final choice in choices) {
      final stored = choice.toStorageString();
      final row = RowMetaPB.fromBuffer(_row(stored).writeToBuffer());
      final decoded = EmojiIconData.fromStorageString(row.icon);
      expect(decoded.type, choice.type);
      expect(decoded.emoji, choice.emoji);
      expect(decoded.toStorageString(), stored);
      expect(decoded.toViewIcon().ty, choice.toViewIcon().ty);
      expect(jsonDecode(stored)['appflowy_icon'], 1);
    }
    expect(EmojiIconData.none().toStorageString(), '');
    expect(EmojiIconData.fromStorageString(null).isEmpty, isTrue);
  });

  for (final appearance in vividIconTestAppearances) {
    for (final entry in _Entry.values) {
      testWidgets(
          '$appearance ${entry.name}: full picker, Vivid save, cold render, '
          'tab restore and clear', (tester) async {
        final store = _MemoryRows(_row(entry == _Entry.banner ? '' : '📘'));
        var fixture = _PickerFixture(entry, store);
        try {
          await tester.pumpWidget(fixture.build(appearance));
          await tester.pumpAndSettle();
          await fixture.open(tester);
          _expectPicker(
            tester,
            entry == _Entry.banner
                ? PickerTabType.defaultIcons
                : PickerTabType.emoji,
          );
          await _chooseVivid(tester);
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          expect(store.writes, hasLength(1));
          final saved = store.read().icon;
          _expectVividData(EmojiIconData.fromStorageString(saved));
          if (entry == _Entry.rename) {
            _expectVividData(fixture.selections.single);
            expect(fixture.title.text, _title);
          }

          await fixture.dispose(tester);
          resetIconPacksForTesting();
          fixture = _PickerFixture(entry, store);
          await tester.pumpWidget(fixture.build(appearance));
          await tester.pumpAndSettle();
          await fixture.showIdentity(tester);
          _expectVividPaint(tester);
          expect(find.text(saved), findsNothing);
          expect(isIconPackLoaded(kDefaultIconPack), isFalse);
          expect(iconPacksVersion.value, 0);
          await settleVividIconPictures(tester);

          // Only the renderer was cold. Preload the ordinary library before
          // opening the real picker so its async asset load uses the real clock.
          await tester.runAsync(() => loadIconPack(kDefaultIconPack));
          await fixture.open(tester);
          _expectPicker(tester, PickerTabType.icon);
          await tester.tap(find.text(LocaleKeys.button_remove.tr()));
          await tester.pumpAndSettle();
          expect(store.read().icon, '');
          expect(store.writes.last, '');
          await fixture.showIdentity(tester);
          expect(find.byType(RawEmojiIconWidget), findsNothing);
          await fixture.open(tester);
          _expectPicker(tester, PickerTabType.defaultIcons);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });

      testWidgets('$appearance ${entry.name}: default icon restores its tab',
          (tester) async {
        final stored =
            IconsData('appflowy_default_collections', 'book', '4278255360')
                .toEmojiIconData()
                .toStorageString();
        final fixture = _PickerFixture(entry, _MemoryRows(_row(stored)));
        try {
          await tester.pumpWidget(fixture.build(appearance));
          await tester.pumpAndSettle();
          await fixture.open(tester);
          _expectPicker(tester, PickerTabType.defaultIcons);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });

      testWidgets(
          '$appearance ${entry.name}: upload result keeps its type and path',
          (tester) async {
        final store = _MemoryRows(_row('📘'));
        final fixture = _PickerFixture(entry, store);
        try {
          await tester.pumpWidget(fixture.build(appearance));
          await tester.pumpAndSettle();
          await fixture.open(tester);
          await tester.tap(find.text('Upload'));
          await tester.pumpAndSettle();
          final upload = tester.widget<IconUploader>(find.byType(IconUploader));
          expect(upload.documentId, _documentId);

          // Fake only the completed upload boundary. Do not mount the shared
          // custom-image renderer: it fetches the native current-user profile.
          store.onMetaChanged = null;
          const path = r'C:\owned row icons\diagram # 2.svg';
          upload.onUrl(path);
          await tester.pumpAndSettle();
          final restored = EmojiIconData.fromStorageString(store.read().icon);
          expect(restored.type, FlowyIconType.custom);
          expect(restored.emoji, path);
          expect(restored.toPickerTabType(), PickerTabType.custom);
          expect(restored.toStorageString(), store.writes.single);
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          if (entry == _Entry.rename) {
            expect(fixture.selections.single.type, FlowyIconType.custom);
            expect(fixture.selections.single.emoji, path);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }

    testWidgets('$appearance: read-only row identities fit narrow 2x layouts',
        (tester) async {
      final title = TextEditingController(text: _title)
        ..selection = const TextSelection.collapsed(offset: 2);
      final stored = _vivid().toStorageString();
      var iconWrites = 0;
      var nameWrites = 0;
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowBannerHeader(
                      rowMeta: _row(stored),
                      editable: false,
                      contentInset: 16,
                      onIconChanged: (_) => iconWrites++,
                      onCoverChanged: (_) {},
                    ),
                    RenameRowPopover(
                      textController: title,
                      icon: EmojiIconData.fromStorageString(stored),
                      documentId: _documentId,
                      editable: false,
                      onUpdateName: (_) => nameWrites++,
                      onUpdateIcon: (_) => iconWrites++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        expect(find.byType(IconWidget), findsNWidgets(2));
        expect(find.byType(EmojiPickerButton), findsNothing);
        expect(find.byType(AppFlowyPopover), findsNothing);
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        expect(title.selection, const TextSelection.collapsed(offset: 2));
        await tester.tap(find.byType(RawEmojiIconWidget).first);
        await tester.pumpAndSettle();
        expect(iconWrites, 0);
        expect(nameWrites, 0);
        expect(title.text, _title);
        expect(
          PaperTheme.isEnabled(tester.element(find.byType(RowBannerHeader))),
          appearance == 'paper',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await disposeVividIconPicker(tester);
        title.dispose();
      }
    });

    for (final renderer in ['desktop grid', 'card', 'mobile grid']) {
      testWidgets(
          '$appearance: $renderer decodes cold/live row icons without '
          'replacing the title editor', (tester) async {
        final fixture = _CellFixture(_vivid().toStorageString());
        try {
          await tester
              .pumpWidget(vividIconTestApp(appearance, const SizedBox()));
          await tester.pumpAndSettle();
          resetIconPacksForTesting();
          await tester.pumpWidget(
            vividIconTestApp(
              appearance,
              SizedBox(width: 180, child: fixture.build(renderer)),
            ),
          );
          _expectVividPaint(tester);
          expect(iconPacksVersion.value, 0);
          expect(isIconPackLoaded(kDefaultIconPack), isFalse);
          await settleVividIconPictures(tester);

          TextEditingController? controller;
          FocusNode? focus;
          EditableTextState? editor;
          if (renderer != 'desktop grid') {
            final context = tester.element(find.byType(TextField));
            context
                .read<TextCellBloc>()
                .add(const TextCellEvent.enableEdit(true));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), 'Uncommitted title');
            final field = tester.widget<TextField>(find.byType(TextField));
            controller = field.controller!;
            focus = field.focusNode!;
            controller.selection =
                const TextSelection(baseOffset: 2, extentOffset: 7);
            editor = tester.state<EditableTextState>(find.byType(EditableText));
            expect(focus.hasFocus, isTrue);
          }

          for (final value in ['👩🏽‍💻', _vivid().toStorageString(), '']) {
            fixture.row.updateRowMeta(_row(value));
            await tester.pumpAndSettle();
            final decoded = EmojiIconData.fromStorageString(value);
            if (decoded.isEmpty) {
              expect(find.byType(RawEmojiIconWidget), findsNothing);
              if (renderer == 'desktop grid') {
                expect(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is FlowySvg && widget.svg == FlowySvgs.notes_s,
                  ),
                  findsOneWidget,
                );
              }
            } else {
              final raw = tester
                  .widget<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget));
              expect(raw.emoji.type, decoded.type);
              expect(raw.emoji.emoji, decoded.emoji);
              if (decoded.type == FlowyIconType.icon) {
                _expectVividPaint(tester);
                expect(find.text(value), findsNothing);
              } else {
                expect(find.text(value), findsOneWidget);
              }
            }
            if (controller != null) {
              expect(
                tester.state<EditableTextState>(find.byType(EditableText)),
                same(editor),
              );
              expect(
                tester.widget<TextField>(find.byType(TextField)).controller,
                same(controller),
              );
              expect(controller.text, 'Uncommitted title');
              expect(
                controller.selection,
                const TextSelection(baseOffset: 2, extentOffset: 7),
              );
              expect(focus!.hasFocus, isTrue);
            }
          }
          expect(fixture.cell.writes, isEmpty);
          if (renderer == 'card') {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(fixture.cell.writes, ['Uncommitted title']);
            expect(focus!.hasFocus, isFalse);
            expect(
              tester.widget<TextField>(find.byType(TextField)).readOnly,
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }
  }

  for (final entry in _Entry.values) {
    testWidgets('${entry.name}: a disabled picker rejects an old callback',
        (tester) async {
      final title = TextEditingController(text: _title);
      var editable = true;
      var writes = 0;
      late StateSetter rebuild;
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            'paper',
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SizedBox(
                  width: 220,
                  child: entry == _Entry.banner
                      ? RowIcon(
                          icon: EmojiIconData.emoji('📘'),
                          documentId: _documentId,
                          editable: editable,
                          onIconChanged: (_) => writes++,
                        )
                      : RenameRowPopover(
                          textController: title,
                          icon: EmojiIconData.emoji('📘'),
                          documentId: _documentId,
                          editable: editable,
                          onUpdateName: (_) {},
                          onUpdateIcon: (_) => writes++,
                        ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byType(entry == _Entry.banner ? RowIcon : EmojiPickerButton),
        );
        await tester.pumpAndSettle();
        final staleSelection = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .onSelectedEmoji!;
        rebuild(() => editable = false);
        await tester.pumpAndSettle();
        staleSelection(_vivid().toSelectedResult());
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeVividIconPicker(tester);
        title.dispose();
      }
    });

    for (final packId in ['color', 'phosphor_regular']) {
      testWidgets('${entry.name}: real $packId library choice is not emoji',
          (tester) async {
        final pack = kIconPacks.firstWhere((pack) => pack.id == packId);
        final groups = await tester.runAsync(() => loadIconPack(pack));
        expect(groups, isNotEmpty);
        final group = groups!.firstWhere((group) => group.icons.isNotEmpty);
        final icon = group.icons.first;
        final store = _MemoryRows(_row('📘'));
        final fixture = _PickerFixture(entry, store);
        try {
          await tester.pumpWidget(fixture.build('paper'));
          await tester.pumpAndSettle();
          await fixture.open(tester);
          await tester.tap(find.text('Icons'));
          await tester.pumpAndSettle();
          await tester.tap(vividIconStyleButton(pack.displayName));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(
              of: find.byType(IconSearchBar),
              matching: find.byType(TextField),
            ),
            icon.name,
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          final glyph = find.descendant(
            of: find.byType(IconPicker),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is FlowySvg && widget.svgString == icon.content,
            ),
          );
          final button = find
              .ancestor(
                of: glyph,
                matching:
                    find.byType(pack.isColorful ? TextButton : FlowyButton),
              )
              .first;
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          if (!pack.isColorful) {
            final colors = find.descendant(
              of: find.byType(IconColorPicker),
              matching: find.byWidgetPredicate(
                (widget) => widget is GestureDetector && widget.onTap != null,
              ),
            );
            await tester.tap(colors.first);
            await tester.pumpAndSettle();
          }
          final saved = EmojiIconData.fromStorageString(store.read().icon);
          expect(saved.type, FlowyIconType.icon);
          final data = IconsData.fromJson(jsonDecode(saved.emoji));
          expect(data.groupName, group.name);
          expect(data.iconName, icon.name);
          expect(data.svgString, icon.content);
          expect(data.color, pack.isColorful ? isNull : isNotNull);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }
  }

  for (final renderer in ['desktop grid', 'mobile grid']) {
    testWidgets('$renderer: a non-primary field never receives a row icon',
        (tester) async {
      final fixture = _CellFixture(_vivid().toStorageString(), primary: false);
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            'light',
            SizedBox(width: 180, child: fixture.build(renderer)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RawEmojiIconWidget), findsNothing);
        fixture.row.updateRowMeta(_row('📘'));
        await tester.pumpAndSettle();
        expect(find.byType(RawEmojiIconWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('card: missing row metadata keeps the notes fallback',
      (tester) async {
    final fixture = _CellFixture('', showNotes: true);
    fixture.cell.hasRowMetadata = false;
    // Recreate the bloc from the same injected data boundary, as the real
    // card does on mount. The fixture's outer bloc is not used by the card.
    try {
      await tester.pumpWidget(
        vividIconTestApp(
          'paper',
          SizedBox(width: 180, child: fixture.build('card')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RawEmojiIconWidget), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is FlowySvg && widget.svg == FlowySvgs.notes_s,
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

EmojiIconData _vivid() =>
    IconsData(vividIconTestGroup, 'rocket', null).toEmojiIconData();

RowMetaPB _row(String icon) => RowMetaPB(
      id: _rowId,
      documentId: _documentId,
      icon: icon,
      cover: RowCoverPB(),
      isDocumentEmpty: false,
    );

void _expectPicker(WidgetTester tester, PickerTabType initial) {
  final picker =
      tester.widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker));
  expect(picker.tabs, kAllIconPickerTabs);
  expect(picker.effectiveTabs, [
    PickerTabType.emoji,
    PickerTabType.defaultIcons,
    PickerTabType.icon,
    PickerTabType.custom,
  ]);
  expect(picker.documentId, _documentId);
  expect(picker.initialType, initial);
  final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
  expect(tabs.tabs[tabs.controller.index], initial);
}

Future<void> _chooseVivid(WidgetTester tester) async {
  await tester.tap(find.text('Icons'));
  await tester.pumpAndSettle();
  expect(vividIconStyleButton('Vivid').hitTestable(), findsOneWidget);
  expect(vividIconStyleButton('Color').hitTestable(), findsOneWidget);
  expect(vividIconStyleButton('Line').hitTestable(), findsOneWidget);
  await tester.tap(vividIconStyleButton('Vivid'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(vividIconOption('rocket'));
  await tester.tap(vividIconOption('rocket'));
  await tester.pumpAndSettle();
}

void _expectVividData(EmojiIconData icon) {
  expect(icon.type, FlowyIconType.icon);
  final data = IconsData.fromJson(jsonDecode(icon.emoji));
  expect(data.groupName, vividIconTestGroup);
  expect(data.iconName, 'rocket');
  expect(data.color, isNull);
}

void _expectVividPaint(WidgetTester tester) {
  final raw = find.byType(RawEmojiIconWidget);
  expect(raw, findsOneWidget);
  _expectVividData(tester.widget<RawEmojiIconWidget>(raw).emoji);
  final svg = tester.widget<FlowySvg>(
    find.descendant(of: raw, matching: find.byType(FlowySvg)),
  );
  expect(svg.svgString, findLoadedIcon(vividIconTestGroup, 'rocket')!.content);
  expect(svg.blendMode, isNull);
  expect(svg.color, isNull);
  expect(find.byType(IconWidget), findsOneWidget);
}

class _PickerFixture {
  _PickerFixture(this.entry, this.store) {
    if (entry == _Entry.banner) {
      banner = RowBannerBloc(
        viewId: _viewId,
        fieldController: _Fields(),
        rowMeta: store.read(),
        rowBackendService: store,
      );
      store.onMetaChanged =
          (row) => banner!.add(RowBannerEvent.didReceiveRowMeta(row));
      // No initial event: field/profile loading is unrelated native transport.
    }
  }

  final _Entry entry;
  final _MemoryRows store;
  final title = TextEditingController(text: _title);
  final rename = PopoverController();
  final selections = <EmojiIconData>[];
  RowBannerBloc? banner;
  bool _disposed = false;

  Widget build(String appearance) => vividIconTestApp(
        appearance,
        SizedBox(
          width: 320,
          child: entry == _Entry.banner
              ? BlocBuilder<RowBannerBloc, RowBannerState>(
                  bloc: banner,
                  builder: (context, state) => RowBannerHeader(
                    rowMeta: state.rowMeta,
                    contentInset: 16,
                    onIconChanged: (icon) =>
                        banner!.add(RowBannerEvent.setIcon(icon ?? '')),
                    onCoverChanged: (_) {},
                  ),
                )
              : AppFlowyPopover(
                  controller: rename,
                  triggerActions: PopoverTriggerFlags.none,
                  direction: PopoverDirection.bottomWithLeftAligned,
                  constraints:
                      const BoxConstraints(maxWidth: 220, maxHeight: 44),
                  margin: EdgeInsets.zero,
                  popupBuilder: (_) => RenameRowPopover(
                    textController: title,
                    icon: EmojiIconData.fromStorageString(store.read().icon),
                    documentId: _documentId,
                    onUpdateName: (_) {},
                    onUpdateIcon: (icon) {
                      selections.add(icon);
                      unawaited(
                        store.updateMeta(
                          rowId: _rowId,
                          iconURL: icon.toStorageString(),
                        ),
                      );
                    },
                  ),
                  child: TextButton(
                    onPressed: rename.show,
                    child: const Text('Rename row'),
                  ),
                ),
        ),
      );

  Future<void> showIdentity(WidgetTester tester) async {
    if (entry == _Entry.rename &&
        find.byType(RenameRowPopover).evaluate().isEmpty) {
      await tester.tap(find.text('Rename row'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester) async {
    await showIdentity(tester);
    if (entry == _Entry.rename) {
      await tester.tap(find.byType(EmojiPickerButton));
    } else if (find.byType(RowIcon).evaluate().isNotEmpty) {
      await tester.tap(find.byType(RowIcon));
    } else {
      await tester
          .tap(find.text(LocaleKeys.document_plugins_cover_addIcon.tr()));
    }
    await tester.pumpAndSettle();
    expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    store.onMetaChanged = null;
    await disposeVividIconPicker(tester);
    if (banner != null) await tester.runAsync(banner!.close);
    title.dispose();
  }
}

/// The real banner bloc writes through this boundary and receives fresh wire
/// metadata back. Nothing calls the native SDK or touches a user's workspace.
class _MemoryRows extends RowBackendService {
  _MemoryRows(RowMetaPB row)
      : bytes = row.writeToBuffer(),
        super(viewId: _viewId);

  List<int> bytes;
  final writes = <String>[];
  ValueChanged<RowMetaPB>? onMetaChanged;

  RowMetaPB read() => RowMetaPB.fromBuffer(bytes);

  @override
  Future<FlowyResult<void, FlowyError>> updateMeta({
    required String rowId,
    String? iconURL,
    RowCoverPB? cover,
    bool? isDocumentEmpty,
  }) async {
    expectSync(rowId, _rowId);
    expectSync(iconURL, isNotNull);
    final row = read()..icon = iconURL!;
    writes.add(iconURL);
    bytes = row.writeToBuffer();
    onMetaChanged?.call(read());
    return FlowyResult.success(null);
  }
}

class _Fields extends Fake implements FieldController {
  _Fields({bool primary = true})
      : field = FieldInfo.initial(
          FieldPB(
            id: _cell.fieldId,
            name: 'Title',
            fieldType: FieldType.RichText,
            isPrimary: primary,
          ),
        );

  final FieldInfo field;

  @override
  List<FieldInfo> get fieldInfos => [field];

  @override
  FieldInfo? getField(String fieldId) => fieldId == field.id ? field : null;

  @override
  void addSingleFieldListener(
    String fieldId, {
    required OnReceiveField onFieldChanged,
    bool Function()? listenWhen,
  }) {}

  @override
  void removeSingleFieldListener({
    required String fieldId,
    required OnReceiveField onFieldChanged,
  }) {}
}

class _Database extends Fake implements DatabaseController {}

class _CachedCell extends Fake implements CellController<String, String> {
  _CachedCell(this.row, this.fieldInfo);

  final RowInfo row;
  final writes = <String>[];
  bool hasRowMetadata = true;
  @override
  final FieldInfo fieldInfo;
  @override
  ValueNotifier<String>? get icon =>
      hasRowMetadata ? row.rowIconNotifier : null;
  @override
  ValueNotifier<bool>? get hasDocument =>
      hasRowMetadata ? row.rowDocumentNotifier : null;
  @override
  String? getCellData({bool loadIfNotExist = true}) => _title;

  @override
  VoidCallback? addListener({
    required void Function(String?) onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
  }) =>
      () {};

  @override
  void removeListener({
    required VoidCallback onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
    VoidCallback? onRowMetaChanged,
  }) {}

  @override
  Future<void> saveCellData(
    String data, {
    bool debounce = false,
    void Function(FlowyError?)? onFinish,
  }) async {
    writes.add(data);
    onFinish?.call(null);
  }

  @override
  Future<void> dispose() async {}
}

class _CellContainer extends Fake implements CellContainerNotifier {}

class _CellFixture {
  _CellFixture(String icon, {bool primary = true, this.showNotes = false})
      : fields = _Fields(primary: primary) {
    row = RowInfo(
      fields: UnmodifiableListView([fields.field]),
      rowMeta: _row(icon),
    );
    cell = _CachedCell(row, fields.field);
    bloc = TextCellBloc(cellController: cell);
  }

  final _Fields fields;
  final bool showNotes;
  late final RowInfo row;
  late final _CachedCell cell;
  late final TextCellBloc bloc;
  final focus = FocusNode();
  final text = TextEditingController(text: _title);
  final compact = ValueNotifier(false);

  Widget build(String renderer) => BlocProvider<TextCellBloc>.value(
        value: bloc,
        child: Builder(
          builder: (context) => switch (renderer) {
            'desktop grid' => const DesktopGridRowIcon(),
            'mobile grid' => MobileGridTextCellSkin().build(
                context,
                _CellContainer(),
                compact,
                bloc,
                focus,
                text,
              ),
            _ => TextCardCell(
                databaseController: _Database(),
                cellContext: _cell,
                cellController: cell,
                showNotes: showNotes,
                style: TextCardCellStyle(
                  padding: const EdgeInsets.all(4),
                  textStyle: Theme.of(context).textTheme.bodyMedium!,
                  titleTextStyle: Theme.of(context).textTheme.bodyMedium!,
                ),
              ),
          },
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    // The production card owns its real bloc; only the cell IO boundary is
    // fake, including cleanup and any writes triggered while focus changes.
    await disposeVividIconPicker(tester);
    await tester.runAsync(bloc.close);
    row.dispose();
    text.dispose();
    focus.dispose();
    compact.dispose();
  }
}
