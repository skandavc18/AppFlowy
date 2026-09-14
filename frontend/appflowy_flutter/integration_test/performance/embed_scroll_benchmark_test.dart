import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/csv_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/deferred_page_embed.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart' show FlowyOverlay;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart' show PdfViewer;
import 'package:window_manager/window_manager.dart';

const _windowSize = Size(1280, 900);
const _surfaceSize = Size(1280, 800);
const _previewSize = Size(740, 400);
const _blockCount = 24;
const _csvRows = 120;
const _csvColumns = 6;
const _panUpdates = 260;
const _panDelta = 44.0;
const _panInterval = Duration(microseconds: 8333);
const _stationaryTime = Duration(seconds: 3);
const _settleInterval = Duration(milliseconds: 8);
const _settleTimeout = Duration(seconds: 90);
const _watchTimeout = Duration(seconds: 120);
const _modeOrder = [false, true, true, false];
const _reportKeys = ['eager_1', 'deferred_1', 'deferred_2', 'eager_2'];
const _pacingFirst = bool.fromEnvironment('PERF_PACING_FIRST');

typedef _PreviewFile = ({File file, String name, FilePreviewKind kind});

// Native profile fixture only: no normal integration/app startup helpers,
// SharedPreferences, backend initialization, or live workspace changes.
// The existing large_page_performance_driver.dart writes the binding's JSON;
// PERF_RUN defaults to embed_mount. Frame timings are not a hover-bar metric.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native profile: scrolling past real CSV and PDF preview bodies',
    (tester) async {
      expect(
        !kIsWeb && kProfileMode && Platform.isWindows,
        isTrue,
        reason: 'Use the native Windows profile integration runner and the '
            'existing large-page performance driver, not a mocked widget test.',
      );
      final previousFramePolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      addTearDown(() async {
        binding.framePolicy = previousFramePolicy;
        await binding.setSurfaceSize(null);
      });
      await windowManager.ensureInitialized();
      await windowManager.setSize(_windowSize);
      await windowManager.show();
      await binding.setSurfaceSize(_surfaceSize);

      final samples = <String, dynamic>{};
      final distances = <String, double>{};
      binding.reportData = {
        'run': const String.fromEnvironment(
          'PERF_RUN',
          defaultValue: 'embed_mount',
        ),
        'mode': 'profile',
        'refresh_rate_hz': tester.view.display.refreshRate,
        'device_pixel_ratio': tester.view.devicePixelRatio,
        'fixture': '24 file-typed blocks with fixed 740x400 preview bodies, '
            'alternating real FilePreview CSV (120 rows including header, '
            '6 columns) and generated one-page native pdfrx PDF; '
            'preview-body frame/lifecycle benchmark, NOT FileBlockComponent '
            'or its backend-dependent CSV OfficeDocumentView routing; '
            'CustomPage, all default editor services, PremiumScrollScope, '
            'FlowyOverlay, desktop light theme; identical headers and padding',
        'cache_policy': 'Fresh EditorState and distinct local file paths per '
            'body/run; identical generated content; no OS cache purge.',
        'paint_counter': 'Paint visits at the mounted FilePreview boundary, '
            'not native PDF raster completions or hover-bar visibility.',
        'surface_size': [_surfaceSize.width, _surfaceSize.height],
        'preview_size': [_previewSize.width, _previewSize.height],
        'mode_order': _modeOrder,
        'pacing_first': _pacingFirst,
        'movement_report_keys': _reportKeys,
        'input': {
          'updates': _panUpdates,
          'delta_y': -_panDelta,
          'interval_us': _panInterval.inMicroseconds,
          'direct_scale':
              const PremiumScrollPhysicsConfig().desktopDirectManipulationScale,
          'expected_distance_before_gesture_slop': _expectedDistance,
          'clicked_embeds': false,
        },
        'samples': samples,
        'page_scroll_distances': distances,
      };

      final root = await Directory.systemTemp.createTemp('appflowy_embed_mount_');
      try {
        Rect? baselineViewport;
        double? baselineDistance;
        for (var index = 0; index < _modeOrder.length; index++) {
          final key = _reportKeys[index];
          // File generation and disk writes never enter a measured phase.
          final directory = await Directory.fromUri(
            root.uri.resolve('$key/'),
          ).create();
          final files = await _writeFixture(directory);
          final result = await _runSample(
            tester,
            binding,
            files,
            defer: _modeOrder[index],
            reportKey: key,
            samples: samples,
          );
          distances[key] = result.distance;
          if (baselineViewport != null) {
            expect(result.viewport, baselineViewport);
            expect(
              result.distance,
              closeTo(baselineDistance!, 0.1),
              reason: 'Every mode must move the same page distance; an inner '
                  'preview consuming input would invalidate the comparison.',
            );
          } else {
            baselineViewport = result.viewport;
            baselineDistance = result.distance;
          }
        }
      } finally {
        // Keep every run's files until all viewers have left the tree. Native
        // PDF disposal can finish asynchronously after Flutter State.dispose.
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainNativeDisposals(tester);
        await _deleteFixture(tester, root);
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

double get _expectedDistance => _panUpdates *
    _panDelta *
    const PremiumScrollPhysicsConfig().desktopDirectManipulationScale;

Future<({double distance, Rect viewport})> _runSample(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  List<_PreviewFile> files, {
  required bool defer,
  required String reportKey,
  required Map<String, dynamic> samples,
}) async {
  final editor = EditorState(document: _document(files));
  final scroll = EditorScrollController(editorState: editor);
  final counts = _Counts();
  final framePacing = switch (reportKey) {
    'deferred_1' => _pacingFirst,
    'deferred_2' => !_pacingFirst,
    _ => true,
  };
  final sample = <String, dynamic>{
    'deferred': defer,
    'frame_pacing': framePacing,
  };
  samples[reportKey] = sample;
  TestGesture? mouse;
  _TrackpadPan? pan;
  try {
    await binding.watchPerformance(
      () async {
        await tester.pumpWidget(
          _app(editor, scroll, files, counts, defer, framePacing),
        );
        await _settlePreviews(tester, counts, minimumMounts: 3);
      },
      reportKey: '${reportKey}_mount',
    ).timeout(_watchTimeout);

    final viewport = _checkGeometry(counts, defer: defer);
    final firstFrame = _frameRects(counts)[0]!;
    final point = Offset(viewport.center.dx - 20, viewport.center.dy);
    expect(firstFrame.contains(point), isTrue);
    sample['pointer_position'] = [point.dx, point.dy];
    sample['viewport_bounds'] = [
      viewport.left,
      viewport.top,
      viewport.width,
      viewport.height,
    ];

    // Hover inside the real preview, not the page margin or a resize handle.
    // No click/focus activation: the production file gate must give the page
    // ownership even when the native PDF or CSV has its own scroll surface.
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: point);
    await mouse.moveTo(point);
    await _settlePreviews(tester, counts, minimumMounts: 3);
    final pagePosition = Scrollable.of(
      counts.frameKeys[0].currentContext!,
    ).position;
    expect(
      pagePosition.physics.applyPhysicsToUserOffset(pagePosition, 100),
      closeTo(100 * const PremiumScrollPhysicsConfig().desktopDirectManipulationScale, 0.001),
      reason: 'FlowyOverlay must retain the production premium scroll policy.',
    );
    expect(counts.csvMounts, greaterThan(0));
    expect(counts.pdfMounts, greaterThan(0));

    final gesture = _TrackpadPan(tester, point);
    pan = gesture;
    late Map<String, int> initial;
    late Map<String, int> afterScroll;
    late double startOffset;
    late double afterScrollOffset;
    await binding.watchPerformance(
      () async {
        // Scalar snapshots only; no tree scans, file generation, or artificial
        // CPU work in the movement sample.
        initial = counts.snapshot();
        startOffset = scroll.offsetNotifier.value;
        await gesture.start();
        await gesture.update();
        afterScroll = counts.snapshot();
        afterScrollOffset = scroll.offsetNotifier.value;
      },
      reportKey: reportKey,
    ).timeout(_watchTimeout);

    // watchPerformance itself waits for batched frame timings. Do NOT end the
    // pan in its movement callback: that wait must not admit pending previews.
    final beforeIdle = counts.snapshot();
    final beforeIdleOffset = scroll.offsetNotifier.value;
    sample
      ..['initial'] = initial
      ..['after_scroll'] = afterScroll
      ..['before_idle'] = beforeIdle;
    expect(pagePosition.isScrollingNotifier.value, isTrue);
    expect(_checkGeometry(counts, defer: defer), viewport);
    expect(startOffset, closeTo(0, 0.1));
    expect(beforeIdleOffset, closeTo(afterScrollOffset, 0.1));

    final movementMounts =
        afterScroll['total_mounts']! - initial['total_mounts']!;
    final mountsThroughRecorderWait =
        beforeIdle['total_mounts']! - initial['total_mounts']!;
    sample
      ..['movement_new_mounts'] = movementMounts
      ..['new_mounts_through_recorder_wait'] = mountsThroughRecorderWait;
    if (defer) {
      expect(movementMounts, 0);
      expect(
        mountsThroughRecorderWait,
        0,
        reason: 'Pending bodies must stay unmounted until the pan ends, '
            'including the recorder\'s frame-timing delivery wait.',
      );
    } else {
      expect(movementMounts, greaterThan(0));
      expect(afterScroll['body_paints']!, greaterThan(initial['body_paints']!));
    }

    await binding.watchPerformance(
      () async {
        // Keep the pan open through this recorder's pre-sample flush too, so
        // the first idle admissions are measured, not warmed ahead of it.
        await gesture.end();
        await _settlePreviews(
          tester,
          counts,
          minimumMounts: beforeIdle['total_mounts']! + (defer ? 1 : 0),
        );
      },
      reportKey: '${reportKey}_idle',
    ).timeout(_watchTimeout);

    final afterIdle = counts.snapshot();
    final finalOffset = scroll.offsetNotifier.value;
    final distance = finalOffset - startOffset;
    sample
      ..['after_idle'] = afterIdle
      ..['idle_new_mounts'] =
          afterIdle['total_mounts']! - beforeIdle['total_mounts']!
      ..['page_offsets'] = {
        'initial': startOffset,
        'after_scroll': afterScrollOffset,
        'before_idle': beforeIdleOffset,
        'after_idle': finalOffset,
      }
      ..['page_scroll_distance'] = distance;
    expect(pagePosition.isScrollingNotifier.value, isFalse);
    expect(finalOffset, closeTo(beforeIdleOffset, 0.1));
    expect(_checkGeometry(counts, defer: defer), viewport);
    expect(
      distance,
      closeTo(_expectedDistance, _panDelta),
        reason: 'Use the configured direct gain, allow gesture-start slop, '
          'and compare modes within 0.1px.',
    );
    if (defer) {
      expect(afterIdle['total_mounts']!, greaterThan(beforeIdle['total_mounts']!));
    }
    for (final key in [reportKey, '${reportKey}_mount', '${reportKey}_idle']) {
      final timings = binding.reportData![key] as Map<String, dynamic>;
      expect(timings['frame_count'], greaterThan(0));
    }
    if (defer) {
      sample['kinetic_coast'] = await _checkNativeCoast(
        tester,
        binding,
        pagePosition,
        point,
        counts,
        reportKey: '${reportKey}_coast',
      );
      sample['native_cadence'] = await _checkNativeCadence(
        binding,
        pagePosition,
        reportKey: '${reportKey}_native_cadence',
      );
      await _settlePreviews(tester, counts, minimumMounts: counts.totalMounts);
      sample['coarse_trackpad_cadence'] = await _checkCoarseTrackpadCadence(
        tester,
        binding,
        pagePosition,
        point,
        counts,
        reportKey: '${reportKey}_coarse_trackpad',
      );
      await _settlePreviews(tester, counts, minimumMounts: counts.totalMounts);
    }
    return (distance: distance, viewport: viewport);
  } finally {
    try {
      // Also end a partially delivered pan if a timeout/assertion interrupts
      // either recording. end() is idempotent after a successful idle phase.
      await pan?.end();
      await mouse?.removePointer();
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainNativeDisposals(tester);
        expect(counts.liveBodies, isEmpty);
      } finally {
        scroll.dispose();
        editor.dispose();
      }
    }
  }
}

