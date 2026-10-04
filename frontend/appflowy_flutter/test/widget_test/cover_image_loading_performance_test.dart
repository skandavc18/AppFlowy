import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

const _a = 'https://example.invalid/cover-a.png';
const _b = 'https://example.invalid/cover-b.png';
const _imageKey = ValueKey('tested-cover');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FileInfo photo;
  late Uint8List png;
  late _ControlledCache cache;
  late bool loggingDisabled;

  setUpAll(() async {
    await initializeWorkspaceOverlayTests();
    loggingDisabled = Log.shared.disableLog;
    Log.shared.disableLog = true;
    temporary = await Directory.systemTemp.createTemp('cover_image_loading_');
    final file = const LocalFileSystem().file('${temporary.path}/red.png');
    // Actual small PNG; no live HTTP, native workspace, or global cache-manager
    // replacement. Fixtures are created only when this suite is executed.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 60);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      png = bytes!.buffer.asUint8List();
      await file.writeAsBytes(png);
    } finally {
      image.dispose();
      picture.dispose();
    }
    photo = FileInfo(file, FileSource.Cache, DateTime.utc(2100), _a);
  });

  setUp(() {
    cache = _ControlledCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    FlowyNetworkRetryCounter().reset();
  });
  tearDown(() async {
    await cache.close();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(FlowyNetworkRetryCounter().scopedUrlCount, 0);
  });
  tearDownAll(() async {
    Log.shared.disableLog = loggingDisabled;
    await temporary.delete(recursive: true);
  });

  Widget app(Widget child, {String theme = 'light', double dpr = 2}) =>
      workspaceOverlayTestApp(
        appearance: theme,
        textScale: 2,
        child: MediaQuery(
          data: MediaQueryData(
            devicePixelRatio: dpr,
            textScaler: const TextScaler.linear(2),
          ),
          child: FlowyImageCacheScope(manager: cache, child: child),
        ),
      );

  Widget network(
    String url, {
    Key? key,
    ValueChanged<bool>? callback,
    Set<int> codes = const {404},
    UserProfilePB? profile,
  }) =>
      FlowyNetworkImage(
        key: key ?? _imageKey,
        url: url,
        width: 120,
        height: 60,
        userProfilePB: profile,
        onImageLoaded: callback,
        retryErrorCodes: codes,
        retryDuration: const Duration(milliseconds: 20),
        maxRetries: 2,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidgetBuilder: (_, __, ___) => const SizedBox.shrink(),
      );

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets(
      'successful startup without callback performs no extra cache lookup',
      (tester) async {
    await tester.pumpWidget(app(network(_a)));
    await tester.pump();
    expect(cache.probes, isEmpty);
    cache.requests.single.stream.add(photo);
    await _expectRedFrame(tester);
    expect(cache.probes, isEmpty);
    expect(cache.requests.length, 1);
    await unmount(tester);
  });

  testWidgets(
      'same URL retry rebuilds only its subscribers and coalesces timers',
      (tester) async {
    final eviction = Completer<void>();
    cache.eviction = eviction.future;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            network(_a, key: const ValueKey('a1')),
            network(_a, key: const ValueKey('a2')),
            network(_b, key: const ValueKey('b')),
          ],
        ),
      ),
    );
    await tester.pump();
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    final error = HttpExceptionWithStatus(404, 'fixture missing');
    images[0].errorListener!(error);
    images[1].errorListener!(error);
    await tester.pump(const Duration(milliseconds: 20));
    expect(cache.removed.length, 1);
    eviction.complete();
    await tester.pump();
    // Completing eviction schedules setState after this frame's build phase.
    await tester.pump();
    final after = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(FlowyNetworkRetryCounter().getRetryCount(_a), 1);
    expect(after[0], isNot(same(images[0])));
    expect(after[1], isNot(same(images[1])));
    expect(after[2], same(images[2]), reason: 'Unrelated URL must not rebuild');
    await unmount(tester);
  });

  testWidgets('dispose cancels pending retry and late error callbacks',
      (tester) async {
    await tester.pumpWidget(app(network(_a)));
    await tester.pump();
    final image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    image.errorListener!(HttpExceptionWithStatus(404, 'fixture'));
    await unmount(tester);
    image.errorListener!(HttpExceptionWithStatus(404, 'late fixture'));
    await tester.pump(const Duration(seconds: 1));
    expect(cache.removed, isEmpty);
    expect(FlowyNetworkRetryCounter().values, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source switch discards old probe and retry, keeps current metadata callback',
      (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(app(network(_a, callback: results.add)));
    await tester.pump();
    final old =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    old.errorListener!(HttpExceptionWithStatus(404, 'fixture'));
    await tester.pumpWidget(app(network(_b, callback: results.add)));
    cache.probes[0].result.complete(photo);
    await tester.pump();
    expect(results, isEmpty);
    cache.probes[1].result.complete(null);
    await tester.pump();
    expect(results, [false]);
    await tester.pump(const Duration(seconds: 1));
    expect(cache.removed, isEmpty);
    expect(FlowyNetworkRetryCounter().getRetryCount(_b), 0);
    await unmount(tester);
  });

  testWidgets(
      'late callback after disposal is ignored; a new consumer gets cache metadata',
      (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(app(network(_a)));
    await tester.pumpWidget(app(network(_a, callback: results.add)));
    expect(cache.probes.length, 1);
    cache.probes.single.result.complete(photo);
    await tester.pump();
    expect(results, [true]);
    await tester.pumpWidget(app(network(_b, callback: results.add)));
    await unmount(tester);
    cache.probes.last.result.complete(photo);
    await tester.pump();
    expect(results, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry is bounded and only configured HTTP statuses qualify',
      (tester) async {
    await tester.pumpWidget(app(network(_a, codes: const {503})));
    await tester.pump();
    for (final error in [
      HttpExceptionWithStatus(404, 'missing'),
      HttpExceptionWithStatus(401, 'auth'),
      StateError('decode'),
    ]) {
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .errorListener!(error);
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(cache.removed, isEmpty);
    for (var attempt = 0; attempt < 3; attempt++) {
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .errorListener!(HttpExceptionWithStatus(503, 'temporary'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
    }
    expect(cache.removed.length, 2);
    expect(FlowyNetworkRetryCounter().getRetryCount(_a), 2);
    await unmount(tester);
  });

  testWidgets('same URL cache-scope replacement drops old metadata results',
      (tester) async {
    final results = <bool>[];
    final first = cache;
    await tester.pumpWidget(app(network(_a, callback: results.add)));
    await tester.pump();
    cache = _ControlledCache();
    await tester.pumpWidget(app(network(_a, callback: results.add)));
    first.probes.single.result.complete(photo);
    cache.probes.single.result.complete(null);
    await tester.pump();
    expect(results, [false]);
    await unmount(tester);
    await first.close();
  });

  testWidgets(
      'generic callers retain public memCache dimensions and fullscreen defaults',
      (tester) async {
    await tester.pumpWidget(
      app(
        const FlowyNetworkImage(
          url: _a,
          memCacheWidth: 128,
          memCacheHeight: 96,
        ),
      ),
    );
    await tester.pump();
    final sized =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect((sized.memCacheWidth, sized.memCacheHeight), (128, 96));
    await tester.pumpWidget(app(const FlowyNetworkImage(url: _b)));
    final full =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect((full.memCacheWidth, full.memCacheHeight), (null, null));
    await unmount(tester);
  });

  testWidgets(
      'same URL token mutation rejects obsolete callbacks and cache identity',
      (tester) async {
    const url = 'https://test.appflowy.cloud/cover.png';
    final profile = UserProfilePB(token: '{"access_token":"fixture-old"}');
    final results = <bool>[];
    await tester
        .pumpWidget(app(network(url, profile: profile, callback: results.add)));
    await tester.pump();
    final old =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    final firstRequest = cache.requests.single;
    old.errorListener!(HttpExceptionWithStatus(404, 'fixture'));
    profile.token = '{"access_token":"fixture-new"}';
    await tester
        .pumpWidget(app(network(url, profile: profile, callback: results.add)));
    await tester.pump();
    final current =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(current.cacheKey, isNot(old.cacheKey));
    expect(current.cacheKey, isNot(contains('fixture-new')));
    expect(current.httpHeaders, {'Authorization': 'Bearer fixture-new'});
    expect(firstRequest.headers, {'Authorization': 'Bearer fixture-old'});
    expect(cache.requests.length, 2);
    cache.probes[0].result.complete(
      FileInfo(photo.file, FileSource.Cache, DateTime.utc(2100), url),
    );
    await tester.pump();
    expect(results, isEmpty);
    cache.probes[1].result.complete(null);
    await tester.pump();
    expect(results, [false]);
    old.errorListener!(HttpExceptionWithStatus(404, 'obsolete'));
    await tester.pump(const Duration(seconds: 1));
    expect(cache.removed, isEmpty);
    await unmount(tester);
  });

  testWidgets(
      'custom cloud URL retains explicitly supplied profile authentication',
      (tester) async {
    await tester.pumpWidget(
      app(
        network(
          _a,
          profile: UserProfilePB(token: '{"access_token":"fixture-private"}'),
        ),
      ),
    );
    await tester.pump();
    expect(
      cache.requests.single.headers,
      {'Authorization': 'Bearer fixture-private'},
    );
    await unmount(tester);
  });

  testWidgets(
      'cloud cover without a token remains guarded and makes no request',
      (tester) async {
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 600,
          height: 200,
          child: ViewCoverImage(
            cover: PageStyleCover(
              type: PageStyleCoverImageType.customImage,
              value: 'https://test.appflowy.cloud/guarded.png',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FlowyNetworkImage), findsNothing);
    expect(cache.requests, isEmpty);
    await unmount(tester);
  });

  testWidgets(
      'actual failed cover stream retries transient HTTP, never permanent 404',
      (tester) async {
    await tester.pumpWidget(
      app(
        const FlowyNetworkImage(
          url: _a,
          width: 44,
          height: 32,
          coverDecodeSize: CoverImageDecodeSize(96, 64),
          retryErrorCodes: {503},
          retryDuration: Duration(milliseconds: 20),
        ),
      ),
    );
    await tester.pump();
    cache.requests.single.stream
        .addError(HttpExceptionWithStatus(503, 'fixture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(cache.requests.length, 2);
    cache.requests.last.stream.add(photo);
    await _expectRedFrame(tester);
    expect(FlowyNetworkRetryCounter().getRetryCount(_a), 1);
    await unmount(tester);
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 44,
          height: 32,
          child: ViewCoverImage(
            cover: PageStyleCover(
              type: PageStyleCoverImageType.customImage,
              value: _b,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    cache.requests.last.stream
        .addError(HttpExceptionWithStatus(404, 'fixture'));
    await tester.pump();
    final removals = cache.removed.length;
    await tester.pump(const Duration(seconds: 31));
    expect(cache.removed.length, removals);
    expect(FlowyNetworkRetryCounter().getRetryCount(_b), 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final theme in ['light', 'dark', 'paper']) {
    for (final fit in CoverImageFit.values) {
      testWidgets(
          '$theme/$fit 200% text: real cached cover frame has no placeholder fade',
          (tester) async {
        final appearance =
            CoverAppearance(fit: fit, position: CoverPosition.top);
        await tester.pumpWidget(
          app(
            PageCoverPresentation(
              appearance: appearance,
              alignment: appearance.alignment,
              child: const SizedBox(
                width: 44,
                height: 32,
                child: ViewCoverImage(
                  cover: PageStyleCover(
                    type: PageStyleCoverImageType.customImage,
                    value: _a,
                  ),
                ),
              ),
            ),
            theme: theme,
          ),
        );
        await tester.pump();
        final flowy =
            tester.widget<FlowyNetworkImage>(find.byType(FlowyNetworkImage));
        expect(flowy.progressIndicatorBuilder, isNull);
        expect(flowy.retryErrorCodes, isNot(contains(404)));
        expect(flowy.coverDecodeSize, const CoverImageDecodeSize(96, 64));
        expect(
          (flowy.fadeInDuration, flowy.fadeOutDuration),
          (Duration.zero, Duration.zero),
        );
        final context = tester.element(find.byType(ViewCoverImage));
        expect(PaperTheme.isEnabled(context), theme == 'paper');
        expect(MediaQuery.textScalerOf(context).scale(10), 20);
        cache.requests.single.stream.add(DownloadProgress(_a, 100, 20));
        await tester.pump();
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .every((image) => image.image == null),
          isTrue,
        );
        cache.requests.single.stream.add(photo);
        await _expectRedFrame(tester);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.fit, appearance.boxFit);
        expect(raw.alignment, Alignment.topCenter);
        expect(raw.image!.width / raw.image!.height, closeTo(2, .05));
        expect(
          find.descendant(
            of: find.byType(FlowyNetworkImage),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );
        expect(
          (raw.image!.width, raw.image!.height),
          fit == CoverImageFit.fit ? (96, 48) : (120, 60),
        );
        expect(cache.probes, isEmpty);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  }

  testWidgets(
      'static placeholder ignores chunks, then reveals the actual decoded frame',
      (tester) async {
    var placeholders = 0;
    await tester.pumpWidget(
      app(
        FlowyNetworkImage(
          url: _a,
          width: 44,
          height: 32,
          coverDecodeSize: const CoverImageDecodeSize(96, 64),
          placeholderBuilder: (_, __) {
            placeholders++;
            return const SizedBox(width: 44, height: 32);
          },
        ),
      ),
    );
    await tester.pump();
    final before = placeholders;
    for (var i = 1; i <= 5; i++) {
      cache.requests.single.stream.add(DownloadProgress(_a, 100, i * 10));
      await tester.pump();
    }
    expect(placeholders, before);
    cache.requests.single.stream.add(photo);
    await _expectRedFrame(tester);
    await unmount(tester);
  });

  testWidgets(
      'local cover decodes real bytes and keeps its key within a resize bucket',
      (tester) async {
    Widget cover(double width) => app(
          SizedBox(
            width: width,
            height: 32,
            child: ViewCoverImage(
              cover: PageStyleCover(
                type: PageStyleCoverImageType.localImage,
                value: photo.file.path,
              ),
            ),
          ),
        );
    await tester.pumpWidget(cover(44));
    await _expectRedFrame(tester);
    final before = tester.widget<Image>(find.byType(Image)).image;
    final state = tester.state(find.byType(Image));
    await tester.pumpWidget(cover(45));
    expect(tester.widget<Image>(find.byType(Image)).image, before);
    expect(tester.state(find.byType(Image)), same(state));
    await _expectRedFrame(tester);
    expect(cache.requests, isEmpty);
    expect(cache.probes, isEmpty);
    await unmount(tester);
  });

  testWidgets('tiny thumbnail does not inherit hero fit or position',
      (tester) async {
    await tester.pumpWidget(
      app(
        PageCoverPresentation(
          appearance: const CoverAppearance(fit: CoverImageFit.fit),
          alignment: Alignment.bottomCenter,
          child: ViewCoverThumbnail(
            cover: PageStyleCover(
              type: PageStyleCoverImageType.localImage,
              value: photo.file.path,
            ),
          ),
        ),
      ),
    );
    await _expectRedFrame(tester);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.fit, BoxFit.cover);
    expect(raw.alignment, Alignment.center);
    final provider =
        tester.widget<Image>(find.byType(Image)).image as CoverImageProvider;
    expect(provider.size, const CoverImageDecodeSize(96, 64));
    await unmount(tester);
  });

  testWidgets(
      'obsolete eviction completion cannot retry the replacement source',
      (tester) async {
    final eviction = Completer<void>();
    cache.eviction = eviction.future;
    await tester.pumpWidget(app(network(_a)));
    await tester.pump();
    tester
        .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .errorListener!(HttpExceptionWithStatus(404, 'fixture'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(cache.removed.length, 1);
    await tester.pumpWidget(app(network(_b)));
    eviction.complete();
    await tester.pump();
    expect(FlowyNetworkRetryCounter().getRetryCount(_b), 0);
    expect(cache.removed.length, 1);
    await unmount(tester);
  });

  testWidgets(
      'cache metadata failure reports false without aborting image loading',
      (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(app(network(_a, callback: results.add)));
    await tester.pump();
    cache.probes.single.result
        .completeError(StateError('fixture cache failure'));
    await tester.pump();
    expect(results, [false]);
    cache.requests.single.stream.add(photo);
    await _expectRedFrame(tester);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('asset cover uses real PNG bytes through the bounded decoder',
      (tester) async {
    await tester.pumpWidget(
      app(
        DefaultAssetBundle(
          bundle: _CoverAssetBundle(png),
          child: const SizedBox(
            width: 44,
            height: 32,
            child: ViewCoverImage(
              fit: BoxFit.contain,
              cover: PageStyleCover(
                type: PageStyleCoverImageType.builtInImage,
                value: 'n1',
              ),
            ),
          ),
        ),
      ),
    );
    await _expectRedFrame(tester);
    final provider =
        tester.widget<Image>(find.byType(Image)).image as CoverImageProvider;
    expect(
      provider.imageProvider,
      AssetImage(PageStyleCoverImageType.builtInImagePath('n1')),
    );
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect((raw.image!.width, raw.image!.height), (96, 48));
    expect(cache.requests, isEmpty);
    await unmount(tester);
  });
}

class _CoverAssetBundle extends CachingAssetBundle {
  _CoverAssetBundle(this.bytes);
  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) => key.endsWith('.png')
      ? Future.value(ByteData.sublistView(bytes))
      : rootBundle.load(key);
}

class _Probe {
  _Probe(this.key);
  final String key;
  final result = Completer<FileInfo?>();
}

class _Request {
  _Request(this.url, this.key, this.headers);
  final String url;
  final String? key;
  final Map<String, String>? headers;
  final stream = StreamController<FileResponse>();
}

class _ControlledCache extends Fake implements BaseCacheManager {
  final probes = <_Probe>[];
  final requests = <_Request>[];
  final removed = <String>[];
  Future<void>? eviction;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) {
    final probe = _Probe(key);
    probes.add(probe);
    return probe.result.future;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final request = _Request(url, key, headers);
    requests.add(request);
    return request.stream.stream;
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    await eviction;
  }

  Future<void> close() async {
    for (final probe in probes) {
      if (!probe.result.isCompleted) probe.result.complete(null);
    }
    for (final request in requests) {
      await request.stream.close();
    }
  }
}

Future<void> _expectRedFrame(WidgetTester tester) async {
  RawImage? frame;
  // Bounded real IO turns advance file/buffer/codec work; fake time never
  // advances by the old 500/1000ms fade, so readiness cannot hide behind it.
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
    final frames = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((raw) => raw.image != null);
    if (frames.isNotEmpty) {
      frame = frames.first;
      break;
    }
  }
  expect(
    frame,
    isNotNull,
    reason: 'A backdrop/URL is not a decoded cover frame',
  );
  final image = frame!.image!.clone();
  try {
    final pixels = await tester.runAsync(() => image.toByteData());
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    expect(pixels!.buffer.asUint8List(offset, 4), [255, 0, 0, 255]);
  } finally {
    image.dispose();
  }
}
