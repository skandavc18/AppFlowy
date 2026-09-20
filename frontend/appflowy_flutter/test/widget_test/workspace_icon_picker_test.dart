import 'dart:convert';

import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_color_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_uploader.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/rename_view_popover.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart'
    show AppFlowyPopover, FlowyButton, PopoverController;
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _workspaceId = 'workspace-icon-picker-test';
const _workspaceName = 'Workspace';
const _legacyEmoji = '🐻';
const _customIcon = EmojiIconData(
  FlowyIconType.custom,
  'https://workspace-icon.invalid/uploaded.png',
);

EmojiIconData _defaultIcon() => EmojiIconData.icon(
      IconsData('appflowy_default_collections', 'book', '4283665274'),
    );

EmojiIconData _vividIcon() => EmojiIconData.icon(
      IconsData(vividIconTestGroup, 'rocket', null),
    );

void main() {
  late bool previousRecentsEnabled;
  setUpAll(() async {
    previousRecentsEnabled = RecentIcons.enable;
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecentsEnabled);

  test('view rename offers the same complete icon tabs', () {
    final rename = RenameViewPopover(
      view: ViewPB(id: 'view'),
      name: 'View',
      emoji: EmojiIconData.none(),
      popoverController: PopoverController(),
    );
    expect(rename.tabs, kAllIconPickerTabs);
  });

  for (final invalidation in ['workspace changed', 'read-only', 'dismissed']) {
    testWidgets('workspace picker rejects selection after $invalidation',
        (tester) async {
      var owner = _workspaceId;
      var editable = true;
      var writes = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(vividIconTestApp(
        'paper',
        StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return WorkspaceIcon(
            workspaceIcon: _legacyEmoji,
            workspaceName: _workspaceName,
            documentId: owner,
            iconSize: 36,
            isEditable: editable,
            fontSize: 18,
            emojiSize: 24,
            borderRadius: 12,
            figmaLineHeight: 26,
            onSelected: (_) => writes++,
          );
        },),
      ),);
      await tester.pumpAndSettle();
      await _openPicker(tester);
      final staleSelection = tester
          .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
          .onSelectedEmoji!;
      if (invalidation == 'dismissed') {
        tester
            .widget<AppFlowyPopover>(find.descendant(
              of: find.byType(WorkspaceIcon),
              matching: find.byType(AppFlowyPopover),
            ).first,)
            .controller!
            .close();
      } else {
        rebuild(() {
          if (invalidation == 'workspace changed') {
            owner = 'another-workspace';
          } else {
            editable = false;
          }
        });
      }
      await tester.pumpAndSettle();
      staleSelection(_vividIcon().toSelectedResult());
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });
  }

  group('workspace string storage and synthetic roots', () {
    final choices = <String, EmojiIconData>{
      'legacy emoji': EmojiIconData.emoji(_legacyEmoji),
      'default icon': _defaultIcon(),
      'Vivid icon': _vividIcon(),
      'custom image': _customIcon,
      'cleared icon': EmojiIconData.none(),
    };

    for (final entry in choices.entries) {
      test('${entry.key} survives workspace and ViewPB round trips', () {
        final data = entry.value;
        final stored = data.toStorageString();
        _expectStoredIcon(stored, data);
        final root = workspaceRootFolderView(
          workspaceId: _workspaceId,
          icon: stored,
        );
        final restored = ViewPB.fromBuffer(root.writeToBuffer());
        expect(restored.id, _workspaceId);
        expect(restored.name, _workspaceName);
        expect(restored.parentViewId, isEmpty);
        expect(restored.isWorkspaceRootFolder, isTrue);
        expect(restored.icon.value, data.emoji);
        if (data.isNotEmpty) {
          expect(restored.icon.ty, data.type.toProto());
          expect(restored.icon.toEmojiIconData().toStorageString(), stored);
        }
      });

      test('${entry.key} normalizes without mutating or repeatedly copying',
          () {
        final original = ViewPB(
          id: _workspaceId,
          name: 'Old name',
          layout: ViewLayoutPB.Document,
          icon: ViewIconPB(ty: ViewIconTypePB.Emoji, value: '🌻'),
          extra: jsonEncode({
            'future': {'enabled': true},
          }),
          childViews: [ViewPB(id: 'child', parentViewId: _workspaceId)],
        );
        final originalBytes = original.writeToBuffer();
        final stored = entry.value.toStorageString();
        final normalized = original.asWorkspaceRootFolder(
          workspaceId: _workspaceId,
          icon: stored,
        );
        expect(original.writeToBuffer(), originalBytes);
        expect(normalized.isWorkspaceRootFolder, isTrue);
        expect(normalized.name, _workspaceName);
        expect(normalized.childViews.single.id, 'child');
        expect(decodeViewExtra(normalized.extra)['future'], {'enabled': true});
        expect(normalized.icon.value, entry.value.emoji);
        if (entry.value.isNotEmpty) {
          expect(normalized.icon.ty, entry.value.type.toProto());
        }
        expect(
          normalized.asWorkspaceRootFolder(
            workspaceId: _workspaceId,
            icon: stored,
          ),
          same(normalized),
        );
      });
    }

    test('omitted workspace icon preserves an already typed root', () {
      final root = workspaceRootFolderView(
        workspaceId: _workspaceId,
        icon: _customIcon.toStorageString(),
      );
      expect(
        root.asWorkspaceRootFolder(
          workspaceId: _workspaceId,
        ),
        same(root),
      );
      expect(root.icon.ty, ViewIconTypePB.Url);
    });

    test('workspace normalization leaves child and other workspace icons alone',
        () {
      for (final view in [
        ViewPB(id: 'another-workspace'),
        ViewPB(id: _workspaceId, parentViewId: 'parent'),
      ]) {
        expect(
          view.asWorkspaceRootFolder(
            workspaceId: _workspaceId,
            icon: _vividIcon().toStorageString(),
          ),
          same(view),
        );
      }
    });
  });

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance: legacy emoji renders and native selection saves',
        (tester) async {
      final saved = <String>[];
      await _pumpWorkspace(tester, appearance, onSaved: saved.add);
      expect(_renderedIcon(tester).emoji.type, FlowyIconType.emoji);
      expect(_renderedIcon(tester).emoji.emoji, _legacyEmoji);
      expect(_renderedIcon(tester).emojiSize, 24);
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.emoji);
      final emojiPicker = find.byType(FlowyEmojiPicker);
      await tester.enterText(
        find.descendant(of: emojiPicker, matching: find.byType(TextField)),
        'sunflower',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final sunflower = find.descendant(
        of: emojiPicker,
        matching: find.widgetWithText(FlowyButton, '🌻'),
      );
      expect(sunflower.hitTestable(), findsOneWidget);
      await tester.tap(sunflower);
      await tester.pumpAndSettle();
      expect(saved, ['🌻']);
      expect(_renderedIcon(tester).emoji.emoji, '🌻');
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.emoji);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets('$appearance: empty workspace retains its initial and defaults',
        (tester) async {
      await _pumpWorkspace(tester, appearance, initialIcon: '');
      expect(find.text('W'), findsOneWidget);
      expect(find.byType(RawEmojiIconWidget), findsNothing);
      expect(tester.getSize(find.byType(WorkspaceIcon)), const Size(36, 36));
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.defaultIcons);
      expect(
        tester.widget<FlowyIconPicker>(find.byType(FlowyIconPicker)).fixedPack,
        kAppFlowyDefaultIconPack,
      );
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets('$appearance: all tabs are visible and Vivid saves its type',
        (tester) async {
      final saved = <String>[];
      await _pumpWorkspace(tester, appearance, onSaved: saved.add);
      await _openPicker(tester);
      final picker = tester.widget<FlowyIconEmojiPicker>(
        find.byType(FlowyIconEmojiPicker),
      );
      expect(picker.tabs, kAllIconPickerTabs);
      expect(picker.documentId, _workspaceId);
      final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
      expect(tabs.tabs, [
        PickerTabType.emoji,
        PickerTabType.defaultIcons,
        PickerTabType.icon,
        PickerTabType.custom,
      ]);
      final bar = tester.getRect(find.byType(TabBar));
      for (final tab in tabs.tabs) {
        final label = find.text(tab.tr);
        expect(label.hitTestable(), findsOneWidget);
        final rect = tester.getRect(label);
        expect(rect.left, greaterThanOrEqualTo(bar.left));
        expect(rect.right, lessThanOrEqualTo(bar.right));
        await tester.tap(label);
        await tester.pumpAndSettle();
        _expectSelectedTab(tester, tab);
      }
      final uploader = tester.widget<IconUploader>(find.byType(IconUploader));
      expect(uploader.documentId, _workspaceId);
      expect(saved, isEmpty);
      await tester.tap(find.text(PickerTabType.icon.tr));
      await tester.pumpAndSettle();
      await tester.tap(vividIconStyleButton('Vivid'));
      await settleVividIconPictures(tester);
      await tester.tap(vividIconOption('rocket'));
      await settleVividIconPictures(tester);
      expect(saved, hasLength(1));
      _expectStoredIcon(saved.single, _vividIcon());
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      final rendered = _renderedIcon(tester);
      expect(rendered.emoji.type, FlowyIconType.icon);
      final svg = tester.widget<FlowySvg>(
        find.descendant(
          of: find.byType(WorkspaceIcon),
          matching: find.byType(FlowySvg),
        ),
      );
      expect(svg.blendMode, isNull);
      expect(svg.color, isNull);
      expect(
        svg.svgString,
        findLoadedIcon(vividIconTestGroup, 'rocket')!.content,
      );
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.icon);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets('$appearance: default selection retains its color and tab',
        (tester) async {
      final saved = <String>[];
      await _pumpWorkspace(tester, appearance, onSaved: saved.add);
      await _openPicker(tester);
      await tester.tap(find.text(PickerTabType.defaultIcons.tr));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'book');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final bookSvg = find.byWidgetPredicate(
        (widget) =>
            widget is FlowySvg &&
            widget.svgString ==
                findLoadedIcon('appflowy_default_collections', 'book')!.content,
      );
      await tester.tap(
        find.ancestor(of: bookSvg, matching: find.byType(FlowyButton)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(IconColorPicker), findsOneWidget);
      final colorTargets = find.descendant(
        of: find.byType(IconColorPicker),
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTap != null,
        ),
      );
      await tester.tap(colorTargets.first);
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      final restored = EmojiIconData.fromStorageString(saved.single);
      expect(restored.type, FlowyIconType.icon);
      final icon = IconsData.fromJson(jsonDecode(restored.emoji));
      expect(icon.groupName, 'appflowy_default_collections');
      expect(icon.iconName, 'book');
      expect(icon.color, isNotNull);
      expect(_renderedIcon(tester).emoji.emoji, restored.emoji);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.defaultIcons);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets(
        '$appearance: fake upload completion saves a tagged custom icon',
        (tester) async {
      final saved = <String>[];
      final upload = _FakeIconUpload();
      await _pumpWorkspace(
        tester,
        appearance,
        onSaved: saved.add,
        echoSelection: false,
      );
      await _openPicker(tester);
      await tester.tap(find.text(PickerTabType.custom.tr));
      await tester.pumpAndSettle();
      _expectSelectedTab(tester, PickerTabType.custom);
      upload.complete(tester.widget<IconUploader>(find.byType(IconUploader)));
      await tester.pumpAndSettle();
      expect(upload.owners, [_workspaceId]);
      expect(saved, hasLength(1));
      _expectStoredIcon(saved.single, _customIcon);
      expect(
        EmojiIconData.fromStorageString(saved.single).toPickerTabType(),
        PickerTabType.custom,
      );
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets('$appearance: Remove saves legacy empty and restores fallback',
        (tester) async {
      final saved = <String>[];
      await _pumpWorkspace(
        tester,
        appearance,
        initialIcon: _vividIcon().toStorageString(),
        onSaved: saved.add,
      );
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.icon);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(saved, ['']);
      expect(EmojiIconData.fromStorageString(saved.single).isEmpty, isTrue);
      expect(find.byType(RawEmojiIconWidget), findsNothing);
      expect(find.text('W'), findsOneWidget);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      await _openPicker(tester);
      _expectSelectedTab(tester, PickerTabType.defaultIcons);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets(
        '$appearance: read-only icons render without picker interaction',
        (tester) async {
      for (final data in [
        EmojiIconData.none(),
        EmojiIconData.emoji(_legacyEmoji),
        _defaultIcon(),
        _vividIcon(),
      ]) {
        final saved = <String>[];
        await _pumpWorkspace(
          tester,
          appearance,
          initialIcon: data.toStorageString(),
          isEditable: false,
          onSaved: saved.add,
        );
        expect(find.byType(AppFlowyPopover), findsNothing);
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        if (data.isEmpty) {
          expect(find.text('W'), findsOneWidget);
        } else {
          expect(_renderedIcon(tester).emoji.type, data.type);
          expect(_renderedIcon(tester).emoji.emoji, data.emoji);
        }
        if (data.type == FlowyIconType.icon && data.isNotEmpty) {
          expect(find.byType(IconWidget), findsOneWidget);
          expect(find.byType(FlowySvg), findsOneWidget);
        }
        final frame = tester.widget<Container>(
          find.descendant(
            of: find.byType(WorkspaceIcon),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.constraints ==
                      const BoxConstraints.tightFor(width: 36, height: 36),
            ),
          ),
        );
        final border = (frame.decoration! as BoxDecoration).border! as Border;
        expect(
          border.top.color,
          EditorSurfaceStyle.embedBorder(
            tester.element(find.byType(WorkspaceIcon)),
          ),
        );
        await tester.tap(find.byType(WorkspaceIcon));
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(saved, isEmpty);
        expect(tester.takeException(), isNull);
        await disposeVividIconPicker(tester);
      }
    });
  }
}

void _expectStoredIcon(String stored, EmojiIconData expected) {
  if (expected.isEmpty) {
    expect(stored, isEmpty);
  } else if (expected.type == FlowyIconType.emoji) {
    expect(stored, expected.emoji);
  } else {
    expect(jsonDecode(stored), {
      'appflowy_icon': 1,
      'type': expected.type.name,
      'value': expected.emoji,
    });
  }
  final restored = EmojiIconData.fromStorageString(stored);
  expect(restored.type, expected.type);
  expect(restored.emoji, expected.emoji);
}

RawEmojiIconWidget _renderedIcon(WidgetTester tester) =>
    tester.widget<RawEmojiIconWidget>(
      find.descendant(
        of: find.byType(WorkspaceIcon),
        matching: find.byType(RawEmojiIconWidget),
      ),
    );

void _expectSelectedTab(WidgetTester tester, PickerTabType expected) {
  final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
  expect(tabs.tabs[tabs.controller.index], expected);
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byType(WorkspaceIcon));
  await tester.pumpAndSettle();
  expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
  final surface = tester.widget<Container>(
    find
        .ancestor(
          of: find.byType(FlowyIconEmojiPicker),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is ShapeDecoration,
          ),
        )
        .first,
  );
  final context = tester.element(find.byType(FlowyIconEmojiPicker));
  final color = (surface.decoration! as ShapeDecoration).color;
  expect(color, Theme.of(context).cardColor);
  if (PaperTheme.isEnabled(context)) {
    expect(color, isNot(Colors.white));
  }
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  String appearance, {
  String initialIcon = _legacyEmoji,
  bool isEditable = true,
  bool echoSelection = true,
  ValueChanged<String>? onSaved,
}) async {
  await tester.pumpWidget(
    vividIconTestApp(
      appearance,
      _WorkspaceIconFixture(
        initialIcon: initialIcon,
        isEditable: isEditable,
        echoSelection: echoSelection,
        onSaved: onSaved,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    PaperTheme.isEnabled(tester.element(find.byType(WorkspaceIcon))),
    appearance == 'paper',
  );
}

class _WorkspaceIconFixture extends StatefulWidget {
  const _WorkspaceIconFixture({
    required this.initialIcon,
    required this.isEditable,
    required this.echoSelection,
    required this.onSaved,
  });

  final String initialIcon;
  final bool isEditable;
  final bool echoSelection;
  final ValueChanged<String>? onSaved;

  @override
  State<_WorkspaceIconFixture> createState() => _WorkspaceIconFixtureState();
}

class _WorkspaceIconFixtureState extends State<_WorkspaceIconFixture> {
  late String stored = widget.initialIcon;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: WorkspaceIcon(
            workspaceIcon: stored,
            workspaceName: _workspaceName,
            documentId: _workspaceId,
            iconSize: 36,
            emojiSize: 24,
            fontSize: 18,
            figmaLineHeight: 26,
            borderRadius: 12,
            isEditable: widget.isEditable,
            onSelected: (result) {
              // The fixture uses the same string-storage boundary as every
              // production workspace callback, not the lossy result.emoji.
              final value = result.toStorageString();
              widget.onSaved?.call(value);
              if (widget.echoSelection) {
                setState(() => stored = value);
              }
            },
          ),
        ),
      );
}

/// Completes the existing uploader callback without file, network or native
/// backend access. The custom test defers the parent's refreshed workspace,
/// because the shared custom-image renderer directly reads the profile via
/// FFI and has no injectable backend. Its transport is outside this fixture.
class _FakeIconUpload {
  final owners = <String>[];

  void complete(IconUploader uploader) {
    owners.add(uploader.documentId);
    uploader.onUrl(_customIcon.emoji);
  }
}