// No tester.pump(), timer-driven scroll updates or fake frame timestamps in the
// measured interval. The real engine vsync drives ScrollPosition's animation.
// Raster completion is not physical monitor presentation; report it honestly.
Future<Map<String, dynamic>> _checkNativeCadence(
  IntegrationTestWidgetsFlutterBinding binding,
  ScrollPosition position, {
  required String reportKey,
}) async {
  final frames = <Map<String, num>>[];
  final timings = <ui.FrameTiming>[];
  var recording = false;
  void record(Duration _) {
    if (!recording) return;
    frames.add({
      'frame_us': binding.currentSystemFrameTimeStamp.inMicroseconds,
      'pixels': position.pixels,
    });
    binding.addPostFrameCallback(record);
  }

  void onTimings(List<ui.FrameTiming> batch) => timings.addAll(batch);
  binding.addTimingsCallback(onTimings);
  try {
    await binding.watchPerformance(
      () async {
        final start = position.pixels;
        final end = start - 1200;
        expect(end, greaterThan(position.minScrollExtent));
        expect(end, lessThan(position.maxScrollExtent));
        recording = true;
        binding.addPostFrameCallback(record);
        try {
          await position.animateTo(
            end,
            duration: const Duration(seconds: 3),
            curve: Curves.linear,
          ).timeout(const Duration(seconds: 10));
          await binding.endOfFrame;
        } finally {
          recording = false;
        }
        expect(position.pixels, closeTo(end, 0.1));
      },
      reportKey: reportKey,
    ).timeout(_watchTimeout);
  } finally {
    recording = false;
    binding.removeTimingsCallback(onTimings);
  }
  expect(frames.length, greaterThan(10));
  final first = frames.first['frame_us']!.toInt();
  final last = frames.last['frame_us']!.toInt();
  final visibleTimings = timings.where((timing) {
    final vsync = timing.timestampInMicroseconds(ui.FramePhase.vsyncStart);
    return vsync >= first && vsync <= last;
  }).toList();
  final intervals = [
    for (var i = 1; i < frames.length; i++)
      frames[i]['frame_us']! - frames[i - 1]['frame_us']!,
  ];
  final changedFrames = [
    for (var i = 1; i < frames.length; i++)
      if (frames[i]['pixels'] != frames[i - 1]['pixels']) frames[i],
  ];
  final sorted = intervals.map((value) => value.toDouble()).toList()..sort();
  double percentile(double percent) =>
      sorted[(percent * (sorted.length - 1)).round()] / 1000;
  return {
    'scope': 'Native engine callbacks and raster completions during a 3-second '
        '1200px continuous page animation, not pump cadence or physical presents.',
    'callbacks': frames.length,
    'changed_offsets': changedFrames.length,
    'duration_ms': (last - first) / 1000,
    'callback_hz': intervals.length * 1e6 / (last - first),
    'changed_offset_hz': changedFrames.length * 1e6 / (last - first),
    'interval_p50_ms': percentile(0.5),
    'interval_p90_ms': percentile(0.9),
    'interval_p99_ms': percentile(0.99),
    'frames': frames,
    'frame_timings': [
      for (final timing in visibleTimings)
        {
          'vsync_us': timing.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          'build_start_us': timing.timestampInMicroseconds(ui.FramePhase.buildStart),
          'raster_finish_us': timing.timestampInMicroseconds(ui.FramePhase.rasterFinish),
          'build_us': timing.buildDuration.inMicroseconds,
          'raster_us': timing.rasterDuration.inMicroseconds,
        },
    ],
  };
}

