import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

class MemoryOcrSource extends ImageEditorSource {
  MemoryOcrSource(String id, this.bytes, {this.read})
      : super(url: id, type: CustomImageType.local);

  final Uint8List bytes;
  final Future<Uint8List> Function()? read;
  int reads = 0;

  @override
  Future<Uint8List> readBytes() {
    reads++;
    return read?.call() ?? Future.value(bytes);
  }
}

class ControlledOcrService extends OcrService {
  final calls = <OcrTestCall>[];

  @override
  Future<OcrResult> recognizeBytes(
    Uint8List bytes, {
    required Size imageSize,
    OcrCancellationToken? cancellation,
    ValueChanged<String>? onEngineSelected,
  }) {
    final call =
        OcrTestCall(Uint8List.fromList(bytes), imageSize, cancellation);
    calls.add(call);
    onEngineSelected?.call('Test local OCR');
    return call.done.future;
  }

  void finishPending() {
    for (final call in calls) {
      if (!call.done.isCompleted) call.done.complete(OcrResult.empty);
    }
  }
}

class OcrTestCall {
  OcrTestCall(this.bytes, this.imageSize, this.cancellation);
  final Uint8List bytes;
  final Size imageSize;
  final OcrCancellationToken? cancellation;
  final done = Completer<OcrResult>();
}

class OcrTestClipboard {
  final writes = <String>[];
  Completer<void>? acknowledgement;
  Object? failure;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add((call.arguments as Map)['text'] as String);
        if (failure != null) throw failure!;
        await acknowledgement?.future;
      } else if (call.method == 'Clipboard.getData') {
        return {'text': writes.isEmpty ? '' : writes.last};
      } else if (call.method == 'Clipboard.hasStrings') {
        return {'value': writes.isNotEmpty};
      }
      return null;
    });
  }

  void release() {
    if (acknowledgement?.isCompleted == false) acknowledgement!.complete();
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

Widget ocrTestApp(
  Widget child, {
  String mode = 'light',
  bool reduceMotion = true,
  double textScale = 1,
  GlobalKey<NavigatorState>? navigatorKey,
  String fontFamily = 'Ahem',
  Map<String, dynamic>? translations,
}) {
  final theme = ocrTestTheme(mode, fontFamily: fontFamily);
  Widget app(BuildContext? localizationContext) => MaterialApp(
        navigatorKey: navigatorKey,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        locale: localizationContext?.locale,
        supportedLocales:
            localizationContext?.supportedLocales ?? const [Locale('en', 'US')],
        localizationsDelegates: localizationContext?.localizationDelegates,
        builder: (context, child) => AppFlowyTheme(
          data: theme.brightness == Brightness.dark
              ? AppFlowyDefaultTheme().dark()
              : AppFlowyDefaultTheme().light(),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
        home: Scaffold(body: child),
      );
  // Opt-in so the routing/disposal fixtures keep their original mount timing.
  if (translations == null) return app(null);
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    startLocale: const Locale('en', 'US'),
    fallbackLocale: const Locale('en', 'US'),
    path: 'assets/translations',
    saveLocale: false,
    assetLoader: _OcrTestTranslations(translations),
    child: Builder(builder: (context) => app(context)),
  );
}

ThemeData ocrTestTheme(String mode, {String fontFamily = 'Ahem'}) {
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  return DesktopAppearance()
      .getThemeData(
        mode == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        brightness,
        fontFamily,
        fontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
}

/// Preload the real English bundle in setUpAll, outside the widget fake clock.
Future<Map<String, dynamic>> loadOcrTestTranslations() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  return const TestBundleAssetLoader().load(
    'assets/translations',
    const Locale('en', 'US'),
  );
}

class _OcrTestTranslations extends AssetLoader {
  const _OcrTestTranslations(this.translations);
  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      // EasyLocalization uses Future.wait: keep delivery asynchronous.
      Future.value(translations);
}

Future<Uint8List> makeOcrTestPng({
  Color color = const Color(0xFFDFB986),
  void Function(Canvas canvas, Size size)? paint,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(color, BlendMode.src);
  paint?.call(canvas, const Size(320, 180));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 180);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> waitForOcrCalls(
  WidgetTester tester,
  ControlledOcrService service,
  int count,
) async {
  // Engine completions stay in the widget zone. Only the real Flutter image
  // codec gets IO turns; no timer-driven production search is fast-forwarded.
  for (var turn = 0; turn < 200 && service.calls.length < count; turn++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  expect(
    service.calls.length,
    count,
    reason: 'The bounded image decode must complete',
  );
}

Future<void> ocrChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump();
}

OcrResult ocrTestResult({String engine = 'Test local OCR'}) => OcrResult(
      engine: engine,
      lines: [
        OcrLine.fromWords(const [
          OcrWord(text: 'Hello', bounds: Rect.fromLTWH(.1, .15, .2, .15)),
          OcrWord(text: 'WORLD', bounds: Rect.fromLTWH(.5, .15, .25, .15)),
        ]),
        OcrLine.fromWords(const [
          OcrWord(text: 'hello', bounds: Rect.fromLTWH(.1, .6, .2, .15)),
          OcrWord(text: 'worldwide', bounds: Rect.fromLTWH(.5, .6, .35, .15)),
        ]),
      ],
    );
