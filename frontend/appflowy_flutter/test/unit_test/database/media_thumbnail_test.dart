import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/media_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller_builder.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/type_option/type_option_data_parser.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_row_detail/desktop_row_detail_media_cell.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reorderables/reorderables.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File jpeg;
  late File png;
  late File large;
  late File invalid;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    temporary = await Directory.systemTemp.createTemp('appflowy_media_tests_');
    jpeg = File('${temporary.path}/red #1 100%.JFIF');
    png = File('${temporary.path}/blue.png');
    large = File('${temporary.path}/large.png');
    invalid = File('${temporary.path}/unsupported.HEIC');
    await jpeg.writeAsBytes(base64Decode(_redJpeg));
    await png.writeAsBytes(await _solidPng(40, 80));
    await large.writeAsBytes(await _solidPng(2048, 1024));
    await invalid.writeAsBytes([0, 1, 2, 3, 4]);
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await temporary.delete(recursive: true);
  });

  List<MediaFilePB> photos(String legacyName, MediaFileTypePB legacyType) => [
        MediaFilePB(
          id: 'blue',
          name: 'first.png',
          url: png.path,
          fileType: MediaFileTypePB.Image,
        ),
        MediaFilePB(
          id: 'red',
          name: legacyName,
          // This is a real JPEG with a JFIF header, not PNG renamed to JFIF.
          url: jpeg.uri.toString(),
          fileType: legacyType,
        ),
      ];

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final size in [const Size.square(40), const Size(86.4, 68)]) {
      for (final legacy in [
        ('old.JPG', MediaFileTypePB.Other),
        ('old.JFIF', MediaFileTypePB.Other),
        ('old.JFIF', MediaFileTypePB.Link),
      ]) {
        testWidgets(
            '$appearance $size: two photos including ${legacy.$2} ${legacy.$1} retain pixels after reorder',
            (tester) async {
          final files = photos(legacy.$1, legacy.$2);
          final saved = files.map((file) => file.writeToBuffer()).toList();
          await tester.pumpWidget(_app(appearance, _strip(files, size)));
          await _finishImages(tester);
          expect(find.byType(MediaFileThumbnail), findsNWidgets(2));
          await _expectColor(tester, 'blue', red: false);
          await _expectColor(tester, 'red', red: true);
          final blueState = tester.state(_image('blue'));
          final redState = tester.state(_image('red'));
          expect(_raw(tester, 'blue').fit, BoxFit.cover);
          expect(_raw(tester, 'red').fit, BoxFit.cover);

          // Fresh protobuf instances model a backend update; IDs, not object
          // identity or positions, must keep each thumbnail with its file.
          final reordered = saved.reversed.map(MediaFilePB.fromBuffer).toList();
          await tester.pumpWidget(_app(appearance, _strip(reordered, size)));
          await _finishImages(tester);
          expect(
            tester.getTopLeft(_thumbnail('red')).dx,
            lessThan(tester.getTopLeft(_thumbnail('blue')).dx),
          );
          expect(tester.state(_image('blue')), same(blueState));
          expect(tester.state(_image('red')), same(redState));
          await _expectColor(tester, 'blue', red: false);
          await _expectColor(tester, 'red', red: true);
          expect(files[0].writeToBuffer(), orderedEquals(saved[0]));
          expect(files[1].writeToBuffer(), orderedEquals(saved[1]));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    testWidgets(
        '$appearance: actual row skin retains state on updates and cached pixels on reorder',
        (tester) async {
      final files = photos('old.JPG', MediaFileTypePB.Other);
      final controller = _MemoryMediaController(files);
      final bloc = MediaCellBloc(cellController: controller);
      final skin = DekstopRowDetailMediaCellSkin();
      final cellNotifier = CellContainerNotifier();
      final popover = PopoverController();
      ui.Image? cachedRed;
      try {
        await tester.pumpWidget(
          _app(appearance, _rowSkin(skin, bloc, cellNotifier, popover, 260)),
        );
        await _finishImages(tester);
        expect(find.byType(ReorderableWrap), findsOneWidget);
        expect(find.byType(MediaFileThumbnail), findsNWidgets(2));
        await _expectColor(tester, 'blue', red: false);
        await _expectColor(tester, 'red', red: true);
        final state = tester.state(_image('red'));
        cachedRed = _raw(tester, 'red').image!.clone();
        controller.replaceFiles([
          for (final file in files)
            MediaFilePB.fromBuffer(file.writeToBuffer()),
        ]);
        await tester.pumpAndSettle();
        expect(tester.state(_image('red')), same(state));

        // ReorderableWrap wraps items in index-keyed drag targets. It may
        // remount a moved item, but must reuse its decoded image and display
        // the right pixels immediately instead of an empty/wrong thumbnail.
        controller.replaceFiles(files.reversed.toList());
        await tester.pumpAndSettle();
        expect(_raw(tester, 'red').image!.isCloneOf(cachedRed), isTrue);
        await _finishImages(tester);
        expect(
          tester.getTopLeft(_thumbnail('red')).dx,
          lessThan(tester.getTopLeft(_thumbnail('blue')).dx),
        );
        await _expectColor(tester, 'blue', red: false);
        await _expectColor(tester, 'red', red: true);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(bloc.close);
        cachedRed?.dispose();
        skin.dispose();
        cellNotifier.dispose();
      }
    });

    testWidgets(
        '$appearance: decode failures are visible and explicit documents are not images',
        (tester) async {
      final files = [
        MediaFilePB(
          id: 'broken',
          name: 'unsupported.HEIC',
          url: invalid.path,
          fileType: MediaFileTypePB.Image,
        ),
        MediaFilePB(
          id: 'missing',
          name: 'missing.JPG',
          url: '${temporary.path}/missing.JPG',
        ),
        MediaFilePB(
          id: 'document',
          name: 'actually-a-document.JPG',
          url: png.path,
          fileType: MediaFileTypePB.Document,
        ),
        MediaFilePB(
          id: 'no-profile',
          name: 'cloud.JPG',
          url: 'https://example.invalid/file',
          uploadType: FileUploadTypePB.CloudFile,
        ),
      ];
      await tester
          .pumpWidget(_app(appearance, _strip(files, const Size.square(40))));
      await _finishImages(tester);
      expect(find.byIcon(Icons.broken_image_rounded), findsNWidgets(3));
      expect(_image('document'), findsNothing);
      expect(_image('no-profile'), findsNothing);
      final background = tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('media-unavailable-broken')),
          )
          .color;
      if (appearance == 'paper') {
        expect(background, PaperTheme.editorPreviewBackground);
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('media-unavailable-broken'))),
        const Size.square(40),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        '$appearance: narrow row collapse counts the footer file and expands safely',
        (tester) async {
      final files = List.generate(
        5,
        (index) => MediaFilePB(
          id: 'file-$index',
          name: 'photo-$index.JPG',
          url: jpeg.path,
        ),
      );
      final controller = _MemoryMediaController(files);
      final bloc = MediaCellBloc(cellController: controller);
      final skin = DekstopRowDetailMediaCellSkin();
      final cellNotifier = CellContainerNotifier();
      final popover = PopoverController();
      try {
        // Exactly two tiles and their one gap fit in the padded row.
        await tester.pumpWidget(
          _app(
            appearance,
            _rowSkin(skin, bloc, cellNotifier, popover, 196.8),
          ),
        );
        await _finishImages(tester);
        expect(
          tester
              .widget<ReorderableWrap>(find.byType(ReorderableWrap))
              .children
              .length,
          3,
        );
        expect(
          find.text(LocaleKeys.grid_media_extraCount.tr(args: ['2'])),
          findsOneWidget,
        );

        for (final width in [0.0, 16.0, 24.0, 64.0, 100.0]) {
          await tester.pumpWidget(
            _app(
              appearance,
              _rowSkin(skin, bloc, cellNotifier, popover, width),
            ),
          );
          await _finishImages(tester);
          if (width > 16) {
            expect(
              tester
                  .widget<ReorderableWrap>(find.byType(ReorderableWrap))
                  .children
                  .length,
              1,
            );
            expect(
              find.text(LocaleKeys.grid_media_extraCount.tr(args: ['4'])),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull, reason: 'width $width');
        }
        await tester
            .tap(find.text(LocaleKeys.grid_media_extraCount.tr(args: ['4'])));
        await tester.pumpAndSettle();
        await _finishImages(tester);
        expect(
          tester
              .widget<ReorderableWrap>(find.byType(ReorderableWrap))
              .children
              .length,
          5,
        );
        expect(
          tester.widget<ReorderableWrap>(find.byType(ReorderableWrap)).footer,
          isNull,
        );
        expect(
          bloc.state.files.map((file) => file.id),
          files.map((file) => file.id),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(bloc.close);
        skin.dispose();
        cellNotifier.dispose();
      }
    });
  }

  for (final size in [const Size.square(40), const Size(86.4, 68)]) {
    testWidgets(
        '$size: oversized photos decode at device-pixel thumbnail width without distortion',
        (tester) async {
      final file = MediaFilePB(
        id: 'large',
        name: 'large.PNG',
        url: large.uri.toString(),
      );
      await tester.pumpWidget(
        _app(
          'light',
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2),
            child: _strip([file], size),
          ),
        ),
      );
      await _finishImages(tester);
      final image = _raw(tester, 'large');
      final target = (size.width * 2).ceil();
      expect(image.image!.width, target);
      expect(image.image!.height, closeTo(target / 2, 1));
      expect(image.image!.width, lessThan(2048));
      expect(image.fit, BoxFit.cover);
      expect(tester.getSize(_thumbnail('large')), size);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'AFImage accepts raw local paths and escaped file URIs including literal hash and percent',
      (tester) async {
    for (final url in [jpeg.path, jpeg.uri.toString()]) {
      final file = MediaFilePB(id: 'local', name: 'real.JFIF', url: url);
      await tester
          .pumpWidget(_app('paper', _strip([file], const Size.square(40))));
      await _finishImages(tester);
      await _expectColor(tester, 'local', red: true);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'AFImage remains full-resolution by default and clips without saveLayer',
      (tester) async {
    await tester.pumpWidget(
      _app(
        'light',
        AFImage(
          url: large.path,
          uploadType: FileUploadTypePB.LocalFile,
          width: 40,
          height: 40,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    await _finishImages(tester);
    final raw = tester.widget<RawImage>(
      find.descendant(
        of: find.byType(AFImage),
        matching: find.byType(RawImage),
      ),
    );
    expect(raw.image!.width, 2048);
    expect(raw.image!.height, 1024);
    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(AFImage),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'AFImage forwards optional decode hints and fit to cloud and network loaders',
      (tester) async {
    // Inspect the stateless hand-off without mounting the disk cache or making
    // profile/backend reads. Real local decoding is covered above.
    await tester.pumpWidget(
      _app(
        'light',
        Builder(
          builder: (context) {
            for (final hints in [false, true]) {
              final cloud = AFImage(
                url: 'https://example.invalid/image',
                uploadType: FileUploadTypePB.CloudFile,
                userProfile: UserProfilePB(),
                fit: BoxFit.contain,
                cacheWidth: hints ? 80 : null,
                cacheHeight: hints ? 60 : null,
              ).build(context) as FlowyNetworkImage;
              expect(cloud.memCacheWidth, hints ? 80 : null);
              expect(cloud.memCacheHeight, hints ? 60 : null);
              expect(cloud.fit, BoxFit.contain);
              final network = AFImage(
                url: 'https://example.invalid/image',
                uploadType: FileUploadTypePB.NetworkFile,
                cacheWidth: hints ? 80 : null,
                fit: BoxFit.contain,
              ).build(context) as Image;
              expect(network.fit, BoxFit.contain);
              if (hints) {
                final provider = network.image as ResizeImage;
                expect(provider.width, 80);
                expect(provider.height, isNull);
              } else {
                expect(network.image, isA<NetworkImage>());
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'media viewer renders a legacy local file URI with full-resolution contain fit',
      (tester) async {
    final file = MediaFilePB(
      id: 'viewer',
      name: 'legacy.JFIF',
      url: jpeg.uri.toString(),
    );
    final provider = MediaFileImageProvider(files: [file]);
    await tester.pumpWidget(
      _app(
        'dark',
        Builder(builder: (context) => provider.renderImage(context, 0)),
      ),
    );
    await _finishImages(tester);
    final raw = tester.widget<RawImage>(
      find.descendant(
        of: find.byType(AFImage),
        matching: find.byType(RawImage),
      ),
    );
    expect(raw.image!.width, 16);
    expect(raw.image!.height, 8);
    expect(raw.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MemoryMediaController extends Fake implements MediaCellController {
  _MemoryMediaController(List<MediaFilePB> files)
      : _data = MediaCellDataPB(files: files);

  MediaCellDataPB _data;
  VoidCallback? _listener;

  @override
  String get viewId => 'test-media-view';
  @override
  String get rowId => 'test-media-row';
  @override
  String get fieldId => 'test-media-field';
  @override
  FieldInfo get fieldInfo => FieldInfo.initial(
        FieldPB(
          id: fieldId,
          name: 'Photos',
          fieldType: FieldType.Media,
          typeOptionData:
              MediaTypeOptionPB(hideFileNames: true).writeToBuffer(),
        ),
      );
  @override
  MediaCellDataPB getCellData({bool loadIfNotExist = true}) => _data;
  @override
  T getTypeOption<T>(TypeOptionParser parser) =>
      parser.fromBuffer(fieldInfo.field.typeOptionData) as T;
  @override
  VoidCallback? addListener({
    required void Function(MediaCellDataPB?) onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
  }) {
    _listener = () => onCellChanged(_data);
    return _listener;
  }

  @override
  void removeListener({
    required VoidCallback onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
    VoidCallback? onRowMetaChanged,
  }) {
    _listener = null;
  }

  void replaceFiles(List<MediaFilePB> files) {
    _data = MediaCellDataPB(files: files);
    _listener?.call();
  }

  @override
  Future<void> dispose() async => _listener = null;
}

Widget _rowSkin(
  DekstopRowDetailMediaCellSkin skin,
  MediaCellBloc bloc,
  CellContainerNotifier notifier,
  PopoverController popover,
  double width,
) =>
    SizedBox(
      width: width,
      child: Builder(
        builder: (context) => skin.build(context, notifier, popover, bloc),
      ),
    );

Widget _strip(List<MediaFilePB> files, Size size) => IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final file in files) MediaFileThumbnail(file: file, size: size),
        ],
      ),
    );

Finder _thumbnail(String id) => find.byWidgetPredicate(
      (widget) => widget is MediaFileThumbnail && widget.file.id == id,
    );
Finder _image(String id) =>
    find.descendant(of: _thumbnail(id), matching: find.byType(Image));
RawImage _raw(WidgetTester tester, String id) => tester.widget<RawImage>(
      find.descendant(of: _thumbnail(id), matching: find.byType(RawImage)),
    );

Future<void> _finishImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final images = tester
      .widgetList<Image>(
        find.descendant(
          of: find.byType(AFImage),
          matching: find.byType(Image),
        ),
      )
      .toList();
  var completed = 0;
  final listeners = <(ImageStream, ImageStreamListener)>[];
  for (final image in images) {
    var finished = false;
    void finish() {
      if (!finished) completed++;
      finished = true;
    }

    final stream = image.image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        finish();
      },
      onError: (Object error, StackTrace? stack) => finish(),
    );
    stream.addListener(listener);
    listeners.add((stream, listener));
  }
  try {
    // FileImage starts IO on the fake clock during build; each real IO turn
    // needs a pump to run the continuation that starts the next decode stage.
    for (var attempt = 0;
        completed < images.length && attempt < 200;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      completed,
      images.length,
      reason: 'Image streams must complete or report an error',
    );
  } finally {
    for (final entry in listeners) {
      entry.$1.removeListener(entry.$2);
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _expectColor(
  WidgetTester tester,
  String id, {
  required bool red,
}) async {
  final image = _raw(tester, id).image;
  expect(image, isNotNull, reason: '$id must have actual decoded pixels');
  final bytes = await tester.runAsync(() => image!.toByteData());
  final offset = ((image!.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  expect(bytes!.getUint8(offset + (red ? 0 : 2)), greaterThan(180));
  expect(bytes.getUint8(offset + (red ? 2 : 0)), lessThan(80));
}

Future<List<int>> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF143CDC), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Widget _app(String appearance, Widget child) => EasyLocalization(
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
          theme: DesktopAppearance().getThemeData(
            appearance == 'paper'
                ? AppTheme.builtins.firstWhere(
                    (theme) => theme.themeName == BuiltInTheme.paper,
                  )
                : AppTheme.fallback,
            appearance == 'dark' ? Brightness.dark : Brightness.light,
            'DM Sans',
            builtInCodeFontFamily,
          ),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );

// Synthetic 16x8 solid red JPEG, encoded with a standard JFIF header.
const _redJpeg =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAIABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDw+iiivxw/0AP/2Q==';