Future<Map<String, dynamic>> _checkCoarseTrackpadCadence(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  ScrollPosition position,
  Offset point,
  _Counts counts, {
  required String reportKey,
}) async {
  const updates = 150;
  const interval = Duration(microseconds: 16667);
  const delta = 12.0;
  final frames = <Map<String, num>>[];
  final packets = <int>[];
  var recording = false;
  var active = false;
  void record(Duration _) {
    if (!recording) return;
    frames.add({
      'frame_us': binding.currentSystemFrameTimeStamp.inMicroseconds,
      'pixels': position.pixels,
    });
    binding.addPostFrameCallback(record);
  }

  final result = <String, dynamic>{};
  try {
    await binding.watchPerformance(
      () async {
        final start = position.pixels;
        final mounts = counts.totalMounts;
        final clock = Stopwatch()..start();
        active = true;
        recording = true;
        binding.addPostFrameCallback(record);
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(pointer: 97, device: 97, position: point),
        );
        for (var step = 1; step <= updates; step++) {
          final wait = interval * step - clock.elapsed;
          if (wait > Duration.zero) await Future<void>.delayed(wait);
          final now = clock.elapsed;
          packets.add(now.inMicroseconds);
          await tester.sendEventToBinding(
            PointerPanZoomUpdateEvent(
              pointer: 97,
              device: 97,
              position: point,
              pan: Offset(0, delta * step),
              panDelta: const Offset(0, delta),
              timeStamp: now,
            ),
          );
        }
        // Let the final confirmed packet reach its endpoint; then release
        // with a real event-time pause so no fling contaminates drag cadence.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(
            pointer: 97,
            device: 97,
            position: point,
            timeStamp: clock.elapsed,
          ),
        );
        active = false;
        recording = false;
        final distance = start - position.pixels;
        expect(
          distance,
          closeTo(updates * delta * const PremiumScrollPhysicsConfig().desktopDirectManipulationScale, 0.1),
        );
        expect(counts.totalMounts, mounts);
        expect(position.isScrollingNotifier.value, isFalse);
        result['distance'] = distance;
      },
      reportKey: reportKey,
    ).timeout(_watchTimeout);
  } finally {
    recording = false;
    if (active) {
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 97, device: 97, position: point),
      );
    }
  }
  final changed = [
    for (var i = 1; i < frames.length; i++)
      if (frames[i]['pixels'] != frames[i - 1]['pixels']) frames[i],
  ];
  expect(changed.length, greaterThan(10));
  final duration = changed.last['frame_us']! - changed.first['frame_us']!;
  return result
    ..['scope'] = 'Real 60Hz target input timing, no tester.pump during drag; '
        'counts engine frames whose actual scroll offset changed, not physical presents.'
    ..['input_packets'] = packets.length
    ..['input_hz'] = (packets.length - 1) * 1e6 / (packets.last - packets.first)
    ..['changed_offset_frames'] = changed.length
    ..['changed_offset_hz'] = (changed.length - 1) * 1e6 / duration
    ..['frames'] = frames
    ..['packet_times_us'] = packets;
}

