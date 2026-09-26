import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _away = Offset(880, 680);
const _ids = ['page', 'viewer', 'image', 'other-tab', 'sibling'];

// Deliberately no editor, PDF, image, or webview package dependency. These are
// routing contracts exercised through Flutter's real focus/shortcut dispatch.
void main() {
  test('editable ownership defaults off and retains the compatibility alias',
      () {
    final ordinary = ContextualFindRegion(
      onFind: () {},
      child: const SizedBox.shrink(),
    );
    final owned = ContextualFindRegion(
      onFind: () {},
      findInEditable: true,
      child: const SizedBox.shrink(),
    );
    final legacy = ContextualFindRegion(
      onFind: () {},
      ownsEditable: true,
      child: const SizedBox.shrink(),
    );
    expect(ordinary.findInEditable, isFalse);
    expect(ordinary.ownsEditable, isFalse);
    expect(owned.findInEditable, isTrue);
    expect(owned.ownsEditable, isTrue);
    expect(legacy.findInEditable, isTrue);
  });

  for (final owned in [false, true]) {
    _test('actual RenderEditable hover needs opt-in (owned=$owned)',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        fixture.focusOnFind = false;
        fixture.change(() {
          fixture.viewerFindInEditable = owned;
          fixture.viewerCanReplace = true;
          fixture.inheritSelection.add('viewer');
          fixture.selected.addAll(['file', 'page']);
        });
        final draft = tester.state<_DraftState>(find.byType(_Draft));
        draft.text.value = const TextEditingValue(
          text: 'unsaved code needle',
          selection: TextSelection(baseOffset: 2, extentOffset: 8),
        );
        await tester.pump();
        final value = draft.text.value;
        final primary = FocusManager.instance.primaryFocus;
        final builds = draft.builds;
        final point = _editablePoint(tester, find.byType(_Draft));
        await mouse.moveTo(point);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(primary));
        expect(draft.text.value, value);
        expect(draft.builds, builds);

        expect(
          ContextualFindRegion.dispatch(tester.element(_region('page'))),
          owned,
        );
        await tester.pump();
        await _chord(tester);
        await _chord(tester, key: LogicalKeyboardKey.keyH);
        expect(
          fixture.calls,
          owned ? ['find:viewer', 'find:viewer', 'replace:viewer'] : isEmpty,
        );
        expect(fixture.outerCalls, owned ? isEmpty : ['find', 'replace']);
        expect(fixture.localCalls, isEmpty);
        expect(FocusManager.instance.primaryFocus, same(primary));
        expect(draft.text.value, value);
        expect(tester.state(find.byType(_Draft)), same(draft));

        // The neighbouring page title is a real, unowned EditableText. Even
        // after code Find was activated it must not fall back to that owner.
        await mouse.moveTo(
          _editablePoint(
            tester,
            _fieldForFocus(fixture.insideFocus),
          ),
        );
        final calls = List.of(fixture.calls);
        expect(
          ContextualFindRegion.dispatch(tester.element(_region('page'))),
          isFalse,
        );
        await _chord(tester);
        expect(fixture.calls, calls);
        expect(FocusManager.instance.primaryFocus, same(primary));
        expect(draft.text.value, value);
      });
    });
  }

  _test('owned code focus works but never borrows a native title/query focus',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      fixture.change(() => fixture.viewerFindInEditable = true);
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byType(_Draft),
          matching: find.byType(EditableText),
        ),
      );
      editable.widget.focusNode.requestFocus();
      await mouse.moveTo(_away);
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls, ['find:viewer']);
      expect(editable.widget.focusNode.hasPrimaryFocus, isTrue);
      fixture.calls.clear();

      for (final (node, label) in [
        (fixture.insideFocus, 'inside'),
        (fixture.outsideFocus, 'outside'),
      ]) {
        node.requestFocus();
        await tester.pump();
        await mouse.moveTo(_editablePoint(tester, find.byType(_Draft)));
        await _chord(tester);
        expect(fixture.calls, isEmpty);
        expect(node.hasPrimaryFocus, isTrue);
        expect(fixture.localCalls.last, '$label:find');
      }
      expect(fixture.outerCalls, isEmpty);
    });
  });

  _test('hovered image/viewer wins before the focused page swallows Find',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      final draft = tester.state<_DraftState>(find.byType(_Draft));
      draft.text.value = const TextEditingValue(
        text: 'An untouched editor selection',
        selection: TextSelection(baseOffset: 3, extentOffset: 12),
      );
      await tester.pump();
      final value = draft.text.value;
      final builds = draft.builds;
      final primary = FocusManager.instance.primaryFocus;

      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        for (final id in ['image', 'viewer', 'page']) {
          await mouse.moveTo(tester.getCenter(_hit(id)));
          if (id == 'page') {
            // Page text is a fallback while a viewer still owns find. An
            // explicit content click retires that last viewer ownership.
            await tester.tap(_hit('page'));
          }
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, same(primary));
          expect(draft.text.value, value);
          // Pure hover has not rebuilt any renderer or opened a search UI.
          if (fixture.calls.isEmpty) expect(draft.builds, builds);
          final before =
              fixture.calls.where((call) => call.startsWith('find:')).length;
          expect(await _chord(tester, modifier: modifier), isTrue);
          expect(fixture.calls.last, 'find:$id');
          expect(
            fixture.calls.where((call) => call.startsWith('find:')).length,
            before + 1,
          );
          expect(fixture.outerCalls, isEmpty);
          expect(fixture.localCalls, isEmpty);
          expect(FocusManager.instance.primaryFocus, same(primary));
          expect(draft.text.value, value);
        }
      }
      final owners = tester.widgetList<Focus>(
        find.byWidgetPredicate(
          (widget) => widget is Focus && widget.debugLabel == 'Same label',
        ),
      );
      expect(owners, isNotEmpty);
      for (final owner in owners) {
        expect(owner.canRequestFocus, isFalse);
        expect(owner.skipTraversal, isTrue);
      }
    });
  });

  _test('one callback per press; owned repeats never reach local Shortcuts',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      await mouse.moveTo(tester.getCenter(_hit('image')));
      final events = ContextualFindRegion.debugKeyEventCount;
      expect(await _chord(tester, repeats: 3), isTrue);
      expect(fixture.calls, ['find:image']);
      expect(fixture.localCalls, isEmpty);
      expect(fixture.outerCalls, isEmpty);
      // Modifier down/up, F down/up, and three repeat events, once each.
      expect(ContextualFindRegion.debugKeyEventCount - events, 7);
      expect(await _chord(tester), isTrue);
      expect(fixture.calls, ['find:image', 'find:image']);
    });
  });

  _test('owned repeats and key-up drain after the target is removed',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(tester.getCenter(_hit('image')));
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      var handledUp = false;
      try {
        expect(handled, isTrue);
        expect(fixture.calls, ['find:image']);
        fixture.toolbarFocus.requestFocus();
        fixture.change(() => fixture.showViewer = false);
        await tester.pump();
        await tester.pump();
        expect(ContextualFindRegion.debugRegisteredRegionCount, 1);
        expect(
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyF),
          isTrue,
        );
        expect(fixture.localCalls, isEmpty);
      } finally {
        handledUp = await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
      }
      expect(handledUp, isTrue);
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
      expect(fixture.localCalls, ['toolbar:find']);
      expect(fixture.outerCalls, isEmpty);
    });
  });

  for (final external in [false, true]) {
    _test('query focus stays with its viewer (external=$external)',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        fixture.change(() => fixture.externalQuery = external);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_hit('viewer')));
        await _chord(tester);
        expect(fixture.queryFocus['viewer']!.hasPrimaryFocus, isTrue);
        fixture.queries['viewer']!.value = const TextEditingValue(
          text: 'retained query',
          selection: TextSelection(baseOffset: 2, extentOffset: 8),
        );
        final value = fixture.queries['viewer']!.value;
        await mouse.moveTo(_away);
        await _chord(tester);
        expect(fixture.calls, ['find:viewer', 'find:viewer']);
        expect(fixture.queries['viewer']!.value, value);
        expect(fixture.queryFocus['viewer']!.hasPrimaryFocus, isTrue);

        await mouse.moveTo(tester.getCenter(_hit('page')));
        await _chord(tester);
        expect(fixture.calls.last, 'find:viewer');
        expect(fixture.queryFocus['viewer']!.hasPrimaryFocus, isTrue);

        // The query itself is not page-content hover, even when external to
        // the viewer but placed in the same page's widget hierarchy.
        await mouse.moveTo(_editablePoint(tester, _query('viewer')));
        await _chord(tester);
        expect(fixture.calls.last, 'find:viewer');
        expect(fixture.outerCalls, isEmpty);
        expect(fixture.localCalls, isEmpty);
      });
    });
  }

  _test('an external query keeps its owner when another pane is hovered',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      final page = tester.state(_region('page'));
      final viewer = tester.state(_region('viewer'));
      final portalFinder = find.byKey(const ValueKey('page-portal'));
      final portal = tester.state(portalFinder);
      final draft = tester.state<_DraftState>(find.byType(_Draft));
      final pageBox = _mountedBox(tester, _region('page'));
      final viewerBox = _mountedBox(tester, _region('viewer'));

      void expectRetainedPanes() {
        expect(tester.takeException(), isNull);
        expect(tester.state(_region('page')), same(page));
        expect(tester.state(_region('viewer')), same(viewer));
        expect(tester.state(portalFinder), same(portal));
        expect(tester.state(find.byType(_Draft)), same(draft));
        expect(_mountedBox(tester, _region('page')), same(pageBox));
        expect(_mountedBox(tester, _region('viewer')), same(viewerBox));
        expect(
          tester.widget<OverlayPortal>(portalFinder).controller,
          same(fixture.portal),
        );
        expect(
          ContextualFindRegion.debugRegisteredRegionCount,
          fixture.showSibling ? 5 : 4,
        );
      }

      fixture.change(() => fixture.showSibling = true);
      await tester.pump();
      expectRetainedPanes();
      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester);
      final queryFocus = fixture.queryFocus['viewer']!;
      expect(queryFocus.hasPrimaryFocus, isTrue);
      final query = tester.state<EditableTextState>(
        find.descendant(
          of: _query('viewer'),
          matching: find.byType(EditableText),
        ),
      );
      expect(query.widget.focusNode, same(queryFocus));
      fixture.queries['viewer']!.value = const TextEditingValue(
        text: 'retained external query',
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
      );
      await tester.pump();
      final value = fixture.queries['viewer']!.value;
      await mouse.moveTo(tester.getCenter(_hit('sibling')));
      await _chord(tester);
      expect(fixture.calls, ['find:viewer', 'find:viewer']);
      expect(queryFocus.hasPrimaryFocus, isTrue);
      expect(fixture.open, {'viewer'});

      // Exercise both list edits with a mounted, focused native query. Keys on
      // the regions alone cannot retain their unkeyed Positioned ancestors.
      for (final showSibling in [false, true]) {
        fixture.change(() => fixture.showSibling = showSibling);
        await tester.pump();
        expectRetainedPanes();
        expect(query.mounted, isTrue);
        expect(
          tester.state<EditableTextState>(
            find.descendant(
              of: _query('viewer'),
              matching: find.byType(EditableText),
            ),
          ),
          same(query),
        );
        expect(queryFocus.hasPrimaryFocus, isTrue);
        expect(fixture.queries['viewer']!.value, value);
        _editablePoint(tester, _query('viewer'));
      }
      await _chord(tester);
      expect(fixture.calls, List.filled(3, 'find:viewer'));
      expect(queryFocus.hasPrimaryFocus, isTrue);
      expect(fixture.queries['viewer']!.value, value);
      expect(fixture.open, {'viewer'});
      expect(fixture.outerCalls, isEmpty);
      expect(fixture.localCalls, isEmpty);
    });
  });

  _test('live inactive parent blocks nested hover without a rebuild',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(tester.getCenter(_hit('image')));
      fixture.inactive.add('page');
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      fixture.inactive.clear();
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
    });
  });

  _test(
      'live selected embed beats page fallback; focused viewer beats selection',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(tester.getCenter(_hit('page')));
      // No rebuild: selection must be queried at dispatch, not captured on enter.
      fixture.selected.addAll(['viewer', 'image']);
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
      fixture.focus['viewer']!.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:viewer');
      fixture.focus['page']!.requestFocus();
      fixture.selected.clear();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');
    });
  });

  _test('one file marker selects its deepest visible viewer, not another pane',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      fixture.change(() {
        fixture.showSibling = true;
        fixture.inheritSelection.addAll(['viewer', 'image', 'other-tab']);
      });
      await tester.pump();
      final viewer = tester.state(_region('viewer'));
      final draft = tester.state<_DraftState>(find.byType(_Draft));
      draft.text.value = const TextEditingValue(
        text: 'unsaved selected file',
        selection: TextSelection(baseOffset: 2, extentOffset: 9),
      );
      draft.scroll.jumpTo(48);
      final value = draft.text.value;
      final position = draft.scroll.position;
      final primary = FocusManager.instance.primaryFocus;
      await mouse.moveTo(tester.getCenter(_hit('page')));

      // No rebuild or preview hover: both page and file selection are live.
      fixture.selected.addAll(['page', 'file']);
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
      expect(FocusManager.instance.primaryFocus, same(primary));
      expect(
        ContextualFindSelection.maybeOf(tester.element(_region('page'))),
        isNull,
      );
      expect(
        ContextualFindSelection.maybeOf(tester.element(_region('sibling'))),
        isNull,
      );

      fixture.change(() => fixture.tab = 1);
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:other-tab');
      expect(tester.state(_region('viewer', offstage: true)), same(viewer));
      fixture.change(() => fixture.tab = 0);
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:image');

      fixture.selected.remove('file');
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');
      expect(tester.state(_region('viewer')), same(viewer));
      expect(tester.state(find.byType(_Draft)), same(draft));
      expect(draft.text.value, value);
      expect(draft.scroll.position, same(position));
      expect(draft.scroll.offset, 48);
      expect(FocusManager.instance.primaryFocus, same(primary));
      expect(fixture.calls, isNot(contains('find:sibling')));
    });
  });

  _test(
      'null selection inherits but explicit false and true remain authoritative',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      fixture.change(() => fixture.showImage = false);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(_hit('page')));
      fixture.selected.addAll(['page', 'file']);
      final viewer = tester.element(_region('viewer'));
      expect(ContextualFindSelection.maybeOf(viewer)!.isSelected(), isTrue);
      expect(
        tester.widget<ContextualFindRegion>(_region('viewer')).isSelected!(),
        isFalse,
      );
      await _chord(tester);
      expect(fixture.calls, ['find:page']);

      fixture.change(() => fixture.inheritSelection.add('viewer'));
      await tester.pump();
      expect(
        tester.widget<ContextualFindRegion>(_region('viewer')).isSelected,
        isNull,
      );
      await _chord(tester);
      expect(fixture.calls.last, 'find:viewer');

      fixture.change(() => fixture.inheritSelection.remove('viewer'));
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');
      fixture.selected
        ..remove('file')
        ..add('viewer');
      await _chord(tester);
      expect(fixture.calls.last, 'find:viewer');
      expect(ContextualFindSelection.maybeOf(viewer)!.isSelected(), isFalse);
    });
  });

  _test('nearest marker cannot select an enclosing or independent find root',
      (tester) async {
    final focus = FocusNode();
    final calls = <String>[];
    var selected = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: focus,
            autofocus: true,
            child: ContextualFindSelection(
              isSelected: () => true,
              child: Row(
                children: [
                  Expanded(
                    child: ContextualFindRegion(
                      key: const ValueKey('region-page'),
                      onFind: () => calls.add('page'),
                      child: ContextualFindSelection(
                        isSelected: () => true,
                        child: Center(
                          child: ContextualFindSelection(
                            isSelected: () => selected,
                            child: ContextualFindRegion(
                              key: const ValueKey('region-viewer'),
                              onFind: () => calls.add('viewer'),
                              child: const SizedBox(width: 100, height: 100),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ContextualFindRegion(
                      key: const ValueKey('region-sibling'),
                      onFind: () => calls.add('sibling'),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final page = tester.element(_region('page'));
      final sibling = tester.element(_region('sibling'));
      expect(ContextualFindSelection.maybeOf(page), isNull);
      expect(ContextualFindSelection.maybeOf(sibling), isNull);
      expect(
        ContextualFindSelection.maybeOf(
          tester.element(_region('viewer')),
        )!
            .isSelected(),
        isFalse,
      );
      expect(ContextualFindRegion.dispatch(page), isFalse);
      expect(ContextualFindRegion.dispatch(sibling), isFalse);
      expect(calls, isEmpty);

      selected = true;
      expect(ContextualFindRegion.dispatch(sibling), isFalse);
      expect(ContextualFindRegion.dispatch(page), isTrue);
      expect(calls, ['viewer']);
      expect(focus.hasPrimaryFocus, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    }
  });

  for (final mode in [
    'inactive',
    'disabled',
    'offstage',
    'ticker',
    'opacity',
    'clip',
    'offscreen',
  ]) {
    _test('selected file marker cannot bypass $mode viewer availability',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        fixture.focusOnFind = false;
        fixture.change(() {
          fixture.showImage = false;
          fixture.inheritSelection.addAll(['viewer', 'other-tab']);
        });
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_hit('page')));
        fixture.selected.addAll(['page', 'file']);
        await _chord(tester);
        expect(fixture.calls, ['find:viewer']);
        final viewer = tester.state(_region('viewer'));

        if (mode == 'inactive') {
          fixture.inactive.add('viewer'); // Live readiness, no rebuild.
        } else {
          fixture.change(() => fixture.visibility = mode);
          await tester.pump();
        }
        await _chord(tester);
        expect(fixture.calls.last, 'find:page');
        expect(tester.state(_region('viewer', offstage: true)), same(viewer));

        fixture.inactive.clear();
        fixture.change(() => fixture.visibility = 'visible');
        await tester.pump();
        await _chord(tester);
        expect(fixture.calls.last, 'find:viewer');
      });
    });
  }

  _test(
      'selected file does not steal toolbar/native focus or bypass native find',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      fixture.change(() {
        fixture.showImage = false;
        fixture.showNative = true;
        fixture.inheritSelection.add('viewer');
      });
      await tester.pump();
      fixture.selected.addAll(['page', 'file']);
      await mouse.moveTo(tester.getCenter(_hit('page')));
      for (final node in [fixture.toolbarFocus, fixture.nativeFocus]) {
        node.requestFocus();
        await tester.pump();
        await _chord(tester);
        expect(node.hasPrimaryFocus, isTrue);
        expect(fixture.calls, isEmpty);
      }
      expect(fixture.localCalls, ['toolbar:find', 'platform:find']);
      expect(fixture.outerCalls, isEmpty);

      fixture.focus['page']!.requestFocus();
      fixture.change(() => fixture.nativeViewer = true);
      await tester.pump();
      expect(
        ContextualFindRegion.dispatch(tester.element(_region('page'))),
        isFalse,
      );
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.outerCalls, ['find']);
    });
  });

  for (final routed in [false, true]) {
    _test(
        'selected embedded PDF stays behind fullscreen dialog (routed=$routed)',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        fixture.focusOnFind = false;
        fixture.change(() {
          fixture.showImage = false;
          fixture.inheritSelection.add('viewer');
        });
        await tester.pump();
        fixture.selected.addAll(['page', 'file']);
        await mouse.moveTo(tester.getCenter(_hit('page')));
        var dialogCalls = 0;
        const content = Focus(
          autofocus: true,
          child: SizedBox.expand(),
        );
        final dialog = showDialog<void>(
          context: tester.element(_region('viewer')),
          builder: (_) => Dialog.fullscreen(
            child: routed
                ? ContextualFindRegion(
                    key: const ValueKey('region-fullscreen'),
                    onFind: () => dialogCalls++,
                    child: content,
                  )
                : _localShortcuts(() => dialogCalls++, child: content),
          ),
        );
        await tester.pumpAndSettle();
        if (routed) {
          expect(
            ContextualFindSelection.maybeOf(
              tester.element(_region('fullscreen')),
            ),
            isNull,
          );
        }
        expect(
          ContextualFindRegion.dispatch(tester.element(_region('page'))),
          isFalse,
        );
        await _chord(tester);
        expect(dialogCalls, 1);
        expect(fixture.calls, isEmpty);
        fixture.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await dialog;

        fixture.focus['page']!.requestFocus();
        await tester.pump();
        await _chord(tester);
        expect(fixture.calls, ['find:viewer']);
        expect(dialogCalls, 1);
      });
    });
  }

  _test('last owner expires on nonfocusable outside clicks and focus changes',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester);
      await mouse.moveTo(_away);
      await _chord(tester);
      expect(fixture.calls, ['find:viewer', 'find:viewer']);
      final focus = FocusManager.instance.primaryFocus;
      await tester.tap(find.byKey(const ValueKey('nonfocusable-outside')));
      await tester.pump();
      expect(fixture.outsideTaps, 1);
      expect(FocusManager.instance.primaryFocus, same(focus));
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');

      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester);
      await mouse.moveTo(_away);
      fixture.toolbarFocus.requestFocus();
      await tester.pump();
      final before = fixture.calls.length;
      await _chord(tester);
      expect(fixture.calls.length, before);
      expect(fixture.localCalls.last, 'toolbar:find');
      fixture.focus['page']!.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');
    });
  });

  _test(
      'dismiss every already-open old owner before opening, without refocusing',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.change(() {
        fixture.showSibling = true;
        fixture.open.addAll(['page', 'viewer', 'sibling']);
      });
      await tester.pump();
      fixture.queryFocus['viewer']!.requestFocus();
      await tester.pump();
      final focusHistory = <FocusNode?>[];
      void changed() => focusHistory.add(FocusManager.instance.primaryFocus);
      FocusManager.instance.addListener(changed);
      try {
        await mouse.moveTo(tester.getCenter(_hit('image')));
        await _chord(tester);
        expect(fixture.calls, ['dismiss:page', 'dismiss:viewer', 'find:image']);
        expect(fixture.open, {'image', 'sibling'});
        expect(fixture.queryFocus['image']!.hasPrimaryFocus, isTrue);
        expect(focusHistory, isNot(contains(fixture.focus['page'])));
        expect(focusHistory, isNot(contains(fixture.focus['viewer'])));
        expect(fixture.outerCalls, isEmpty);
      } finally {
        FocusManager.instance.removeListener(changed);
      }
    });
  });

  _test(
      'replace stays with selected owner; read-only viewers never replace page',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      for (final id in ['viewer', 'image']) {
        await mouse.moveTo(tester.getCenter(_hit(id)));
        expect(await _chord(tester, key: LogicalKeyboardKey.keyH), isTrue);
        expect(fixture.calls, isEmpty);
        expect(fixture.outerCalls, isEmpty);
        expect(fixture.localCalls, isEmpty);
        expect(
          ContextualFindRegion.dispatch(
            tester.element(_region('page')),
            replace: true,
          ),
          isTrue,
        );
        expect(fixture.calls, isEmpty);
      }
      fixture.change(() => fixture.viewerCanReplace = true);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester, key: LogicalKeyboardKey.keyH);
      expect(fixture.calls, ['replace:viewer']);
      await mouse.moveTo(tester.getCenter(_hit('page')));
      await tester.tap(_hit('page'));
      await _chord(tester, key: LogicalKeyboardKey.keyH);
      expect(fixture.calls.last, 'replace:page');
    });
  });

  _test('Alt/Shift/extra modifiers and unrelated keys retain native shortcuts',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      await mouse.moveTo(tester.getCenter(_hit('image')));
      for (final extra in [
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await _chord(tester, extra: [extra]);
      }
      await _chord(
        tester,
        modifier: LogicalKeyboardKey.controlLeft,
        extra: [LogicalKeyboardKey.metaLeft],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(fixture.calls, isEmpty);
      expect(fixture.localCalls, [
        'alt-find',
        'shift-find',
        'both-modifiers',
        'escape',
        'down',
        'plain-f',
      ]);
      expect(fixture.outerCalls, isEmpty);
    });
  });

  for (final where in ['outside', 'inside']) {
    _test('unrelated $where TextField owns Find even with an image hovered',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        await mouse.moveTo(tester.getCenter(_hit('image')));
        final node =
            where == 'outside' ? fixture.outsideFocus : fixture.insideFocus;
        node.requestFocus();
        await tester.pump();
        await _chord(tester);
        expect(node.hasPrimaryFocus, isTrue);
        expect(fixture.calls, isEmpty);
        expect(fixture.localCalls, ['$where:find']);
        expect(fixture.outerCalls, isEmpty);
      });
    });
  }

  for (final mode in [
    'disabled',
    'offstage',
    'ticker',
    'opacity',
    'clip',
    'offscreen',
  ]) {
    _test('$mode target cannot claim its retained focus or selection',
        (tester) async {
      await _withFixture(tester, (fixture, mouse) async {
        fixture.focusOnFind = false;
        fixture.focus['viewer']!.requestFocus();
        await tester.pump();
        await mouse.moveTo(_away);
        fixture.selected.add('viewer');
        fixture.change(() => fixture.visibility = mode);
        await tester.pump();
        expect(_region('viewer', offstage: true), findsOneWidget);
        await _chord(tester);
        expect(fixture.calls, isEmpty);
        // Returning onstage must use current geometry/focus, not a cached false.
        fixture.change(() => fixture.visibility = 'visible');
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_hit('viewer')));
        await _chord(tester);
        expect(fixture.calls, ['find:viewer']);
      });
    });
  }

  _test('disabled hovered child does not redirect Find to its parent',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.change(() => fixture.imageEnabled = false);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(_hit('image')));
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.outerCalls, ['find']);
    });
  });

  _test(
      'disposed hover is hit-tested anew; removing focused query drops ownership',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(tester.getCenter(_hit('image')));
      await _chord(tester);
      final imageContext = tester.element(_region('image'));
      fixture.change(() => fixture.showImage = false);
      await tester.pump();
      expect(imageContext.mounted, isFalse);
      expect(ContextualFindRegion.dispatch(imageContext), isFalse);
      await _chord(tester); // No mouse movement; now the viewer is underneath.
      expect(fixture.calls.last, 'find:viewer');

      fixture.focusOnFind = true;
      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester);
      expect(fixture.queryFocus['viewer']!.hasPrimaryFocus, isTrue);
      await mouse.moveTo(_away);
      fixture.change(() => fixture.showViewer = false);
      await tester.pump();
      await tester.pump();
      expect(fixture.queryFocus['viewer']!.parent, isNull);
      final before = fixture.calls.length;
      await _chord(tester);
      expect(fixture.calls.skip(before), isNot(contains('find:viewer')));
      expect(fixture.calls.skip(before), isNot(contains('find:image')));
      expect(ContextualFindRegion.debugRegisteredRegionCount, 1);
    });
  });

  _test(
      'removed focused descendant cannot leave a cached focused viewer behind',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      await mouse.moveTo(_away);
      fixture.childFocus.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls, ['find:viewer']);
      fixture.change(() => fixture.showFocusedChild = false);
      await tester.pump();
      await tester.pump();
      expect(fixture.childFocus.parent, isNull);
      fixture.focus['page']!.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:page');
    });
  });

  _test(
      'retained tabs, themes and resize preserve state and refresh cursor hits',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      final regionState = tester.state(_region('viewer'));
      final viewerBox = _mountedBox(tester, _region('viewer'));
      final draft = tester.state<_DraftState>(find.byType(_Draft));
      draft.text.value = const TextEditingValue(
        text: 'Unsaved preview draft',
        selection: TextSelection(baseOffset: 1, extentOffset: 9),
      );
      draft.scroll.jumpTo(72);
      final value = draft.text.value;
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(_Draft),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(scrollable.widget.controller, same(draft.scroll));
      final viewerPoint = tester.getCenter(_hit('viewer'));
      await mouse.moveTo(viewerPoint);
      await _chord(tester);
      expect(fixture.calls, ['find:viewer']);
      for (final theme in [ThemeData.light(), ThemeData.dark(), _warmTheme]) {
        expect(
          theme.platform,
          defaultTargetPlatform,
          reason: 'Changing appearance must not change the test platform.',
        );
        fixture.change(() => fixture.theme = theme);
        await tester.pump();
        expect(
          Theme.of(tester.element(_hit('viewer'))).platform,
          defaultTargetPlatform,
        );
        expect(_mountedBox(tester, _region('viewer')), same(viewerBox));
        expect(
          tester
              .hitTestOnBinding(viewerPoint)
              .path
              .map((entry) => entry.target),
          contains(same(viewerBox)),
          reason: 'The stationary pointer must still hit the retained viewer.',
        );
        await _chord(tester);
        expect(fixture.calls.last, 'find:viewer');
        expect(tester.state(_region('viewer')), same(regionState));
        expect(tester.state(find.byType(_Draft)), same(draft));
        expect(draft.text.value, value);
        // Flutter recreates ScrollPosition when inherited scroll behavior
        // changes with a theme. Its owning scrollable/controller and offset
        // must survive; a router must not remount the content.
        expect(
          tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(_Draft),
                  matching: find.byType(Scrollable),
                )
                .last,
          ),
          same(scrollable),
        );
        expect(draft.scroll.offset, 72);
        expect(
          Theme.of(tester.element(_hit('viewer'))).colorScheme.surface,
          theme.colorScheme.surface,
        );
      }
      fixture.selected.add('viewer');
      fixture.change(() => fixture.tab = 1);
      await tester.pump();
      await _chord(
        tester,
      ); // Stationary pointer, same rectangle, different tab.
      expect(fixture.calls.last, 'find:other-tab');
      expect(
        tester.state(_region('viewer', offstage: true)),
        same(regionState),
      );
      expect(draft.text.value, value);
      fixture.change(() => fixture.tab = 0);
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls.last, 'find:viewer');
      fixture.selected.clear();
      fixture.change(() => fixture.viewerLeft = 210);
      tester.view.physicalSize = const Size(840, 700);
      await tester.pump();
      await _chord(tester); // Old cursor is now over page text, not the viewer.
      expect(fixture.calls.last, 'find:page');
      expect(tester.state(_region('viewer')), same(regionState));
      expect(draft.text.value, value);
      expect(
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(_Draft),
                matching: find.byType(Scrollable),
              )
              .last,
        ),
        same(scrollable),
      );
      expect(draft.scroll.offset, 72);
    });
  });

  _test('dialog and popup route own keys despite stationary underlying hover',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      await mouse.moveTo(tester.getCenter(_hit('image')));
      final dialog = showDialog<void>(
        context: tester.element(_hit('page')),
        builder: (_) => AlertDialog(
          content: _localShortcuts(
            () => fixture.localCalls.add('dialog:find'),
            child: const Focus(
              autofocus: true,
              child: Text('Dialog owns the keyboard'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.localCalls, ['dialog:find']);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;

      final menu = showMenu<void>(
        context: tester.element(_hit('page')),
        position: const RelativeRect.fromLTRB(20, 20, 700, 500),
        items: const [PopupMenuItem(child: Text('Context menu action'))],
      );
      await tester.pumpAndSettle();
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await menu;
      fixture.focus['page']!.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
    });
  });

  _test('current dialog region wins, including over nested navigator regions',
      (tester) async {
    final nested = GlobalKey<NavigatorState>();
    final pageFocus = FocusNode();
    var pageCalls = 0;
    var dialogCalls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => ContextualFindRegion(
                onFind: () => pageCalls++,
                isSelected: () => true,
                child: Focus(
                  focusNode: pageFocus,
                  autofocus: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _chord(tester);
      expect(pageCalls, 1);
      final dialog = showDialog<void>(
        context: pageFocus.context!,
        builder: (_) => AlertDialog(
          content: ContextualFindRegion(
            onFind: () => dialogCalls++,
            child: const Focus(
              autofocus: true,
              child: SizedBox(width: 180, height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _chord(tester);
      expect(pageCalls, 1);
      expect(dialogCalls, 1);
      Navigator.of(pageFocus.context!, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await dialog;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      pageFocus.dispose();
    }
  });

  _test('non-route overlay occlusion and portal menu focus prevent page hijack',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      await mouse.moveTo(tester.getCenter(_hit('image')));
      final overlay = OverlayEntry(
        builder: (_) => const Positioned.fill(
          child: ColoredBox(color: Color(0xFF424242)),
        ),
      );
      Overlay.of(tester.element(_hit('page'))).insert(overlay);
      try {
        await tester.pump();
        await _chord(tester);
        expect(fixture.calls, isEmpty);
        expect(fixture.outerCalls, ['find']);
      } finally {
        overlay.remove();
        overlay.dispose();
        await tester.pump();
      }
      fixture.outerCalls.clear();
      fixture.portal.show();
      await tester.pump();
      fixture.portalFocus.requestFocus();
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.localCalls, ['portal:find']);
      expect(fixture.outerCalls, isEmpty);
      fixture.portal.hide();
      await tester.pump();
    });
  });

  _test('native platform view and texture-backed opt-out retain local commands',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.change(() => fixture.showNative = true);
      await tester.pump();
      fixture.nativeFocus.requestFocus();
      await tester.pump();
      expect(fixture.nativeFocus.hasPrimaryFocus, isTrue);
      await mouse.moveTo(tester.getCenter(_hit('image')));
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.localCalls, ['platform:find']);
      fixture.change(() => fixture.nativeViewer = true);
      fixture.focus['viewer']!.requestFocus();
      await tester.pump();
      expect(fixture.focus['viewer']!.hasPrimaryFocus, isTrue);
      await _chord(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.localCalls, ['platform:find', 'viewer:find']);
      expect(fixture.outerCalls, isEmpty);

      // Prove the negative cases used a live router, not a leaked handler on
      // an earlier test's FocusManager.
      fixture.focusOnFind = false;
      fixture.change(() => fixture.nativeViewer = false);
      await tester.pump();
      await _chord(tester);
      expect(fixture.calls, ['find:image']);
      expect(fixture.localCalls, ['platform:find', 'viewer:find']);
      expect(fixture.outerCalls, isEmpty);
    });
  });

  _test(
      'explicit dispatch is subtree-scoped; identical labels never join owners',
      (tester) async {
    await _withFixture(tester, (fixture, mouse) async {
      fixture.focusOnFind = false;
      fixture.change(() {
        fixture.showSibling = true;
        fixture.open.addAll(['viewer', 'sibling']);
      });
      await tester.pump();
      final viewer = tester.element(_region('viewer'));
      final page = tester.element(_region('page'));
      await mouse.moveTo(tester.getCenter(_hit('image')));
      expect(ContextualFindRegion.dispatch(viewer), isTrue);
      await tester.pump();
      expect(fixture.calls, ['dismiss:viewer', 'find:image']);
      expect(fixture.open.contains('sibling'), isTrue);
      fixture.calls.clear();
      await mouse.moveTo(tester.getCenter(_hit('sibling')));
      expect(ContextualFindRegion.dispatch(viewer), isFalse);
      expect(ContextualFindRegion.dispatch(page), isFalse);
      expect(fixture.calls, isEmpty);
      await _chord(tester);
      expect(fixture.calls, ['find:sibling']);
      expect(fixture.open.contains('image'), isTrue);
      expect(fixture.open.contains('sibling'), isTrue);
    });
  });

  _test('frontmost overlapping sibling wins, not a deeper behind sibling',
      (tester) async {
    final focus = FocusNode();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final calls = <String>[];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: focus,
            autofocus: true,
            child: Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Builder(
                        builder: (_) => ContextualFindRegion(
                          debugLabel: 'same',
                          onFind: () => calls.add('behind'),
                          child: const ColoredBox(color: Color(0xFF999999)),
                        ),
                      ),
                    ),
                    ContextualFindRegion(
                      debugLabel: 'same',
                      onFind: () => calls.add('front'),
                      child: const ColoredBox(
                        key: ValueKey('front'),
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('front'))),
      );
      await _chord(tester);
      expect(calls, ['front']);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    }
  });

  _test('fixture body failure still disposes before a fresh mount',
      (tester) async {
    final failure = StateError('Deliberate fixture body failure');
    late _FixtureState oldFixture;
    late RenderBox oldPage;
    late EditableTextState oldQuery;
    late RenderEditable oldQueryRender;
    var caught = false;
    try {
      await _withFixture(tester, (fixture, mouse) async {
        oldFixture = fixture;
        oldPage = _mountedBox(tester, _region('page'));
        await mouse.moveTo(tester.getCenter(_hit('viewer')));
        await _chord(tester);
        oldQuery = tester.state<EditableTextState>(
          find.descendant(
            of: _query('viewer'),
            matching: find.byType(EditableText),
          ),
        );
        expect(oldQuery.widget.focusNode.hasPrimaryFocus, isTrue);
        oldQueryRender = oldQuery.renderEditable;
        expect(oldQueryRender.attached, isTrue);
        fixture.portal.show();
        await tester.pump();
        throw failure;
      });
    } on StateError catch (error) {
      expect(error, same(failure));
      caught = true;
    }
    expect(caught, isTrue);
    expect(oldFixture.mounted, isFalse);
    expect(oldQuery.mounted, isFalse);
    expect(oldPage.attached, isFalse);
    expect(oldQueryRender.attached, isFalse);
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
    expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);

    await _withFixture(tester, (fixture, mouse) async {
      await mouse.moveTo(tester.getCenter(_hit('viewer')));
      await _chord(tester);
      expect(fixture.calls, ['find:viewer']);
    });
  });

  _test(
      'one global registration, final cleanup, then stationary-cursor remount',
      (tester) async {
    final count = ValueNotifier(0);
    final focus = FocusNode();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    var calls = 0;
    var nativeCalls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: _localShortcuts(
            () => nativeCalls++,
            child: Focus(
              focusNode: focus,
              autofocus: true,
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: count,
                  builder: (_, value, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < value; index++)
                        ContextualFindRegion(
                          key: ValueKey('registered-$index'),
                          onFind: () => calls++,
                          child: const SizedBox(width: 80, height: 80),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final routes =
          GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
      expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
      count.value = 3;
      await tester.pump();
      expect(ContextualFindRegion.debugRegisteredRegionCount, 3);
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isTrue);
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        routes + 1,
      );
      await mouse.addPointer(
        location: tester.getCenter(
          find.byKey(const ValueKey('registered-0')),
        ),
      );
      var events = ContextualFindRegion.debugKeyEventCount;
      await _chord(tester);
      expect(calls, 1);
      expect(ContextualFindRegion.debugKeyEventCount - events, 4);
      count.value = 1;
      await tester.pump();
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isTrue);
      expect(ContextualFindRegion.debugRegisteredRegionCount, 1);
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        routes + 1,
      );
      await mouse
          .moveTo(tester.getCenter(find.byKey(const ValueKey('registered-0'))));
      count.value = 0;
      await tester.pump();
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
      expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        routes,
      );
      events = ContextualFindRegion.debugKeyEventCount;
      await _chord(tester);
      expect(ContextualFindRegion.debugKeyEventCount, events);
      expect(nativeCalls, 1);

      count.value = 1;
      await tester
          .pump(); // No movement; MouseRegion must seed the live cursor.
      events = ContextualFindRegion.debugKeyEventCount;
      await _chord(tester);
      expect(calls, 2);
      expect(nativeCalls, 1);
      expect(ContextualFindRegion.debugKeyEventCount - events, 4);
      count.value = 0;
      await tester.pump();
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        routes,
      );
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
      count.dispose();
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        expect(
          ContextualFindRegion.debugRegisteredRegionCount,
          0,
          reason: 'A previous test left find regions registered before $name.',
        );
        expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
        final routes =
            GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
        // Keep cleanup failures separate from the original body failure, and
        // check standalone fixtures too. Never reset the production singleton.
        addTearDown(() {
          expect(
            ContextualFindRegion.debugRegisteredRegionCount,
            0,
            reason:
                '$name must unmount all find regions, including on failure.',
          );
          expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
          expect(
            GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
            routes,
          );
        });
        await body(tester);
      },
      variant:
          TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS}),
      timeout: const Timeout(Duration(seconds: 20)),
    );

