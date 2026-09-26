import 'dart:async';

import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'document_find_host_test_support.dart';

void main() {
  setUpFindHostTests();

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
      '$mode: real CoverTitle paint never invokes its rename listener',
      (tester) async {
        final view = ViewPB(id: 'normal-document', name: 'A needle title');
        final viewBloc = FindHostView(view);
        final info = FindHostViewInfo();
        final shared = SharedEditorContext();
        final appearance = DocumentAppearanceCubit();
        final editor = EditorState(
          document:
              Document(root: pageNode(children: [paragraphNode(text: 'Body')])),
        )..disableSealTimer = true;
        DocumentFindSession? session;
        var bodyWrites = 0;
        final transactions = editor.transactionStream.listen((event) {
          if (event.$1 == TransactionTime.after &&
              event.$2.operations.isNotEmpty) {
            bodyWrites++;
          }
        });
        try {
          await tester.pumpWidget(
            findHostApp(
              MultiProvider(
                providers: [
                  Provider<AppearanceSettingsCubit>.value(
                    value: FindHostAppearance(),
                  ),
                  Provider<EditorState>.value(value: editor),
                  Provider<SharedEditorContext>.value(value: shared),
                  Provider<ViewInfoBloc>.value(value: info),
                  BlocProvider<DocumentAppearanceCubit>.value(
                      value: appearance),
                ],
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _CoverTitleBoundary(view: view, bloc: viewBloc),
                  ),
                ),
              ),
              mode: mode,
            ),
          );
          await tester.pump();
          final fieldFinder = find.byType(EditableText);
          expect(fieldFinder, findsOneWidget);
          final field = tester.widget<EditableText>(fieldFinder);
          final fieldElement = tester.element(fieldFinder);
          final controller = field.controller;
          expect(controller, isA<DocumentFindTitleController>());
          expect(field.focusNode, same(shared.coverTitleFocusNode));
          expect(DocumentFindTitle.of(editor).text, view.name);
          shared.coverTitleFocusNode.requestFocus();
          await tester.pump();
          // Native focus can repair the initial invalid caret and notify the
          // real listener. Finish that normal work before measuring Find paint.
          await tester.pump(const Duration(milliseconds: 251));
          final originalViewEvents = List<ViewEvent>.of(viewBloc.events);
          final originalInfoEvents = List<ViewInfoEvent>.of(info.events);
          final original = controller.value;
          var notifications = 0;
          controller.addListener(() => notifications++);

          session = DocumentFindSession(editor,
              currentView: () => viewBloc.state.view);
          session.search('needle', const FindOptions());
          await tester.pump();
          expect(session.matches.single.kind, DocumentFindResultKind.title);
          expect(session.currentIsWritable, isFalse);
          final highlightedField = tester.widget<EditableText>(fieldFinder);
          final span = highlightedField.controller.buildTextSpan(
            context: tester.element(fieldFinder),
            style: highlightedField.style,
            withComposing: true,
          );
          expect(_highlightedText(span), 'needle');
          session.navigate();
          session.search('A', const FindOptions());
          session.search('needle', const FindOptions());
          expect(await session.replaceCurrent('wrong'), isFalse);
          expect(await session.replaceAll('wrong'), isFalse);
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.value, original);
          expect(notifications, 0);
          expect(viewBloc.events, originalViewEvents);
          // The production listener always emits titleChanged, even if a
          // same-value controller notification does not enqueue a rename.
          expect(info.events, originalInfoEvents);
          expect(bodyWrites, 0);
          expect(tester.element(fieldFinder), same(fieldElement));
          expect(shared.coverTitleFocusNode.hasPrimaryFocus, isTrue);

          // Positive control: this is the real rename listener, not a title
          // stand-in with an unobserved or disconnected persistence callback.
          controller.value = const TextEditingValue(
            text: 'Actually edited needle title',
            selection: TextSelection.collapsed(offset: 28),
          );
          await tester.pump(const Duration(milliseconds: 251));
          expect(notifications, 1);
          expect(viewBloc.events, [
            ...originalViewEvents,
            const ViewEvent.rename('Actually edited needle title'),
          ]);
          expect(info.events, [
            ...originalInfoEvents,
            const ViewInfoEvent.titleChanged('Actually edited needle title'),
          ]);
          session.navigate();
          session.dispose();
          session = null;
          await tester.pump(const Duration(milliseconds: 300));
          expect(notifications, 1);
          expect(viewBloc.events, hasLength(originalViewEvents.length + 1));
          expect(info.events, hasLength(originalInfoEvents.length + 1));
          expect(bodyWrites, 0);
          expect(tester.takeException(), isNull);
        } finally {
          session?.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          expect(DocumentFindTitle.of(editor).text, isNull);
          unawaited(transactions.cancel());
          unawaited(viewBloc.close());
          unawaited(appearance.close());
          shared.dispose();
          editor.dispose();
          editor.editableNotifier.dispose();
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

/// CoverTitle has no backend injection constructor. Keep the exact production
/// child returned by its public build method, including the private native
/// title state and rename listener, and replace ONLY its owning ViewBloc.
class _CoverTitleBoundary extends CoverTitle {
  const _CoverTitleBoundary({required super.view, required this.bloc});
  final FindHostView bloc;
  @override
  Widget build(BuildContext context) {
    final native = super.build(context) as BlocProvider<ViewBloc>;
    return BlocProvider<ViewBloc>.value(value: bloc, child: native.child);
  }
}

String _highlightedText(InlineSpan span, [bool marked = false]) {
  if (span is! TextSpan) return '';
  final highlighted = marked || span.style?.backgroundColor != null;
  return '${highlighted ? span.text ?? '' : ''}'
      '${(span.children ?? const <InlineSpan>[]).map((child) => _highlightedText(child, highlighted)).join()}';
}
