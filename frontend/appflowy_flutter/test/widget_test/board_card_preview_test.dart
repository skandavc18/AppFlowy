import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/database/card/mobile_card_content.dart';
import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/board/presentation/toolbar/card_preview_button.dart';
import 'package:appflowy/plugins/database/widgets/card/card.dart';
import 'package:appflowy/plugins/database/widgets/card/card_bloc.dart';
import 'package:appflowy/plugins/database/widgets/card/container/card_container.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/desktop_board_card_cell_style.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/mobile_board_card_cell_style.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_board/appflowy_board.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

// Production composition, covers, menu, and real read-only document rendering.
// Non-empty synthetic pages enter the production cache through DocumentService's
// read boundary; no Rust, network, authentication or real workspace is used.
// Populated pages also pass through RowCardContainer's actual IntrinsicHeight.
// The state-retention fixture below is deliberately a LAYOUT test, not proof of
// RowCard's private _CardContentCell/GlobalKey or TextCardCell persistence.
const _appearances = ['light', 'dark', 'paper'];
const _titleField = ValueKey('fixture-primary-editor');
const _titleFooter = ValueKey('row-card-title-footer');
const _status = ValueKey('fixture-status');
const _owner = ValueKey('fixture-owner');
const _sheet = ValueKey('board-card-preview-sheet');
const _shortTitle = 'Plan a quieter workspace';
const _longTitle =
    'A much longer editable card title that needs every line to stay visible '
    'when the text grows, including these final words';
const _coverColor = Color(0xFF368F72);
const _localColor = Color(0xFF2C8973);
const _footColor = Color(0xCC000000);
const _assetId = '3';
const _assetPath = 'assets/images/built_in_cover_images/m_cover_image_3.png';
const _viewId = 'synthetic-board-preview';

const _labels = {
  CardPreviewMode.pageAndTitle: LocaleKeys.gallery_facePage,
  CardPreviewMode.cover: LocaleKeys.gallery_faceCover,
  CardPreviewMode.pageContent: LocaleKeys.gallery_faceContent,
  CardPreviewMode.none: LocaleKeys.gallery_faceNone,
  CardPreviewMode.portrait: LocaleKeys.gallery_facePortrait,
  CardPreviewMode.titleAndProperties: LocaleKeys.cardPreview_titleAndProperties,
};
const _icons = {
  CardPreviewMode.pageAndTitle: Icons.sticky_note_2_rounded,
  CardPreviewMode.cover: Icons.image_rounded,
  CardPreviewMode.pageContent: Icons.article_rounded,
  CardPreviewMode.none: Icons.notes_rounded,
  CardPreviewMode.portrait: Icons.crop_portrait_rounded,
  CardPreviewMode.titleAndProperties: Icons.view_list_rounded,
};
const _faces = <CardPreviewMode, ({bool page, bool cover, bool title})>{
  CardPreviewMode.pageAndTitle: (page: true, cover: false, title: true),
  CardPreviewMode.cover: (page: false, cover: true, title: true),
  CardPreviewMode.pageContent: (page: true, cover: false, title: false),
  CardPreviewMode.none: (page: false, cover: false, title: true),
  CardPreviewMode.portrait: (page: false, cover: true, title: true),
  CardPreviewMode.titleAndProperties: (page: false, cover: false, title: true),
};