Finder _region(String id, {bool offstage = false}) =>
    find.byKey(ValueKey('region-$id'), skipOffstage: !offstage);
Finder _hit(String id) => find.byKey(ValueKey('hit-$id'));
Finder _query(String id) => find.byKey(ValueKey('query-$id'));

Finder _fieldForFocus(FocusNode node) => find.byWidgetPredicate(
      (widget) => widget is TextField && identical(widget.focusNode, node),
    );

RenderBox _mountedBox(WidgetTester tester, Finder finder) {
  expect(tester.element(finder).mounted, isTrue);
  final render = tester.renderObject<RenderBox>(finder);
  expect(render.attached, isTrue);
  expect(render.hasSize, isTrue);
  expect(render.size.isFinite, isTrue);
  expect(render.size.isEmpty, isFalse);
  return render;
}

Offset _editablePoint(WidgetTester tester, Finder field) {
  final render = tester
      .state<EditableTextState>(
        find.descendant(
          of: field,
          matching: find.byType(EditableText),
        ),
      )
      .renderEditable;
  expect(render, isA<RenderEditable>());
  expect(render.attached, isTrue);
  expect(render.size.isEmpty, isFalse);
  final point = render.localToGlobal(render.size.center(Offset.zero));
  expect(
    tester.hitTestOnBinding(point).path.any(
          (entry) => identical(entry.target, render),
        ),
    isTrue,
    reason: 'Hit the editable text itself, not its padding or a label proxy.',
  );
  return point;
}