// Unlike the held-pan mount comparison above, this phase deliberately releases
// a moving trackpad gesture. It verifies deceleration over real native previews
// and separately records post-release travel; it must not change the held-pan
// movement result used by the original eager/deferred comparison.
Future<Map<String, dynamic>> _checkNativeCoast(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  ScrollPosition position,
  Offset point,
  _Counts counts, {
  required String reportKey,
}) async {
  const updates = 24;
  const delta = 28.0;
  const config = PremiumScrollPhysicsConfig();
  final expectedVelocity = delta /
      (_panInterval.inMicroseconds / Duration.microsecondsPerSecond) *
      config.desktopDirectManipulationScale;
  final result = <String, dynamic>{
    'expected_release_velocity': expectedVelocity,
    'expected_direct_distance': updates * delta * config.desktopDirectManipulationScale,
    'maximum_coast_distance': expectedVelocity / config.desktopCoastFriction,
    'timing_scope': 'Input and coasting plus recorder delivery/idle load frames; '
        'not a guarantee of native frame rate on every user document.',
  };
  var active = false;
  try {
    await binding.watchPerformance(
      () async {
        final mounts = counts.totalMounts;
        final start = position.pixels;
        active = true;
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(pointer: 96, device: 96, position: point),
        );
        for (var step = 1; step <= updates; step++) {
          await tester.sendEventToBinding(
            PointerPanZoomUpdateEvent(
              pointer: 96,
              device: 96,
              position: point,
              pan: Offset(0, -delta * step),
              panDelta: const Offset(0, -delta),
              timeStamp: _panInterval * step,
            ),
          );
          await tester.pump(_panInterval);
        }
        final releasedAt = position.pixels;
        expect(
          releasedAt - start,
          closeTo(updates * delta * config.desktopDirectManipulationScale, 0.1),
        );
        expect(
          position.maxScrollExtent - releasedAt,
          greaterThan(expectedVelocity / config.desktopCoastFriction + 100),
          reason: 'Measure free coasting, not a boundary spring.',
        );
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(
            pointer: 96,
            device: 96,
            position: point,
            timeStamp: _panInterval * updates + const Duration(milliseconds: 1),
          ),
        );
        active = false;
        var previousVelocity = expectedVelocity;
        var previousOffset = releasedAt;
        var observedCoast = false;
        final trace = <Map<String, double>>[];
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (position.isScrollingNotifier.value) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('The native trackpad coast did not stop.');
          }
          await tester.pump(_panInterval);
          // Read-only test probe of the real ScrollActivity, not a second
          // simulation advancing the page or a per-frame tree traversal.
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          final velocity = position.activity?.velocity ?? 0;
          final offset = position.pixels;
          expect(offset, greaterThanOrEqualTo(previousOffset - 0.1));
          expect(velocity, inInclusiveRange(0, previousVelocity + 0.1));
          if (velocity > 0) {
            observedCoast = true;
            previousVelocity = velocity;
          }
          previousOffset = offset;
          trace.add({'pixels': offset, 'velocity': velocity});
        }
        final distance = position.pixels - releasedAt;
        expect(observedCoast, isTrue);
        expect(distance, greaterThan(100));
        expect(distance, lessThanOrEqualTo(expectedVelocity / config.desktopCoastFriction + 0.1));
        expect(counts.totalMounts, mounts);
        result
          ..['direct_distance'] = releasedAt - start
          ..['coast_distance'] = distance
          ..['new_bodies_during_input_and_coast'] = counts.totalMounts - mounts
          ..['trajectory'] = trace;
      },
      reportKey: reportKey,
    ).timeout(_watchTimeout);
    // Any bodies admitted after the coast belong to the idle phase. Finish
    // their native work outside the motion assertions before changing mode.
    await _settlePreviews(tester, counts, minimumMounts: counts.totalMounts);
    return result;
  } finally {
    if (active) {
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: 96,
          device: 96,
          position: point,
          timeStamp: _panInterval * updates + const Duration(milliseconds: 1),
        ),
      );
    }
  }
}

