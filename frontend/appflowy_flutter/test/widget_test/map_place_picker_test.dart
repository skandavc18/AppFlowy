import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/map/map_block_component.dart';
import 'package:appflowy/shared/maps/app_map_marker.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_place_field.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _paris = MapSuggestion(
  title: 'Paris',
  subtitle: 'Paris, Ile-de-France, France',
  point: LatLng(48.8566, 2.3522),
);
const _texas = MapSuggestion(
  title: 'Paris, Texas',
  subtitle: 'Paris, Lamar County, Texas, United States',
  point: LatLng(33.6609, -95.5555),
);

const _placeField = ValueKey('map-block-place-field');
const _chooseOnMap = ValueKey('map-block-choose-on-map');

void main() {
  setUp(() {
    // Every lookup is answered from memory: no test reaches a geocoder.
    MapSuggestionCache.instance
      ..debugRemember('paris', const [_paris, _texas])
      ..debugRemember('atlantis', const []);
  });
  tearDown(MapSuggestionCache.instance.debugForget);

  group('MapPlaceField', () {
    testWidgets('offers places while typing and picks one with the keys',
        (tester) async {
      final host = await _pumpField(tester);

      await _type(tester, find.byType(TextField), 'Paris');
      expect(find.byType(MapSuggestionList), findsOneWidget);
      expect(_row('Paris'), findsOneWidget);
      expect(_row('Paris, Texas'), findsOneWidget);
      // Drawn in the window's overlay, just under the field.
      expect(
        tester.getTopLeft(find.byType(MapSuggestionList)).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(host.picked, [_texas]);
      expect(host.submitted, isEmpty);
      expect(host.controller.text, 'Paris, Texas');
      expect(find.byType(MapSuggestionList), findsNothing);
    });

    testWidgets('a click picks, Escape closes, Enter hands back the words',
        (tester) async {
      final host = await _pumpField(tester);

      await _type(tester, find.byType(TextField), 'Paris');
      await tester.tap(_row('Paris'));
      await tester.pump();
      await tester.pump();
      expect(host.picked, [_paris]);
      expect(host.controller.text, 'Paris');
      expect(find.byType(MapSuggestionList), findsNothing);

      await _type(tester, find.byType(TextField), 'Paris');
      expect(find.byType(MapSuggestionList), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MapSuggestionList), findsNothing);
      expect(host.picked, [_paris]);

      await _type(tester, find.byType(TextField), 'Atlantis');
      expect(find.text('map.noPlacesFound'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(host.submitted, ['Atlantis']);
      expect(host.picked, [_paris]);
    });
  });

  group('Map block', () {
    testWidgets('typed coordinates are offered and pinned from the empty block',
        (tester) async {
      const typed = '48.8584, 2.2945';
      final point = parseMapLocation(typed).point!;
      MapSuggestionCache.instance.debugRemember(typed, const []);
      final block = await _pumpBlock(tester);

      await _type(
        tester,
        find.descendant(
          of: find.byKey(_placeField),
          matching: find.byType(TextField),
        ),
        typed,
      );
      expect(_row(point.label), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settleEdits(tester);

      expect(block[MapBlockKeys.latitude], point.latitude);
      expect(block[MapBlockKeys.longitude], point.longitude);
      expect(block[MapBlockKeys.place], point.label);
      // Chosen before there was a map, so the map opens looking at it.
      expect(block[MapBlockKeys.viewLatitude], point.latitude);
      expect(block[MapBlockKeys.viewLongitude], point.longitude);
      expect(block[MapBlockKeys.zoom], 14.0);
      expect(find.byType(AppMapView), findsOneWidget);
      expect(find.byType(AppMapMarker), findsOneWidget);
      await tester.pump();
      expect(_camera(tester).center.latitude, closeTo(point.latitude, 1e-9));
      expect(_camera(tester).zoom, 14);
    });

    testWidgets(
        'a place is chosen by clicking the map, and looking around leaves '
        'the pin where it was put', (tester) async {
      final block = await _pumpBlock(tester);

      await tester.tap(find.byKey(_chooseOnMap));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AppMapView), findsOneWidget);
      expect(find.text('map.pinFromMap'), findsOneWidget);
      expect(find.byType(AppMapMarker), findsNothing);

      final map = find.byType(AppMapView);
      final origin = tester.getTopLeft(map);
      final center = tester.getCenter(map);
      final tapped = _camera(tester).toLatLng(center - origin);
      await _click(tester, center);
      await _settleEdits(tester);

      expect(block[MapBlockKeys.latitude], closeTo(tapped.latitude, 1e-9));
      expect(block[MapBlockKeys.longitude], closeTo(tapped.longitude, 1e-9));
      expect(block[MapBlockKeys.place], tapped.label);
      expect(find.text('map.pinFromMap'), findsNothing);
      expect(find.byType(AppMapMarker), findsOneWidget);
      // Named by its coordinates, the pin must not wear their first digit.
      expect(
        find.descendant(
          of: find.byType(AppMapMarker),
          matching: find.text('·'),
        ),
        findsOneWidget,
      );
      final pinnedLatitude = block[MapBlockKeys.latitude];
      final pinnedLongitude = block[MapBlockKeys.longitude];
      final pinning = block.editor.undoManager.undoStack.last;
      final pinningOperations = pinning.operations.length;

      // A plain click no longer pins; it focuses the map for the keys.
      await _click(tester, center + const Offset(-90, 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settleEdits(tester);

      expect(block[MapBlockKeys.latitude], pinnedLatitude);
      expect(block[MapBlockKeys.longitude], pinnedLongitude);
      final viewLongitude = block[MapBlockKeys.viewLongitude];
      expect(viewLongitude, isA<double>());
      expect(viewLongitude, _camera(tester).center.longitude);
      expect(viewLongitude, isNot(tapped.longitude));
      // Looking around is kept, but is not something to undo.
      expect(block.editor.undoManager.undoStack.last, same(pinning));
      expect(pinning.operations, hasLength(pinningOperations));

      // Right-click offers to move the pin to that spot.
      final target = center + const Offset(110, 50);
      final moved = _camera(tester).toLatLng(target - origin);
      await tester.tapAt(
        target,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('map.pinHere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settleEdits(tester);
      expect(block[MapBlockKeys.latitude], closeTo(moved.latitude, 1e-9));
      expect(block[MapBlockKeys.longitude], closeTo(moved.longitude, 1e-9));
    });

    testWidgets('choosing on the map can be called off', (tester) async {
      final block = await _pumpBlock(tester);

      await tester.tap(find.byKey(_chooseOnMap));
      await tester.pump();
      expect(find.byType(AppMapView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-block-pick-toggle')));
      await tester.pump();
      expect(find.byType(AppMapView), findsNothing);
      expect(find.byKey(_placeField), findsOneWidget);
      expect(block[MapBlockKeys.latitude], isNull);
    });

    testWidgets('a pin can be taken off, from its button or the map menu',
        (tester) async {
      final block = await _pumpBlock(
        tester,
        node: mapBlockNode(
          latitude: 48.8566,
          longitude: 2.3522,
          place: 'Paris',
        ),
      );
      expect(find.byType(AppMapMarker), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-block-remove-pin')));
      await _settleEdits(tester);

      for (final key in [
        MapBlockKeys.latitude,
        MapBlockKeys.longitude,
        MapBlockKeys.place,
        MapBlockKeys.viewLatitude,
        MapBlockKeys.viewLongitude,
        MapBlockKeys.zoom,
      ]) {
        expect(block[key], isNull, reason: key);
      }
      // Back to asking for a place.
      expect(find.byType(AppMapView), findsNothing);
      expect(find.byKey(_placeField), findsOneWidget);

      // Taking it off is a single step back.
      block.editor.undoManager.undo();
      await _settleEdits(tester);
      expect(block[MapBlockKeys.latitude], 48.8566);
      expect(block[MapBlockKeys.place], 'Paris');
      expect(find.byType(AppMapMarker), findsOneWidget);

      // Right-clicking the map offers the same.
      final target =
          tester.getCenter(find.byType(AppMapView)) + const Offset(110, 50);
      await tester.tapAt(
        target,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('map.removePin'), findsOneWidget);
      await tester.tap(find.text('map.removePin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settleEdits(tester);
      expect(block[MapBlockKeys.latitude], isNull);
      expect(block[MapBlockKeys.longitude], isNull);
      expect(find.byKey(_placeField), findsOneWidget);
    });
  });

  group('typing in a map that sits in a page', () {
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets(
      'Backspace edits the map search box, not the page',
      (tester) async {
        final page = await _pumpPage(
          tester,
          mapBlockNode(latitude: 48.8566, longitude: 2.3522, place: 'Paris'),
        );
        final field = find.descendant(
          of: find.byType(AppMapSearchField),
          matching: find.byType(EditableText),
        );

        await _typeAndErase(tester, field);
        expect(tester.widget<EditableText>(field).controller.text, 'Pari');
        expect(page.paragraph.delta!.toPlainText(), 'outside');
        expect(page.mapIsInPage, isTrue);
      },
      variant: windows,
    );

    testWidgets(
      'the keys the map moves with still type into its search box',
      (tester) async {
        await _pumpPage(
          tester,
          mapBlockNode(latitude: 48.8566, longitude: 2.3522, place: 'Paris'),
        );
        final field = find.descendant(
          of: find.byType(AppMapSearchField),
          matching: find.byType(EditableText),
        );
        tester.widget<EditableText>(field).focusNode.requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final before = _camera(tester);

        // Unhandled is what lets the platform type the character.
        for (final key in [
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.minus,
          LogicalKeyboardKey.equal,
        ]) {
          expect(
            await tester.sendKeyEvent(key, platform: 'windows'),
            isFalse,
            reason: '$key',
          );
        }
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowLeft,
          platform: 'windows',
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(_camera(tester).center, before.center);
        expect(_camera(tester).zoom, before.zoom);
      },
      variant: windows,
    );

    testWidgets(
      'Backspace edits the empty block\'s place field, not the page',
      (tester) async {
        final page = await _pumpPage(tester, mapBlockNode());
        final field = find.descendant(
          of: find.byKey(_placeField),
          matching: find.byType(EditableText),
        );

        await _typeAndErase(tester, field);
        expect(tester.widget<EditableText>(field).controller.text, 'Pari');
        expect(page.paragraph.delta!.toPlainText(), 'outside');
        expect(page.mapIsInPage, isTrue);
      },
      variant: windows,
    );

    testWidgets(
      'Enter searches from the map even where the host binds Enter',
      (tester) async {
        var hostEnter = 0;
        final page = await _pumpPage(
          tester,
          mapBlockNode(latitude: 48.8566, longitude: 2.3522, place: 'Paris'),
          onHostEnter: () => hostEnter++,
        );
        final field = find.descendant(
          of: find.byType(AppMapSearchField),
          matching: find.byType(EditableText),
        );

        final point = await _typeAndSubmit(tester, field);
        expect(hostEnter, 0);
        expect(page.map.attributes[MapBlockKeys.latitude], point.latitude);
        expect(page.map.attributes[MapBlockKeys.longitude], point.longitude);
      },
      variant: windows,
    );

    testWidgets(
      'Enter pins from the empty block even where the host binds Enter',
      (tester) async {
        var hostEnter = 0;
        final page = await _pumpPage(
          tester,
          mapBlockNode(),
          onHostEnter: () => hostEnter++,
        );
        final field = find.descendant(
          of: find.byKey(_placeField),
          matching: find.byType(EditableText),
        );

        final point = await _typeAndSubmit(tester, field);
        expect(hostEnter, 0);
        expect(page.map.attributes[MapBlockKeys.latitude], point.latitude);
        expect(page.map.attributes[MapBlockKeys.longitude], point.longitude);
      },
      variant: windows,
    );
  });
}

class _PageHost {
  _PageHost(this.editor, this.paragraph, this.map);

  final EditorState editor;
  final Node paragraph;
  final Node map;

  bool get mapIsInPage => editor.document.root.children.contains(map);
}

/// A real editor holding a paragraph and [map], with the caret left in the
/// paragraph — where it is when somebody clicks from the text into the map.
/// [onHostEnter] binds Enter around the editor, the way a canvas does.
Future<_PageHost> _pumpPage(
  WidgetTester tester,
  Node map, {
  VoidCallback? onHostEnter,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  final paragraph = paragraphNode(text: 'outside');
  final editor = EditorState(
    document: Document(root: pageNode(children: [paragraph, map])),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  Widget page = AppFlowyEditor(
    editorState: editor,
    blockComponentBuilders: {
      ...standardBlockComponentBuilderMap,
      MapBlockKeys.type: MapBlockComponentBuilder(),
    },
  );
  if (onHostEnter != null) {
    page = CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): onHostEnter},
      child: page,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  await tester.pump();
  unawaited(
    editor.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 7)),
      reason: SelectionUpdateReason.uiEvent,
    ),
  );
  await tester.pump();
  expect(editor.selection, isNotNull);
  return _PageHost(editor, paragraph, map);
}

/// Types 'Paris' into [field] and presses Backspace once, as a keyboard does.
Future<void> _typeAndErase(WidgetTester tester, Finder field) async {
  MapSuggestionCache.instance.debugRemember('pari', const []);
  tester.widget<EditableText>(field).focusNode.requestFocus();
  await tester.pump();
  await tester.enterText(field, 'Paris');
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace, platform: 'windows');
  await tester.pump();
}

/// Types coordinates into [field], lets their suggestion show, and presses
/// Enter without choosing it. Returns where they point.
Future<LatLng> _typeAndSubmit(WidgetTester tester, Finder field) async {
  const typed = '51.5072, -0.1276';
  MapSuggestionCache.instance.debugRemember(typed, const []);
  tester.widget<EditableText>(field).focusNode.requestFocus();
  await tester.pump();
  await tester.enterText(field, typed);
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
  expect(
    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'windows'),
    isTrue,
  );
  await _settleEdits(tester);
  // The map glides to what was found.
  await tester.pump(const Duration(milliseconds: 700));
  return parseMapLocation(typed).point!;
}

class _FieldHost {
  final controller = TextEditingController();
  final picked = <MapSuggestion>[];
  final submitted = <String>[];
}

Future<_FieldHost> _pumpField(WidgetTester tester) async {
  final host = _FieldHost();
  addTearDown(host.controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: SizedBox(
              width: 320,
              child: Builder(
                builder: (context) => MapPlaceField(
                  palette: mapPaletteOf(context),
                  controller: host.controller,
                  hintText: 'Find a place',
                  onPicked: host.picked.add,
                  onSubmitted: host.submitted.add,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return host;
}

class _BlockHost {
  _BlockHost(this.editor, this.node);

  final EditorState editor;
  final Node node;

  /// The block's attribute as stored now; the editor hands out copies.
  Object? operator [](String key) => node.attributes[key];
}

Future<_BlockHost> _pumpBlock(WidgetTester tester, {Node? node}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  final block = node ?? mapBlockNode();
  final editor =
      EditorState(document: Document(root: pageNode(children: [block])))
        ..editorStyle = const EditorStyle.desktop();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Provider<EditorState>.value(
        value: editor,
        child: Scaffold(
          // The editor rebuilds a block whenever its node changes.
          body: ListenableBuilder(
            listenable: block,
            builder: (context, _) =>
                MapBlockComponent(key: block.key, node: block),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _BlockHost(editor, block);
}

Finder _row(String title) => find.descendant(
      of: find.byType(MapSuggestionList),
      matching: find.text(title),
    );

/// Types [query] and lets the lookup debounce answer from the seeded cache.
Future<void> _type(WidgetTester tester, Finder field, String query) async {
  await tester.enterText(field, query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
  await tester.pump();
}

/// A mouse click on the map, given the time to tell it from a double click.
Future<void> _click(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  await tester.pump(kDoubleTapTimeout);
  await tester.pump();
}

/// Lets the block rebuild and the editor seal its undo history.
Future<void> _settleEdits(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

MapCamera _camera(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is MapTilePainter,
    ),
  );
  return (paint.painter! as MapTilePainter).camera;
}
