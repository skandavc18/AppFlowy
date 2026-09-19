import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/file_viewer/attachment_file_viewer.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _sheet = ValueKey('media-actions-appearance');
const _imageViewer = ValueKey('appearance-image-viewer');
const _fileViewer = ValueKey('appearance-file-viewer');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _reveal = ValueKey('media-action-reveal');
const _fade = Duration(milliseconds: 140);
// AnimatedSwitcher disposes its outgoing child strictly after the endpoint.
const _settledFade = Duration(milliseconds: 141);

enum _Sample {
  idle('Idle', 'No pointer or keyboard focus'),
  hovered('Hovered', 'Pointer on the Copy button'),
  copying('Copying', 'Awaiting the injected service'),
  copied('Copied', 'Successful completion, not just a tap');

  const _Sample(this.label, this.caption);
  final String label;
  final String caption;
}

ValueKey<String> _photoKey(_Sample sample) => ValueKey('photo-${sample.name}');
ValueKey<String> _fileKey(_Sample sample) => ValueKey('file-${sample.name}');
ValueKey<String> _photoNameKey(_Sample sample) =>
    ValueKey('photo-name-${sample.name}');

List<Key> get _hosts => [
      for (final sample in _Sample.values) ...[
        _photoKey(sample),
        _fileKey(sample),
      ],
      _imageViewer,
      _fileViewer,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryImage photo;
  late bool originalFontFetching;
  final loadedFamilies = <String>{};

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    originalFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    // Load the resolved desktop family, not an unrelated golden-only face.
    for (final mode in _modes) {
      final text = _theme(mode).textTheme;
      loadedFamilies.addAll([
        text.bodyMedium!.fontFamily!,
        text.titleSmall!.fontFamily!,
        text.labelSmall!.fontFamily!,
        text.labelLarge!.fontFamily!,
      ]);
    }
    for (final family in loadedFamilies) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    photo = await _makePhoto();
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = originalFontFetching;
  });

  for (final mode in _modes) {
    testWidgets(
      '$mode: real media controls, page chips and viewer appearance',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 1180);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        final pointers = _HoverPointers(tester);
        final originalDocuments = fixture.documents;
        final successHosts = [
          _photoKey(_Sample.copied),
          _fileKey(_Sample.copied),
          _imageViewer,
          _fileViewer,
        ];
        final busyHosts = [
          _photoKey(_Sample.copying),
          _fileKey(_Sample.copying),
        ];

        try {
          await _mount(tester, fixture, photo, mode);
          expect(find.byType(FileBlockComponent), findsNWidgets(4));
          expect(find.byType(InteractiveImageViewer), findsOneWidget);
          expect(find.byType(InteractiveImageToolbar), findsOneWidget);
          expect(find.byType(AttachmentFileViewer), findsOneWidget);
          expect(find.byType(MediaActionButtons), findsNWidgets(10));
          expect(find.byType(MaterializedFileBuilder), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RawImage &&
                  widget.image?.width == 800 &&
                  widget.image?.height == 480,
            ),
            findsNWidgets(5),
            reason: 'Every photo must decode, not capture a blank placeholder',
          );
          for (final host in _hosts) {
            expect(_paintedOpacity(tester, host), 0);
            expect(_part(host, _copy).hitTestable(), findsNothing);
          }
          final bodyBounds = _bodyBounds(tester);
          expect(fixture.actions.calls, isEmpty);
          expect(fixture.ioCalls, 0);

          // Independent real pointer devices hold the side-by-side specimens
          // open. No private state, replacement controls or forced visibility.
          pointers.enter(_photoKey(_Sample.hovered));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(
            _paintedOpacity(tester, _photoKey(_Sample.hovered)),
            inExclusiveRange(0, 1),
          );
          await tester.pump(const Duration(milliseconds: 70));
          expect(_paintedOpacity(tester, _photoKey(_Sample.hovered)), 1);
          pointers.leave(_photoKey(_Sample.hovered));
          await tester.pump();
          expect(
            _part(_photoKey(_Sample.hovered), _copy).hitTestable(),
            findsNothing,
          );
          await tester.pump(_fade);
          expect(_paintedOpacity(tester, _photoKey(_Sample.hovered)), 0);

          for (final host in _hosts.skip(2)) {
            pointers.enter(host);
          }
          await tester.pump();
          await tester.pump(_settledFade);
          for (final host in _hosts.skip(2)) {
            expect(_paintedOpacity(tester, host), 1);
            expect(_part(host, _copy).hitTestable(), findsOneWidget);
          }
          for (final host in [
            _photoKey(_Sample.hovered),
            _fileKey(_Sample.hovered),
          ]) {
            pointers.move(host, tester.getCenter(_part(host, _copy)));
          }
          await tester.pump();
          await tester.pump(_settledFade);
          expect(
            fixture.actions.calls,
            isEmpty,
            reason: 'Hover must never invoke a media operation',
          );
          expect(_bodyBounds(tester), bodyBounds);
          final actionBounds = _actionBounds(tester);

          for (final host in [...busyHosts, ...successHosts]) {
            await tester.tap(_part(host, _copy));
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(fixture.actions.calls, hasLength(6));
          expect(
            fixture.actions.calls.every((call) => call.kind == 'copy'),
            isTrue,
          );
          expect(find.byKey(_copied), findsNothing);
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          for (final host in [...busyHosts, ...successHosts]) {
            expect(_button(tester, host, _copy).onPressed, isNull);
            expect(_button(tester, host, _share).onPressed, isNull);
          }

          final feedbackDeadline = tester.binding.clock.now().add(
                const Duration(milliseconds: 1600),
              );
          for (final host in successHosts) {
            final source = _buttons(tester, host).source;
            fixture.actions.calls
                .singleWhere((call) => call.source == source)
                .done
                .complete();
          }
          await tester.pump();
          await tester.pump(_settledFade);
          expect(find.byKey(_copied), findsNWidgets(4));
          expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
          expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
          for (final host in successHosts) {
            final badge = _part(host, _copied);
            final text = tester.widget<Text>(badge);
            expect(text.data, 'Copied');
            expect(text.style!.fontSize, 10);
            expect(loadedFamilies, contains(text.style!.fontFamily));
            expect(text.style!.fontFamily, isNot('Ahem'));
            expect(_button(tester, host, _copy).tooltip, 'Copied');
            final node = tester.getSemantics(_part(host, _copy));
            expect(node.label, 'Copied');
            expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(node.hasFlag(ui.SemanticsFlag.isLiveRegion), isTrue);
            _expectBadgeUnclipped(tester, badge);
          }
          for (final host in busyHosts) {
            expect(_part(host, _copied), findsNothing);
            expect(_button(tester, host, _copy).onPressed, isNull);
            expect(_button(tester, host, _share).onPressed, isNull);
          }
          expect(_bodyBounds(tester), bodyBounds);
          expect(_actionBounds(tester), actionBounds);
          _expectPalette(tester, mode, loadedFamilies);
          expect(fixture.documents, originalDocuments);
          expect(fixture.ioCalls, 0);
          expect(tester.takeException(), isNull);

          // Deliberately do not pumpAndSettle with the two pending spinners.
          // All animation clocks above are deterministic in update/compare runs.
          await expectLater(
            find.byKey(_sheet),
            matchesGoldenFile('goldens/media_actions_$mode.png'),
          );

          await tester.pump(
            feedbackDeadline.difference(tester.binding.clock.now()) -
                const Duration(milliseconds: 1),
          );
          expect(find.byKey(_copied), findsNWidgets(4));
          await tester.pump(const Duration(milliseconds: 1));
          for (final host in successHosts) {
            expect(_button(tester, host, _copy).tooltip, 'Copy');
          }
          await tester.pump(_settledFade);
          expect(find.byKey(_copied), findsNothing);
          expect(_actionBounds(tester), actionBounds);

          final anchor = tester.getRect(_part(_fileViewer, _share));
          await tester.tap(_part(_fileViewer, _share));
          await tester.pump();
          final share = fixture.actions.calls.last;
          expect(share.kind, 'share');
          expect(share.source.name, 'media.bin');
          expect(share.origin, anchor);
          share.done.complete();
          await tester.pump();
          await tester.pump(_settledFade);
          expect(find.byKey(_copied), findsNothing);
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          expect(fixture.actions.calls, hasLength(7));
          expect(fixture.ioCalls, 0);
          expect(fixture.documents, originalDocuments);
          expect(tester.takeException(), isNull);
        } finally {
          pointers.dispose();
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          // Resolve every fake operation, even when an assertion fails. The
          // unmounted real buttons must not leave feedback timers or tickers.
          fixture.actions.completePending();
          await tester.pump();
          fixture.dispose();
          expect(tester.binding.transientCallbackCount, 0);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

class _Fixture {
  final actions = _Actions();
  int ioCalls = 0;
  final editors = {
    for (final sample in _Sample.values)
      sample: EditorState(
        document: Document(
          root: pageNode(
            children: [
              Node(
                type: FileBlockKeys.type,
                attributes: {
                  FileBlockKeys.url: 'synthetic/${sample.name}/Field notes.bin',
                  FileBlockKeys.name: 'Field notes.bin',
                  FileBlockKeys.urlType: FileUrlType.local.toIntValue(),
                  FileBlockKeys.displayMode: 'file',
                },
              ),
            ],
          ),
        ),
      )
        ..disableSealTimer = true
        ..editable = false,
  };

  List<String> get documents => [
        for (final editor in editors.values)
          jsonEncode(editor.document.toJson()),
      ];

  void dispose() {
    for (final editor in editors.values) {
      editor.dispose();
    }
  }
}

class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource source) => _begin('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _begin('share', source, sharePositionOrigin);

  Future<void> _begin(String kind, MediaActionSource source, Rect? origin) {
    final call = _Call(kind, source, origin);
    calls.add(call);
    return call.done.future;
  }

  void completePending() {
    for (final call in calls) {
      if (!call.done.isCompleted) call.done.complete();
    }
  }
}

class _Call {
  _Call(this.kind, this.source, this.origin);
  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final done = Completer<void>();
}

class _Appearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => _AppearanceState();
}