Future<bool> _chord(
  WidgetTester tester, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyF,
  LogicalKeyboardKey? modifier,
  List<LogicalKeyboardKey> extra = const [],
  int repeats = 0,
}) async {
  modifier ??= defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  for (final key in extra) {
    await tester.sendKeyDownEvent(key);
  }
  final handled = await tester.sendKeyDownEvent(key);
  try {
    for (var repeat = 0; repeat < repeats; repeat++) {
      expect(await tester.sendKeyRepeatEvent(key), isTrue);
    }
  } finally {
    await tester.sendKeyUpEvent(key);
    for (final key in extra.reversed) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
  await tester.pump();
  return handled;
}

Widget _localShortcuts(
  VoidCallback find, {
  required Widget child,
  VoidCallback? replace,
}) =>
    CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): find,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): find,
        if (replace != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              replace,
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true): replace,
        },
      },
      child: child,
    );

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_FixtureState fixture, TestGesture mouse) body,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 720);
  final key = GlobalKey<_FixtureState>();
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  try {
    await mouse.addPointer(location: _away);
    await tester.pumpWidget(_Fixture(key: key));
    expect(tester.takeException(), isNull, reason: 'Fixture mount failed.');
    final fixture = key.currentState!;
    fixture.focus['page']!.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(fixture.focus['page']!.hasPrimaryFocus, isTrue);
    expect(ContextualFindRegion.debugRegisteredRegionCount, 4);
    expect(ContextualFindRegion.debugHasEarlyKeyHandler, isTrue);
    await body(fixture, mouse);
    expect(tester.takeException(), isNull);
  } finally {
    try {
      await mouse.removePointer();
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }
  }
}

