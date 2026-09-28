import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://example.invalid/native-cover.png';
const _other = 'https://example.invalid/other-cover.png';
const _frameDeadline = Duration(seconds: 2);

// Counts at Flutter's real codec boundary, then delegates unmodified. No fake
// codec/ImageInfo, engine changes, ScrollAware override or production hook.
class _CodecBinding extends AutomatedTestWidgetsFlutterBinding {
  final intrinsic = <(int, int)>[];
  int decodes = 0;

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(ui.ImmutableBuffer buffer,
      {ui.TargetImageSizeCallback? getTargetSize}) {
    decodes++;
    return super.instantiateImageCodecWithSize(buffer,
        getTargetSize: (width, height) {
      intrinsic.add((width, height));
      return getTargetSize?.call(width, height) ?? const ui.TargetImageSize();
    });
  }
}

void main() {
  final binding = _CodecBinding();
  late Directory temporary;
  late FileInfo landscape;
  late FileInfo blue;
  late _Cache cache;
  late bool disabledLog;

  setUpAll(() async {
    disabledLog = Log.shared.disableLog;
    Log.shared.disableLog = true;
    temporary = await Directory.systemTemp.createTemp('cover_native_quality_');
    landscape = await _png(temporary, 'landscape', 1200, 800);
    blue = await _png(temporary, 'blue', 1200, 800, solidBlue: true);
  });
  setUp(() {
    cache = _Cache();
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
    binding.intrinsic.clear();
    binding.decodes = 0;
    FlowyNetworkRetryCounter().reset();
  });
  tearDown(() async {
    await cache.close();
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
    expect(FlowyNetworkRetryCounter().scopedUrlCount, 0);
    expect(FlowyNetworkRetryCounter().values, isEmpty);
  });
  tearDownAll(() async {
    Log.shared.disableLog = disabledLog;
    await temporary.delete(recursive: true);
  });

  Widget host(Widget child) => MaterialApp(
        home: Center(child: FlowyImageCacheScope(manager: cache, child: child)),
      );
  Widget cover({
    String url = _url,
    UserProfilePB? profile,
    BoxFit fit = BoxFit.cover,
    CoverImageDecodeSize size = const CoverImageDecodeSize(640, 224),
    PlaceholderWidgetBuilder? placeholder,
  }) =>
      FlowyNetworkImage(
        key: const ValueKey('native-cover'),
        url: url,
        userProfilePB: profile,
        width: 300,
        height: 100,
        fit: fit,
        coverDecodeSize: size,
        placeholderBuilder: placeholder ?? (_, __) => const SizedBox.shrink(),
        retryErrorCodes: const {503},
        retryDuration: const Duration(milliseconds: 20),
        maxRetries: 2,
      );
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final fit in [BoxFit.contain, BoxFit.cover, BoxFit.fill]) {
    testWidgets(
        '$fit cold/disk-warm/memory-warm real frame operations and latency',
        (tester) async {
      var placeholders = 0;
      Widget content() => cover(
          fit: fit,
          placeholder: (_, __) {
            placeholders++;
            return const SizedBox(width: 300, height: 100);
          });
      final timings = <String, int>{};
      final operations = <String, (int, int, int)>{};
      for (final phase in ['cold', 'disk-warm', 'memory-warm']) {
        final requestsBefore = cache.requests.length;
        final decodesBefore = binding.decodes;
        placeholders = 0;
        await tester.pumpWidget(host(content()));
        await tester.pump();
        if (phase == 'cold') {
          expect(cache.requests.length, 1);
          final image = tester.widget<Image>(find.byType(Image));
          final before = placeholders;
          for (var chunk = 1; chunk <= 5; chunk++) {
            cache.requests.single.stream
                .add(DownloadProgress(_url, 100, chunk * 10));
            await tester.pump();
            expect(tester.widget<Image>(find.byType(Image)), same(image));
          }
          expect(placeholders, before);
          // Controlled transport delay, not an invented real-network measure.
          Timer(const Duration(milliseconds: 200),
              () => cache.deliver(landscape));
          await tester.pump(const Duration(milliseconds: 199));
          expect(binding.decodes, 0);
          expect(_frames(tester), isEmpty);
          await tester.pump(const Duration(milliseconds: 1));
        }
        final watch = Stopwatch()..start();
        final image = await _frame(tester);
        watch.stop();
        timings[phase] = watch.elapsedMicroseconds;
        expect(watch.elapsed, lessThanOrEqualTo(_frameDeadline));
        expect((image.width, image.height),
            fit == BoxFit.contain ? (336, 224) : (640, 427));
        await _quadrants(tester, image);
        expect(find.byType(FadeTransition), findsNothing);
        expect(cache.probes, 0);
        final expectedWork = phase == 'memory-warm' ? 0 : 1;
        expect(cache.requests.length - requestsBefore, expectedWork);
        expect(binding.decodes - decodesBefore, expectedWork);
        expect(placeholders, expectedWork);
        operations[phase] = (
          cache.requests.length - requestsBefore,
          binding.decodes - decodesBefore,
          placeholders
        );
        await unmount(tester);
        if (phase == 'cold') {
          binding.imageCache.clear();
          binding.imageCache.clearLiveImages();
        }
      }
      expect(binding.intrinsic, [(1200, 800), (1200, 800)]);
      // Labels and counts only: never headers, URLs or cache credentials.
      debugPrint('COVER_NATIVE $fit frame_us=$timings '
          'request_decode_placeholder=$operations synthetic_cold_ms=200 '
          'frame_deadline_ms=2000 chunks=5 chunk_image_rebuilds=0 fades=0');
    });
  }

  for (final spec in [
    ('portrait', 800, 1200, const CoverImageDecodeSize(640, 224), 640, 960),
    ('panorama-cap', 6000, 60, const CoverImageDecodeSize(640, 224), 4096, 41),
    ('portrait-cap', 60, 6000, const CoverImageDecodeSize(640, 224), 41, 4096),
    ('tiny', 2, 1, const CoverImageDecodeSize(640, 224), 2, 1),
  ]) {
    testWidgets('${spec.$1} real codec obeys intrinsic aspect and cap',
        (tester) async {
      final info = (await tester
          .runAsync(() => _png(temporary, spec.$1, spec.$2, spec.$3)))!;
      cache.ready = info;
      await tester.pumpWidget(host(cover(size: spec.$4)));
      final image = await _frame(tester);
      expect((image.width, image.height), (spec.$5, spec.$6));
      expect(binding.intrinsic, [(spec.$2, spec.$3)]);
      expect(binding.decodes, 1);
      debugPrint('COVER_NATIVE ${spec.$1} intrinsic=${spec.$2}x${spec.$3} '
          'decoded=${image.width}x${image.height}');
      await unmount(tester);
    });
  }

  testWidgets(
      'one-pixel bucket aliases reuse actual decoded image, boundary decodes once',
      (tester) async {
    cache.ready = landscape;
    CoverImageDecodeSize size(double width) =>
        CoverImageDecodeSize.fromConstraints(
            BoxConstraints.tightFor(width: width, height: 100), 2)!;
    await tester.pumpWidget(host(cover(size: size(301))));
    final original = (await _frame(tester)).clone();
    try {
      await tester.pumpWidget(host(cover(size: size(302))));
      expect((await _frame(tester)).isCloneOf(original), isTrue);
      expect(binding.decodes, 1);
      expect(cache.requests.length, 1);
      await tester.pumpWidget(host(cover(size: size(321))));
      await tester.pump();
      final changed = await _frame(tester);
      expect(changed.isCloneOf(original), isFalse);
      expect((changed.width, changed.height), (768, 512));
      expect(binding.decodes, 2);
      expect(cache.requests.length, 2);
    } finally {
      original.dispose();
      await unmount(tester);
    }
  });

  testWidgets(
      'native pending source, credentials and scoped-cache generations reject obsolete frames',
      (tester) async {
    final originalCache = cache;
    final profile = UserProfilePB(token: '{"access_token":"fixture-old"}');
    await tester.pumpWidget(host(cover(profile: profile)));
    await tester.pump();
    final old = cache.requests.single;
    profile.token = '{"access_token":"fixture-new"}';
    await tester.pumpWidget(host(cover(profile: profile)));
    await tester.pump();
    final newAuth = cache.requests.last;
    expect(newAuth.key, isNot(old.key));
    expect(newAuth.key, isNot(contains('fixture-new')));
    expect(old.headers, {'Authorization': 'Bearer fixture-old'});
    expect(newAuth.headers, {'Authorization': 'Bearer fixture-new'});
    await tester.pumpWidget(host(cover(url: _other, profile: profile)));
    await tester.pump();
    final oldSource = cache.requests.last;
    cache = _Cache();
    await tester.pumpWidget(host(cover(url: _other, profile: profile)));
    await tester.pump();
    expect(cache.requests.single.key, isNot(oldSource.key));
    expect(
        cache.requests.single.headers, {'Authorization': 'Bearer fixture-new'});
    old.stream.add(landscape);
    newAuth.stream.addError(HttpExceptionWithStatus(503, 'obsolete'));
    oldSource.stream.add(landscape);
    cache.deliver(blue);
    final image = await _frame(tester);
    await _pixel(tester, image, 0.25, 0.25, [0, 0, 255, 255]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(originalCache.removed, isEmpty);
    expect(cache.removed, isEmpty);
    expect(FlowyNetworkRetryCounter().getRetryCount(_other), 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
    // Old file/codec futures need real IO turns even after their Image owners
    // detached. Do not await their stream shutdown inside a frozen test clock.
    var closed = false;
    final closing = originalCache.close().then((_) => closed = true);
    final cleanup = Stopwatch()..start();
    while (!closed && cleanup.elapsed < _frameDeadline) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pump();
    }
    expect(closed, isTrue,
        reason: 'Old generation streams must finish within 2s');
    await closing;
  });

  testWidgets(
      'actual invalid PNG evicts failed decode and same URL can recover on remount',
      (tester) async {
    final corrupt =
        const LocalFileSystem().file('${temporary.path}/corrupt.png');
    await tester.runAsync(() => corrupt.writeAsString('not a PNG'));
    await tester.pumpWidget(host(cover()));
    await tester.pump();
    cache
        .deliver(FileInfo(corrupt, FileSource.Cache, DateTime.utc(2100), _url));
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final watch = Stopwatch()..start();
    while (binding.imageCache.statusForKey(key).pending &&
        watch.elapsed < _frameDeadline) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pump();
    }
    expect(binding.imageCache.statusForKey(key).untracked, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(cache.removed, isEmpty,
        reason: 'Decoder failures are not transient HTTP retries');
    expect(_frames(tester), isEmpty);
    await unmount(tester);
    cache.ready = landscape;
    await tester.pumpWidget(host(cover()));
    await _quadrants(tester, await _frame(tester));
    expect(cache.requests.length, 2);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'same URL retry shares eviction; other URL stays idle; last-owner reuse resets limit',
      (tester) async {
    final eviction = Completer<void>();
    cache.eviction = eviction.future;
    Widget pair() => host(Column(children: [
          // Distinct owner keys, otherwise identical native cover providers.
          KeyedSubtree(key: const ValueKey('a'), child: cover()),
          KeyedSubtree(key: const ValueKey('b'), child: cover()),
          KeyedSubtree(key: const ValueKey('c'), child: cover(url: _other)),
        ]));
    await tester.pumpWidget(pair());
    await tester.pump();
    expect(cache.requests.length, 2);
    final unrelated = tester.widgetList<Image>(find.byType(Image)).last;
    cache.requests.first.stream
        .addError(HttpExceptionWithStatus(503, 'temporary'));
    await tester.pump();
    // Stream error delivery sets Image's error state; the following build
    // invokes its errorBuilder and starts the production retry timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 19));
    expect(cache.removed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.removed.length, 1);
    eviction.complete();
    await tester.pump();
    await tester.pump();
    expect(FlowyNetworkRetryCounter().getRetryCount(_url), 1);
    expect(FlowyNetworkRetryCounter().getRetryCount(_other), 0);
    expect(tester.widgetList<Image>(find.byType(Image)).last, same(unrelated));
    expect(cache.requests.length, 3);
    await unmount(tester);
    expect(FlowyNetworkRetryCounter().values, isEmpty);
    cache.eviction = null;
    await tester.pumpWidget(host(cover()));
    await tester.pump();
    expect(FlowyNetworkRetryCounter().getRetryCount(_url), 0);
    cache.requests.last.stream
        .addError(HttpExceptionWithStatus(503, 'new owner'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(cache.removed.length, 2,
        reason: 'Completed eviction must not poison a later owner');
    expect(FlowyNetworkRetryCounter().getRetryCount(_url), 1);
    await unmount(tester);
  });
}

class _Request {
  _Request(this.key, this.headers);
  final String? key;
  final Map<String, String>? headers;
  final stream = StreamController<FileResponse>();
}

// Only transport/cache metadata is simulated. FileInfo points at genuine
// temporary PNG files read by CachedNetworkImageProvider and the native codec.
class _Cache extends Fake implements BaseCacheManager {
  final requests = <_Request>[];
  final removed = <String>[];
  int probes = 0;
  FileInfo? ready;
  Future<void>? eviction;

  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    probes++;
    return ready;
  }

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    final request = _Request(key, headers);
    requests.add(request);
    if (ready != null) request.stream.add(ready!);
    return request.stream.stream;
  }

  void deliver(FileInfo info) {
    ready = info;
    requests.last.stream.add(info);
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    ready = null;
    await eviction;
  }

  Future<void> close() async {
    for (final request in requests) {
      await request.stream.close();
    }
  }
}

Future<FileInfo> _png(Directory directory, String name, int width, int height,
    {bool solidBlue = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = solidBlue
      ? List<Color>.filled(4, const Color(0xFF0000FF))
      : const [
          Color(0xFFFF0000),
          Color(0xFF00FF00),
          Color(0xFF0000FF),
          Color(0xFFFFFFFF)
        ];
  for (var i = 0; i < 4; i++) {
    canvas.drawRect(
        Rect.fromLTWH(
            (i % 2) * width / 2, (i ~/ 2) * height / 2, width / 2, height / 2),
        Paint()..color = colors[i]);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = const LocalFileSystem().file('${directory.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    return FileInfo(file, FileSource.Cache, DateTime.utc(2100), _url);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Iterable<ui.Image> _frames(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .map((raw) => raw.image)
    .whereType<ui.Image>();

Future<ui.Image> _frame(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  while (_frames(tester).isEmpty && watch.elapsed < _frameDeadline) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    await tester.pump();
  }
  expect(_frames(tester), hasLength(1),
      reason: 'Require a native decoded frame within 2s, not a placeholder');
  return _frames(tester).single;
}

Future<void> _pixel(WidgetTester tester, ui.Image image, double x, double y,
    List<int> rgba) async {
  final bytes = (await tester.runAsync(() => image.toByteData()))!;
  final offset =
      ((image.height * y).floor() * image.width + (image.width * x).floor()) *
          4;
  expect(bytes.buffer.asUint8List(offset, 4), rgba);
}

Future<void> _quadrants(WidgetTester tester, ui.Image image) async {
  await _pixel(tester, image, .25, .25, [255, 0, 0, 255]);
  await _pixel(tester, image, .75, .25, [0, 255, 0, 255]);
  await _pixel(tester, image, .25, .75, [0, 0, 255, 255]);
  await _pixel(tester, image, .75, .75, [255, 255, 255, 255]);
}
