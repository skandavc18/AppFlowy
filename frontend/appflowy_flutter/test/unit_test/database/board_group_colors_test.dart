import 'dart:convert';

import 'package:appflowy/plugins/database/board/application/board_group_colors.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = BoardColumnColor.tint(SelectOptionColorPB.Blue);
const _pink = BoardColumnColor.tint(SelectOptionColorPB.Pink);

ViewPB _board({String extra = ''}) => ViewPB()
  ..id = 'board'
  ..extra = extra;

/// The view's `extra` as the backend holds it.
class _Store {
  _Store([this.extra = '']);

  String extra;
  var refuseNextWrite = false;
  final writes = <String>[];

  Future<String> read(String viewId) async => extra;

  Future<void> write(String viewId, String value) async {
    if (refuseNextWrite) {
      refuseNextWrite = false;
      throw StateError('refused');
    }
    writes.add(value);
    extra = value;
  }

  BoardGroupColors get colors => BoardGroupColors.fromExtra(extra);
}

void main() {
  group('what a board remembers about its column colours', () {
    test('choices survive being written and read back', () {
      final colors = const BoardGroupColors()
          .withColor('todo', _blue)
          .withColor('done', BoardColumnColor.plain);
      final extra = colors.mergeIntoExtra(
        jsonEncode({
          'appflowy_card_preview': {'version': 1, 'mode': 'page'},
        }),
      );

      expect(BoardGroupColors.fromExtra(extra), colors);
      expect(BoardGroupColors.fromExtra(extra)['todo'], _blue);
      expect(BoardGroupColors.fromExtra(extra)['done'], BoardColumnColor.plain);
      expect(BoardGroupColors.fromExtra(extra)['doing'], isNull);
      // Every other mark the view wears rides along untouched.
      expect(
        (jsonDecode(extra) as Map)['appflowy_card_preview'],
        {'version': 1, 'mode': 'page'},
      );
    });

    test('a board with no colours chosen leaves nothing behind', () {
      final chosen = const BoardGroupColors().withColor('todo', _blue);
      final extra = chosen.mergeIntoExtra('{"other": 1}');
      final cleared = chosen.withColor('todo', null).mergeIntoExtra(extra);

      expect(jsonDecode(cleared), {'other': 1});
      expect(BoardGroupColors.fromExtra(cleared).isEmpty, isTrue);
    });

    test('what a later version wrote is not guessed at', () {
      String extraOf(Object envelope) =>
          jsonEncode({BoardGroupColors.envelopeKey: envelope});

      expect(
        BoardGroupColors.fromExtra(
          extraOf({
            'version': 2,
            'groups': {'todo': 8},
          }),
        ).isEmpty,
        isTrue,
      );
      final mixed = BoardGroupColors.fromExtra(
        extraOf({
          'version': 1,
          'groups': {'todo': 99, 'doing': 'Magenta', 'done': 8},
        }),
      );
      expect(mixed['todo'], isNull);
      expect(mixed['doing'], isNull);
      expect(mixed['done'], _blue);
      expect(BoardGroupColors.fromExtra('not json').isEmpty, isTrue);
    });

    test('a column shows its own choice, else its option colour', () {
      expect(
        BoardColumnColor.resolve(
          chosen: null,
          optionColor: SelectOptionColorPB.Green,
        ),
        SelectOptionColorPB.Green,
      );
      expect(
        BoardColumnColor.resolve(
          chosen: BoardColumnColor.plain,
          optionColor: SelectOptionColorPB.Green,
        ),
        isNull,
      );
      expect(
        BoardColumnColor.resolve(
          chosen: _pink,
          optionColor: SelectOptionColorPB.Green,
        ),
        SelectOptionColorPB.Pink,
      );
      expect(
        BoardColumnColor.resolve(chosen: _pink, optionColor: null),
        SelectOptionColorPB.Pink,
      );
    });
  });

  group('choosing a column colour', () {
    test('shows at once and merges into what is stored now', () async {
      final store = _Store(
        jsonEncode({
          'appflowy_card_preview': {'version': 1, 'mode': 'page'},
        }),
      );
      final registry = BoardGroupColorRegistry(
        readExtra: store.read,
        writeExtra: store.write,
      );
      // The view this window holds predates the card preview choice.
      final view = _board();
      final notifier = registry.notifierFor(view);
      final save = registry.set(view, 'todo', _blue);

      expect(notifier.value['todo'], _blue);
      await save;

      expect(store.colors['todo'], _blue);
      expect(
        (jsonDecode(store.extra) as Map)['appflowy_card_preview'],
        {'version': 1, 'mode': 'page'},
      );
      expect(notifier.value['todo'], _blue);
      registry.reset();
    });

    test('quick choices for different columns all land', () async {
      final store = _Store();
      final registry = BoardGroupColorRegistry(
        readExtra: store.read,
        writeExtra: store.write,
      );
      final view = _board();
      final first = registry.set(view, 'todo', _blue);
      final second = registry.set(view, 'done', BoardColumnColor.plain);
      await Future.wait([first, second]);

      expect(store.writes, hasLength(2));
      expect(store.colors['todo'], _blue);
      expect(store.colors['done'], BoardColumnColor.plain);
      expect(registry.colorsFor(view), store.colors);
      registry.reset();
    });

    test('a refused save falls back to what is really stored', () async {
      final store = _Store(
        const BoardGroupColors().withColor('todo', _pink).mergeIntoExtra(''),
      )..refuseNextWrite = true;
      final registry = BoardGroupColorRegistry(
        readExtra: store.read,
        writeExtra: store.write,
      );
      final view = _board();
      final notifier = registry.notifierFor(view);
      final save = registry.set(view, 'todo', _blue);
      expect(notifier.value['todo'], _blue);
      await save;

      expect(notifier.value['todo'], _pink);
      expect(store.colors['todo'], _pink);
      registry.reset();
    });

    test('returning a column to its group keeps the other choices', () async {
      final store = _Store();
      final registry = BoardGroupColorRegistry(
        readExtra: store.read,
        writeExtra: store.write,
      );
      final view = _board();
      await registry.set(view, 'todo', _blue);
      await registry.set(view, 'done', _pink);
      await registry.set(view, 'todo', null);

      expect(store.colors['todo'], isNull);
      expect(store.colors['done'], _pink);
      expect(registry.colorsFor(view)['todo'], isNull);

      await registry.set(view, 'done', null);
      expect(
        (jsonDecode(store.extra) as Map)
            .containsKey(BoardGroupColors.envelopeKey),
        isFalse,
      );
      registry.reset();
    });

    test('a board opened later starts from what its view carries', () {
      final registry = BoardGroupColorRegistry(
        readExtra: (_) async => '',
        writeExtra: (_, __) async {},
      );
      final view = _board(
        extra: const BoardGroupColors()
            .withColor('todo', _blue)
            .mergeIntoExtra(''),
      );

      expect(registry.colorsFor(view)['todo'], _blue);
      registry.reset();
    });
  });
}