late Directory _imageDirectory;
late File _localImage;
late AppearanceSettingsCubit _appearanceCubit;
late DocumentAppearanceCubit _documentAppearanceCubit;
final _syntheticDocumentIds = <String>{};
int _nextDocumentId = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    getIt.pushNewScope();
    final preferences = DartKeyValue();
    getIt.registerSingleton<KeyValueStorage>(preferences);
    await preferences.get('synthetic-board-preview-fixture');
    _appearanceCubit = AppearanceSettingsCubit(
      AppearanceSettingsPB(
        font: 'DM Sans',
        locale: LocaleSettingsPB(languageCode: 'en', countryCode: 'US'),
      ),
      DateTimeSettingsPB(),
      AppTheme.fallback,
    );
    _documentAppearanceCubit = DocumentAppearanceCubit();
    await _appearanceCubit.readTextScaleFactor();
    await _appearanceCubit.readKineticScrolling();
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await AppFlowyEditorLocalizations.load(const Locale('en', 'US'));
    await GoogleFonts.pendingFonts([GoogleFonts.robotoMono()]);
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    // Load the RESOLVED theme families, not just the requested family: desktop
    // appearance can substitute a platform/fallback family. No Ahem goldens.
    final families = _appearances
        .map(
          (appearance) => _theme(appearance).textTheme.bodyMedium!.fontFamily!,
        )
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    _imageDirectory =
        Directory.systemTemp.createTempSync('board-card-previews-');
    _localImage = File('${_imageDirectory.path}/local cover # 100%.png');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 48, 32),
      Paint()..color = _localColor,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(48, 32);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      _localImage.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  });

  tearDown(() {
    // Every populated-page test unmounts first, so invalidation cannot trigger
    // a backend fetch from a still-mounted preview. Never clear unrelated IDs.
    for (final id in _syntheticDocumentIds) {
      RowPageDocument.discard(id);
      RowPageText.forget(id);
      expect(RowPageDocument.knows(id), isFalse);
      expect(RowPageText.peek(id), isNull);
    }
    _syntheticDocumentIds.clear();
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _imageDirectory.deleteSync(recursive: true);
    await _appearanceCubit.close();
    await _documentAppearanceCubit.close();
    await getIt.popScope();
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });

  group('six production card faces', () {
    for (final mode in CardPreviewMode.values) {
      testWidgets('${mode.id}: only the intended title and property controls',
          (tester) async {
        final row = _row(cover: _cover('color'));
        final before = row.writeToBuffer();
        await _pump(tester, _layout(mode, row: row));

        _expectFace(tester, mode);
        final face = tester.getRect(_face(mode));
        expect(
          tester.widget<ClipRRect>(_face(mode)).borderRadius,
          BorderRadius.circular(4),
        );
        if (_faces[mode]!.title) {
          final title = tester.getRect(find.byKey(_titleField));
          expect(title.left - face.left, 4);
          expect(face.right - title.right, 4);
          if (_faces[mode]!.page) {
            expect(
              tester.getBottomLeft(find.byType(CardPagePreview)).dy,
              lessThanOrEqualTo(title.top),
            );
          }
        } else {
          expect(face, tester.getRect(find.byType(CardPagePreview)));
          expect(tester.getSize(find.byKey(_titleFooter)).height, 0);
        }
        if (_faces[mode]!.page) {
          expect(
            find.text(LocaleKeys.cardPreview_pageEmpty.tr()),
            findsOneWidget,
          );
        }
        expect(row.writeToBuffer(), orderedEquals(before));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('default style and missing setting still render cover',
        (tester) async {
      const style = RowCardStyleConfiguration(cellStyleMap: {});
      expect(style.preview, CardPreviewMode.cover);
      expect(
        style.showProperties,
        isTrue,
        reason: 'Calendar keeps the general card-style default',
      );
      expect(CardPreviewSetting.fromExtra('').mode, style.preview);
      final layout = RowCardPreviewLayout(
        rowMeta: _row(cover: _cover('color')),
        mode: style.preview,
        titleBuilder: (context, foreground) => _DraftTitle(
          initialText: _shortTitle,
          foreground: foreground,
        ),
        properties: const [
          _Property(key: _status, label: 'Status: Ready'),
          _Property(key: _owner, label: 'Owner: Ada'),
        ],
      );
      expect(layout.showProperties, isFalse);
      expect(layout.isEditing, isFalse);
      await _pump(tester, layout);
      _expectFace(tester, CardPreviewMode.cover);
      expect(tester.getSize(find.byType(CardCover)).height, 100);
      expect(tester.takeException(), isNull);
    });

    for (final entry in {
      'cover': CardPreviewMode.cover,
      'page': CardPreviewMode.pageContent,
      'none': CardPreviewMode.none,
    }.entries) {
      testWidgets(
          'legacy ${entry.key} retains its ID with the clean board face',
          (tester) async {
        final setting = CardPreviewSetting.fromExtra(
          '{"appflowy_card_preview":{"version":1,"mode":"${entry.key}"}}',
        );
        await _pump(
          tester,
          _layout(setting.mode, row: _row(cover: _cover('color'))),
        );
        _expectFace(tester, entry.value);
        expect(setting.mode.id, entry.key);
        _expectNoProperties();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('large text in actual preview layout', () {
    for (final appearance in _appearances) {
      for (final compact in [false, true]) {
        for (final mode in CardPreviewMode.values) {
          testWidgets(
            '$appearance / ${compact ? 176 : 232}px / ${mode.id}: '
            '2x visible long title stays inside a growing card',
            (tester) async {
              final width = compact ? 176.0 : 232.0;
              await _pump(
                tester,
                _layout(
                  mode,
                  row: _row(cover: _cover('color')),
                  compact: compact,
                  title: _longTitle,
                  isEditing: true,
                ),
                appearance: appearance,
                width: width,
                textScale: 2,
              );
              _expectFace(tester, mode, isEditing: true);
              final face = tester.getRect(_face(mode));
              final field = tester.widget<TextField>(find.byKey(_titleField));
              final title = tester.getRect(find.byKey(_titleField));
              final editable = tester.state<EditableTextState>(
                find.descendant(
                  of: find.byKey(_titleField),
                  matching: find.byType(EditableText),
                ),
              );
              expect(face.width, width);
              expect(field.controller!.text, _longTitle);
              expect(field.maxLines, isNull);
              expect(title.height, greaterThan(100));
              _expectContains(face, title);
              final lastCaret = editable.renderEditable.getLocalRectForCaret(
                const TextPosition(offset: _longTitle.length),
              );
              expect(
                lastCaret.bottom,
                lessThanOrEqualTo(editable.renderEditable.size.height + 1),
              );
              expect(editable.renderEditable.maxScrollExtent, 0);
              final context = tester.element(find.byKey(_titleField));
              expect(MediaQuery.textScalerOf(context).scale(14), 28);
              expect(PaperTheme.isEnabled(context), appearance == 'paper');
              if (mode == CardPreviewMode.portrait) {
                expect(face.height, greaterThan(compact ? 164 : 220));
                _expectPortraitCover(tester);
              }
              if (mode == CardPreviewMode.cover) {
                expect(
                  tester.getSize(find.byType(CardCover)).height,
                  compact ? 50 : 100,
                );
              }
              if (mode != CardPreviewMode.titleAndProperties) {
                _expectNoProperties();
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('title and row data use provided native controls', () {
    for (final appearance in _appearances) {
      for (final compact in [false, true]) {
        testWidgets(
            '$appearance / $compact: empty properties add no artificial gap',
            (tester) async {
          await _pump(
            tester,
            _layout(
              CardPreviewMode.titleAndProperties,
              row: _row(cover: _cover('color')),
              compact: compact,
              title: _longTitle,
              properties: const [],
            ),
            appearance: appearance,
            width: compact ? 176 : 232,
            textScale: 2,
          );
          final layout = tester.widget<RowCardPreviewLayout>(
            find.byType(RowCardPreviewLayout),
          );
          final face =
              tester.getRect(_face(CardPreviewMode.titleAndProperties));
          final title = tester.getRect(find.byKey(_titleField));
          expect(layout.showProperties, isFalse);
          expect(layout.properties, isEmpty);
          expect(
            face.height,
            closeTo(title.height + layout.padding.vertical, 0.01),
          );
          expect(title.top - face.top, closeTo(layout.padding.top, 0.01));
          expect(
            face.bottom - title.bottom,
            closeTo(layout.padding.bottom, 0.01),
          );
          expect(
            tester.widget<TextField>(find.byKey(_titleField)).readOnly,
            isFalse,
          );
          expect(find.byType(CardPagePreview), findsNothing);
          expect(find.byType(CardCover), findsNothing);
          _expectContains(face, title);
          _expectNoProperties();
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets(
          '$appearance: narrow 2x row data keeps button and checkbox '
          'tap and keyboard behavior', (tester) async {
        final statusFocus = FocusNode();
        final ownerFocus = FocusNode();
        final checkboxFocus = FocusNode();
        final checked = ValueNotifier(false);
        const checkboxKey = ValueKey('fixture-row-data-checkbox');
        final presses = <String>[];
        final row = _row(cover: _cover('color'));
        final beforeRow = row.writeToBuffer();
        var cardTaps = 0;
        try {
          await _pump(
            tester,
            _cardHost(
              _layout(
                CardPreviewMode.titleAndProperties,
                row: row,
                compact: true,
                title: 'Editable title',
                properties: [
                  _Property(
                    key: _status,
                    label: 'Status: Ready',
                    focusNode: statusFocus,
                    onPressed: () => presses.add('status'),
                  ),
                  _Property(
                    key: _owner,
                    label: 'Owner: Ada',
                    focusNode: ownerFocus,
                    onPressed: () => presses.add('owner'),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: checked,
                    builder: (context, value, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: Checkbox(
                        key: checkboxKey,
                        focusNode: checkboxFocus,
                        value: value,
                        onChanged: (value) => checked.value = value!,
                      ),
                    ),
                  ),
                ],
              ),
              onTap: () => cardTaps++,
            ),
            appearance: appearance,
            width: 176,
            textScale: 2,
          );
          _expectFace(tester, CardPreviewMode.titleAndProperties);
          expect(find.byType(Checkbox), findsOneWidget);
          final checkbox = find.byKey(checkboxKey);
          _expectContains(
            tester.getRect(_face(CardPreviewMode.titleAndProperties)),
            tester.getRect(checkbox),
          );
          expect(find.byKey(_status).hitTestable(), findsOneWidget);
          expect(find.byKey(_owner).hitTestable(), findsOneWidget);
          expect(checkbox.hitTestable(), findsOneWidget);

          await tester.tap(find.byKey(_status));
          await tester.pumpAndSettle();
          expect(presses, ['status']);
          statusFocus.requestFocus();
          await tester.pumpAndSettle();
          expect(statusFocus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(ownerFocus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(presses, ['status', 'owner']);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(checkboxFocus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(checked.value, isTrue);
          expect(tester.widget<Checkbox>(checkbox).value, isTrue);
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          expect(checked.value, isFalse);
          expect(tester.widget<Checkbox>(checkbox).value, isFalse);
          expect(
            cardTaps,
            0,
            reason: 'native controls own their card gestures',
          );
          expect(
            tester.widget<TextField>(find.byKey(_titleField)).controller!.text,
            'Editable title',
          );
          expect(row.writeToBuffer(), orderedEquals(beforeRow));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          statusFocus.dispose();
          ownerFocus.dispose();
          checkboxFocus.dispose();
          checked.dispose();
        }
      });
    }
  });

  group('portrait minimums, padding, radius and explicit tint', () {
    for (final appearance in _appearances) {
      for (final compact in [false, true]) {
        testWidgets(
            '$appearance / ${compact ? 176 : 232}px: short title keeps minimum',
            (tester) async {
          const tint = Color(0xFF748D7C);
          const padding = EdgeInsets.fromLTRB(9, 7, 11, 13);
          final width = compact ? 176.0 : 232.0;
          for (final cover in [null, _cover('color')]) {
            await _pump(
              tester,
              _layout(
                CardPreviewMode.portrait,
                row: _row(cover: cover),
                title: 'A title',
                compact: compact,
                tint: tint,
                padding: padding,
                radius: 17,
              ),
              appearance: appearance,
              width: width,
            );
            final face = tester.getRect(_face(CardPreviewMode.portrait));
            final title = tester.getRect(find.byKey(_titleField));
            expect(face.size, Size(width, compact ? 164 : 220));
            expect(title.left - face.left, padding.left);
            expect(face.right - title.right, padding.right);
            expect(face.bottom - title.bottom, closeTo(padding.bottom, 0.01));
            expect(_portraitBackground(tester).color, tint);
            expect(
              tester
                  .widget<ClipRRect>(_face(CardPreviewMode.portrait))
                  .borderRadius,
              BorderRadius.circular(17),
            );
            if (cover != null) {
              _expectPortraitCover(tester);
            } else {
              expect(find.byType(CardCover), findsNothing);
              expect(
                find.byKey(const ValueKey('row-card-cover-scrim')),
                findsNothing,
              );
            }
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  });

  group('stored cover renderers, not generated stand-ins', () {
    for (final mode in [CardPreviewMode.cover, CardPreviewMode.portrait]) {
      for (final kind in [
        'color',
        'tint',
        'gradient',
        'asset',
        'local path',
        'local URI',
      ]) {
        testWidgets('${mode.id}: renders actual $kind cover', (tester) async {
          final cover = _cover(kind);
          await _pump(tester, _layout(mode, row: _row(cover: cover)));
          final coverFinder = find.byType(CardCover);
          expect(coverFinder, findsOneWidget);
          final widget = tester.widget<CardCover>(coverFinder);
          expect(widget.cover, same(cover));
          expect(
            widget.height,
            mode == CardPreviewMode.portrait ? double.infinity : isNull,
          );
          expect(
            tester.getSize(coverFinder).height,
            mode == CardPreviewMode.portrait ? 220 : 100,
          );
          expect(find.byType(CardPagePreview), findsNothing);
          expect(find.byType(RowPagePreview), findsNothing);

          if (kind == 'color' || kind == 'tint') {
            final expected = kind == 'color'
                ? _coverColor
                : FlowyTint.tint5.color(tester.element(coverFinder));
            expect(
              find.descendant(
                of: coverFinder,
                matching: find.byWidgetPredicate(
                  (widget) => widget is ColoredBox && widget.color == expected,
                ),
              ),
              findsOneWidget,
            );
            expect(find.byType(Image), findsNothing);
          } else if (kind == 'gradient') {
            final gradient = tester.widget<DecoratedBox>(
              find.descendant(
                of: coverFinder,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DecoratedBox &&
                      widget.decoration is BoxDecoration &&
                      (widget.decoration as BoxDecoration).gradient != null,
                ),
              ),
            );
            expect(
              (gradient.decoration as BoxDecoration).gradient,
              FlowyGradientColor.gradient3.linear,
            );
          } else {
            final image = tester.widget<Image>(find.byType(Image));
            expect(image.fit, BoxFit.cover);
            if (kind == 'asset') {
              expect(find.byType(AFImage), findsNothing);
              expect((image.image as AssetImage).assetName, _assetPath);
              expect(
                PageStyleCoverImageType.builtInImagePath(_assetId),
                _assetPath,
              );
            } else {
              final afImage = tester.widget<AFImage>(find.byType(AFImage));
              expect(afImage.uploadType, FileUploadTypePB.LocalFile);
              expect(afImage.url, cover.data);
              expect((image.image as FileImage).file.uri, _localImage.uri);
            }
            await _decodeImages(tester);
            final raw = tester.widget<RawImage>(find.byType(RawImage));
            expect(
              raw.image,
              isNotNull,
              reason: 'a real decoded image must paint',
            );
            expect(raw.image!.width, greaterThan(1));
            expect(raw.image!.height, greaterThan(1));
            if (kind != 'asset') {
              expect(raw.image!.width, 48);
              expect(raw.image!.height, 32);
              final pixels = await tester.runAsync(
                () => raw.image!.toByteData(),
              );
              expect(pixels!.buffer.asUint8List().take(4), [44, 137, 115, 255]);
            }
          }
          if (mode == CardPreviewMode.portrait) {
            _expectPortraitCover(tester);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    test('canRender requires data and a profile only for cloud file covers',
        () {
      expect(CardCover.canRender(null, null), isFalse);
      for (final type in CoverTypePB.values) {
        expect(CardCover.canRender(RowCoverPB(coverType: type), null), isFalse);
      }
      final cloud = _unavailableCover('cloud without profile')!;
      expect(CardCover.canRender(cloud, null), isFalse);
      expect(CardCover.canRender(cloud, UserProfilePB()), isTrue);
      for (final kind in ['color', 'tint', 'gradient', 'asset', 'local path']) {
        expect(CardCover.canRender(_cover(kind), null), isTrue, reason: kind);
      }
    });
  });

  group('missing covers stay honest and themed', () {
    for (final appearance in _appearances) {
      for (final mode in [CardPreviewMode.cover, CardPreviewMode.portrait]) {
        for (final missing in [
          'absent',
          'present but empty',
          'cloud without profile',
        ]) {
          testWidgets('$appearance / ${mode.id}: $missing', (tester) async {
            final row = _row(cover: _unavailableCover(missing));
            final before = row.writeToBuffer();
            expect(row.hasCover(), missing != 'absent');
            await _pump(
              tester,
              _layout(mode, row: row),
              appearance: appearance,
            );

            final context = tester.element(find.byKey(_titleField));
            final palette = tableViewPaletteOf(context);
            expect(
              tester.widget<_DraftTitle>(find.byType(_DraftTitle)).foreground,
              isNull,
            );
            expect(
              tester.widget<TextField>(find.byKey(_titleField)).style!.color,
              palette.textPrimary,
            );
            expect(find.byType(AFImage), findsNothing);
            expect(find.byType(Image), findsNothing);
            expect(find.byType(CardPagePreview), findsNothing);
            expect(find.byType(RowPagePreview), findsNothing);
            expect(
              find.byKey(const ValueKey('row-card-cover-scrim')),
              findsNothing,
            );
            expect(
              find.descendant(
                of: _face(mode),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DecoratedBox &&
                      widget.decoration is BoxDecoration &&
                      (widget.decoration as BoxDecoration).gradient != null,
                ),
              ),
              findsNothing,
              reason: 'no fabricated gradient may replace a missing cover',
            );
            if (mode == CardPreviewMode.cover) {
              expect(tester.getSize(find.byType(CardCover)).height, 0);
              final title = tester.getRect(find.byKey(_titleField));
              expect(tester.getSize(_face(mode)).height, title.height + 8);
            } else {
              expect(find.byType(CardCover), findsNothing);
              expect(find.byKey(_status), findsNothing);
              expect(tester.getSize(_face(mode)).height, 220);
              expect(_portraitBackground(tester).color, palette.sunken);
              expect(Theme.of(context).hintColor, _theme(appearance).hintColor);
            }
            _expectNoProperties();
            expect(PaperTheme.isEnabled(context), appearance == 'paper');
            if (appearance == 'paper') {
              expect(palette.sunken, isNot(Colors.white));
              expect(palette.sunken.r, greaterThan(palette.sunken.b));
            }
            expect(row.writeToBuffer(), orderedEquals(before));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('page and cover are independent', () {
    for (final mode in [
      CardPreviewMode.cover,
      CardPreviewMode.none,
      CardPreviewMode.portrait,
      CardPreviewMode.titleAndProperties,
    ]) {
      testWidgets('${mode.id}: never consults the row document',
          (tester) async {
        final row = _ObservedRow(_row(cover: _cover('color')));
        await _pump(tester, _layout(mode, row: row));
        expect(row.documentReads, 0);
        expect(find.byType(CardPagePreview), findsNothing);
        expect(find.byType(RowPagePreview), findsNothing);
        expect(find.byType(RowPageTextView), findsNothing);
        if (mode == CardPreviewMode.titleAndProperties) {
          expect(row.coverReads, 0);
          expect(row.coverPresenceReads, 0);
          expect(find.byType(CardCover), findsNothing);
          expect(find.byType(AFImage), findsNothing);
          expect(find.byType(Image), findsNothing);
          _expectRowDataProperties(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
    for (final mode in [
      CardPreviewMode.pageAndTitle,
      CardPreviewMode.pageContent,
    ]) {
      testWidgets(
          '${mode.id}: reads the page identity without inspecting cover',
          (tester) async {
        final row = _ObservedRow(_row(cover: _cover('asset')));
        await _pump(tester, _layout(mode, row: row));
        expect(row.documentReads, greaterThan(0));
        expect(row.coverReads, 0);
        expect(row.coverPresenceReads, 0);
        expect(find.byType(CardCover), findsNothing);
        expect(find.byType(Image), findsNothing);
        final preview =
            tester.widget<RowPagePreview>(find.byType(RowPagePreview));
        expect(preview.documentId, isEmpty);
        expect(preview.interactive, isFalse);
        expect(
          find.text(LocaleKeys.cardPreview_pageEmpty.tr()),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    for (final compact in [false, true]) {
      testWidgets(
          '${compact ? 'compact' : 'regular'}: both page faces reserve the viewport',
          (tester) async {
        final height = compact ? 144.0 : 196.0;
        await _pump(
          tester,
          _layout(CardPreviewMode.pageAndTitle, row: _row(), compact: compact),
        );
        final page =
            tester.widget<CardPagePreview>(find.byType(CardPagePreview));
        final preview =
            tester.widget<RowPagePreview>(find.byType(RowPagePreview));
        expect(page.height, height);
        expect(preview.height, height);
        expect(preview.scale, compact ? 0.52 : 0.58);
        expect(tester.getSize(find.byType(RowPagePreview)).height, height);
        final tallHeight = tester.getSize(find.byType(CardPagePreview)).height;
        expect(tallHeight, height + (compact ? 13 : 16));
        final withTitle = tester.getSize(_face(CardPreviewMode.pageAndTitle));

        await _pump(
          tester,
          _layout(CardPreviewMode.pageContent, row: _row(), compact: compact),
        );
        final content =
            tester.widget<CardPagePreview>(find.byType(CardPagePreview));
        final legacy =
            tester.widget<RowPagePreview>(find.byType(RowPagePreview));
        expect(content.height, height);
        expect(legacy.height, height);
        expect(legacy.scale, compact ? 0.52 : 0.58);
        expect(tester.getSize(find.byType(RowPagePreview)).height, height);
        expect(
          tester.getSize(find.byType(CardPagePreview)).height,
          tallHeight,
        );
        expect(
          tester.getSize(_face(CardPreviewMode.pageContent)).height,
          tallHeight,
        );
        expect(withTitle.height, greaterThan(tallHeight));
        expect(tester.getSize(find.byKey(_titleFooter)).height, 0);
        expect(find.byKey(_titleField), findsNothing);
        _expectNoProperties();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('idle page-only footer and explicit title editing', () {
    for (final appearance in _appearances) {
      for (final compact in [false, true]) {
        testWidgets(
            '$appearance / $compact: hidden means no height, hits, '
            'semantics or focus, even with properties requested',
            (tester) async {
          final semantics = tester.ensureSemantics();
          final editing = ValueNotifier(false);
          final titleKey = GlobalKey<_DraftTitleState>();
          final nextCard = FocusNode();
          var cardTaps = 0;
          try {
            await _pump(
              tester,
              Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: editing,
                    builder: (context, value, _) => _cardHost(
                      _layout(
                        CardPreviewMode.pageContent,
                        row: _row(),
                        compact: compact,
                        title: _longTitle,
                        titleKey: titleKey,
                        isEditing: value,
                        showProperties: true,
                      ),
                      onTap: () => cardTaps++,
                    ),
                  ),
                  TextButton(
                    focusNode: nextCard,
                    onPressed: () {},
                    child: const Text('Next card'),
                  ),
                ],
              ),
              appearance: appearance,
              width: compact ? 176 : 232,
              textScale: 2,
            );
            final state = titleKey.currentState!;
            final controller = state.controller;
            final focus = state.focus;
            final idleBounds =
                tester.getRect(_face(CardPreviewMode.pageContent));
            final hiddenTitle = find.byKey(_titleField, skipOffstage: false);
            _expectFace(tester, CardPreviewMode.pageContent);
            expect(idleBounds.height, compact ? 157 : 212);
            expect(
              tester.widget<Offstage>(find.byKey(_titleFooter)).offstage,
              isTrue,
            );
            expect(tester.getSize(find.byKey(_titleFooter)).height, 0);
            expect(hiddenTitle.hitTestable(), findsNothing);
            expect(TickerMode.of(state.context), isFalse);
            expect(focus.canRequestFocus, isFalse);
            expect(_semanticsValues(tester), isNot(contains(_longTitle)));
            expect(
              find.bySemanticsLabel(RegExp('Status: Ready|Owner: Ada')),
              findsNothing,
            );

            focus.requestFocus();
            await tester.pump();
            await tester.pump();
            expect(focus.hasFocus, isFalse);
            await tester
                .tapAt(Offset(idleBounds.center.dx, idleBounds.bottom - 2));
            await tester.pump();
            expect(cardTaps, 1);
            expect(focus.hasFocus, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.pump();
            expect(
              nextCard.hasFocus,
              isTrue,
              reason: 'keyboard traversal must skip the retained title',
            );

            // Revealing the existing editor is an explicit host action, never a
            // side effect of choosing Page preview or tapping its document.
            editing.value = true;
            await tester.pump();
            await tester.pump();
            expect(titleKey.currentState, same(state));
            expect(state.controller, same(controller));
            expect(state.focus, same(focus));
            expect(TickerMode.of(state.context), isTrue);
            expect(focus.canRequestFocus, isTrue);
            expect(
              find.byKey(_titleField).hitTestable(at: Alignment.topCenter),
              findsOneWidget,
            );
            expect(_semanticsValues(tester), contains(_longTitle));
            _expectFace(tester, CardPreviewMode.pageContent, isEditing: true);
            _expectNoProperties();
            await tester.showKeyboard(find.byKey(_titleField));
            const draft = TextEditingValue(
              text: 'Keep this unsaved title draft',
              selection: TextSelection(baseOffset: 5, extentOffset: 12),
              composing: TextRange(start: 5, end: 12),
            );
            tester.testTextInput.updateEditingValue(draft);
            await tester.pump();
            await tester.pump();
            expect(focus.hasFocus, isTrue);
            expect(_semanticsValues(tester), contains(draft.text));

            editing.value = false;
            await tester.pump();
            await tester.pump();
            expect(titleKey.currentState, same(state));
            expect(controller.text, draft.text);
            expect(controller.selection, draft.selection);
            expect(state.submits, 0);
            expect(focus.hasFocus, isFalse);
            expect(focus.canRequestFocus, isFalse);
            expect(TickerMode.of(state.context), isFalse);
            expect(
              tester.getSize(_face(CardPreviewMode.pageContent)),
              idleBounds.size,
            );
            expect(tester.getSize(find.byKey(_titleFooter)).height, 0);
            expect(hiddenTitle.hitTestable(), findsNothing);
            expect(_semanticsValues(tester), isNot(contains(draft.text)));
            _expectNoProperties();
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            editing.dispose();
            nextCard.dispose();
          }
        });
      }
    }
  });

  group('real documents inside the intrinsic card host', () {
    for (final appearance in _appearances) {
      for (final compact in [false, true]) {
        for (final mode in [
          CardPreviewMode.pageAndTitle,
          CardPreviewMode.pageContent,
        ]) {
          testWidgets(
              '$appearance / $compact / ${mode.id}: heading and bullets '
              'paint in bounds without taking card taps or focus',
              (tester) async {
            final page = _StoredPage();
            await page.prime();
            final row =
                _row(documentId: page.documentId, cover: _cover('color'));
            final beforeRow = row.writeToBuffer();
            final beforeDocument = page.data.writeToBuffer();
            var taps = 0;
            try {
              await _pump(
                tester,
                _cardHost(
                  _layout(mode, row: row, compact: compact),
                  onTap: () => taps++,
                ),
                appearance: appearance,
                width: compact ? 176 : 232,
              );
              _expectFace(tester, mode);
              expect(find.byType(AppFlowyEditor), findsOneWidget);
              expect(find.byType(RowPageTextView), findsNothing);
              expect(
                find.text(LocaleKeys.cardPreview_pageEmpty.tr()),
                findsNothing,
              );
              expect(
                find.ancestor(
                  of: find.byType(RowPagePreview),
                  matching: find.byType(IntrinsicHeight),
                ),
                findsOneWidget,
              );
              final editor =
                  tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
              _expectReadOnlyEditor(editor);
              final nodes = editor.editorState.document.root.children;
              expect(nodes.map((node) => node.delta?.toPlainText()), page.text);
              expect(nodes.map((node) => node.type), [
                HeadingBlockKeys.type,
                BulletedListBlockKeys.type,
                BulletedListBlockKeys.type,
                HeadingBlockKeys.type,
                BulletedListBlockKeys.type,
                BulletedListBlockKeys.type,
              ]);
              final viewport = tester.getRect(find.byType(RowPagePreview));
              final face = tester.getRect(_face(mode));
              expect(viewport.height, compact ? 144 : 196);
              expect(viewport.width, (compact ? 176 : 232) - 24);
              _expectContains(face, viewport);
              for (final text in page.text) {
                expect(_paintedText(text), findsOneWidget);
                _expectContains(
                  viewport,
                  _paintedBounds(tester, _paintedText(text)),
                );
                expect(_paintedText(text).hitTestable(), findsNothing);
              }
              final pageBand = tester.getRect(find.byType(CardPagePreview));
              expect(pageBand.height, compact ? 157 : 212);
              if (mode == CardPreviewMode.pageContent) {
                expect(face, pageBand);
                expect(tester.getSize(find.byKey(_titleFooter)).height, 0);
              } else {
                expect(
                  tester.getTopLeft(find.byKey(_titleField)).dy,
                  pageBand.bottom + 4,
                );
              }
              final context = tester.element(find.byType(AppFlowyEditor));
              expect(PaperTheme.isEnabled(context), appearance == 'paper');
              expect(
                editor.editorState.editorStyle.textStyleConfiguration.text
                    .fontFamily,
                'DM Sans',
              );
              final scope = FocusScope.of(context);
              expect(scope.canRequestFocus, isFalse);
              expect(scope.descendantsAreFocusable, isFalse);
              scope.requestFocus();
              await tester.pump();
              await tester.pump();
              expect(scope.hasFocus, isFalse);
              await tester.tapAt(
                _paintedBounds(tester, _paintedText(page.heading)).center,
              );
              await tester.pump();
              expect(taps, 1);
              expect(editor.editorState.selection, isNull);
              expect(scope.hasFocus, isFalse);
              expect(page.reads, 1);
              expect(RowPageDocument.peek(page.documentId), same(page.data));
              expect(page.data.writeToBuffer(), orderedEquals(beforeDocument));
              expect(row.writeToBuffer(), orderedEquals(beforeRow));
              _expectNoProperties();
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
            }
          });
        }
      }
    }

    test('document cache deduplicates reads and isolates synthetic identities',
        () async {
      final page = _StoredPage();
      final other = _StoredPage(heading: 'Other ideas');
      final first =
          RowPageDocument.read(page.documentId, documentService: page);
      final concurrent =
          RowPageDocument.read(page.documentId, documentService: page);
      expect(concurrent, same(first));
      expect(await first, same(page.data));
      expect(await RowPageDocument.read(page.documentId), same(page.data));
      expect(page.reads, 1);
      await other.prime();
      RowPageDocument.discard(page.documentId);
      RowPageText.forget(page.documentId);
      expect(RowPageDocument.knows(page.documentId), isFalse);
      expect(RowPageDocument.peek(other.documentId), same(other.data));
      await page.prime();
      expect(page.reads, 2);
      expect(other.reads, 1);
      expect(RowPageText.peek(page.documentId), isNull);
    });

    for (final mode in [
      CardPreviewMode.pageAndTitle,
      CardPreviewMode.pageContent,
    ]) {
      testWidgets(
          '${mode.id}: changed document nodes keep a bounded face, not property rows',
          (tester) async {
        final original = _StoredPage(heading: 'Initial ideas');
        final changed = _StoredPage(heading: 'Revised ideas', extraBullets: 40);
        await original.prime();
        await changed.prime();
        final row = ValueNotifier(_row(documentId: original.documentId));
        final titleKey = GlobalKey<_DraftTitleState>();
        try {
          await _pump(
            tester,
            ValueListenableBuilder<RowMetaPB>(
              valueListenable: row,
              builder: (context, value, _) => _cardHost(
                _layout(mode, row: value, titleKey: titleKey),
              ),
            ),
            appearance: 'paper',
          );
          final beforeSize = tester.getSize(_face(mode));
          final title = titleKey.currentState!;
          final oldEditor = tester
              .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
              .editorState;
          final next = _row(documentId: changed.documentId);
          final beforeRow = next.writeToBuffer();
          row.value = next;
          await tester.pumpAndSettle();
          final editor =
              tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
          expect(editor.editorState, isNot(same(oldEditor)));
          expect(oldEditor.isDisposed, isTrue);
          expect(
            editor.editorState.document.root.children
                .map((node) => node.delta?.toPlainText()),
            changed.text,
          );
          expect(_paintedText('Initial ideas'), findsNothing);
          expect(_paintedText('Revised ideas'), findsOneWidget);
          expect(tester.getSize(_face(mode)), beforeSize);
          expect(tester.getSize(find.byType(RowPagePreview)).height, 196);
          expect(titleKey.currentState, same(title));
          expect(next.writeToBuffer(), orderedEquals(beforeRow));
          expect(original.reads, 1);
          expect(changed.reads, 1);
          _expectReadOnlyEditor(editor);
          _expectNoProperties();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          row.dispose();
        }
      });

      testWidgets(
          '${mode.id}: real document lets the real board own a mouse drag',
          (tester) async {
        final page = _StoredPage();
        await page.prime();
        final row = _row(documentId: page.documentId);
        final beforeRow = row.writeToBuffer();
        final starts = <(String, int)>[];
        final items = [_BoardItem('page-card'), _BoardItem('other-card')];
        final board = AppFlowyBoardController(
          onStartDraggingCard: (group, index) => starts.add((group, index)),
        )..addGroup(
            AppFlowyGroupData(
              id: 'synthetic-group',
              name: 'Ideas',
              items: items,
            ),
          );
        var taps = 0;
        TestGesture? gesture;
        try {
          await _pump(
            tester,
            SizedBox(
              height: 520,
              child: AppFlowyBoard(
                controller: board,
                groupConstraints: const BoxConstraints.tightFor(width: 232),
                config: const AppFlowyBoardConfig(
                  groupMargin: EdgeInsets.zero,
                  groupBodyPadding: EdgeInsets.zero,
                ),
                cardBuilder: (context, group, item) => Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: item.id == 'page-card'
                      ? _cardHost(_layout(mode, row: row), onTap: () => taps++)
                      : const SizedBox(height: 72, child: Text('Another card')),
                ),
              ),
            ),
            appearance: 'paper',
          );
          expect(find.byType(AppFlowyEditor), findsOneWidget);
          final start =
              _paintedBounds(tester, _paintedText(page.heading)).center;
          await tester.tapAt(start);
          await tester.pump();
          expect(taps, 1);
          gesture = await tester.startGesture(
            start,
            kind: ui.PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 32));
          await tester.pump(const Duration(milliseconds: 16));
          expect(starts, [('synthetic-group', 0)]);
          await gesture.moveBy(const Offset(0, 32));
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            starts,
            hasLength(1),
            reason: 'the same drag survives rebuilt feedback',
          );
          for (final editor in tester
              .widgetList<AppFlowyEditor>(find.byType(AppFlowyEditor))) {
            _expectReadOnlyEditor(editor);
          }
          await gesture.up();
          gesture = null;
          await tester.pumpAndSettle();
          expect(taps, 1, reason: 'dragging is not a second card tap');
          expect(
            page.reads,
            1,
            reason: 'drag feedback reuses the production page cache',
          );
          expect(row.writeToBuffer(), orderedEquals(beforeRow));
          _expectNoProperties();
          expect(tester.takeException(), isNull);
        } finally {
          await gesture?.cancel();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          board.clear();
          board.dispose();
          for (final item in items) {
            item.draggable.dispose();
          }
        }
      });
    }
  });

  group('Calendar-style hosts retain explicitly forwarded default fields', () {
    for (final mode in [CardPreviewMode.cover, CardPreviewMode.none]) {
      testWidgets('${mode.id}: Calendar default keeps property controls',
          (tester) async {
        const style = RowCardStyleConfiguration(cellStyleMap: {});
        expect(style.showProperties, isTrue);
        await _pump(
          tester,
          _layout(mode, row: _row(), showProperties: style.showProperties),
        );
        final title = tester.getRect(find.byKey(_titleField));
        expect(find.byKey(_status).hitTestable(), findsOneWidget);
        expect(find.byKey(_owner).hitTestable(), findsOneWidget);
        expect(find.byType(TextButton), findsNWidgets(2));
        expect(
          tester.getTopLeft(find.byKey(_status)).dy,
          greaterThanOrEqualTo(title.bottom),
        );
        expect(
          tester.getTopLeft(find.byKey(_owner)).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(_status)).dy),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('page motion and tint', () {
    for (final mode in [
      CardPreviewMode.pageAndTitle,
      CardPreviewMode.pageContent,
    ]) {
      for (final reduced in [false, true]) {
        testWidgets('${mode.id}: reduced motion $reduced respects tint changes',
            (tester) async {
          const firstTint = Color(0xFFF0E6D5);
          const nextTint = Color(0xFFE7D1B1);
          await _pump(
            tester,
            _layout(mode, row: _row(), tint: firstTint),
            appearance: 'paper',
            reducedMotion: reduced,
          );
          final animated = find.descendant(
            of: find.byType(CardPagePreview),
            matching: find.byType(AnimatedContainer),
          );
          expect(
            tester.widget<AnimatedContainer>(animated).duration,
            reduced ? Duration.zero : const Duration(milliseconds: 140),
          );
          final before = tester.getSize(find.byType(CardPagePreview));
          await tester.pumpWidget(
            _app(
              _layout(mode, row: _row(), tint: nextTint),
              appearance: 'paper',
              reducedMotion: reduced,
            ),
          );
          await tester.pump();
          final painted = find
              .descendant(
                of: animated,
                matching: find.byType(DecoratedBox),
              )
              .first;
          if (!reduced) {
            expect(
              (tester.widget<DecoratedBox>(painted).decoration as BoxDecoration)
                  .color,
              firstTint,
            );
            await tester.pump(const Duration(milliseconds: 140));
          }
          expect(
            (tester.widget<DecoratedBox>(painted).decoration as BoxDecoration)
                .color,
            nextTint,
          );
          expect(tester.getSize(find.byType(CardPagePreview)), before);
          if (!reduced) {
            // Flutter's _InterpolationSimulation.isDone uses elapsed > duration,
            // not >=. The pixels above must reach their target at exactly 140ms;
            // the final ticker is stopped on the first tick after that boundary.
            await tester.pump(const Duration(microseconds: 1));
          }
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('title-only style transformation', () {
    test('null foreground returns the original style map', () {
      final styles = _sampleStyles();
      expect(cardPreviewTitleStyleMap(styles, null), same(styles));
    });
    test('white ink copies only rich-text title style, never property styles',
        () {
      final styles = _sampleStyles();
      final original = styles[FieldType.RichText]! as TextCardCellStyle;
      final changed = cardPreviewTitleStyleMap(styles, Colors.white);
      final text = changed[FieldType.RichText]! as TextCardCellStyle;
      expect(changed, isNot(same(styles)));
      expect(changed.keys, orderedEquals(styles.keys));
      expect(text, isNot(same(original)));
      expect(
        text.titleTextStyle,
        original.titleTextStyle.copyWith(color: Colors.white),
      );
      expect(text.textStyle, same(original.textStyle));
      expect(text.padding, original.padding);
      expect(text.maxLines, original.maxLines);
      expect(changed[FieldType.Number], same(styles[FieldType.Number]));
      expect(original.titleTextStyle.color, Colors.indigo);
      expect(styles[FieldType.RichText], same(original));
    });
    test('missing or non-text rich-text style is left untouched', () {
      for (final styles in <CardCellStyleMap>[
        {},
        {FieldType.RichText: const _OtherStyle()},
      ]) {
        expect(cardPreviewTitleStyleMap(styles, Colors.white), same(styles));
      }
    });
  });

  group('mobile production composition with an isolated cell boundary', () {
    testWidgets('Calendar default still builds and displays every field',
        (tester) async {
      final cells = _RecordingCellBuilder();
      const style = RowCardStyleConfiguration(cellStyleMap: {});
      expect(style.showProperties, isTrue);
      await _pump(
        tester,
        MobileCardContent(
          rowMeta: _row(),
          cellBuilder: cells,
          cells: cells.metas,
          styleConfiguration: style,
          userProfile: null,
        ),
      );
      final title = find.byKey(const ValueKey('mobile-primary'));
      expect(title, findsOneWidget);
      for (final id in ['property-before', 'property-after']) {
        final property = find.byKey(ValueKey('mobile-$id'));
        expect(property, findsOneWidget);
        expect(
          tester.getTopLeft(property).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
        );
        final styles = mobileBoardCardCellStyleMap(tester.element(property));
        expect(
          tester.widget<Text>(property).style,
          (styles[FieldType.RichText]! as TextCardCellStyle).textStyle,
        );
      }
      expect(
        cells.calls.map((call) => call.fieldId).toSet(),
        {'primary', 'property-before', 'property-after'},
      );
      expect(tester.takeException(), isNull);
    });

    for (final primaryFirst in [false, true]) {
      for (final mode in CardPreviewMode.values) {
        testWidgets(
            '${mode.id} / primary first $primaryFirst: title identity and '
            'explicit row-data opt-in control which cells are built',
            (tester) async {
          final cells = _RecordingCellBuilder();
          final metas = cells.metas;
          if (primaryFirst) metas.insert(0, metas.removeAt(1));
          final row = _row(cover: _cover('color'));
          final beforeRow = row.writeToBuffer();
          final showsProperties = mode == CardPreviewMode.titleAndProperties;
          await _pump(
            tester,
            MobileCardContent(
              rowMeta: row,
              cellBuilder: cells,
              cells: metas,
              styleConfiguration: RowCardStyleConfiguration(
                cellStyleMap: const {},
                preview: mode,
                showProperties: false,
              ),
              userProfile: null,
            ),
            appearance: 'paper',
          );
          expect(_face(mode), findsOneWidget);
          final layout = tester.widget<RowCardPreviewLayout>(
            find.byType(RowCardPreviewLayout),
          );
          expect(layout.showProperties, showsProperties);
          expect(layout.properties, hasLength(showsProperties ? 2 : 0));
          final title = find.byKey(
            const ValueKey('mobile-primary'),
            skipOffstage: false,
          );
          expect(title, findsOneWidget);
          expect(
            find.byKey(const ValueKey('mobile-primary')),
            _faces[mode]!.title ? findsOneWidget : findsNothing,
          );
          final styles = mobileBoardCardCellStyleMap(tester.element(title));
          final text = styles[FieldType.RichText]! as TextCardCellStyle;
          double? previousBottom =
              showsProperties ? tester.getBottomLeft(title).dy + 6 : null;
          for (final id in ['property-before', 'property-after']) {
            final property = find.byKey(
              ValueKey('mobile-$id'),
              skipOffstage: false,
            );
            expect(property, showsProperties ? findsOneWidget : findsNothing);
            if (showsProperties) {
              expect(tester.widget<Text>(property).style, text.textStyle);
              expect(
                tester.getTopLeft(property).dy,
                closeTo(previousBottom!, 0.01),
              );
              previousBottom = tester.getBottomLeft(property).dy;
            }
          }
          expect(cells.calls, isNotEmpty);
          expect(
            cells.calls.map((call) => call.fieldId).toSet(),
            {
              'primary',
              if (showsProperties) ...['property-before', 'property-after'],
            },
            reason: 'only the new board face may construct nonprimary cells',
          );
          expect(
            tester.widget<Text>(title).style!.color,
            mode == CardPreviewMode.portrait
                ? Colors.white
                : text.titleTextStyle.color,
          );
          expect(cells.calls.every((call) => call.rowId == row.id), isTrue);
          expect(
            cells.calls.every((call) => call.hasNotes == !row.isDocumentEmpty),
            isTrue,
          );
          expect(row.writeToBuffer(), orderedEquals(beforeRow));
          expect(tester.takeException(), isNull);
        });
      }
    }
    testWidgets('a missing primary field is not replaced by the first property',
        (tester) async {
      final cells = _RecordingCellBuilder(includePrimary: false);
      for (final mode in [
        ...CardPreviewMode.values,
        ...CardPreviewMode.values.reversed,
      ]) {
        cells.calls.clear();
        final showsProperties = mode == CardPreviewMode.titleAndProperties;
        await _pump(
          tester,
          MobileCardContent(
            rowMeta: _row(cover: _cover('color')),
            cellBuilder: cells,
            cells: cells.metas,
            styleConfiguration: RowCardStyleConfiguration(
              cellStyleMap: const {},
              preview: mode,
              showProperties: false,
            ),
            userProfile: null,
          ),
        );
        expect(_face(mode), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-primary'), skipOffstage: false),
          findsNothing,
        );
        final layout = tester.widget<RowCardPreviewLayout>(
          find.byType(RowCardPreviewLayout),
        );
        expect(layout.showProperties, showsProperties);
        expect(layout.properties, hasLength(showsProperties ? 2 : 0));
        for (final id in ['property-before', 'property-after']) {
          final property =
              find.byKey(ValueKey('mobile-$id'), skipOffstage: false);
          expect(property, showsProperties ? findsOneWidget : findsNothing);
          if (showsProperties) {
            final styles =
                mobileBoardCardCellStyleMap(tester.element(property));
            expect(
              tester.widget<Text>(property).style,
              (styles[FieldType.RichText]! as TextCardCellStyle).textStyle,
              reason: 'a legitimate property must not acquire title styling',
            );
          }
        }
        expect(
          cells.calls.map((call) => call.fieldId).toSet(),
          showsProperties ? {'property-before', 'property-after'} : isEmpty,
        );
        if (showsProperties) {
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('mobile-property-after')))
                .dy,
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('mobile-property-before')),
                )
                .dy,
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('LAYOUT-ONLY borrowed GlobalKey retention (not RowCard integration)',
      () {
    for (final appearance in _appearances) {
      testWidgets(
          '$appearance: draft, selection, controller and focus survive all faces',
          (tester) async {
        final mode = ValueNotifier(CardPreviewMode.none);
        final titleKey = GlobalKey<_DraftTitleState>();
        final row = _row(cover: _cover('color'));
        final beforeRow = row.writeToBuffer();
        try {
          await _pump(
            tester,
            ValueListenableBuilder<CardPreviewMode>(
              valueListenable: mode,
              builder: (context, value, _) => _layout(
                value,
                row: row,
                titleKey: titleKey,
                isEditing: true,
              ),
            ),
            appearance: appearance,
          );
          final state = titleKey.currentState!;
          final controller = state.controller;
          final focus = state.focus;
          await tester.showKeyboard(find.byKey(_titleField));
          const draft = TextEditingValue(
            text: 'An unsaved title still being composed',
            selection: TextSelection(baseOffset: 3, extentOffset: 14),
            composing: TextRange(start: 3, end: 14),
          );
          tester.testTextInput.updateEditingValue(draft);
          await tester.pump();
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          for (final next in [
            ...CardPreviewMode.values,
            ...CardPreviewMode.values.reversed,
          ]) {
            mode.value = next;
            await tester.pump();
            await tester.pump();
            _expectFace(tester, next, isEditing: true);
            expect(titleKey.currentState, same(state), reason: next.id);
            expect(state.controller, same(controller), reason: next.id);
            expect(state.focus, same(focus), reason: next.id);
            expect(controller.value, draft, reason: next.id);
            expect(focus.hasFocus, isTrue, reason: next.id);
            expect(
              FocusManager.instance.primaryFocus,
              same(focus),
              reason: next.id,
            );
            expect(
              state.submits,
              0,
              reason: 'changing face must not submit the draft',
            );
            expect(
              tester.widget<TextField>(find.byKey(_titleField)).style!.color,
              next == CardPreviewMode.portrait
                  ? Colors.white
                  : tableViewPaletteOf(
                      tester.element(find.byKey(_titleField)),
                    ).textPrimary,
            );
          }
          expect(row.writeToBuffer(), orderedEquals(beforeRow));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          mode.dispose();
        }
      });
    }
  });

  group('production menu drives sibling card and fake persistence boundary',
      () {
    for (final appearance in _appearances) {
      testWidgets(
          '$appearance: all six localized choices update card and checkmark',
          (tester) async {
        final store = _MemoryExtras();
        final registry = CardPreviewRegistry(
          readExtra: store.read,
          writeExtra: store.write,
        );
        final view = ViewPB(
          id: _viewId,
          name: 'Board preview fixture',
          layout: ViewLayoutPB.Board,
        );
        final beforeView = view.writeToBuffer();
        final row = _row(cover: _cover('color'));
        final beforeRow = row.writeToBuffer();
        try {
          await _pump(
            tester,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardPreviewButton(view: view, registry: registry),
                const SizedBox(height: 24),
                ValueListenableBuilder<CardPreviewMode>(
                  valueListenable: registry.notifierFor(view),
                  builder: (context, mode, _) => _layout(mode, row: row),
                ),
              ],
            ),
            appearance: appearance,
          );
          _expectFace(tester, CardPreviewMode.cover);
          var selected = CardPreviewMode.cover;
          for (final choice in CardPreviewMode.values) {
            await tester.tap(find.byType(FlowyIconButton));
            await tester.pumpAndSettle();
            _expectMenu(tester, selected);
            final surface =
                tester.widget<AppMenuSurface>(find.byType(AppMenuSurface));
            if (appearance == 'paper') {
              expect(surface.style!.surface, PaperTheme.popupBackground);
              expect(surface.style!.hover, PaperTheme.controlHover);
            }
            await tester.tap(
              find.descendant(
                of: find.byType(AppMenuSurface),
                matching: find.text(_labels[choice]!.tr()),
              ),
            );
            await tester.pumpAndSettle();
            selected = choice;
            expect(find.byType(AppMenuSurface), findsNothing);
            expect(registry.modeFor(view), choice);
            expect(CardPreviewSetting.fromExtra(store.extra).mode, choice);
            expect(jsonDecode(store.extra)['unrelated'], {
              'keep': [1, 'fresh'],
            });
            _expectFace(tester, choice);
            final icon = tester
                .widget<FlowyIconButton>(find.byType(FlowyIconButton))
                .icon as Icon;
            expect(icon.icon, _icons[choice]);
          }
          await tester.tap(find.byType(FlowyIconButton));
          await tester.pumpAndSettle();
          _expectMenu(tester, CardPreviewMode.titleAndProperties);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(store.writes, CardPreviewMode.values);
          expect(store.reads, CardPreviewMode.values.length);
          expect(view.writeToBuffer(), orderedEquals(beforeView));
          expect(row.writeToBuffer(), orderedEquals(beforeRow));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          registry.reset();
        }
      });
    }
  });

  group('real-font golden sheets (populated documents, real covers)', () {
    for (final appearance in _appearances) {
      testWidgets('$appearance: regular, compact, stored covers and fallbacks',
          (tester) async {
        tester.view.physicalSize = const Size(1600, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final page = _StoredPage();
        await page.prime();
        try {
          await _pump(
            tester,
            _goldenSheet(appearance, documentId: page.documentId),
            appearance: appearance,
            width: 1560,
            reducedMotion: true,
          );
          await _decodeImages(tester);
          expect(find.byType(AppFlowyEditor), findsNWidgets(4));
          expect(find.byType(RowPageTextView), findsNothing);
          expect(
            find.text(LocaleKeys.cardPreview_pageEmpty.tr()),
            findsNothing,
          );
          for (final editor in tester.widgetList<AppFlowyEditor>(
            find.byType(AppFlowyEditor),
          )) {
            _expectReadOnlyEditor(editor);
            expect(
              editor.editorState.document.root.children
                  .map((node) => node.delta?.toPlainText()),
              page.text,
            );
            expect(
              editor.editorState.editorStyle.textStyleConfiguration.text
                  .fontFamily,
              'DM Sans',
            );
          }
          for (final text in page.text.take(3)) {
            expect(_paintedText(text), findsNWidgets(4));
          }
          expect(find.byKey(_titleField), findsNWidgets(15));
          expect(
            find.byKey(_titleField, skipOffstage: false),
            findsNWidgets(17),
          );
          expect(_face(CardPreviewMode.titleAndProperties), findsNWidgets(2));
          expect(find.byKey(_status), findsNWidgets(2));
          expect(find.byKey(_owner), findsNWidgets(2));
          expect(find.byType(_Property), findsNWidgets(4));
          expect(find.byType(TextButton), findsNWidgets(4));
          for (final mode in CardPreviewMode.values) {
            expect(
              find.descendant(
                of: _face(mode),
                matching: find.byType(_Property, skipOffstage: false),
                skipOffstage: false,
              ),
              mode == CardPreviewMode.titleAndProperties
                  ? findsNWidgets(4)
                  : findsNothing,
            );
          }
          expect(page.reads, 1);
          for (final raw
              in tester.widgetList<RawImage>(find.byType(RawImage))) {
            expect(raw.image, isNotNull);
          }
          for (final field
              in tester.widgetList<TextField>(find.byKey(_titleField))) {
            expect(
              field.style!.fontFamily,
              _theme(appearance).textTheme.bodyMedium!.fontFamily,
            );
            expect(field.style!.fontFamily, isNot('Ahem'));
          }
          final propertyLabels = tester.widgetList<Text>(
            find.descendant(
              of: find.byType(_Property),
              matching: find.byType(Text),
            ),
          );
          expect(propertyLabels, hasLength(4));
          for (final label in propertyLabels) {
            expect(
              label.style!.fontFamily,
              _theme(appearance).textTheme.bodyMedium!.fontFamily,
            );
            expect(label.style!.fontFamily, isNot('Ahem'));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_sheet),
            matchesGoldenFile('goldens/board_card_previews_$appearance.png'),
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  });
}

Finder _face(CardPreviewMode mode) =>
    find.byKey(ValueKey('row-card-face-${mode.id}'));

void _expectFace(
  WidgetTester tester,
  CardPreviewMode mode, {
  bool isEditing = false,
}) {
  final expected = _faces[mode]!;
  expect(_face(mode), findsOneWidget);
  for (final other in CardPreviewMode.values.where((value) => value != mode)) {
    expect(_face(other), findsNothing);
  }
  expect(
    find.byKey(_titleField),
    expected.title || isEditing ? findsOneWidget : findsNothing,
  );
  expect(find.byKey(_titleField, skipOffstage: false), findsOneWidget);
  expect(
    find.byType(CardPagePreview),
    expected.page ? findsOneWidget : findsNothing,
  );
  expect(
    find.byType(RowPagePreview),
    expected.page ? findsOneWidget : findsNothing,
  );
  expect(
    find.byType(CardCover),
    expected.cover ? findsOneWidget : findsNothing,
  );
  if (mode == CardPreviewMode.titleAndProperties) {
    _expectRowDataProperties(tester);
  } else {
    _expectNoProperties();
  }
  expect(
    tester
        .widget<_DraftTitle>(find.byType(_DraftTitle, skipOffstage: false))
        .foreground,
    mode == CardPreviewMode.portrait ? Colors.white : isNull,
  );
}

void _expectRowDataProperties(WidgetTester tester) {
  expect(find.byKey(_status), findsOneWidget);
  expect(find.byKey(_owner), findsOneWidget);
  expect(find.byType(_Property), findsNWidgets(2));
  final buttons = find.descendant(
    of: _face(CardPreviewMode.titleAndProperties),
    matching: find.byType(TextButton),
  );
  expect(buttons, findsNWidgets(2));
  for (final button in tester.widgetList<TextButton>(buttons)) {
    expect(button.onPressed, isNotNull);
  }
  final face = tester.getRect(_face(CardPreviewMode.titleAndProperties));
  final title = tester.getRect(find.byKey(_titleField));
  final status = tester.getRect(find.byKey(_status));
  final owner = tester.getRect(find.byKey(_owner));
  expect(status.top - title.bottom, closeTo(6, 0.01));
  expect(owner.top, closeTo(status.bottom, 0.01));
  _expectContains(face, status);
  _expectContains(face, owner);
}

void _expectNoProperties() {
  expect(find.byKey(_status, skipOffstage: false), findsNothing);
  expect(find.byKey(_owner, skipOffstage: false), findsNothing);
  expect(find.byType(_Property, skipOffstage: false), findsNothing);
  expect(
    find.descendant(
      of: find.byType(RowCardPreviewLayout),
      matching: find.byType(TextButton, skipOffstage: false),
      skipOffstage: false,
    ),
    findsNothing,
    reason: 'property controls must be absent, not merely hidden offstage',
  );
}

List<String> _semanticsValues(WidgetTester tester) {
  final values = <String>[];
  void visit(SemanticsNode node) {
    values.add(node.getSemanticsData().value);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(Scaffold)));
  return values;
}

Rect _paintedBounds(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

void _expectContains(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - 0.01));
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.01));
  expect(inner.right, lessThanOrEqualTo(outer.right + 0.01));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.01));
}

void _expectPortraitCover(WidgetTester tester) {
  final face = tester.getRect(_face(CardPreviewMode.portrait));
  expect(tester.getRect(find.byType(CardCover)), face);
  final scrim = find.byKey(const ValueKey('row-card-cover-scrim'));
  expect(scrim, findsOneWidget);
  expect(tester.getSize(scrim).height, 28);
  final gradient =
      (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration).gradient!
          as LinearGradient;
  expect(gradient.begin, Alignment.topCenter);
  expect(gradient.end, Alignment.bottomCenter);
  expect(gradient.colors, [const Color(0x00000000), _footColor]);
  final foot = find.ancestor(
    of: find.byKey(_titleField),
    matching: find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == _footColor,
    ),
  );
  expect(foot, findsOneWidget);
  final footBounds = tester.getRect(foot);
  _expectContains(footBounds, tester.getRect(find.byKey(_titleField)));
  expect(footBounds.bottom, face.bottom);
  expect(tester.getBottomLeft(scrim).dy, footBounds.top);
  final context = tester.element(find.byKey(_titleField));
  expect(Theme.of(context).hintColor, Colors.white.withValues(alpha: 0.8));
  expect(Theme.of(context).textSelectionTheme.cursorColor, Colors.white);
  expect(
    Theme.of(context).textSelectionTheme.selectionColor,
    Colors.white.withValues(alpha: 0.3),
  );
  expect(
    tester.widget<TextField>(find.byKey(_titleField)).style!.color,
    Colors.white,
  );
  expect(find.byKey(_status), findsNothing);
  expect(find.byKey(_owner), findsNothing);
}

ColoredBox _portraitBackground(WidgetTester tester) =>
    tester.widget<ColoredBox>(
      find
          .descendant(
            of: _face(CardPreviewMode.portrait),
            matching: find.byType(ColoredBox),
          )
          .first,
    );

void _expectMenu(WidgetTester tester, CardPreviewMode selected) {
  final rows = tester.widgetList<AppMenuRow>(find.byType(AppMenuRow)).toList();
  expect(rows, hasLength(6));
  expect(CardPreviewMode.values, orderedEquals(_labels.keys));
  expect(LocaleKeys.cardPreview_titleAndProperties.tr(), 'Title and row data');
  expect(rows.map((row) => row.label), _labels.values.map((key) => key.tr()));
  expect(
    rows.where((row) => row.selected).single.label,
    _labels[selected]!.tr(),
  );
  for (final mode in CardPreviewMode.values) {
    expect(
      _labels[mode]!.tr(),
      isNot(_labels[mode]),
      reason: 'use real translations',
    );
    final row = find.byWidget(rows[mode.index]);
    expect(
      find.descendant(of: row, matching: find.byIcon(_icons[mode]!)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.check_rounded)),
      mode == selected ? findsOneWidget : findsNothing,
    );
  }
  expect(find.byIcon(Icons.check_rounded), findsOneWidget);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
  double width = 232,
  double textScale = 1,
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    _app(
      child,
      appearance: appearance,
      width: width,
      textScale: textScale,
      reducedMotion: reducedMotion,
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(
  Widget child, {
  String appearance = 'light',
  double width = 232,
  double textScale = 1,
  bool reducedMotion = false,
}) =>
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
            ),
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: _appearanceCubit),
                BlocProvider.value(value: _documentAppearanceCubit),
              ],
              child: child!,
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(width: width, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );

RowMetaPB _row({RowCoverPB? cover, String documentId = ''}) => RowMetaPB(
      id: 'synthetic-card-row',
      documentId: documentId,
      isDocumentEmpty: documentId.isEmpty,
      cover: cover,
    );

RowCoverPB _cover(String kind) => switch (kind) {
      'color' =>
        RowCoverPB(coverType: CoverTypePB.ColorCover, data: '0xFF368F72'),
      'tint' =>
        RowCoverPB(coverType: CoverTypePB.ColorCover, data: FlowyTint.tint5.id),
      'gradient' => RowCoverPB(
          coverType: CoverTypePB.GradientCover,
          data: FlowyGradientColor.gradient3.id,
        ),
      'asset' => RowCoverPB(coverType: CoverTypePB.AssetCover, data: _assetId),
      'local path' || 'local URI' => RowCoverPB(
          coverType: CoverTypePB.FileCover,
          uploadType: FileUploadTypePB.LocalFile,
          data: kind == 'local URI'
              ? _localImage.uri.toString()
              : _localImage.path,
        ),
      _ => throw ArgumentError.value(kind),
    };

RowCoverPB? _unavailableCover(String kind) => switch (kind) {
      'absent' => null,
      'present but empty' => RowCoverPB(),
      'cloud without profile' => RowCoverPB(
          coverType: CoverTypePB.FileCover,
          uploadType: FileUploadTypePB.CloudFile,
          data: 'synthetic-private-cover-never-fetched',
        ),
      _ => throw ArgumentError.value(kind),
    };

Widget _layout(
  CardPreviewMode mode, {
  required RowMetaPB row,
  bool compact = false,
  bool isEditing = false,
  bool showProperties = false,
  List<Widget> properties = const [
    _Property(key: _status, label: 'Status: Ready'),
    _Property(key: _owner, label: 'Owner: Ada'),
  ],
  String title = _shortTitle,
  Key? titleKey,
  Color? tint,
  EdgeInsets padding = const EdgeInsets.all(4),
  double radius = 4,
}) =>
    RowCardPreviewLayout(
      rowMeta: row,
      mode: mode,
      isCompact: compact,
      isEditing: isEditing,
      showProperties: showProperties,
      tint: tint,
      padding: padding,
      radius: radius,
      titleBuilder: (context, foreground) => _DraftTitle(
        key: titleKey,
        initialText: title,
        foreground: foreground,
      ),
      properties: properties,
    );

// A test-owned editor with the real board's typography and a real Flutter
// controller/focus node. It is NOT TextCardCell and does not simulate its bloc.
class _DraftTitle extends StatefulWidget {
  const _DraftTitle({
    super.key,
    required this.initialText,
    required this.foreground,
  });

  final String initialText;
  final Color? foreground;

  @override
  State<_DraftTitle> createState() => _DraftTitleState();
}

class _DraftTitleState extends State<_DraftTitle> {
  late final controller = TextEditingController(text: widget.initialText);
  final focus = FocusNode();
  int submits = 0;

  @override
  Widget build(BuildContext context) {
    final styles = cardPreviewTitleStyleMap(
      desktopBoardCardCellStyleMap(context),
      widget.foreground,
    );
    final text = styles[FieldType.RichText]! as TextCardCellStyle;
    return TextField(
      key: _titleField,
      controller: controller,
      focusNode: focus,
      maxLines: null,
      minLines: 1,
      showCursor: false,
      style: text.titleTextStyle,
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        contentPadding: text.padding,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),
      onSubmitted: (_) => submits++,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _Property extends StatelessWidget {
  const _Property({
    super.key,
    required this.label,
    this.onPressed,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final text = desktopBoardCardCellStyleMap(context)[FieldType.RichText]!
        as TextCardCellStyle;
    return TextButton(
      onPressed: onPressed ?? () {},
      focusNode: focusNode,
      child: Padding(
        padding: text.padding,
        child: Text(label, style: text.textStyle, maxLines: text.maxLines),
      ),
    );
  }
}

Future<void> _decodeImages(WidgetTester tester) async {
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toSet();
  final errors = <Object>[];
  final listeners = <(ImageStream, ImageStreamListener)>[];
  var completed = 0;
  for (final provider in providers) {
    var finished = false;
    void finish() {
      if (!finished) completed++;
      finished = true;
    }

    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (image, _) {
        image.dispose();
        finish();
      },
      onError: (Object error, StackTrace? stack) {
        errors.add(error);
        finish();
      },
    );
    stream.addListener(listener);
    listeners.add((stream, listener));
  }
  try {
    // FileImage starts IO in the build's fake zone. Awaiting that stream from
    // runAsync deadlocks: pump each continuation between bounded real IO turns.
    for (var attempt = 0;
        completed < providers.length && attempt < 200;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      completed,
      providers.length,
      reason: 'every image must finish decoding',
    );
  } finally {
    for (final (stream, listener) in listeners) {
      stream.removeListener(listener);
    }
  }
  await tester.pumpAndSettle();
  expect(
    errors,
    isEmpty,
    reason: 'only real bundled assets and owned local files',
  );
}

CardCellStyleMap _sampleStyles() => {
      FieldType.RichText: TextCardCellStyle(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        textStyle:
            const TextStyle(color: Colors.teal, fontSize: 11, height: 1.4),
        titleTextStyle: const TextStyle(
          color: Colors.indigo,
          fontFamily: 'DM Sans',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontVariations: [ui.FontVariation('wght', 620)],
          letterSpacing: -0.15,
          height: 1.35,
        ),
        maxLines: 3,
      ),
      FieldType.Number: const _OtherStyle(),
    };

class _OtherStyle extends CardCellStyle {
  const _OtherStyle() : super(padding: const EdgeInsets.all(9));
}

// Observe lazy data access without permitting any document/backend fetch even
// if a regression starts constructing a page preview in a non-page face.
class _ObservedRow extends Fake implements RowMetaPB {
  _ObservedRow(this.row);

  final RowMetaPB row;
  int documentReads = 0;
  int coverReads = 0;
  int coverPresenceReads = 0;

  @override
  String get documentId {
    documentReads++;
    return '';
  }

  @override
  bool hasCover() {
    coverPresenceReads++;
    return row.hasCover();
  }

  @override
  RowCoverPB get cover {
    coverReads++;
    return row.cover;
  }
}

class _MemoryExtras {
  String extra = '{"unrelated":{"keep":[1,"fresh"]}}';
  int reads = 0;
  final writes = <CardPreviewMode>[];

  Future<String> read(String id) async {
    expectSync(id, _viewId);
    reads++;
    return extra;
  }

  Future<void> write(String id, String value) async {
    expectSync(id, _viewId);
    extra = value;
    writes.add(CardPreviewSetting.fromExtra(value).mode);
  }
}

class _Fields extends Fake implements FieldController {
  _Fields({required bool includePrimary})
      : fields = [
          FieldInfo.initial(
            FieldPB(
              id: 'property-before',
              name: 'A property before title',
              fieldType: FieldType.RichText,
            ),
          ),
          if (includePrimary)
            FieldInfo.initial(
              FieldPB(
                id: 'primary',
                name: 'The actual primary title',
                fieldType: FieldType.RichText,
                isPrimary: true,
              ),
            ),
          FieldInfo.initial(
            FieldPB(
              id: 'property-after',
              name: 'A second property',
              fieldType: FieldType.RichText,
            ),
          ),
        ];

  final List<FieldInfo> fields;

  @override
  FieldInfo? getField(String fieldId) {
    for (final field in fields) {
      if (field.id == fieldId) return field;
    }
    return null;
  }
}

class _Database extends Fake implements DatabaseController {
  _Database(this.fieldController);

  @override
  final FieldController fieldController;
}

class _RecordingCellBuilder extends Fake implements CardCellBuilder {
  _RecordingCellBuilder({bool includePrimary = true})
      : fields = _Fields(includePrimary: includePrimary);

  final _Fields fields;
  final calls = <({String fieldId, String rowId, bool hasNotes})>[];

  @override
  late final DatabaseController databaseController = _Database(fields);

  List<CellMeta> get metas => [
        for (final field in fields.fields)
          CellMeta(
            fieldId: field.id,
            rowId: 'synthetic-card-row',
            fieldType: field.fieldType,
          ),
      ];

  @override
  Widget build({
    required CellContext cellContext,
    required CardCellStyleMap styleMap,
    EditableCardNotifier? cellNotifier,
    required bool hasNotes,
  }) {
    final field = fields.getField(cellContext.fieldId)!;
    final text = styleMap[FieldType.RichText]! as TextCardCellStyle;
    calls.add(
      (
        fieldId: cellContext.fieldId,
        rowId: cellContext.rowId,
        hasNotes: hasNotes,
      ),
    );
    return Text(
      field.name,
      key: ValueKey('mobile-${field.id}'),
      style: field.isPrimary ? text.titleTextStyle : text.textStyle,
    );
  }
}

Widget _goldenSheet(String appearance, {required String documentId}) => Builder(
      builder: (context) {
        final palette = tableViewPaletteOf(context);
        final theme = Theme.of(context);
        return RepaintBoundary(
          key: _sheet,
          child: ColoredBox(
            color: palette.canvas,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Board card previews · $appearance',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Real Ideas / Tasks documents · clean faces and row data · real cover renderers',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  const Text('Regular · 232 px'),
                  const SizedBox(height: 12),
                  _goldenFaces(compact: false, documentId: documentId),
                  const SizedBox(height: 28),
                  const Text('Compact · 176 px · 200% text'),
                  const SizedBox(height: 12),
                  _goldenFaces(compact: true, documentId: documentId),
                  const SizedBox(height: 28),
                  const Text(
                    'Stored tint / gradient / local image / removed cover / cloud without profile',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final kind in [
                        'tint',
                        'gradient',
                        'local path',
                        'present but empty',
                        'cloud without profile',
                      ]) ...[
                        if (kind != 'tint') const SizedBox(width: 16),
                        _goldenCard(
                          _layout(
                            CardPreviewMode.portrait,
                            row: _row(
                              cover: ['tint', 'gradient', 'local path']
                                      .contains(kind)
                                  ? _cover(kind)
                                  : _unavailableCover(kind),
                            ),
                            title: kind == 'cloud without profile'
                                ? 'Private cover, no profile'
                                : kind == 'present but empty'
                                    ? 'Cover removed'
                                    : 'The stored $kind',
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                            radius: 14,
                          ),
                          width: 232,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

Widget _goldenFaces({required bool compact, required String documentId}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in CardPreviewMode.values) ...[
          if (mode != CardPreviewMode.pageAndTitle) const SizedBox(width: 16),
          SizedBox(
            width: 232,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(_icons[mode], size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_labels[mode]!.tr())),
                  ],
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(compact ? 2 : 1),
                    ),
                    child: _goldenCard(
                      _layout(
                        mode,
                        row: _row(
                          cover: _cover('asset'),
                          documentId: documentId,
                        ),
                        compact: compact,
                        title: compact
                            ? 'A longer card title with enough room to wrap'
                            : _shortTitle,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                        radius: 14,
                      ),
                      width: compact ? 176 : 232,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

Widget _goldenCard(Widget child, {required double width}) => Builder(
      builder: (context) => SizedBox(
        width: width,
        child: Material(
          color: tableViewPaletteOf(context).surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: _cardHost(child),
        ),
      ),
    );

Widget _cardHost(Widget child, {VoidCallback? onTap}) => RowCardContainer(
      onTap: (_) => onTap?.call(),
      openAccessory: (_) {},
      accessories: const [],
      buildAccessoryWhen: () => false,
      child: child,
    );

class _BoardItem extends AppFlowyGroupItem {
  _BoardItem(this.id);

  @override
  final String id;
}

// Only document transport is fake: protobuf conversion, cache, preview canvas,
// block builders, editor, appearance cubits and intrinsic card host are real.
class _StoredPage extends Fake implements DocumentService {
  _StoredPage({this.heading = 'Ideas', this.extraBullets = 0}) {
    _syntheticDocumentIds.add(documentId);
  }

  final String documentId = 'synthetic-board-preview-page-${_nextDocumentId++}';
  final String heading;
  final int extraBullets;
  int reads = 0;
  late final text = [
    heading,
    'A calmer workspace',
    'Make room for details',
    'Tasks',
    'Sketch the layout',
    'Review the essentials',
    for (var i = 0; i < extraBullets; i++) 'Another real page item $i',
  ];
  late final DocumentDataPB data = DocumentDataPBFromTo.fromDocument(
    Document(
      root: pageNode(
        children: [
          headingNode(level: 1, text: text[0]),
          bulletedListNode(text: text[1]),
          bulletedListNode(text: text[2]),
          headingNode(level: 2, text: text[3]),
          for (final value in text.skip(4)) bulletedListNode(text: value),
        ],
      ),
    ),
  )!;

  Future<void> prime() async {
    final loaded = await RowPageDocument.read(
      documentId,
      documentService: this,
    );
    expect(loaded, same(data));
    expect(RowPageDocument.knows(documentId), isTrue);
    expect(RowPageDocument.peek(documentId), same(data));
  }

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    expectSync(documentId, this.documentId);
    reads++;
    return FlowyResult.success(data);
  }
}

Finder _paintedText(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    );

void _expectReadOnlyEditor(AppFlowyEditor editor) {
  expect(editor.editable, isFalse);
  expect(editor.editorState.editable, isFalse);
  expect(editor.disableSelectionService, isTrue);
  expect(editor.disableKeyboardService, isTrue);
  expect(editor.disableAutoScroll, isTrue);
  expect(editor.contextMenuItems, isEmpty);
  expect(editor.editorState.selection, isNull);
}