Document _document(List<_PreviewFile> files) => Document(
      root: pageNode(
        children: [
          for (var index = 0; index < files.length; index++)
            Node(
              type: FileBlockKeys.type,
              attributes: {
                'fixture_index': index,
                'name': files[index].name,
                'width': _previewSize.width,
                'height': _previewSize.height,
              },
            ),
        ],
      ),
    );

Widget _app(
  EditorState editor,
  EditorScrollController scroll,
  List<_PreviewFile> files,
  _Counts counts,
  bool defer,
  bool framePacing,
) =>
    MaterialApp(
      theme: DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: PremiumScrollScope(
          enabled: true,
          config: PremiumScrollPhysicsConfig(desktopFramePacing: framePacing),
          child: FlowyOverlay(
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: AppFlowyEditor(
                  key: counts.editorKey,
                  editorState: editor,
                  editorScrollController: scroll,
                  editorStyle: const EditorStyle.desktop(
                    maxWidth: 1000,
                    padding: EdgeInsets.symmetric(horizontal: 80),
                  ),
                  // Intentionally omit service overrides: all defaults stay on.
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                    FileBlockKeys.type: _PreviewBlockBuilder(files, counts),
                  },
                  contextMenuItems: const [],
                  blockWrapper: (_, {required node, required child}) {
                    // CustomPage adds its enabled:true marker OUTSIDE this
                    // wrapper. The nearest marker wins at ResizableMedia.child,
                    // without a production flag or a second page load scope.
                    return PageEmbedPreviewScope(enabled: defer, child: child);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

class _PreviewBlockBuilder extends BlockComponentBuilder {
  _PreviewBlockBuilder(this.files, this.counts);

  final List<_PreviewFile> files;
  final _Counts counts;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final index = node.attributes['fixture_index'] as int;
    return _PreviewBlock(
      key: node.key,
      node: node,
      index: index,
      source: files[index],
      counts: counts,
    );
  }
}

class _PreviewBlock extends BlockComponentStatelessWidget {
  const _PreviewBlock({
    super.key,
    required super.node,
    required this.index,
    required this.source,
    required this.counts,
  }) : super(configuration: const BlockComponentConfiguration());

  final int index;
  final _PreviewFile source;
  final _Counts counts;

  @override
  Widget build(BuildContext context) => ResizableMedia(
        width: _previewSize.width,
        height: _previewSize.height,
        editable: false,
        onResize: (_) {},
        // A non-rendering key lets phase checks inspect fixed frames without
        // scanning all 720 CSV cells or altering their geometry.
        frameBuilder: (frame) => KeyedSubtree(
          key: counts.frameKeys[index],
          child: frame,
        ),
        child: _MountProbe(
          key: ValueKey(node.id),
          id: node.id,
          index: index,
          source: source,
          counts: counts,
        ),
      );
}

class _Counts {
  final editorKey = GlobalKey();
  final frameKeys = List.generate(_blockCount, (_) => GlobalKey());
  final mountedIds = <String>{};
  final paintedIds = <String>{};
  final liveBodies = <int, _MountProbeState>{};
  int totalMounts = 0;
  int csvMounts = 0;
  int pdfMounts = 0;
  int bodyPaints = 0;
  int disposals = 0;

  Map<String, int> snapshot() => {
        // Count every init, including remounts; the set separately counts IDs.
        'total_mounts': totalMounts,
        'unique_mounts': mountedIds.length,
        'csv_mounts': csvMounts,
        'pdf_mounts': pdfMounts,
        'live_bodies': liveBodies.length,
        'disposals': disposals,
        'body_paints': bodyPaints,
        'unique_painted_bodies': paintedIds.length,
      };
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({
    super.key,
    required this.id,
    required this.index,
    required this.source,
    required this.counts,
  });

  final String id;
  final int index;
  final _PreviewFile source;
  final _Counts counts;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.counts.totalMounts++;
    widget.counts.mountedIds.add(widget.id);
    widget.counts.liveBodies[widget.index] = this;
    if (widget.source.kind == FilePreviewKind.csv) {
      widget.counts.csvMounts++;
    } else {
      widget.counts.pdfMounts++;
    }
  }

  @override
  Widget build(BuildContext context) => _PaintProbe(
        counts: widget.counts,
        id: widget.id,
        child: FilePreview(
          file: widget.source.file,
          name: widget.source.name,
          kind: widget.source.kind,
          height: _previewSize.height,
          metadata: const {},
          editable: false,
          onMetadataChanged: (_) {},
        ),
      );

  // Inspect only the shallow body, stopping at CsvPreview/PdfViewer rather
  // than traversing virtualized cells or the native viewer's render subtree.
  bool get previewReady {
    var ready = false;
    void visit(Element element) {
      if (ready) return;
      final child = element.widget;
      if (child is CsvPreview && widget.source.kind == FilePreviewKind.csv) {
        ready = true;
        return;
      }
      if (child is PdfViewer && widget.source.kind == FilePreviewKind.pdf) {
        final error = child.documentRef.resolveListenable().error;
        if (error != null) {
          throw StateError('Generated native PDF preview failed: $error');
        }
        final controller = child.controller;
        ready = controller != null &&
            controller.isReady &&
            controller.pageCount == 1;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return ready;
  }

  @override
  void dispose() {
    widget.counts.liveBodies.remove(widget.index);
    widget.counts.disposals++;
    super.dispose();
  }
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({
    required this.counts,
    required this.id,
    required super.child,
  });

  final _Counts counts;
  final String id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(counts, id);

  @override
  void updateRenderObject(BuildContext context, _RenderPaintProbe renderObject) {
    renderObject
      ..counts = counts
      ..id = id;
  }
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.counts, this.id);

  _Counts counts;
  String id;

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.bodyPaints++;
    counts.paintedIds.add(id);
    super.paint(context, offset);
  }
}

Rect? _rectForKey(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Map<int, Rect> _frameRects(_Counts counts) {
  final frames = <int, Rect>{};
  for (var index = 0; index < counts.frameKeys.length; index++) {
    final rect = _rectForKey(counts.frameKeys[index]);
    if (rect != null) frames[index] = rect;
  }
  return frames;
}

Rect _checkGeometry(_Counts counts, {required bool defer}) {
  final viewport = _rectForKey(counts.editorKey)!;
  expect(viewport.size, const Size(1232, 752));
  final frames = _frameRects(counts);
  expect(frames, isNotEmpty);
  for (final entry in frames.entries) {
    expect(entry.value.width, closeTo(_previewSize.width, 0.01));
    expect(entry.value.height, closeTo(_previewSize.height, 0.01));
    final context = counts.frameKeys[entry.key].currentContext!;
    expect(
      context.getInheritedWidgetOfExactType<PageEmbedPreviewScope>()?.enabled,
      defer,
    );
    expect(context.findAncestorWidgetOfExactType<PageEmbedLoadScope>(), isNotNull);
    expect(
      context.findAncestorWidgetOfExactType<ScrollGestureGate>()?.blocked,
      isTrue,
      reason: 'File previews must remain unclicked so the page owns scrolling.',
    );
  }
  return viewport;
}

Future<void> _settlePreviews(
  WidgetTester tester,
  _Counts counts, {
  required int minimumMounts,
}) async {
  final deadline = DateTime.now().add(_settleTimeout);
  while (true) {
    // Allow the 80ms admission timer to fire even with a static placeholder.
    await tester.pump(const Duration(milliseconds: 200));
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Preview admission/native loading did not settle.');
    }
    await tester.pumpAndSettle(
      _settleInterval,
      EnginePhase.sendSemanticsUpdate,
      remaining,
    );
    // Admission is one ready body per frame, not all bodies in one callback.
    await tester.pump(_settleInterval);
    await tester.pump(_settleInterval);
    final viewport = _rectForKey(counts.editorKey)!;
    final nearViewport = viewport.inflate(math.min(128, viewport.height * 0.2));
    final near = _frameRects(counts).entries.where(
          (entry) => entry.value.overlaps(nearViewport),
        );
    if (counts.totalMounts >= minimumMounts &&
        near.isNotEmpty &&
        near.every((entry) => counts.liveBodies.containsKey(entry.key)) &&
        counts.liveBodies.values.every((body) => body.previewReady)) {
      return;
    }
  }
}

class _TrackpadPan {
  _TrackpadPan(this.tester, this.point);

  final WidgetTester tester;
  final Offset point;
  bool active = false;

  Future<void> start() async {
    active = true;
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 95, device: 95, position: point),
    );
  }

  Future<void> update() async {
    for (var step = 1; step <= _panUpdates; step++) {
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 95,
          device: 95,
          position: point,
          pan: Offset(0, -_panDelta * step),
          panDelta: const Offset(0, -_panDelta),
          timeStamp: _panInterval * step,
        ),
      );
      await tester.pump(_panInterval);
    }
    // A stationary sample beyond the velocity horizon prevents a release
    // fling. Leave the pan open until AFTER the movement recorder returns.
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 95,
        device: 95,
        position: point,
        pan: const Offset(0, -_panDelta * _panUpdates),
        timeStamp: _stationaryTime,
      ),
    );
    await tester.pump(_panInterval);
  }

  Future<void> end() async {
    if (!active) return;
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 95,
        device: 95,
        position: point,
        timeStamp: _stationaryTime,
      ),
    );
    active = false;
  }
}

