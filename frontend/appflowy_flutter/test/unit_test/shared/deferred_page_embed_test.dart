import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/deferred_page_embed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cached offscreen embeds never initialize or build their body', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              const SizedBox(height: 800),
              _embed(_Heavy(counts)),
            ],
          ),
        ),
      );
      expect(find.byType(DeferredPageEmbed, skipOffstage: false), findsOneWidget);
      final placeholder = tester.element(
        find.byType(FocusableActionDetector, skipOffstage: false),
      );
      await _idle(tester, frames: 4);
      for (var step = 1; step <= 5; step++) {
        controller.jumpTo(step * 20.0);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(counts.initialized, isEmpty);
      expect(counts.builds, 0);
      expect(
        tester.element(find.byType(FocusableActionDetector, skipOffstage: false)),
        same(placeholder),
      );
    });
  });

  testWidgets('a real fling past a cached embed never mounts it', (tester) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              const SizedBox(height: 800),
              _embed(_Heavy(counts)),
            ],
          ),
        ),
      );
      expect(find.byType(DeferredPageEmbed, skipOffstage: false), findsOneWidget);
      await tester.fling(find.byType(ListView), const Offset(0, -650), 6000);
      expect(controller.position.isScrollingNotifier.value, isTrue);
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(counts.initialized, isEmpty);
      }
      expect(controller.offset, greaterThan(1000));
      controller.jumpTo(1400);
      await tester.pump();
      await _idle(tester, frames: 3);
      expect(counts.builds, 0);
    });
  });

  testWidgets('visible bodies wait 80ms and then mount on the next frame', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(_app(_list(controller, [_embed(_Heavy(counts))])));
      final frameSize = tester.getSize(find.byType(DeferredPageEmbed));
      expect(counts.initialized, isEmpty);
      await tester.pump(const Duration(milliseconds: 79));
      expect(counts.initialized, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(counts.initialized, isEmpty, reason: 'post-layout queue, not a mount');
      await tester.pump(const Duration(milliseconds: 1));
      expect(counts.initialized, ['body']);
      expect(tester.getSize(find.byType(DeferredPageEmbed)), frameSize);
      expect(counts.builds, 1);
      await _idle(tester, frames: 4);
      expect(counts.builds, 1);
    });
  });

  testWidgets('a page admits only one ready embed in each frame', (tester) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              for (var i = 0; i < 3; i++)
                _embed(_Heavy(counts, id: '$i'), height: 60),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(counts.initialized, isEmpty);
      for (var i = 1; i <= 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        expect(counts.initialized, hasLength(i));
      }
      expect(counts.frames.toSet(), hasLength(3));
    });
  });

  for (final activation in ['frame click', 'Enter', 'Space', 'semantics']) {
    testWidgets('first $activation bypasses the idle wait', (tester) async {
      await _withPage(tester, (controller, counts) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _app(_list(controller, [_embed(_Heavy(counts))])),
          );
          expect(counts.initialized, isEmpty);
          if (activation == 'frame click') {
            // Empty corner, not the glyph/text: the whole fixed frame is a button.
            await tester.tapAt(
              tester.getTopLeft(find.byType(DeferredPageEmbed)) +
                  const Offset(3, 3),
            );
          } else if (activation == 'semantics') {
            final node = tester.getSemantics(
              find.byWidgetPredicate(
                (widget) => widget is Semantics &&
                    widget.properties.label == LocaleKeys.gallery_preview,
              ),
            );
            expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            expect(node.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue);
            node.owner!.performAction(node.id, SemanticsAction.tap);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            expect(counts.initialized, isEmpty, reason: 'focus is not activation');
            await tester.sendKeyEvent(
              activation == 'Enter'
                  ? LogicalKeyboardKey.enter
                  : LogicalKeyboardKey.space,
            );
          }
          await tester.pump();
          expect(counts.initialized, ['body']);
          expect(counts.builds, 1);
        } finally {
          semantics.dispose();
        }
      });
    });
  }

  testWidgets('keyboard activation also bypasses an ongoing scroll', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(_list(controller, [_embed(_Heavy(counts))])));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        unawaited(
          controller.animateTo(
            40,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        // Scrollable itself blocks semantic pointer actions during animateTo,
        // but an explicitly focused keyboard action must still load the body.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(counts.initialized, ['body']);
      } finally {
        semantics.dispose();
      }
    });
  });

  testWidgets('actual GlobalKey element survives scrolling resizing data and theme', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      final key = GlobalKey();
      Widget page({double height = 100, String id = 'body', bool dark = false,
        bool enabled = true, bool preview = true,}) =>
          _app(
            _list(
              controller,
              [
                _embed(
                  _Heavy(counts, key: key, id: id),
                  height: height,
                  enabled: enabled,
                  preview: preview,
                ),
              ],
            ),
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          );
      await tester.pumpWidget(page());
      await _idle(tester);
      final element = key.currentContext;
      final state = tester.state<_HeavyState>(find.byKey(key));
      expect(element, isNotNull);
      state.focus.requestFocus();
      await tester.pump();
      final builds = counts.builds;
      for (final offset in [300.0, 600.0, 100.0, 0.0]) {
        controller.jumpTo(offset);
        await tester.pump(const Duration(milliseconds: 16));
        expect(key.currentContext, same(element));
      }
      expect(counts.builds, builds, reason: 'no body rebuild per scroll pixel');
      await tester.pumpWidget(page(height: 145, id: 'latest', dark: true));
      expect(key.currentContext, same(element));
      expect(tester.state(find.byKey(key)), same(state));
      expect(state.focus.hasFocus, isTrue);
      expect(find.text('latest'), findsOneWidget);
      expect(Theme.of(key.currentContext!).brightness, Brightness.dark);
      expect(tester.getSize(find.byType(DeferredPageEmbed)).height, 145);
      await tester.pumpWidget(page(enabled: false, preview: false));
      await tester.pumpWidget(page());
      expect(key.currentContext, same(element));
      expect(state.focus.hasFocus, isTrue);
      expect(counts.initialized, ['body']);
      expect(counts.deactivated, 0);
      expect(counts.disposed, 0);
    });
  });

  testWidgets('updates before admission mount only the latest child', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      Widget page(String id) => _app(
            _list(
              controller,
              [
                const SizedBox(height: 800),
                _embed(_Heavy(counts, id: id, key: ValueKey(id))),
              ],
            ),
          );
      await tester.pumpWidget(page('old'));
      await tester.pumpWidget(page('latest'));
      expect(counts.builds, 0);
      controller.jumpTo(700);
      await tester.pump();
      await _idle(tester);
      expect(counts.initialized, ['latest']);
      expect(find.text('old'), findsNothing);
    });
  });

  testWidgets('resuming scrolling cancels queued entries until a fresh idle', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              for (var i = 0; i < 3; i++)
                _embed(_Heavy(counts, id: '$i'), height: 60),
            ],
          ),
        ),
      );
      await _idle(tester);
      expect(counts.initialized, hasLength(1));
      unawaited(
        controller.animateTo(
          20,
          duration: const Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(counts.initialized, hasLength(1));
      }
      controller.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 79));
      expect(counts.initialized, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(counts.initialized, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(counts.initialized, hasLength(3));
    });
  });

  testWidgets('leaving during the idle debounce cancels the pending timer', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(_app(_list(controller, [_embed(_Heavy(counts))])));
      await tester.pump(const Duration(milliseconds: 40));
      controller.jumpTo(700);
      await tester.pump();
      await _idle(tester, frames: 3);
      expect(counts.initialized, isEmpty);
      controller.jumpTo(0);
      await tester.pump();
      await _idle(tester);
      expect(counts.initialized, ['body']);
    });
  });

  for (final delay in [20, 80]) {
    testWidgets('disposing with a ${delay}ms idle/queue pending never mounts', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        await tester.pumpWidget(_app(_list(controller, [_embed(_Heavy(counts))])));
        await tester.pump(Duration(milliseconds: delay));
        await tester.pumpWidget(const SizedBox.shrink());
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });
  }

  for (final hide in ['offstage', 'translated']) {
    testWidgets('a queued child rechecks $hide ancestors in its admission frame', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        final hidden = ValueNotifier(false);
        try {
          await tester.pumpWidget(
            _app(
              _list(
                controller,
                [
                  ValueListenableBuilder<bool>(
                    valueListenable: hidden,
                    builder: (_, value, child) => hide == 'offstage'
                        ? Offstage(offstage: value, child: child)
                        : Transform.translate(
                            offset: Offset(0, value ? 700 : 0),
                            child: child,
                          ),
                    child: _embed(_Heavy(counts)),
                  ),
                ],
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 80));
          hidden.value = true;
          await tester.pump(const Duration(milliseconds: 1));
          await _idle(tester, frames: 3);
          expect(counts.initialized, isEmpty);
          hidden.value = false;
          await tester.pump();
          await _idle(tester);
          expect(counts.initialized, ['body']);
          expect(tester.takeException(), isNull);
        } finally {
          hidden.dispose();
        }
      });
    });
  }

  testWidgets('moving a pending GlobalKey between pages cancels the old owner', (
    tester,
  ) async {
    await _withPage(tester, (left, counts) async {
      final right = ScrollController(initialScrollOffset: 700);
      final key = GlobalKey();
      final frame = _embed(_Heavy(counts), key: key);
      Widget page(bool onLeft) => _app(
            Row(
              children: [
                Expanded(child: _list(left, [if (onLeft) frame])),
                Expanded(child: _list(right, [if (!onLeft) frame])),
              ],
            ),
            width: 640,
          );
      try {
        await tester.pumpWidget(page(true));
        final original = tester.state(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pumpWidget(page(false));
        expect(tester.state(find.byKey(key, skipOffstage: false)), same(original));
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty);
        right.jumpTo(0);
        await tester.pump();
        await _idle(tester);
        expect(counts.initialized, ['body']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        right.dispose();
      }
    });
  });

  testWidgets('nested load scopes have independent per-frame queues', (
    tester,
  ) async {
    await _withPage(tester, (left, leftCounts) async {
      final right = ScrollController();
      final rightCounts = _Counts();
      try {
        await tester.pumpWidget(
          _app(
            PageEmbedLoadScope(
              child: Row(
                children: [
                  Expanded(
                    child: _list(
                      left,
                      [
                        _embed(_Heavy(leftCounts, id: 'L1'), height: 60),
                        _embed(_Heavy(leftCounts, id: 'L2'), height: 60),
                      ],
                      scoped: false,
                    ),
                  ),
                  Expanded(
                    child: _list(
                      right,
                      [
                        _embed(_Heavy(rightCounts, id: 'R1'), height: 60),
                        _embed(_Heavy(rightCounts, id: 'R2'), height: 60),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            width: 640,
          ),
        );
        await _idle(tester);
        expect(leftCounts.initialized, ['L1']);
        expect(rightCounts.initialized, ['R1']);
        expect(leftCounts.frames.single, rightCounts.frames.single);
        right.jumpTo(10); // Only this page loses its second ready entry.
        await tester.pump(const Duration(milliseconds: 1));
        expect(leftCounts.initialized, ['L1', 'L2']);
        expect(rightCounts.initialized, ['R1']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        right.dispose();
      }
    });
  });

  for (final fallback in ['no load scope', 'no marker', 'marker disabled', 'disabled']) {
    testWidgets('$fallback mounts immediately without waiting for visibility', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        await tester.pumpWidget(
          _app(
            _list(
              controller,
              [
                const SizedBox(height: 800),
                _embed(
                  _Heavy(counts),
                  enabled: fallback != 'disabled',
                  preview: fallback == 'no marker'
                      ? null
                      : fallback != 'marker disabled',
                ),
              ],
              scoped: fallback != 'no load scope',
            ),
          ),
        );
        expect(counts.initialized, ['body']);
        expect(find.byType(FocusableActionDetector, skipOffstage: false), findsNothing);
      });
    });
  }

  testWidgets('without a Scrollable the scoped child is immediate', (
    tester,
  ) async {
    await _withPage(tester, (_, counts) async {
      await tester.pumpWidget(
        _app(PageEmbedLoadScope(child: _embed(_Heavy(counts)))),
      );
      expect(counts.initialized, ['body']);
    });
  });

  testWidgets('removing a load scope releases a preserved pending child', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      final key = GlobalKey();
      final frame = _embed(_Heavy(counts), key: key);
      Widget page(bool scoped) => _app(
            _list(
              controller,
              [
                const SizedBox(height: 800),
                frame,
              ],
              scoped: scoped,
            ),
          );
      await tester.pumpWidget(page(true));
      final original = tester.state(find.byKey(key, skipOffstage: false));
      await tester.pumpWidget(page(false));
      expect(tester.state(find.byKey(key, skipOffstage: false)), same(original));
      expect(counts.initialized, ['body']);
    });
  });

  testWidgets('single-child page scroll roots also defer their distant bodies', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          PageEmbedLoadScope(
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 800),
                  _embed(_Heavy(counts)),
                  const SizedBox(height: 2400),
                ],
              ),
            ),
          ),
        ),
      );
      await _idle(tester, frames: 3);
      expect(counts.initialized, isEmpty);
      controller.jumpTo(700);
      await tester.pump();
      await _idle(tester);
      expect(counts.initialized, ['body']);
    });
  });

  testWidgets('the first Deferred consumes the marker for nested media frames', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              _embed(DeferredPageEmbed(child: _Heavy(counts))),
            ],
          ),
        ),
      );
      await _idle(tester);
      expect(find.byType(DeferredPageEmbed), findsNWidgets(2));
      expect(counts.initialized, ['body'], reason: 'no second deferred admission');
      expect(counts.markerEnabled, isFalse);
    });
  });

  for (final kind in ['unbounded', 'loose', 'zero']) {
    testWidgets('$kind constraints fall through on the first layout', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        Widget frame = _embed(
          _Heavy(counts),
          height: kind == 'zero' ? 0 : null,
        );
        if (kind == 'loose') {
          frame = Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 100),
              child: frame,
            ),
          );
        }
        await tester.pumpWidget(_app(_list(controller, [frame])));
        expect(counts.initialized, ['body']);
        expect(tester.takeException(), isNull);
      });
    });
  }

  for (final width in [false, true]) {
    testWidgets('intrinsic ${width ? 'width' : 'height'} preserves natural size', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        final baseline = GlobalKey();
        final deferred = GlobalKey();
        final child = PageEmbedPreviewScope(
          enabled: true,
          child: DeferredPageEmbed(key: deferred, child: _Heavy(counts)),
        );
        await tester.pumpWidget(
          _app(
            _list(
              controller,
              [
                Align(child: SizedBox(key: baseline, width: 80, height: 37)),
                Align(
                  child: width
                      ? IntrinsicWidth(child: child)
                      : IntrinsicHeight(child: child),
                ),
              ],
            ),
          ),
        );
        expect(counts.initialized, ['body']);
        expect(tester.getSize(find.byKey(deferred)), tester.getSize(find.byKey(baseline)));
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('an unbounded resize loads once and never closes the actual body', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      final key = GlobalKey();
      Widget page(double? height) => _app(
            _list(
              controller,
              [
                const SizedBox(height: 800),
                _embed(_Heavy(counts, key: key), height: height),
              ],
            ),
          );
      await tester.pumpWidget(page(100));
      expect(counts.initialized, isEmpty);
      await tester.pumpWidget(page(null));
      expect(counts.initialized, ['body']);
      final element = key.currentContext;
      expect(tester.getSize(find.byKey(key, skipOffstage: false)).height, 37);
      await tester.pumpWidget(page(120));
      await _idle(tester, frames: 3);
      expect(key.currentContext, same(element));
      expect(counts.initialized, ['body']);
      expect(counts.deactivated, 0);
    });
  });

  testWidgets('full rectangle intersection admits a tall body with its origin offscreen', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(_list(controller, [_embed(_Heavy(counts), height: 1200)])),
      );
      controller.jumpTo(500);
      await tester.pump();
      expect(tester.getTopLeft(find.byType(DeferredPageEmbed)).dy, lessThan(0));
      await _idle(tester);
      expect(counts.initialized, ['body']);
    });
  });

  testWidgets('cross-axis offscreen frames do not pass a vertical-only check', (
    tester,
  ) async {
    await _withPage(tester, (controller, counts) async {
      await tester.pumpWidget(
        _app(
          _list(
            controller,
            [
              Transform.translate(offset: const Offset(500, 0), child: _embed(_Heavy(counts))),
            ],
          ),
        ),
      );
      await _idle(tester, frames: 3);
      expect(counts.initialized, isEmpty);
    });
  });

  for (final before in [230.0, 350.0]) {
    testWidgets('preload at $before stays bounded by viewport fraction and 128px', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        await tester.pumpWidget(
          _app(
            _list(
              controller,
              [
                SizedBox(height: before),
                _embed(_Heavy(counts)),
              ],
            ),
          ),
        );
        await _idle(tester, frames: 3);
        expect(counts.initialized, before == 230 ? ['body'] : isEmpty);
      });
    });
  }

  testWidgets('large viewport preload is capped at 128 logical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    try {
      await _withPage(tester, (controller, counts) async {
        await tester.pumpWidget(
          _app(
            _list(
              controller,
              [
                const SizedBox(height: 1140),
                _embed(_Heavy(counts)),
              ],
            ),
            height: 1000,
          ),
        );
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty, reason: '140px exceeds the 128px cap');
        controller.jumpTo(20);
        await tester.pump();
        await _idle(tester);
        expect(counts.initialized, ['body']);
      });
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  for (final scale in [0.5, 1.5]) {
    testWidgets('scaled viewport $scale uses transformed bounds not window size', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        await tester.pumpWidget(
          _app(
            Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: _list(
                controller,
                [
                  const SizedBox(height: 350),
                  _embed(_Heavy(counts)),
                ],
              ),
            ),
          ),
        );
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty);
        controller.jumpTo(300);
        await tester.pump();
        await _idle(tester);
        expect(counts.initialized, ['body']);
      });
    });
  }

  testWidgets('inner visibility is clipped by the outer viewport and waits for its fling', (
    tester,
  ) async {
    await _withPage(tester, (outer, counts) async {
      final inner = ScrollController();
      try {
        await tester.pumpWidget(
          _app(
            _list(
              outer,
              [
                SizedBox(
                  height: 600,
                  child: _list(
                    inner,
                    [
                      const SizedBox(height: 400),
                      _embed(_Heavy(counts)),
                    ],
                    scoped: false,
                  ),
                ),
              ],
            ),
          ),
        );
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty, reason: 'inside inner but clipped by outer');
        unawaited(
          outer.animateTo(
            600,
            duration: const Duration(milliseconds: 500),
            curve: Curves.linear,
          ),
        );
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(counts.initialized, isEmpty);
        }
        expect(inner.offset, 0);
        outer.jumpTo(360);
        await tester.pump();
        await _idle(tester);
        expect(counts.initialized, ['body']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        inner.dispose();
      }
    });
  });

  for (final hidden in ['offstage', 'opacity', 'indexed stack']) {
    testWidgets('$hidden ancestors prevent automatic admission', (tester) async {
      await _withPage(tester, (controller, counts) async {
        final frame = _embed(_Heavy(counts));
        final body = switch (hidden) {
          'offstage' => Offstage(child: frame),
          'opacity' => Opacity(opacity: 0, child: frame),
          _ => _PaintOnlyIndexedStack(children: [frame, const SizedBox(height: 100)]),
        };
        await tester.pumpWidget(_app(_list(controller, [body])));
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty);
      });
    });
  }

  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    testWidgets('${appearance.name} preview uses the shared surface and theme face without animation', (
      tester,
    ) async {
      await _withPage(tester, (controller, counts) async {
        final theme = ThemeData(
          brightness: appearance.brightness,
          fontFamily: 'PreviewTestFace',
          extensions: [PaperThemeExtension(enabled: appearance.paper)],
        );
        await tester.pumpWidget(
          _app(
            _list(
              controller,
              [
                const SizedBox(height: 800),
                _embed(_Heavy(counts)),
              ],
            ),
            theme: theme,
          ),
        );
        final frame = find.byType(DeferredPageEmbed, skipOffstage: false);
        final surface = tester.widget<ColoredBox>(
          find.descendant(
            of: frame,
            matching: find.byType(ColoredBox, skipOffstage: false),
            skipOffstage: false,
          ),
        );
        final text = tester.widget<Text>(
          find.descendant(
            of: frame,
            matching: find.byType(Text, skipOffstage: false),
            skipOffstage: false,
          ),
        );
        expect(
          surface.color,
          EditorSurfaceStyle.previewBackgroundFor(
            appearance.brightness,
            theme.colorScheme.surfaceContainerLow,
            isPaper: appearance.paper,
          ),
        );
        expect(text.data, LocaleKeys.gallery_preview);
        expect(text.style, Theme.of(tester.element(frame)).textTheme.bodySmall);
        expect(text.style!.fontFamily, 'PreviewTestFace');
        expect(
          find.descendant(
            of: frame,
            matching: find.byWidgetPredicate(
              (widget) => widget is AnimatedWidget || widget is ImplicitlyAnimatedWidget ||
                  widget is CircularProgressIndicator || widget is LinearProgressIndicator,
            ),
          ),
          findsNothing,
        );
        await _idle(tester, frames: 3);
        expect(counts.initialized, isEmpty);
      });
    });
  }
}