// Inject a warm surface without coupling these routing tests to app theme or
// editor packages. The region must preserve any inherited theme unchanged.
// Construct per variant: caching ThemeData also caches the first platform and
// can switch MaterialPageRoute's transition subtree in the next variant.
ThemeData get _warmTheme => ThemeData.light().copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B754B))
          .copyWith(surface: const Color(0xFFF7F2E8)),
    );

class _Fixture extends StatefulWidget {
  const _Fixture({super.key});

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final navigator = GlobalKey<NavigatorState>();
  final focus = {
    for (final id in _ids) id: FocusNode(debugLabel: '$id content'),
  };
  final queryFocus = {
    for (final id in _ids) id: FocusNode(debugLabel: '$id query'),
  };
  final queries = {for (final id in _ids) id: TextEditingController()};
  final outsideFocus = FocusNode();
  final insideFocus = FocusNode();
  final toolbarFocus = FocusNode();
  final nativeFocus = FocusNode();
  final portalFocus = FocusNode();
  final childFocus = FocusNode();
  final portal = OverlayPortalController();
  final calls = <String>[];
  final localCalls = <String>[];
  final outerCalls = <String>[];
  final selected = <String>{};
  final inheritSelection = <String>{};
  final inactive = <String>{};
  final open = <String>{};
  ThemeData theme = ThemeData.light();
  bool focusOnFind = true;
  bool externalQuery = true;
  bool showViewer = true;
  bool showImage = true;
  bool showSibling = false;
  bool showNative = false;
  bool showFocusedChild = true;
  bool nativeViewer = false;
  bool imageEnabled = true;
  bool viewerCanReplace = false;
  bool viewerFindInEditable = false;
  String visibility = 'visible';
  int tab = 0;
  int outsideTaps = 0;
  double viewerLeft = 30;

