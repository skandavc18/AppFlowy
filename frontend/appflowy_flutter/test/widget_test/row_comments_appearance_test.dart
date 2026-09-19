import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/row/row_comments.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _testTimeout = Timeout(Duration(seconds: 20));
const _pageText = 'The row page is not a comment draft.';
const _sectionKey = ValueKey('row-comments-section');
const _headingKey = ValueKey('row-comments-heading');
const _threadKey = ValueKey('row-comments-thread');
const _composerKey = ValueKey('row-comment-composer');
const _avatarKey = ValueKey('row-comment-composer-avatar');
const _surfaceKey = ValueKey('row-comment-input-surface');
const _inputKey = ValueKey('row-comment-input');
const _cancelKey = ValueKey('row-comment-cancel');
const _postKey = ValueKey('row-comment-post');
const _outsideKey = ValueKey('outside-comments');
const _captureKey = ValueKey('row-comments-visual-reference');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  for (final mode in _modes) {
    testWidgets(
      '$mode: idle comments are a flat aligned 40px invitation',
      (tester) async {
        final fixture = _Fixture();
        final before = fixture.editor.document.toJson();
        try {
          await tester.pumpWidget(_app(fixture, mode: mode));
          await tester.pumpAndSettle();

          final heading = tester.widget<Text>(find.byKey(_headingKey));
          final theme = Theme.of(tester.element(find.byKey(_headingKey)));
          expect(heading.data, 'Comments');
          expect(heading.style!.fontSize, inInclusiveRange(12, 13));
          expect(
            heading.style!.color,
            theme.extension<PremiumThemeExtension>()!.textMuted,
          );
          expect(find.text('COMMENTS'), findsNothing);
          expect(find.text('Add a comment…'), findsOneWidget);
          expect(find.byKey(_threadKey), findsNothing);
          expect(find.byType(UserAvatar), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(_sectionKey),
              matching: find.byType(Icon),
            ),
            findsNothing,
          );
          expect(tester.getSize(find.byKey(_composerKey)).height, 40);
          expect(
            tester.getTopLeft(find.byKey(_avatarKey)).dx,
            tester.getTopLeft(find.byKey(_headingKey)).dx,
          );
          expect(
            tester.getTopLeft(find.byKey(_inputKey)).dx,
            tester.getTopRight(find.byKey(_avatarKey)).dx + 10,
          );
          _expectIdle(tester);
          _expectFlat(tester);
          final fieldOrigin = tester.getTopLeft(find.byKey(_inputKey));

          // Hover must not turn the resting invitation back into a card.
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(find.byKey(_composerKey)));
          await tester.pumpAndSettle();
          _expectIdle(tester, fieldOrigin: fieldOrigin);
          _expectFlat(tester);
          await mouse.removePointer();
          expect(fixture.transactions, isEmpty);
          expect(fixture.editor.document.toJson(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode: composer stays transparent and stationary through focus, draft and blur',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        final before = fixture.editor.document.toJson();
        fixture.editor.selection = Selection.single(path: [0], startOffset: 4);
        try {
          await tester.pumpWidget(_app(fixture, mode: mode));
          await tester.pumpAndSettle();
          expect(fixture.editor.selection, isNotNull);
          final fieldOrigin = tester.getTopLeft(find.byKey(_inputKey));
          final controller = _field(tester).controller!;
          final focusNode = _field(tester).focusNode!;
          _expectIdle(tester, fieldOrigin: fieldOrigin);
          // The full invitation, not only the text glyphs, opens the composer.
          await tester.tap(find.byKey(_avatarKey));
          await tester.pumpAndSettle();

          expect(_field(tester).focusNode!.hasFocus, isTrue);
          expect(_field(tester).maxLines, 6);
          expect(fixture.editor.selection, isNull);
          expect(fixture.transactions, isEmpty);
          final context = tester.element(find.byKey(_surfaceKey));
          final theme = Theme.of(context);
          final palette = theme.extension<PremiumThemeExtension>()!;
          _expectBorderless(tester, fieldOrigin: fieldOrigin);
          _expectFlat(tester);
          if (mode == 'paper') {
            expect(PaperTheme.isEnabled(context), isTrue);
            expect(theme.cardColor.r, greaterThan(theme.cardColor.b));
          }
          expect(_postButton(tester).onPressed, isNull);
          expect(
            _postButton(tester).tooltip,
            LocaleKeys.grid_row_commentPost.tr(),
          );
          expect(
            find.byTooltip(LocaleKeys.grid_row_commentPost.tr()),
            findsOneWidget,
          );
          final disabled = tester.getSemantics(find.byKey(_postKey));
          expect(disabled.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(disabled.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
          expect(disabled.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);

          await tester.enterText(find.byKey(_inputKey), '  \n  ');
          await tester.pumpAndSettle();
          _expectBorderless(tester, fieldOrigin: fieldOrigin);
          expect(_postButton(tester).onPressed, isNull);
          await tester.tap(find.byKey(_postKey));
          await tester.pumpAndSettle();
          expect(fixture.transactions, isEmpty);

          await tester.enterText(find.byKey(_inputKey), 'A local draft');
          await tester.pumpAndSettle();
          _expectBorderless(tester, fieldOrigin: fieldOrigin);
          _expectFlat(tester);
          final post = _postButton(tester);
          final cancel = _cancelButton(tester);
          expect(post.onPressed, isNotNull);
          expect(
            post.icon,
            isA<Icon>().having(
              (icon) => icon.icon,
              'glyph',
              Icons.arrow_upward_rounded,
            ),
          );
          expect(tester.getSize(find.byKey(_postKey)), const Size.square(28));
          expect(
            post.style!.minimumSize!.resolve({}),
            const Size.square(28),
          );
          expect(
            post.style!.maximumSize!.resolve({}),
            const Size.square(28),
          );
          expect(post.style!.shape!.resolve({}), isA<CircleBorder>());
          expect(
            post.style!.foregroundColor!.resolve({}),
            theme.colorScheme.onPrimary,
          );
          expect(
            post.style!.iconColor!.resolve({}),
            theme.colorScheme.onPrimary,
          );
          expect(post.style!.backgroundColor!.resolve({}), palette.accent);
          final primaryHover = Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(alpha: 0.08),
            palette.accent,
          );
          for (final state in [WidgetState.hovered, WidgetState.pressed]) {
            expect(
              post.style!.backgroundColor!.resolve({state}),
              primaryHover,
            );
          }
          expect(
            cancel.style!.foregroundColor!.resolve({}),
            palette.textMuted,
          );
          expect(cancel.style!.backgroundColor!.resolve({})!.a, 0);
          expect(
            cancel.style!.backgroundColor!.resolve({WidgetState.hovered}),
            palette.hover,
          );
          expect(
            cancel.style!.backgroundColor!.resolve({WidgetState.pressed}),
            palette.pressed,
          );
          for (final style in [post.style!, cancel.style!]) {
            expect(
              style.side!.resolve({WidgetState.focused})!.color,
              palette.focusRing,
            );
            expect(
              style.overlayColor!.resolve({WidgetState.hovered}),
              Colors.transparent,
            );
          }
          final enabled = tester.getSemantics(find.byKey(_postKey));
          expect(enabled.hasFlag(ui.SemanticsFlag.isEnabled), isTrue);
          expect(
            enabled.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );

          await tester.tap(
            find.byKey(_outsideKey),
            kind: ui.PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(focusNode.hasFocus, isFalse);
          expect(_field(tester).controller, same(controller));
          expect(_field(tester).focusNode, same(focusNode));
          expect(controller.text, 'A local draft');
          _expectBorderless(tester, fieldOrigin: fieldOrigin);
          _expectFlat(tester);
          await tester.tap(find.byKey(_inputKey));
          await tester.pumpAndSettle();
          expect(focusNode.hasFocus, isTrue);
          _expectBorderless(tester, fieldOrigin: fieldOrigin);
          await tester.tap(find.byKey(_cancelKey));
          await tester.pumpAndSettle();
          expect(_field(tester).controller, same(controller));
          expect(controller.text, isEmpty);
          _expectIdle(tester, fieldOrigin: fieldOrigin);
          _expectFlat(tester);
          expect(fixture.transactions, isEmpty);
          expect(fixture.editor.document.toJson(), before);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode: narrow scaled thread and composer do not overflow',
      (tester) async {
        final comment = _comment(
          'long',
          author: 'An author with a name longer than the available column',
          text: 'A long comment still wraps naturally on a narrow row page.\n'
              'Its second line stays readable too.',
        );
        final fixture = _Fixture(comments: [comment]);
        final before = fixture.editor.document.toJson();
        try {
          await tester.pumpWidget(
            _app(fixture, mode: mode, width: 240, textScale: 2),
          );
          await tester.pumpAndSettle();
          expect(find.text(comment.author), findsOneWidget);
          expect(find.text(comment.text), findsOneWidget);
          expect(find.text('Mar 14, 2024'), findsOneWidget);
          expect(find.byType(UserAvatar), findsNWidgets(2));
          expect(find.text('1'), findsNothing);
          _expectFlat(tester);
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.byKey(_inputKey));
          await tester.tap(find.byKey(_inputKey));
          await tester.enterText(
            find.byKey(_inputKey),
            'A draft that can grow to several lines without growing a second card.',
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(_postKey));
          await tester.pumpAndSettle();
          final bounds = tester.getRect(find.byKey(_surfaceKey));
          for (final key in [_cancelKey, _postKey]) {
            final button = tester.getRect(find.byKey(key));
            expect(button.left, greaterThanOrEqualTo(bounds.left));
            expect(button.right, lessThanOrEqualTo(bounds.right));
          }
          expect(_field(tester).maxLines, 6);
          _expectFlat(tester);
          expect(fixture.editor.document.toJson(), before);
          expect(fixture.transactions, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode: owner delete is hidden and unhittable until its row is hovered',
      (tester) async {
        final mine = _comment('mine');
        final other = _comment('other', authorId: '8');
        final legacy = _comment('legacy', authorId: '');
        final fixture = _Fixture(comments: [mine, other, legacy]);
        final before = fixture.editor.document.toJson();
        final pageBefore = fixture.editor.document.root.children.first.toJson();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await tester.pumpWidget(_app(fixture, mode: mode));
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: false);
          _expectNoActions('other');
          _expectNoActions('legacy');

          // A touch at the invisible action must not delete or synthesize hover.
          // Do not silence missed-hit warnings on a supposed visible action.
          await tester.tapAt(tester.getCenter(_deleteAction('mine')));
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: false);
          expect(fixture.transactions, isEmpty);
          expect(fixture.editor.document.toJson(), before);

          await mouse.moveTo(tester.getCenter(_commentRow('mine')));
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: true);
          _expectFlat(tester);
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: false);

          for (final id in ['other', 'legacy']) {
            await mouse.moveTo(tester.getCenter(_commentRow(id)));
            await tester.pumpAndSettle();
            _expectNoActions(id);
            _expectActions(tester, 'mine', visible: false);
          }

          await mouse.moveTo(tester.getCenter(_commentRow('mine')));
          await tester.pumpAndSettle();
          await _clickDelete(tester, mouse, 'mine');
          expect(fixture.writes, 1);
          expect(_commentRow('mine'), findsNothing);
          expect(
              rowCommentsOf(fixture.editor.document).map((c) => c.toJson()), [
            other.toJson(),
            legacy.toJson(),
          ]);
          expect(
            fixture.editor.document.root.children.first.toJson(),
            pageBefore,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode: reduced motion skips fades and accessible navigation exposes actions',
      (tester) async {
        final fixture = _Fixture(
          comments: [_comment('mine'), _comment('other', authorId: '8')],
        );
        final before = fixture.editor.document.toJson();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await tester.pumpWidget(
            _app(fixture, mode: mode, disableAnimations: true),
          );
          await tester.pumpAndSettle();
          _expectActions(
            tester,
            'mine',
            visible: false,
            duration: Duration.zero,
          );
          await mouse.moveTo(tester.getCenter(_commentRow('mine')));
          await tester.pump();
          _expectActions(
            tester,
            'mine',
            visible: true,
            duration: Duration.zero,
          );
          await mouse.moveTo(Offset.zero);
          await tester.pump();
          _expectActions(
            tester,
            'mine',
            visible: false,
            duration: Duration.zero,
          );

          await tester.pumpWidget(
            _app(
              fixture,
              mode: mode,
              disableAnimations: true,
              accessibleNavigation: true,
            ),
          );
          await tester.pumpAndSettle();
          _expectActions(
            tester,
            'mine',
            visible: true,
            duration: Duration.zero,
          );
          await mouse.moveTo(tester.getCenter(_commentRow('other')));
          await tester.pump();
          _expectNoActions('other');
          await mouse.moveTo(Offset.zero);
          await tester.pump();
          _expectActions(
            tester,
            'mine',
            visible: true,
            duration: Duration.zero,
          );

          await tester.enterText(
            find.byKey(_inputKey),
            'A reduced-motion draft',
          );
          await tester.pumpAndSettle();
          expect(_postButton(tester).style!.animationDuration, Duration.zero);
          expect(_cancelButton(tester).style!.animationDuration, Duration.zero);
          _expectFlat(tester);
          await tester.pumpWidget(
            _app(fixture, mode: mode, disableAnimations: true),
          );
          await tester.pumpAndSettle();
          _expectActions(
            tester,
            'mine',
            visible: false,
            duration: Duration.zero,
          );
          expect(fixture.editor.document.toJson(), before);
          expect(fixture.transactions, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode: resting thread and active draft visual references',
      (tester) async {
        tester.view.physicalSize = const Size(600, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final deterministicCursor = EditableText.debugDeterministicCursor;
        EditableText.debugDeterministicCursor = true;
        final mine = _comment(
          'visual-own',
          text: 'A calmer space for the conversation.',
        );
        final other = _comment(
          'visual-other',
          author: 'Grace Hopper',
          authorId: '8',
          text: 'Keep the details together with the page.',
        );
        final fixture = _Fixture(comments: [mine, other]);
        final before = fixture.editor.document.toJson();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await tester.pumpWidget(
            _app(fixture, mode: mode, captureSection: true),
          );
          await tester.pumpAndSettle();
          expect(find.text('Mar 14, 2024'), findsNWidgets(2));
          expect(find.text(mine.text), findsOneWidget);
          expect(find.text(other.text), findsOneWidget);
          _expectActions(tester, mine.id, visible: false);
          _expectNoActions(other.id);
          _expectIdle(tester);
          _expectFlat(tester);
          final backdrop = tester.widget<ColoredBox>(
            find
                .descendant(
                  of: find.byKey(_captureKey),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(
            backdrop.color,
            Theme.of(tester.element(find.byKey(_sectionKey))).cardColor,
          );
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_captureKey),
            matchesGoldenFile('goldens/row_comments_idle_$mode.png'),
          );

          const draft = 'The draft belongs on the page,\n'
              'without a separate input card.';
          await tester.enterText(find.byKey(_inputKey), draft);
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(_commentRow(mine.id)));
          await tester.pumpAndSettle();
          expect(_field(tester).focusNode!.hasFocus, isTrue);
          expect(_field(tester).controller!.text, draft);
          expect(_postButton(tester).onPressed, isNotNull);
          _expectActions(tester, mine.id, visible: true);
          _expectNoActions(other.id);
          _expectFlat(tester);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_captureKey),
            matchesGoldenFile('goldens/row_comments_active_$mode.png'),
          );
          expect(fixture.editor.document.toJson(), before);
          expect(fixture.transactions, isEmpty);
        } finally {
          EditableText.debugDeterministicCursor = deterministicCursor;
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
    );
  }

  testWidgets(
    'submit awaits the real transaction and rejects repeated activation',
    (tester) async {
      final fixture = _Fixture();
      final page = fixture.editor.document.root.children.first;
      final pageBefore = page.toJson();
      const draft = '  First line\nSecond line  ';
      try {
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_inputKey), draft);
        await tester.pumpAndSettle();
        final submitAgain = _postButton(tester).onPressed!;
        final cancelDuringWrite = _cancelButton(tester).onPressed!;
        final controller = _field(tester).controller!;
        expect(controller.text, draft);
        fixture.onTransaction = (event) {
          // The stream invokes its listener in the subscription's zone, outside
          // the guarded tap. Capture handles first: even tester.widget conflicts
          // with the tap guard here, independently of using expectSync.
          expectSync(controller.text, draft);
          expectSync(event.$2.afterSelection, isNull);
          if (event.$1 == TransactionTime.before) {
            submitAgain();
            cancelDuringWrite();
            expectSync(controller.text, draft);
          }
        };
        await tester.tap(find.byKey(_postKey));
        await tester.pumpAndSettle();
        fixture.onTransaction = null;

        final document = fixture.editor.document;
        final node = rowCommentNodeOf(document)!;
        final saved = rowCommentsOf(document).single;
        expect(fixture.writes, 1);
        expect(document.root.children, [page, node]);
        expect(page.toJson(), pageBefore);
        expect(saved.text, draft.trim());
        expect(saved.author, fixture.profile.name);
        expect(saved.authorId, fixture.profile.id.toString());
        expect(saved.avatar, fixture.profile.iconUrl);
        expect(saved.id, isNotEmpty);
        expect(saved.createdAt.year, DateTime.now().year);
        expect(RowComment.fromJson(saved.toJson())!.toJson(), saved.toJson());
        expect(node.attributes[RowCommentKeys.comments], [saved.toJson()]);
        expect(_field(tester).controller!.text, isEmpty);
        expect(find.text(draft.trim()), findsOneWidget);

        const nextDraft = 'Keep the newer local draft';
        await tester.enterText(find.byKey(_inputKey), 'Another comment');
        await tester.pumpAndSettle();
        fixture.onTransaction = (event) {
          expectSync(controller.text, 'Another comment');
          if (event.$1 == TransactionTime.after) {
            // The real document has changed, but the awaited apply() future has
            // not returned to the composer yet. Neither stale action may write
            // again or discard a draft that changed during that await.
            controller.text = nextDraft;
            submitAgain();
            cancelDuringWrite();
            expectSync(controller.text, nextDraft);
          }
        };
        await tester.tap(find.byKey(_postKey));
        await tester.pumpAndSettle();
        fixture.onTransaction = null;
        expect(fixture.writes, 2);
        expect(rowCommentNodeOf(document), same(node));
        expect(document.root.children.length, 2);
        expect(rowCommentsOf(document).map((comment) => comment.text), [
          draft.trim(),
          'Another comment',
        ]);
        expect(controller.text, nextDraft);
        expect(_field(tester).readOnly, isFalse);
        expect(_postButton(tester).onPressed, isNotNull);
        expect(page.toJson(), pageBefore);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );

  for (final mode in _modes) {
    testWidgets(
      '$mode: Shift+Tab reveals owner delete without hover and blur hides it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final mine = _comment('mine');
        final other = _comment('other', authorId: '8');
        final legacy = _comment('legacy', authorId: '');
        final fixture = _Fixture(comments: [mine, other, legacy]);
        final pageBefore = fixture.editor.document.root.children.first.toJson();
        TestGesture? mouse;
        try {
          await tester.pumpWidget(_app(fixture, mode: mode));
          await tester.pumpAndSettle();
          expect(find.byType(IconButton), findsOneWidget);
          _expectActions(tester, 'mine', visible: false);
          _expectNoActions('other');
          _expectNoActions('legacy');
          expect(find.byTooltip('Delete'), findsOneWidget);
          _expectFlat(tester);
          await tester.tap(find.byKey(_inputKey));
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();

          _expectActions(tester, 'mine', visible: true);
          final delete = tester.getSemantics(_deleteAction('mine'));
          expect(delete.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(delete.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
          expect(
            delete.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          // The keyboard revealed the action before any mouse was introduced.
          mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(_commentRow('mine')));
          await tester.pumpAndSettle();
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: true);
          expect(
            tester
                .getSemantics(_deleteAction('mine'))
                .hasFlag(ui.SemanticsFlag.isFocused),
            isTrue,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(_field(tester).focusNode!.hasFocus, isTrue);
          _expectActions(tester, 'mine', visible: false);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          _expectActions(tester, 'mine', visible: true);
          expect(fixture.transactions, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(fixture.writes, 1);
          expect(_deleteAction('mine'), findsNothing);
          _expectNoActions('other');
          _expectNoActions('legacy');
          expect(
              rowCommentsOf(fixture.editor.document).map((c) => c.toJson()), [
            other.toJson(),
            legacy.toJson(),
          ]);
          expect(
            fixture.editor.document.root.children.first.toJson(),
            pageBefore,
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (mouse != null) {
            await mouse.removePointer();
          }
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _testTimeout,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'surviving comment IDs retain their own state after another row is deleted',
    (tester) async {
      final fixture = _Fixture(
        comments: [_comment('first'), _comment('survivor'), _comment('third')],
      );
      final pageBefore = fixture.editor.document.root.children.first.toJson();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await tester.pumpWidget(_app(fixture, mode: 'paper'));
        await tester.pumpAndSettle();
        final survivorState =
            tester.state(find.byKey(const ValueKey('survivor')));
        final thirdState = tester.state(find.byKey(const ValueKey('third')));
        await mouse.moveTo(tester.getCenter(_commentRow('survivor')));
        await tester.pumpAndSettle();
        _expectActions(tester, 'survivor', visible: true);
        _expectActions(tester, 'third', visible: false);
        await mouse.moveTo(tester.getCenter(_commentRow('first')));
        await tester.pumpAndSettle();
        _expectActions(tester, 'survivor', visible: false);
        await _clickDelete(tester, mouse, 'first');
        // Do not mistake a row moving under a stationary pointer for leaked state.
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();

        expect(fixture.writes, 1);
        expect(find.byKey(const ValueKey('first')), findsNothing);
        expect(
          tester.state(find.byKey(const ValueKey('survivor'))),
          same(survivorState),
        );
        expect(
          tester.state(find.byKey(const ValueKey('third'))),
          same(thirdState),
        );
        expect(rowCommentsOf(fixture.editor.document).map((c) => c.id), [
          'survivor',
          'third',
        ]);
        _expectActions(tester, 'survivor', visible: false);
        _expectActions(tester, 'third', visible: false);
        await mouse.moveTo(tester.getCenter(_commentRow('survivor')));
        await tester.pumpAndSettle();
        _expectActions(tester, 'survivor', visible: true);
        _expectActions(tester, 'third', visible: false);
        await mouse.moveTo(tester.getCenter(_commentRow('third')));
        await tester.pumpAndSettle();
        _expectActions(tester, 'survivor', visible: false);
        _expectActions(tester, 'third', visible: true);
        expect(
          fixture.editor.document.root.children.first.toJson(),
          pageBefore,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'older comments without unique IDs render without key collisions',
    (tester) async {
      final fixture = _Fixture(
        comments: [
          _comment('', authorId: '', text: 'First legacy note'),
          _comment('', authorId: '', text: 'Second legacy note'),
          _comment('duplicate', authorId: '8', text: 'First imported note'),
          _comment('duplicate', authorId: '8', text: 'Second imported note'),
        ],
      );
      final before = fixture.editor.document.toJson();
      try {
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        for (final comment in rowCommentsOf(fixture.editor.document)) {
          expect(find.text(comment.text), findsOneWidget);
        }
        expect(find.byTooltip('Delete'), findsNothing);
        expect(fixture.transactions, isEmpty);
        expect(fixture.editor.document.toJson(), before);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'deleting the final comment keeps its storage block reusable',
    (tester) async {
      final fixture = _Fixture(comments: [_comment('last')]);
      final document = fixture.editor.document;
      final node = rowCommentNodeOf(document)!;
      final pageBefore = document.root.children.first.toJson();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        _expectActions(tester, 'last', visible: false);
        await mouse.moveTo(tester.getCenter(_commentRow('last')));
        await tester.pumpAndSettle();
        await _clickDelete(tester, mouse, 'last');
        expect(fixture.writes, 1);
        expect(rowCommentsOf(document), isEmpty);
        expect(rowCommentNodeOf(document), same(node));
        expect(node.attributes[RowCommentKeys.comments], isEmpty);
        expect(find.byKey(_threadKey), findsNothing);
        _expectIdle(tester);

        await tester.enterText(find.byKey(_inputKey), 'Start again');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_postKey));
        await tester.pumpAndSettle();
        expect(fixture.writes, 2);
        expect(rowCommentNodeOf(document), same(node));
        expect(document.root.children.length, 2);
        expect(rowCommentsOf(document).single.text, 'Start again');
        expect(document.root.children.first.toJson(), pageBefore);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'anonymous readers get no delete action',
    (tester) async {
      final fixture = _Fixture(comments: [_comment('mine')]);
      final before = fixture.editor.document.toJson();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await tester.pumpWidget(_app(fixture, anonymous: true));
        await tester.pumpAndSettle();
        _expectNoActions('mine');
        await mouse.moveTo(tester.getCenter(_commentRow('mine')));
        await tester.pumpAndSettle();
        _expectNoActions('mine');
        expect(find.byType(IconButton), findsNothing);
        expect(find.byTooltip('Delete'), findsNothing);
        expect(fixture.editor.document.toJson(), before);
        expect(fixture.transactions, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'real editor header isolates editing keys and keeps native action traversal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture();
      final before = fixture.editor.document.toJson();
      try {
        await tester.pumpWidget(_app(fixture, insideEditor: true));
        await tester.pumpAndSettle();
        fixture.editor.selection = Selection.single(path: [0], startOffset: 5);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_inputKey));
        await tester.enterText(find.byKey(_inputKey), 'Draft!');
        await tester.pumpAndSettle();
        expect(fixture.editor.selection, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(_field(tester).controller!.text, 'Draft');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pumpAndSettle();
        expect(_field(tester).focusNode!.hasFocus, isTrue);
        expect(fixture.transactions, isEmpty);

        // Desktop text insertion arrives separately from key-down events.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Draft\nSecond line',
            selection: TextSelection.collapsed(offset: 17),
          ),
        );
        await tester.pumpAndSettle();
        expect(_field(tester).controller!.text, 'Draft\nSecond line');
        expect(fixture.editor.document.toJson(), before);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(_field(tester).controller!.text, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(find.byKey(_cancelKey), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(_cancelKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        expect(_field(tester).maxLines, 6);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        _expectIdle(tester);
        expect(fixture.transactions, isEmpty);
        expect(fixture.editor.document.toJson(), before);

        await tester.enterText(
          find.byKey(_inputKey),
          'Posted with the keyboard',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(find.byKey(_postKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(fixture.writes, 1);
        expect(
          rowCommentsOf(fixture.editor.document).single.text,
          'Posted with the keyboard',
        );
        expect(
          fixture.editor.document.root.children.first.delta!.toPlainText(),
          _pageText,
        );
        // The storage block remains invisible to the page renderer.
        expect(find.text('Posted with the keyboard'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'blur and theme changes retain drafts; Escape cancels without writes',
    (tester) async {
      final fixture = _Fixture();
      final before = fixture.editor.document.toJson();
      try {
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_inputKey), 'Keep this draft');
        await tester.pumpAndSettle();
        final controller = _field(tester).controller;
        await tester.tap(
          find.byKey(_outsideKey),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(_field(tester).focusNode!.hasFocus, isFalse);
        expect(controller!.text, 'Keep this draft');
        expect(find.byKey(_cancelKey), findsOneWidget);

        await tester.pumpWidget(_app(fixture, mode: 'paper', width: 280));
        await tester.pumpAndSettle();
        expect(_field(tester).controller, same(controller));
        expect(controller.text, 'Keep this draft');
        _expectBorderless(tester);
        _expectFlat(tester);
        await tester.tap(find.byKey(_inputKey));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _expectIdle(tester);
        expect(controller.text, isEmpty);
        expect(fixture.editor.document.toJson(), before);
        expect(fixture.transactions, isEmpty);

        await tester.enterText(
          find.byKey(_inputKey),
          'Do not post on disposal',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(fixture.editor.document.toJson(), before);
        expect(fixture.transactions, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _testTimeout,
  );
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_inputKey));

IconButton _postButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_postKey));

TextButton _cancelButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(_cancelKey));

Container _surface(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(_surfaceKey));

Finder _commentRow(String id) => find.byKey(ValueKey('row-comment-$id'));

Finder _commentActions(String id) =>
    find.byKey(ValueKey('row-comment-actions-$id'));

Finder _deleteAction(String id) =>
    find.byKey(ValueKey('row-comment-delete-$id'));

void _expectActions(
  WidgetTester tester,
  String id, {
  required bool visible,
  Duration duration = const Duration(milliseconds: 120),
}) {
  final actions = _commentActions(id);
  final opacity = tester.widget<AnimatedOpacity>(actions);
  expect(opacity.opacity, visible ? 1 : 0);
  expect(opacity.duration, duration);
  // Check the painted opacity as well as the animation's target value.
  final fade = tester.widget<FadeTransition>(
    find.descendant(of: actions, matching: find.byType(FadeTransition)).first,
  );
  expect(fade.opacity.value, visible ? 1 : 0);
  final pointer = tester.widget<IgnorePointer>(
    find.ancestor(of: actions, matching: find.byType(IgnorePointer)).first,
  );
  expect(pointer.ignoring, !visible);
  expect(_deleteAction(id), findsOneWidget);
  expect(
    _deleteAction(id).hitTestable(),
    visible ? findsOneWidget : findsNothing,
  );
}

void _expectNoActions(String id) {
  expect(_commentActions(id), findsNothing);
  expect(_deleteAction(id), findsNothing);
}

Future<void> _clickDelete(
  WidgetTester tester,
  TestGesture mouse,
  String id,
) async {
  // Callers must reveal the row first; this helper cannot activate hidden UI.
  _expectActions(tester, id, visible: true);
  final position = tester.getCenter(_deleteAction(id));
  await mouse.moveTo(position);
  await tester.pumpAndSettle();
  await mouse.down(position);
  await mouse.up();
  await tester.pumpAndSettle();
}

void _expectBorderless(WidgetTester tester, {Offset? fieldOrigin}) {
  final surface = _surface(tester);
  expect(surface.color, isNull);
  expect(surface.decoration, isNull);
  expect(surface.foregroundDecoration, isNull);
  expect(surface.constraints!.minHeight, 40);
  expect(surface.padding, const EdgeInsets.symmetric(vertical: 8));
  final decoration = _field(tester).decoration!;
  expect(decoration.border, InputBorder.none);
  expect(decoration.enabledBorder, InputBorder.none);
  expect(decoration.focusedBorder, InputBorder.none);
  expect(decoration.filled, isFalse);
  expect(decoration.hoverColor, Colors.transparent);
  expect(decoration.contentPadding, EdgeInsets.zero);
  if (fieldOrigin != null) {
    expect(
      tester.getTopLeft(find.byKey(_inputKey)),
      fieldOrigin,
      reason: 'The field must not move when focus or the draft changes.',
    );
  }
}

void _expectIdle(WidgetTester tester, {Offset? fieldOrigin}) {
  expect(_field(tester).minLines, 1);
  expect(_field(tester).maxLines, 6);
  expect(_field(tester).decoration!.hintMaxLines, 1);
  expect(_field(tester).focusNode!.hasFocus, isFalse);
  expect(find.byKey(_cancelKey), findsNothing);
  expect(find.byKey(_postKey), findsNothing);
  _expectBorderless(tester, fieldOrigin: fieldOrigin);
}

void _expectFlat(WidgetTester tester) {
  _expectBorderless(tester);
  final section = find.byKey(_sectionKey);
  for (final type in [ViewerCard, Card, Divider, VerticalDivider]) {
    expect(
      find.descendant(of: section, matching: find.byType(type)),
      findsNothing,
    );
  }
  final decorated = find.descendant(
    of: section,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox ||
          widget is Container &&
              (widget.color != null ||
                  widget.decoration != null ||
                  widget.foregroundDecoration != null),
    ),
  );
  for (final element in decorated.evaluate()) {
    // Avatars retain their existing circular decoration; only action buttons
    // may paint a control surface. The thread and input cannot grow a card.
    var isAvatarOrButton = false;
    element.visitAncestorElements((ancestor) {
      isAvatarOrButton = ancestor.widget is UserAvatar ||
          ancestor.widget is TextButton ||
          ancestor.widget is IconButton;
      return !isAvatarOrButton;
    });
    expect(
      isAvatarOrButton,
      isTrue,
      reason:
          '${element.widget.runtimeType} must not decorate the thread or input.',
    );
  }
  expect(
    find.descendant(
      of: section,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            ((widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                false),
      ),
    ),
    findsNothing,
  );
}

RowComment _comment(
  String id, {
  String author = 'Ada Lovelace',
  String authorId = '7',
  String? text,
}) =>
    RowComment(
      id: id,
      author: author,
      authorId: authorId,
      text: text ?? 'Comment $id',
      createdAt: DateTime(2024, 3, 14),
    );

// No DocumentBloc, backend adapter, native database, or mocked EditorState.
class _Fixture {
  _Fixture({List<RowComment> comments = const []})
      : editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                paragraphNode(text: _pageText),
                if (comments.isNotEmpty)
                  Node(
                    type: RowCommentKeys.type,
                    attributes: {
                      RowCommentKeys.comments: [
                        for (final comment in comments) comment.toJson(),
                      ],
                    },
                  ),
              ],
            ),
          ),
        ) {
    editor.disableSealTimer = true;
    _subscription = editor.transactionStream.listen((event) {
      transactions.add(event);
      onTransaction?.call(event);
    });
  }

  final EditorState editor;
  final profile = UserProfilePB(id: Int64(7), name: 'Ada Lovelace');
  final transactions = <EditorTransactionValue>[];
  late final StreamSubscription<EditorTransactionValue> _subscription;
  void Function(EditorTransactionValue)? onTransaction;

  int get writes =>
      transactions.where((event) => event.$1 == TransactionTime.after).length;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Let the binding drain real/fake microtasks around stream cancellation
    // before pumping again; directly awaiting cancel can strand the next pump.
    await tester.runAsync(_subscription.cancel);
    editor.dispose();
    await tester.pump();
  }
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Widget _app(
  _Fixture fixture, {
  String mode = 'light',
  double width = 480,
  double textScale = 1,
  bool insideEditor = false,
  bool anonymous = false,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  bool captureSection = false,
}) {
  final theme = _theme(mode);
  final themeBuilder = AppFlowyDefaultTheme();
  final appFlowyTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? themeBuilder.dark() : themeBuilder.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  final comments = RowCommentSection(
    editorState: fixture.editor,
    userProfile: anonymous ? null : fixture.profile,
    padding: const EdgeInsets.symmetric(horizontal: 24),
  );
  final section = captureSection
      ? RepaintBoundary(
          key: _captureKey,
          child: ColoredBox(
            color: theme.cardColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: comments,
            ),
          ),
        )
      : comments;
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: AppFlowyTheme(data: appFlowyTheme, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: insideEditor
                  ? SizedBox(
                      height: 540,
                      child: AppFlowyEditor(
                        editorState: fixture.editor,
                        editorStyle: const EditorStyle.desktop(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                        ),
                        header: section,
                        blockComponentBuilders: {
                          ...standardBlockComponentBuilderMap,
                          RowCommentKeys.type:
                              RowCommentsBlockComponentBuilder(),
                        },
                        contextMenuItems: const [],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          section,
                          TextButton(
                            key: _outsideKey,
                            onPressed: () {},
                            child: const Text('Outside comments'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