class _AppearanceState extends Fake implements AppearanceSettingsState {
  @override
  UserDateFormatPB get dateFormat => UserDateFormatPB.values.first;
}

class _FileBuilder extends FileBlockComponentBuilder {
  _FileBuilder(this.actions);
  final MediaActionService actions;

  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      FileBlockComponent(
        key: context.node.key,
        node: context.node,
        configuration: configuration,
        mediaActions: actions,
      );
}

/// Only the image data boundary is fake; viewer, toolbar and controls are real.
class _Images extends AFImageProvider {
  const _Images(this.photo);
  final MemoryImage photo;

  @override
  int get imageCount => 1;
  @override
  int get initialIndex => 0;
  @override
  ImageBlockData getImage(int index) => ImageBlockData(
        url: 'synthetic/viewer/Ridge study.png',
        type: CustomImageType.local,
      );
  @override
  String getImageName(int index) => 'Ridge study.png';
  @override
  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]) =>
      Image(image: photo, fit: BoxFit.contain);
}

class _ReferenceSheet extends StatelessWidget {
  const _ReferenceSheet(this.fixture, this.photo, this.mode);
  final _Fixture fixture;
  final MemoryImage photo;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = PremiumThemeExtension.of(context);
    final canvas = EditorSurfaceStyle.canvasBackgroundFor(
      theme.brightness,
      theme.scaffoldBackgroundColor,
      isPaper: PaperTheme.isEnabled(context),
    );
    return RepaintBoundary(
      key: _sheet,
      child: Material(
        color: canvas,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Media actions / ${mode.toUpperCase()}',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Production widgets, isolated reference hosts. '
                'DM Sans + Material Icons. Synthetic artwork; no network or native actions.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 28),
              const _Section(
                'Photo overlay reference',
                'Real MediaHoverRegion / MediaActionReveal / MediaActionButtons '
                    'over a MemoryImage; not a full page image block.',
              ),
              const SizedBox(height: 14),
              _columns([
                for (final sample in _Sample.values)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(sample.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(sample.caption, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 14),
                      _photoSample(sample),
                      const SizedBox(height: 10),
                      Text(
                        'Ridge study.png',
                        key: _photoNameKey(sample),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
              ]),
              const SizedBox(height: 28),
              const _Section(
                'Page file chips / same four states',
                'Actual FileBlockComponent inside read-only AppFlowyEditor '
                    'fixtures. Filename and menu slots stay in place.',
              ),
              _columns([
                for (final sample in _Sample.values)
                  SizedBox(
                    key: _fileKey(sample),
                    height: 104,
                    child: AppFlowyEditor(
                      editorState: fixture.editors[sample]!,
                      editable: false,
                      disableAutoScroll: true,
                      disableKeyboardService: true,
                      disableSelectionService: true,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.fromLTRB(0, 28, 0, 16),
                      ),
                      blockComponentBuilders: {
                        ...standardBlockComponentBuilderMap,
                        FileBlockKeys.type: _FileBuilder(fixture.actions),
                      },
                      contextMenuItems: const [],
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
              const _Section(
                'Actual viewer widgets / copied',
                'Responsive, bounded hosts at 1:1 scale. '
                    'No modal route, desktop app, file opener or share sheet is launched.',
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ViewerPane(
                        label: 'InteractiveImageViewer + its real toolbar',
                        hostKey: _imageViewer,
                        child: InteractiveImageViewer(
                          imageProvider: _Images(photo),
                          actions: fixture.actions,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _ViewerPane(
                        label: 'AttachmentFileViewer / unsupported media.bin',
                        hostKey: _fileViewer,
                        child: AttachmentFileViewer(
                          file: MediaFilePB(
                            id: 'appearance-only',
                            name: 'media.bin',
                            url: 'synthetic/viewer/media.bin',
                            fileType: MediaFileTypePB.Other,
                            uploadType: FileUploadTypePB.LocalFile,
                          ),
                          actions: fixture.actions,
                          materialize: ({
                            required source,
                            required name,
                            required httpHeaders,
                          }) async {
                            fixture.ioCalls++;
                            throw StateError('No file IO in visual references');
                          },
                          openFile: (_) async {
                            fixture.ioCalls++;
                            throw StateError(
                              'No native opener in visual references',
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '28 px inline / 32 px image viewer actions · 10 px Copied badge · '
                'all copy/share calls intercepted',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoSample(_Sample sample) => SizedBox(
        key: _photoKey(sample),
        height: 192,
        child: MediaHoverRegion(
          builder: (context, visible) => Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: EditorSurfaceStyle.embedBorderRadius,
                child: Image(image: photo, fit: BoxFit.cover),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: MediaActionReveal(
                  visible: visible,
                  child: MediaActionButtons(
                    source: MediaActionSource(
                      source: 'synthetic/${sample.name}/Ridge study.png',
                      name: 'Ridge study.png',
                      isImage: true,
                    ),
                    actions: fixture.actions,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.caption);
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PremiumThemeExtension.of(context).textSecondary,
                ),
          ),
        ],
      );
}

Widget _columns(List<Widget> children) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 24),
          Expanded(child: children[index]),
        ],
      ],
    );

class _ViewerPane extends StatelessWidget {
  const _ViewerPane({
    required this.label,
    required this.hostKey,
    required this.child,
  });
  final String label;
  final Key hostKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              key: hostKey,
              borderRadius: EditorSurfaceStyle.embedBorderRadius,
              child: ColoredBox(
                color: PremiumThemeExtension.of(context).mutedSurface,
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: constraints.biggest,
                    ),
                    child: FocusScope(child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _HoverPointers {
  _HoverPointers(this.tester);
  final WidgetTester tester;
  final devices = <Key, int>{};
  final positions = <Key, Offset>{};
  int _nextDevice = 100;

  void enter(Key host) {
    devices.putIfAbsent(host, () {
      final device = _nextDevice++;
      tester.binding.handlePointerEvent(
        PointerAddedEvent(device: device, kind: ui.PointerDeviceKind.mouse),
      );
      return device;
    });
    final target = host == _fileViewer
        ? _part(host, const ValueKey('attachment-file-name'))
        : find.byKey(host);
    move(host, tester.getCenter(target));
  }

  void move(Key host, Offset position) {
    positions[host] = position;
    tester.binding.handlePointerEvent(
      PointerHoverEvent(
        device: devices[host]!,
        kind: ui.PointerDeviceKind.mouse,
        position: position,
      ),
    );
  }

  void leave(Key host) => move(host, Offset.zero);

  void dispose() {
    for (final entry in devices.entries) {
      tester.binding.handlePointerEvent(
        PointerRemovedEvent(
          device: entry.value,
          kind: ui.PointerDeviceKind.mouse,
          position: positions[entry.key] ?? Offset.zero,
        ),
      );
    }
  }
}

Finder _part(Key host, Key key) =>
    find.descendant(of: find.byKey(host), matching: find.byKey(key));

Finder _bar(Key host) => find.descendant(
      of: find.byKey(host),
      matching: find.byType(MediaActionButtons),
    );

MediaActionButtons _buttons(WidgetTester tester, Key host) =>
    tester.widget<MediaActionButtons>(_bar(host));

IconButton _button(WidgetTester tester, Key host, Key key) =>
    tester.widget<IconButton>(_part(host, key));

double _paintedOpacity(WidgetTester tester, Key host) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: _part(host, _reveal),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

List<Rect> _bodyBounds(WidgetTester tester) => [
      for (final sample in _Sample.values) ...[
        tester.getRect(find.byKey(_photoKey(sample))),
        tester.getRect(find.byKey(_photoNameKey(sample))),
        tester.getRect(
          _part(_fileKey(sample), const ValueKey('file-block-chip')),
        ),
      ],
      tester
          .getRect(_part(_fileViewer, const ValueKey('attachment-file-name'))),
    ];

List<Rect> _actionBounds(WidgetTester tester) => [
      for (final host in _hosts) ...[
        tester.getRect(_bar(host)),
        tester.getRect(_part(host, _copy)),
        tester.getRect(_part(host, _share)),
      ],
    ];

void _expectPalette(
  WidgetTester tester,
  String mode,
  Set<String> loadedFamilies,
) {
  for (final host in _hosts) {
    final context = tester.element(_bar(host));
    final palette = PremiumThemeExtension.of(context);
    final imageViewer = host == _imageViewer;
    expect(_buttons(tester, host).onDarkSurface, imageViewer);
    final decorated = _buttons(tester, host).decorated;
    final decoration = tester
        .widget<DecoratedBox>(
          _part(host, const ValueKey('media-action-surface')),
        )
        .decoration as BoxDecoration;
    expect(decoration.color, decorated ? palette.floatingSurface : null);
    expect(decoration.border, isNull);
    if (imageViewer) {
      expect(decorated, isFalse);
      expect(decoration.boxShadow, isNull);
      final group = find
          .ancestor(of: _bar(host), matching: find.byType(DecoratedBox))
          .first;
      final box = tester.widget<DecoratedBox>(group);
      final background = box.decoration as BoxDecoration;
      expect(background.color, Colors.black.withValues(alpha: 0.6));
      expect(background.borderRadius, BorderRadius.circular(6));
      expect((box.child! as Padding).padding, const EdgeInsets.all(4));
      expect(tester.getSize(group), const Size(76, 40));
    }
    for (final key in [_copy, _share]) {
      final button = _button(tester, host, key);
      expect(
        tester.getSize(_part(host, key)),
        Size.square(imageViewer ? 32 : 28),
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        imageViewer ? Colors.white : palette.textSecondary,
      );
      expect(
        button.style!.backgroundColor!.resolve({WidgetState.hovered}),
        imageViewer
            ? Colors.white.withValues(alpha: 0.1)
            : palette.accent.withValues(alpha: 0.07),
      );
    }
    expect(
      loadedFamilies,
      contains(Theme.of(context).textTheme.bodyMedium!.fontFamily),
    );
    expect(PaperTheme.isEnabled(context), mode == 'paper');
    if (mode == 'paper' && decorated) {
      expect(decoration.color, PaperTheme.popupBackground);
      expect(decoration.color!.r, greaterThan(decoration.color!.b));
    }
  }
  final context = tester.element(find.byType(AttachmentFileViewer));
  final theme = Theme.of(context);
  expect(
    tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
    EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      theme.colorScheme.surface,
      isPaper: PaperTheme.isEnabled(context),
    ),
  );
  expect(
    tester
        .widget<InteractiveImageToolbar>(find.byType(InteractiveImageToolbar))
        .hovered,
    isTrue,
  );
  expect(Icons.copy_rounded.fontFamily, 'MaterialIcons');
  expect(Icons.ios_share_rounded.fontFamily, 'MaterialIcons');
}

void _expectBadgeUnclipped(WidgetTester tester, Finder badge) {
  final bounds = tester.getRect(badge).deflate(0.01);
  for (RenderObject child = tester.renderObject(badge);
      child.parent != null;
      child = child.parent!) {
    final parent = child.parent!;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip == null) continue;
    final globalClip =
        MatrixUtils.transformRect(parent.getTransformTo(null), clip)
            .inflate(0.1);
    expect(
      globalClip.contains(bounds.topLeft),
      isTrue,
      reason: '${parent.runtimeType} clips the Copied badge',
    );
    expect(
      globalClip.contains(bounds.bottomRight),
      isTrue,
      reason: '${parent.runtimeType} clips the Copied badge',
    );
  }
}

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  MemoryImage photo,
  String mode,
) async {
  final theme = _theme(mode);
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  await tester.pumpWidget(
    Provider<AppearanceSettingsCubit>.value(
      value: _Appearance(),
      child: EasyLocalization(
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
            builder: (context, child) => AppFlowyTheme(
              data: appTheme,
              // Keep delayed tooltip overlays out of a multi-pointer sheet;
              // button hover washes and native button semantics remain real.
              child: TooltipVisibility(visible: false, child: child!),
            ),
            home: Scaffold(body: _ReferenceSheet(fixture, photo, mode)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(photo, tester.element(find.byKey(_sheet))),
  );
  await tester.pumpAndSettle();
}

/// Original landscape artwork, rasterised in memory only. These colors belong
/// to the picture, never the reference hosts or production control surfaces.
Future<MemoryImage> _makePhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 800, 480);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0, 480),
        const [Color(0xFF9BBEC4), Color(0xFFEDDDB8)],
      ),
  );
  canvas.drawCircle(
    const Offset(600, 112),
    48,
    Paint()..color = const Color(0xFFF9E8BD),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 310)
      ..lineTo(140, 168)
      ..lineTo(268, 275)
      ..lineTo(436, 124)
      ..lineTo(676, 314)
      ..lineTo(800, 244)
      ..lineTo(800, 480)
      ..lineTo(0, 480)
      ..close(),
    Paint()..color = const Color(0xFF708F8A),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 376)
      ..cubicTo(186, 233, 286, 374, 410, 300)
      ..cubicTo(570, 225, 644, 334, 800, 285)
      ..lineTo(800, 480)
      ..lineTo(0, 480)
      ..close(),
    Paint()..color = const Color(0xFF496C63),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 426)
      ..cubicTo(220, 350, 416, 455, 800, 365)
      ..lineTo(800, 480)
      ..lineTo(0, 480)
      ..close(),
    Paint()..color = const Color(0xFF294F49),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 480);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}