  void change(VoidCallback update) => setState(update);

  void _open(String id, {bool replace = false}) {
    calls.add('${replace ? 'replace' : 'find'}:$id');
    setState(() => open.add(id));
    if (focusOnFind) queryFocus[id]!.requestFocus();
  }

  void _dismiss(String id) {
    calls.add('dismiss:$id');
    setState(() => open.remove(id));
    // Intentionally no unfocus/requestFocus or restoration of the old caret.
  }

  KeyEventResult _outerKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        keyboard.isControlPressed != keyboard.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyF ||
          event.logicalKey == LogicalKeyboardKey.keyH) {
        outerCalls.add(
          event.logicalKey == LogicalKeyboardKey.keyF ? 'find' : 'replace',
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _target(String id, Widget child) => ContextualFindRegion(
        key: ValueKey('region-$id'),
        debugLabel: 'Same label',
        // These legacy local-shortcut tests exercise the explicit opt-out.
        // Default navigation/hover behavior is covered by active_page_find.
        claimHoverFromControls: false,
        onFind: () => _open(id),
        onReplace: id == 'page' || (id == 'viewer' && viewerCanReplace)
            ? () => _open(id, replace: true)
            : null,
        onDismiss: () => _dismiss(id),
        findOpen: open.contains(id),
        findFocusNode: queryFocus[id],
        enabled: (id != 'viewer' || visibility != 'disabled') &&
            (id != 'image' || imageEnabled),
        isActive: () => !inactive.contains(id),
        findInEditable: id == 'viewer' && viewerFindInEditable,
        useNativeFind: id == 'viewer' && nativeViewer,
        isSelected:
            inheritSelection.contains(id) ? null : () => selected.contains(id),
        child: _localShortcuts(
          () => localCalls.add('$id:find'),
          replace: () => localCalls.add('$id:replace'),
          child: Focus(
            focusNode: focus[id],
            onKeyEvent: id == 'page' ? _outerKey : null,
            child: child,
          ),
        ),
      );

  Widget _search(String id) => TextField(
        key: ValueKey('query-$id'),
        focusNode: queryFocus[id],
        controller: queries[id],
        decoration: const InputDecoration(isDense: true),
      );

  Widget _label(String id) => SizedBox(
        key: ValueKey('hit-$id'),
        width: 100,
        height: 30,
        child: Text('$id content'),
      );

  Widget _viewer(BuildContext context) => _target(
        'viewer',
        Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Theme.of(context).colorScheme.surface),
            Positioned(left: 8, top: 8, child: _label('viewer')),
            const Positioned(
              left: 8,
              top: 55,
              width: 180,
              height: 120,
              child: _Draft(),
            ),
            if (showFocusedChild)
              Positioned(
                key: const ValueKey('viewer-focused-child'),
                left: 8,
                bottom: 4,
                child: Focus(
                  focusNode: childFocus,
                  child: const Text('Nested focus'),
                ),
              ),
            if (open.contains('viewer') && !externalQuery)
              Positioned(
                key: const ValueKey('viewer-internal-query'),
                left: 8,
                top: 205,
                width: 200,
                height: 38,
                child: _search('viewer'),
              ),
            if (showImage)
              Positioned(
                key: const ValueKey('pane-image'),
                right: 14,
                bottom: 14,
                width: 110,
                height: 90,
                child: _target(
                  'image',
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Stack(
                      children: [
                        Positioned(left: 0, top: 0, child: _label('image')),
                        if (open.contains('image'))
                          Positioned(
                            left: 0,
                            bottom: 0,
                            width: 110,
                            height: 36,
                            child: _search('image'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigator,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Builder(
          builder: (context) => CallbackShortcuts(
            bindings: {
              for (final meta in [false, true]) ...{
                SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: !meta,
                  meta: meta,
                  alt: true,
                ): () => localCalls.add('alt-find'),
                SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: !meta,
                  meta: meta,
                  shift: true,
                ): () => localCalls.add('shift-find'),
              },
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                control: true,
                meta: true,
              ): () => localCalls.add('both-modifiers'),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  localCalls.add('escape'),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  localCalls.add('down'),
              const SingleActivator(LogicalKeyboardKey.keyF): () =>
                  localCalls.add('plain-f'),
            },
            child: Focus(
              onKeyEvent: _outerKey,
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 200,
                      height: 48,
                      child: _localShortcuts(
                        () => localCalls.add('outside:find'),
                        child: TextField(focusNode: outsideFocus),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      width: 200,
                      height: 48,
                      child: _localShortcuts(
                        () => localCalls.add('toolbar:find'),
                        child: TextButton(
                          focusNode: toolbarFocus,
                          onPressed: () {},
                          child: const Text('Unrelated toolbar'),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 70,
                      width: 140,
                      height: 32,
                      child: Listener(
                        key: const ValueKey('nonfocusable-outside'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => outsideTaps++,
                        child: const Text('Outside interaction'),
                      ),
                    ),
                    if (showSibling)
                      Positioned(
                        key: const ValueKey('pane-sibling'),
                        left: 8,
                        top: 150,
                        width: 130,
                        height: 180,
                        child: _target('sibling', _label('sibling')),
                      ),
                    // Key the actual Stack siblings: a key on the inner
                    // region cannot prevent a page/portal remount when
                    // another Positioned is inserted before this pane.
                    Positioned(
                      key: const ValueKey('pane-page'),
                      left: 180,
                      top: 100,
                      width: 600,
                      height: 440,
                      child: _target(
                        'page',
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: _label('page'),
                            ),
                            Positioned(
                              right: 10,
                              top: 12,
                              width: 160,
                              height: 48,
                              child: _localShortcuts(
                                () => localCalls.add('inside:find'),
                                child: TextField(focusNode: insideFocus),
                              ),
                            ),
                            if (showViewer)
                              Positioned(
                                key: const ValueKey('pane-viewer'),
                                left: viewerLeft,
                                top: 80,
                                width: 340,
                                height: 280,
                                child: ClipRect(
                                  clipper: visibility == 'clip'
                                      ? const _EmptyClip()
                                      : null,
                                  child: Transform.translate(
                                    offset: visibility == 'offscreen'
                                        ? const Offset(1000, 0)
                                        : Offset.zero,
                                    child: Offstage(
                                      offstage: visibility == 'offstage',
                                      child: Opacity(
                                        opacity:
                                            visibility == 'opacity' ? 0 : 1,
                                        child: TickerMode(
                                          enabled: visibility != 'ticker',
                                          child: ContextualFindSelection(
                                            isSelected: () =>
                                                selected.contains('file'),
                                            child: IndexedStack(
                                              index: tab,
                                              sizing: StackFit.expand,
                                              children: [
                                                _viewer(context),
                                                _target(
                                                  'other-tab',
                                                  ColoredBox(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.surface,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.topLeft,
                                                      child: _label(
                                                        'other-tab',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (showNative)
                              Positioned(
                                key: const ValueKey('native-surface'),
                                right: 8,
                                top: 160,
                                width: 150,
                                height: 140,
                                child: _localShortcuts(
                                  () => localCalls.add('platform:find'),
                                  child: Focus(
                                    focusNode: nativeFocus,
                                    child: PlatformViewSurface(
                                      controller: _NativeController(),
                                      hitTestBehavior:
                                          PlatformViewHitTestBehavior.opaque,
                                      gestureRecognizers: const <Factory<
                                          OneSequenceGestureRecognizer>>{},
                                    ),
                                  ),
                                ),
                              ),
                            OverlayPortal(
                              key: const ValueKey('page-portal'),
                              controller: portal,
                              overlayChildBuilder: (_) => Positioned(
                                left: 20,
                                top: 560,
                                width: 140,
                                height: 100,
                                child: _localShortcuts(
                                  () => localCalls.add('portal:find'),
                                  child: Focus(
                                    focusNode: portalFocus,
                                    child: const ColoredBox(
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ),
                              ),
                              child: const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showViewer && open.contains('viewer') && externalQuery)
                      Positioned(
                        key: const ValueKey('viewer-external-query'),
                        left: 180,
                        top: 558,
                        width: 280,
                        height: 48,
                        child: _search('viewer'),
                      ),
                    if (open.contains('page'))
                      Positioned(
                        key: const ValueKey('page-external-query'),
                        left: 480,
                        top: 558,
                        width: 280,
                        height: 48,
                        child: _search('page'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    for (final node in [
      ...focus.values,
      ...queryFocus.values,
      outsideFocus,
      insideFocus,
      toolbarFocus,
      nativeFocus,
      portalFocus,
      childFocus,
    ]) {
      node.dispose();
    }
    for (final controller in queries.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _EmptyClip extends CustomClipper<Rect> {
  const _EmptyClip();

  @override
  Rect getClip(Size size) => Rect.zero;

  @override
  bool shouldReclip(_EmptyClip oldClipper) => false;
}

class _NativeController extends Fake implements PlatformViewController {
  @override
  int get viewId => 42;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}
}

class _Draft extends StatefulWidget {
  const _Draft();

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final text = TextEditingController();
  final scroll = ScrollController();
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: TextField(
            controller: text,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            primary: false,
            itemExtent: 24,
            itemCount: 40,
            itemBuilder: (_, index) => Text('Retained row $index'),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }
}