Future<List<_PreviewFile>> _writeFixture(Directory directory) async {
  final csv = StringBuffer();
  for (var row = 0; row < _csvRows; row++) {
    csv.writeln(
      List.generate(
        _csvColumns,
        (column) => row == 0 ? 'Column ${column + 1}' : 'r$row-c${column + 1}',
      ).join(','),
    );
  }
  final pdf = _onePagePdf();
  final files = <_PreviewFile>[];
  for (var index = 0; index < _blockCount; index++) {
    final kind = index.isEven ? FilePreviewKind.csv : FilePreviewKind.pdf;
    final name = 'preview_${index.toString().padLeft(2, '0')}.${kind.name}';
    final file = File.fromUri(directory.uri.resolve(name));
    if (kind == FilePreviewKind.csv) {
      await file.writeAsString(csv.toString(), flush: true);
    } else {
      await file.writeAsBytes(pdf, flush: true);
    }
    files.add((file: file, name: name, kind: kind));
  }
  return files;
}

// A small, original, one-page PDF with a standard built-in font. All xref
// offsets and the stream length are UTF-8 byte counts, not String lengths.
List<int> _onePagePdf() {
  const content = 'BT\n/F1 18 Tf\n50 740 Td\n'
      '(Generated offline preview benchmark) Tj\n'
      '0 -28 Td\n/F1 12 Tf\n'
      '(One local page. No network or external assets.) Tj\nET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${utf8.encode(content).length} >>\nstream\n${content}endstream',
  ];
  final buffer = StringBuffer();
  var byteOffset = 0;
  void append(String text) {
    buffer.write(text);
    byteOffset += utf8.encode(text).length;
  }

  append('%PDF-1.4\n');
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(byteOffset);
    append('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xrefOffset = byteOffset;
  append('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    append('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  append(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return utf8.encode(buffer.toString());
}

Future<void> _drainNativeDisposals(WidgetTester tester) async {
  // Outside all measurements; do not delete PDFs while their viewer is mounted
  // or immediately after its async native release has merely been scheduled.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _deleteFixture(WidgetTester tester, Directory root) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      await root.delete(recursive: true);
      return;
    } on FileSystemException {
      // Windows can briefly retain a native PDF handle after widget disposal.
      // Retry only fixture deletion; never swallow viewer/loading exceptions.
      if (attempt == 39) rethrow;
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