Future<void> _withPage(
  WidgetTester tester,
  Future<void> Function(ScrollController, _Counts) body,
) async {
  final controller = ScrollController();
  try {
    await body(controller, _Counts());
  } finally {
    // Dispose timers/listeners before the test binding checks pending work.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }
}

Future<void> _idle(WidgetTester tester, {int frames = 1}) async {
  await tester.pump(const Duration(milliseconds: 80));
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Widget _app(Widget child, {ThemeData? theme, double width = 320, double height = 200}) => MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

Widget _list(ScrollController controller, List<Widget> children, {bool scoped = true}) {
  final list = ListView(
    controller: controller,
    padding: EdgeInsets.zero,
    cacheExtent: 1000,
    physics: const ClampingScrollPhysics(),
    children: [...children, const SizedBox(height: 2400)],
  );
  return scoped ? PageEmbedLoadScope(child: list) : list;
}

Widget _embed(
  Widget child, {
  Key? key,
  double? height = 100,
  bool enabled = true,
  bool? preview = true,
}) {
  final frame = SizedBox(
    width: 320,
    height: height,
    child: DeferredPageEmbed(key: key, enabled: enabled, child: child),
  );
  return preview == null
      ? frame
      : PageEmbedPreviewScope(enabled: preview, child: frame);
}

// Exercise RenderIndexedStack itself, without widget-level Visibility wrappers.
class _PaintOnlyIndexedStack extends MultiChildRenderObjectWidget {
  const _PaintOnlyIndexedStack({required super.children});

  @override
  RenderIndexedStack createRenderObject(BuildContext context) =>
      RenderIndexedStack(index: 1, textDirection: TextDirection.ltr);
}

class _Counts {
  final initialized = <String>[];
  final frames = <Duration>[];
  int builds = 0, deactivated = 0, disposed = 0;
  bool? markerEnabled;
}

// A native-view stand-in: construction is cheap, initState/build are observable.
class _Heavy extends StatefulWidget {
  const _Heavy(this.counts, {super.key, this.id = 'body'});

  final _Counts counts;
  final String id;

  @override
  State<_Heavy> createState() => _HeavyState();
}

class _HeavyState extends State<_Heavy> {
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.counts.initialized.add(widget.id);
    widget.counts.frames.add(SchedulerBinding.instance.currentFrameTimeStamp);
  }

  @override
  Widget build(BuildContext context) {
    widget.counts.builds++;
    widget.counts.markerEnabled = context
        .dependOnInheritedWidgetOfExactType<PageEmbedPreviewScope>()
        ?.enabled;
    return Focus(
      focusNode: focus,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(width: 80, height: 37, child: Text(widget.id)),
      ),
    );
  }

  @override
  void deactivate() {
    widget.counts.deactivated++;
    super.deactivate();
  }

  @override
  void dispose() {
    widget.counts.disposed++;
    focus.dispose();
    super.dispose();
  }
}
