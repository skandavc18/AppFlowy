import 'dart:async';

import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'vivid_icon_test_support.dart';

void main() {
  setUpAll(prepareVividIconTestAssets);
  setUp(resetVividIconTestPacks);

  for (final appearance in vividIconTestAppearances) {
    for (final editable in [true, false]) {
      testWidgets(
        '$appearance/editable=$editable: size-only legacy cover survives; explicit none wins',
        (tester) async {
          final decoded = await _decodeLegacyCover(tester);
          final editor = EditorState(
            document: Document(
              root: pageNode(children: [paragraphNode(text: 'Body')]),
            ),
          )..disableSealTimer = true;
          editor.document.root.updateAttributes({
            DocumentHeaderBlockKeys.coverType: CoverType.asset.toString(),
            DocumentHeaderBlockKeys.coverDetails: '1',
          });
          final originalDocument = editor.document.toJson();
          final view = ValueNotifier(
            ViewPB(
              id: 'legacy-$appearance-$editable',
              name: 'Retained document title',
              icon: EmojiIconData.emoji('📘').toViewIcon(),
              extra: IconSize.merge('', 113.75),
            ),
          );
          final shared = SharedEditorContext();
          final titleBackend = _TitleBackend(view.value);
          final documentAppearance = _DocumentAppearance();
          final listener = _HeaderListener(view.value.id);
          try {
            await tester.pumpWidget(
              vividIconTestApp(
                appearance,
                MultiProvider(
                  providers: [
                    Provider<SharedEditorContext>.value(value: shared),
                    BlocProvider<DocumentAppearanceCubit>.value(
                      value: documentAppearance,
                    ),
                  ],
                  child: ValueListenableBuilder<ViewPB>(
                    valueListenable: view,
                    builder: (_, current, __) => SizedBox(
                      width: 760,
                      height: 560,
                      child: AppFlowyEditor(
                        editorState: editor,
                        editable: editable,
                        disableKeyboardService: true,
                        editorStyle: const EditorStyle.desktop(maxWidth: 760),
                        header: DocumentCoverWidget(
                          node: editor.document.root,
                          editorState: editor,
                          view: current,
                          tabs: kAllIconPickerTabs,
                          onIconChanged: (_) =>
                              fail('Cover rendering must not change the icon'),
                          titleBuilder: (view) =>
                              _NativeTitle(view: view, backend: titleBackend),
                          viewListenerFactory: listener.forView,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(view.value.cover, isNull);
            expect(find.byType(WorkspacePageCover), findsOneWidget);
            expect(find.byType(DesktopCover), findsOneWidget);
            final headerState = tester.state(find.byType(DocumentCoverWidget));
            final coverState =
                tester.state<DocumentCoverState>(find.byType(DocumentCover));
            final imageState = tester.state(find.byType(Image));
            final titleFinder = find.descendant(
              of: find.byType(_NativeTitle),
              matching: find.byType(EditableText),
            );
            final titleState = tester.state(titleFinder);
            final title = tester.widget<EditableText>(titleFinder);
            expect(title.focusNode, same(shared.coverTitleFocusNode));
            expect(title.controller.text, view.value.name);
            final download = coverState.downloadableCover!;
            expect(download.storage, CoverImageStorage.asset);
            expect(
              download.value,
              'assets/images/built_in_cover_images/m_cover_image_1.png',
            );
            expect(
              find.byKey(const ValueKey('document-decoration-download')),
              findsOneWidget,
            );
            final provider = tester.widget<Image>(find.byType(Image)).image
                as CoverImageProvider;
            expect(
              provider.imageProvider,
              AssetImage(PageStyleCoverImageType.builtInImagePath('1')),
            );
            final target = provider.size.target(
              decoded.image.width,
              decoded.image.height,
              provider.fit,
            );
            // The original predecode is a different cache key. A bounded cover
            // must finish its own native codec work, not just fake-clock settle.
            final readiness = Stopwatch()..start();
            while (tester
                    .widgetList<RawImage>(find.byType(RawImage))
                    .every((raw) => raw.image == null) &&
                readiness.elapsed < const Duration(seconds: 2)) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 1)),
              );
              await tester.pump();
            }
            expect(find.byType(RawImage), findsOneWidget);
            final rendered =
                tester.widget<RawImage>(find.byType(RawImage)).image!;
            expect(
              (rendered.width, rendered.height),
              (target.width, target.height),
            );
            final retainedFrame = rendered.clone();
            addTearDown(retainedFrame.dispose);
            if (!editable) {
              expect(find.byType(FlowyIconEmojiPicker), findsNothing);
              expect(
                find.byKey(const ValueKey('document-decoration-cover')),
                findsNothing,
              );
              expect(
                find.byKey(
                  const ValueKey('document-decoration-remove-cover'),
                ),
                findsNothing,
              );
            }

            view.value = IconSize.applyTo(view.value, 187.375);
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(Image)), same(imageState));
            expect(
              tester
                  .widget<RawImage>(find.byType(RawImage))
                  .image!
                  .isCloneOf(retainedFrame),
              isTrue,
            );
            expect(
              tester.getSize(find.byKey(const ValueKey('page-icon-frame'))),
              const Size.square(187.375),
            );
            expect(coverState.downloadableCover!.value, download.value);

            view.value = ViewPB.fromBuffer(view.value.writeToBuffer())
              ..extra = ViewCoverCodec.mergeCover(
                view.value.extra,
                const PageStyleCover.none(),
              );
            await tester.pumpAndSettle();
            expect(view.value.cover, const PageStyleCover.none());
            expect(find.byType(WorkspacePageCover), findsNothing);
            expect(find.byType(DesktopCover), findsNothing);
            expect(
              find.byKey(const ValueKey('document-decoration-download')),
              findsNothing,
            );
            expect(coverState.downloadableCover, isNull);
            expect(IconSize.decode(view.value.extra), 187.375);
            expect(
              tester.state(find.byType(DocumentCoverWidget)),
              same(headerState),
            );
            expect(tester.state(find.byType(DocumentCover)), same(coverState));
            expect(tester.state(titleFinder), same(titleState));
            expect(
              tester.widget<EditableText>(titleFinder).controller,
              same(title.controller),
            );
            expect(title.controller.text, 'Retained document title');
            expect(titleBackend.events, isEmpty);
            expect(listener.starts, 1);
            expect(editor.document.toJson(), originalDocument);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            unawaited(titleBackend.close());
            unawaited(documentAppearance.close());
            shared.dispose();
            editor.dispose();
            editor.editableNotifier.dispose();
            view.dispose();
            decoded.dispose();
          }
          expect(listener.stopped, isTrue);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}

Future<ImageInfo> _decodeLegacyCover(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final stream = AssetImage(PageStyleCoverImageType.builtInImagePath('1'))
          .resolve(ImageConfiguration.empty);
      final done = Completer<ImageInfo>();
      final listener = ImageStreamListener(
        (info, _) => done.complete(info),
        onError: done.completeError,
      );
      stream.addListener(listener);
      try {
        return await done.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    }))!;

/// Retain CoverTitle's exact native State/controller and replace only ViewBloc.
class _NativeTitle extends CoverTitle {
  const _NativeTitle({required super.view, required this.backend});
  final _TitleBackend backend;

  @override
  Widget build(BuildContext context) {
    final native = super.build(context) as BlocProvider<ViewBloc>;
    return BlocProvider<ViewBloc>.value(value: backend, child: native.child);
  }
}

class _TitleBackend extends Cubit<ViewState> implements ViewBloc {
  _TitleBackend(ViewPB view) : super(ViewState.init(view));
  final events = <ViewEvent>[];
  @override
  ViewPB get view => state.view;
  @override
  void add(ViewEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DocumentAppearance extends DocumentAppearanceCubit {
  _DocumentAppearance() {
    emit(state.copyWith(selectionColor: const Color(0x554478AA)));
  }
}

class _HeaderListener extends ViewListener {
  _HeaderListener(String id) : super(viewId: id);
  ViewListener forView(String id) => this;
  int starts = 0;
  bool stopped = false;

  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) =>
      starts++;

  @override
  Future<void> stop() async => stopped = true;
}
