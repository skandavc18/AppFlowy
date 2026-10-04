import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _titleKey = ValueKey('external-file-title');
const _headerKey = ValueKey('external-file-header');
const _closeKey = ValueKey('external-file-close');
const _nextKey = ValueKey('external-file-next');
const _previousKey = ValueKey('external-file-previous');
const _nativeKey = ValueKey('external-file-native-actions');
const _actionsKey = ValueKey('external-file-actions');

final _sourceField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.expands,
);
late Map<String, dynamic> _translations;

void main() {
  fileControlTestSetup();
  setUpAll(() async {
    _translations = Map<String, dynamic>.from(
      jsonDecode(await rootBundle.loadString('assets/translations/en-US.json'))
          as Map,
    );
  });

  for (final mode in fileControlAppearances) {
    for (final extension in ['css', 'txt']) {
      testWidgets(
          '$mode/$extension: real modal retains source and residual wheel flow',
          (tester) async {
        final node = _node(
          'a',
          extension == 'txt' ? 'Provider notes' : 'source.css',
          mime: extension == 'txt' ? 'text/plain' : null,
        );
        final file = MemoryCodeFile(
          List.generate(500, (i) => 'line $i { color: green; }').join('\n'),
          path: '/external-page-flow/source.$extension',
        );
        await _withModal(
          tester,
          nodes: [node],
          files: [file],
          mode: mode,
          body: (fixture) async {
            fixture.provider.requests.single.result.complete(file.path);
            await _frames(tester);
            expect(_sourceField, findsOneWidget);
            final field = tester.widget<TextField>(_sourceField);
            final editor = tester.state(
              find.descendant(
                of: _sourceField,
                matching: find.byType(EditableText),
              ),
            );
            final renderer = tester.state(find.byType(FilePreview));
            final preview =
                tester.widget<FilePreview>(find.byType(FilePreview));
            final scope = tester
                .widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
            final chrome = scope.chrome;
            expect(scope.rendererName, providerFileNameFor(node));
            expect(scope.displayName, node.name);
            expect(scope.canRead(), isTrue);
            expect(scope.canEdit(), isFalse);
            expect(scope.editable, isFalse);
            expect(preview.bare, isFalse);
            expect(preview.framed, isFalse);
            expect(field.readOnly, isTrue);
            expect(field.scrollController, isNotNull);
            final actionsRect = tester.getRect(find.byKey(_actionsKey));
            final nativeRect = tester.getRect(find.byKey(_nativeKey));
            expect(
              nativeRect.top,
              greaterThanOrEqualTo(
                tester.getRect(find.byKey(_titleKey)).bottom,
              ),
            );
            // The code publisher has its own 6px content inset; the group still
            // hugs that actual right gutter rather than a title-row slot.
            expect(
              actionsRect.right - nativeRect.right,
              inInclusiveRange(0, 6),
            );
            final selection =
                const TextSelection(baseOffset: 2, extentOffset: 12);
            field.controller!.selection = selection;

            if (extension == 'css') {
              final toggle = find.byKey(const ValueKey('code-line-numbers'));
              expect(
                find.descendant(of: find.byKey(_headerKey), matching: toggle),
                findsOneWidget,
              );
              await tester.tap(toggle);
              await _frames(tester);
              expect(find.byTooltip('Show line numbers'), findsOneWidget);
              await tester.tap(toggle);
              await _frames(tester);
              expect(find.byTooltip('Hide line numbers'), findsOneWidget);
            }
            // Drain normal publication. A chrome -> renderer -> chrome loop
            // would continue to schedule frames and increment this count.
            await _frames(tester);
            var publications = 0;
            void published() => publications++;
            chrome.addListener(published);
            await _frames(tester);
            expect(publications, 0);
            chrome.removeListener(published);

            final page = tester
                .state<NestedScrollViewState>(find.byType(NestedScrollView));
            final header = find.byKey(_headerKey, skipOffstage: false);
            final initial = tester.getRect(header);
            final closeRect = tester.getRect(find.byKey(_closeKey));
            final extent = page.outerController.position.maxScrollExtent;
            expect(extent, greaterThan(40));
            final bodyRect = tester
                .getRect(_sourceField)
                .intersect(tester.getRect(find.byType(StandaloneFilePage)));
            final point = Offset(bodyRect.center.dx, bodyRect.bottom - 24);
            await _wheel(tester, point, 40);
            expect(page.outerController.offset, closeTo(40, .01));
            expect(field.scrollController!.offset, 0);
            await _wheel(tester, point, extent + 80 - 40);
            expect(page.outerController.offset, closeTo(extent, .01));
            expect(field.scrollController!.offset, closeTo(80, .01));
            expect(
              tester.getRect(header).top,
              closeTo(initial.top - extent, .01),
            );
            expect(header.hitTestable(), findsNothing);
            expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
            expect(tester.getRect(find.byKey(_closeKey)), closeRect);
            await _wheel(tester, point, -30);
            expect(field.scrollController!.offset, closeTo(50, .01));
            expect(page.outerController.offset, closeTo(extent, .01));
            await _wheel(tester, point, -70);
            expect(field.scrollController!.offset, 0);
            expect(page.outerController.offset, closeTo(extent - 20, .01));
            expect(tester.state(find.byType(FilePreview)), same(renderer));
            expect(
              tester.state(
                find.descendant(
                  of: _sourceField,
                  matching: find.byType(EditableText),
                ),
              ),
              same(editor),
            );
            expect(
              tester.widget<TextField>(_sourceField).controller,
              same(field.controller),
            );
            expect(field.controller!.selection, selection);
            expect(
              tester
                  .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
                  .chrome,
              same(chrome),
            );
            expect(file.reads, 1);
            expect(file.writes, 0);
            expect(fixture.provider.requests, hasLength(1));

            // Reflow changes the measure, not the loaded source/controller.
            tester.view.physicalSize = const Size(360, 740);
            await _frames(tester);
            expect(
              tester.widget<TextField>(_sourceField).controller,
              same(field.controller),
            );
            expect(tester.state(find.byType(FilePreview)), same(renderer));
            expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
            expect(file.reads, 1);
            expect(tester.takeException(), isNull);
          },
        );
      });
    }

    for (final width in [360.0, 1100.0]) {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        testWidgets(
            '$mode/$width/$direction: loading and failure keep title, right actions and close',
            (tester) async {
          final node =
              _node('a', 'A provider title that wraps at large text sizes.bin');
          await _withModal(
            tester,
            nodes: [node],
            mode: mode,
            width: width,
            textScale: 2,
            direction: direction,
            body: (fixture) async {
              final title = tester.getRect(find.byKey(_titleKey));
              final native = tester.getRect(find.byKey(_nativeKey));
              final band = tester.getRect(find.byKey(_actionsKey));
              expect(native.top, greaterThanOrEqualTo(title.bottom));
              expect(native.right, closeTo(band.right, .01));
              expect(find.byType(FileActionBand), findsOneWidget);
              expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
              expect(
                find.ancestor(
                  of: find.byKey(_closeKey),
                  matching: find.byType(StandaloneFilePage),
                ),
                findsNothing,
              );
              final canvas = tester.widget<ColoredBox>(
                find.byKey(const ValueKey('external-file-canvas')),
              );
              expect(
                canvas.color,
                FolderExplorerPalette.of(tester.element(find.byKey(_titleKey)))
                    .background,
              );
              final scope = tester.widget<StandaloneFileScope>(
                find.byType(StandaloneFileScope),
              );
              expect(scope.available, isFalse);
              expect(scope.canRead(), isFalse);
              final pageRect = tester.getRect(find.byType(StandaloneFilePage));
              expect(
                pageRect.bottom,
                closeTo(
                  tester
                      .getRect(
                        find.byKey(const ValueKey('external-file-canvas')),
                      )
                      .bottom,
                  .01,
                ),
              );
              fixture.provider.requests.single.result
                  .completeError(StateError('private provider detail'));
              await _frames(tester);
              expect(
                find.text(LocaleKeys.providers_cannotOpen.tr()),
                findsOneWidget,
              );
              expect(
                find.textContaining('private provider detail'),
                findsNothing,
              );
              expect(find.byKey(_titleKey), findsOneWidget);
              expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        });
      }
    }
  }

  for (final oldFailure in [false, true]) {
    testWidgets(
        'A -> B: stale ${oldFailure ? 'failure' : 'success'} cannot replace B',
        (tester) async {
      final a = _node('a', 'A.txt');
      final b = _node('b', 'B.txt');
      final fileA =
          MemoryCodeFile('Old A content', path: '/external-page-flow/a.txt');
      final fileB = MemoryCodeFile(
        'Current B content',
        path: '/external-page-flow/b.txt',
      );
      await _withModal(
        tester,
        nodes: [a, b],
        files: [fileA, fileB],
        body: (fixture) async {
          final old = fixture.provider.requests.single;
          final oldScope = tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
          final staleSource = tester
              .widget<IconButton>(
                find.byKey(const ValueKey('external-file-open-source')),
              )
              .onPressed!;
          await tester.tap(find.byKey(_nextKey));
          await _frames(tester);
          expect(
            fixture.provider.requests.map((request) => request.node),
            [a, b],
          );
          final current = fixture.provider.requests.last;
          current.result.complete(fileB.path);
          await _frames(tester);
          final textController =
              tester.widget<TextField>(_sourceField).controller!;
          expect(textController.text, fileB.contents);
          final scope = tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
          expect(scope.displayName, b.name);
          expect(scope.canRead(), isTrue);
          expect(scope.chrome, isNot(same(oldScope.chrome)));
          if (oldFailure) {
            old.result
                .completeError(StateError('stale private provider failure'));
          } else {
            old.result.complete(fileA.path);
          }
          staleSource(); // Must not reach a native URL launcher after retarget.
          await _frames(tester);
          expect(tester.widget<Text>(find.byKey(_titleKey)).data, b.name);
          expect(
            tester
                .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
                .chrome,
            same(scope.chrome),
          );
          expect(scope.canRead(), isTrue);
          expect(oldScope.canRead(), isFalse);
          expect(
            tester.widget<TextField>(_sourceField).controller,
            same(textController),
          );
          expect(textController.text, fileB.contents);
          expect(fileA.reads, 0);
          expect(fileB.reads, 1);
          expect(find.text(LocaleKeys.providers_cannotOpen.tr()), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    });
  }

  testWidgets(
      'A -> B -> A distinguishes requests even for the same node and path',
      (tester) async {
    final a = _node('a', 'A.bin');
    final b = _node('b', 'B.bin');
    await _withModal(
      tester,
      nodes: [a, b],
      body: (fixture) async {
        final original = fixture.provider.requests.single;
        await tester.tap(find.byKey(_nextKey));
        await _frames(tester);
        final middle = fixture.provider.requests.last;
        await tester.tap(find.byKey(_previousKey));
        await _frames(tester);
        final latest = fixture.provider.requests.last;
        original.result.complete('/external-page-flow/a.bin');
        middle.result.completeError(StateError('retired request'));
        await _frames(tester);
        expect(tester.widget<Text>(find.byKey(_titleKey)).data, a.name);
        expect(
          tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
              .available,
          isFalse,
        );
        latest.result.complete('/external-page-flow/a.bin');
        await _frames(tester);
        expect(
          tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
              .canRead(),
          isTrue,
        );
        expect(fixture.provider.requests, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
      'changed provider source rejects publication before the pending read returns',
      (tester) async {
    final a = _node('a', 'A.bin');
    final b = _node('b', 'B.bin');
    await _withModal(
      tester,
      nodes: [a, b],
      body: (fixture) async {
        final oldScope = tester
            .widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
        fixture.provider.source =
            CollectionSource.local.copyWith(remoteId: 'replacement');
        fixture.provider.requests.single.result
            .complete('/external-page-flow/old.bin');
        await _frames(tester);
        expect(oldScope.canRead(), isFalse);
        expect(
          tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
              .available,
          isFalse,
        );
        await tester.tap(find.byKey(_nextKey));
        await _frames(tester);
        fixture.provider.requests.last.result
            .complete('/external-page-flow/new.bin');
        await _frames(tester);
        expect(
          tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope))
              .canRead(),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  for (final lateFailure in [false, true]) {
    testWidgets(
        'loading close is route-owned, once-only and ignores late ${lateFailure ? 'error' : 'success'}',
        (tester) async {
      await _withModal(
        tester,
        nodes: [_node('a', 'A.bin')],
        body: (fixture) async {
          final close =
              tester.widget<IconButton>(find.byKey(_closeKey)).onPressed!;
          final scope = tester
              .widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
          final context = tester.element(find.byKey(_titleKey));
          unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('Newer dialog')),
            ),
          );
          await _frames(tester);
          close();
          await _frames(tester);
          expect(find.text('Newer dialog'), findsOneWidget);
          expect(fixture.closed, 0);
          fixture.navigator.currentState!.pop();
          await _frames(tester);
          close();
          close();
          await _frames(tester);
          expect(fixture.closed, 1);
          expect(find.byKey(_closeKey), findsNothing);
          expect(find.text('Host page'), findsOneWidget);
          expect(scope.canRead(), isFalse);
          if (lateFailure) {
            fixture.provider.requests.single.result
                .completeError(StateError('late error'));
          } else {
            fixture.provider.requests.single.result
                .complete('/external-page-flow/late.bin');
          }
          await _frames(tester);
          expect(fixture.closed, 1);
          expect(find.byType(FilePreview), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    });
  }

  for (final extension in ['css', 'txt']) {
    testWidgets(
        '$extension: header Ctrl+F and native query/source arrows do not switch siblings',
        (tester) async {
      final file = MemoryCodeFile(
        'needle one\nneedle two\nother content',
        path: '/external-page-flow/keys.$extension',
      );
      final a = _node('a', 'keys.$extension');
      final b = _node('b', 'next.bin');
      await _withModal(
        tester,
        nodes: [a, b],
        files: [file],
        body: (fixture) async {
          fixture.provider.requests.single.result.complete(file.path);
          await _frames(tester);
          final source = tester.widget<TextField>(_sourceField);
          source.focusNode!.requestFocus();
          source.controller!.selection =
              const TextSelection.collapsed(offset: 5);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(source.controller!.selection.extentOffset, 4);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          expect(source.controller!.selection.extentOffset, 5);
          expect(fixture.provider.requests, hasLength(1));
          final icon = find.descendant(
            of: find.byKey(_closeKey),
            matching: find.byType(Icon),
          );
          final headerFocus = Focus.of(tester.element(icon));
          headerFocus.requestFocus();
          await tester.pump();
          expect(headerFocus.hasFocus, isTrue);
          expect(
            tester
                .widget<ContextualFindScope>(find.byType(ContextualFindScope))
                .findInControls,
            isTrue,
          );
          await _controlKey(tester, LogicalKeyboardKey.keyF);
          await _frames(tester);
          expect(find.byType(FindReplaceBar), findsOneWidget);
          final bar =
              tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
          bar.findController.text = 'needle';
          bar.findController.selection =
              const TextSelection.collapsed(offset: 3);
          await _frames(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(bar.findController.selection.extentOffset, 2);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          expect(bar.findController.selection.extentOffset, 3);
          await _controlKey(tester, LogicalKeyboardKey.keyA);
          expect(
            bar.findController.selection,
            const TextSelection(baseOffset: 0, extentOffset: 6),
          );
          expect(fixture.provider.requests, hasLength(1));
          expect(
            tester.widget<TextField>(_sourceField).controller,
            same(source.controller),
          );
          expect(file.writes, 0);
          // Leaving native text focus restores sibling navigation.
          headerFocus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _frames(tester);
          expect(fixture.provider.requests, hasLength(2));
          expect(fixture.provider.requests.last.node, same(b));
          expect(tester.takeException(), isNull);
        },
      );
    });
  }

  testWidgets(
      'shared renderer keeps bare defaults and forwards the existing PDF read guard',
      (tester) async {
    await _withModal(
      tester,
      nodes: [_node('a', 'pending.bin')],
      body: (_) async {
        final palette =
            FolderExplorerPalette.of(tester.element(find.byKey(_titleKey)));
        final text = externalFileRenderer(
          node: _node('text', 'original.txt'),
          path: '/external-page-flow/original.txt',
          palette: palette,
        ) as FilePreview;
        expect(text.bare, isTrue);
        expect(text.height, isNull);
        expect(text.metadata, isEmpty);
        var available = true;
        bool canRead() => available;
        final pdf = externalFileRenderer(
          node: _node('pdf', 'original.pdf'),
          path: '/external-page-flow/original.pdf',
          palette: palette,
          isAvailable: canRead,
        ) as PdfPreview;
        expect(pdf.bare, isTrue);
        expect(pdf.editable, isFalse);
        expect(pdf.canReadFile, same(canRead));
        expect(pdf.canReadFile!(), isTrue);
        available = false;
        expect(pdf.canReadFile!(), isFalse);
        // Constructors only: native PDF is deliberately not mounted here.
      },
    );
  });
}

ProviderNode _node(String id, String name, {String? mime}) => ProviderNode(
      id: id,
      name: name,
      kind: ProviderNodeKind.other,
      mimeType: mime,
      // Layout/stale-callback fixture only: never activate a current URL.
      webUrl: 'https://provider.invalid/items/$id',
    );

class _Request {
  _Request(this.node);
  final ProviderNode node;
  final result = Completer<String?>();
}

class _Provider extends Fake implements ProviderController {
  @override
  CollectionSource source = CollectionSource.local;
  final requests = <_Request>[];

  @override
  Future<String?> materialize(ProviderNode node) {
    final request = _Request(node);
    requests.add(request);
    return request.result.future;
  }
}

class _Files extends IOOverrides {
  _Files(Iterable<MemoryCodeFile> files)
      : files = {for (final file in files) file.path: file};
  final Map<String, MemoryCodeFile> files;

  @override
  File createFile(String path) => files[path] ?? super.createFile(path);
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

class _Fixture {
  final provider = _Provider();
  final navigator = GlobalKey<NavigatorState>();
  int closed = 0;
}

Future<void> _withModal(
  WidgetTester tester, {
  required List<ProviderNode> nodes,
  required Future<void> Function(_Fixture) body,
  List<MemoryCodeFile> files = const [],
  String mode = 'light',
  double width = 1100,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  final fixture = _Fixture();
  final previousIO = IOOverrides.current;
  IOOverrides.global = _Files(files);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  final theme = fileControlTheme(mode);
  final defaults = AppFlowyDefaultTheme();
  late BuildContext host;
  try {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        fallbackLocale: const Locale('en', 'US'),
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const _Translations(),
        child: Builder(
          builder: (context) => MaterialApp(
            navigatorKey: fixture.navigator,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: mode == 'dark' ? defaults.dark() : defaults.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: true,
                ),
                child: Directionality(textDirection: direction, child: child!),
              ),
            ),
            home: Builder(
              builder: (context) {
                host = context;
                return const Scaffold(body: Text('Host page'));
              },
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    unawaited(
      showExternalFile(
        host,
        controller: fixture.provider,
        node: nodes.first,
        siblings: nodes,
      ).then((_) {
        fixture.closed++;
      }),
    );
    await _frames(tester);
    await body(fixture);
  } finally {
    for (final request in fixture.provider.requests) {
      if (!request.result.isCompleted) request.result.complete(null);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    IOOverrides.global = previousIO;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump();
}

Future<void> _wheel(WidgetTester tester, Offset point, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: point, scrollDelta: Offset(0, delta)),
  );
  await tester.pump();
}

Future<void> _controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
}
