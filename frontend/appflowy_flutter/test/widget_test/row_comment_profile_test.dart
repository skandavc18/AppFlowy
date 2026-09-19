import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/widgets/row/row_comments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file/local.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _avatarKey = ValueKey('row-comment-composer-avatar');
const _inputKey = ValueKey('row-comment-input');
const _postKey = ValueKey('row-comment-post');
const _redUrl = 'https://example.invalid/row-comment-profile/red.png';
const _blueUrl = 'https://example.invalid/row-comment-profile/blue.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  final photos = <String, FileInfo>{};
  late BaseCacheManager previousCache;
  late _PhotoCache cache;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    temporary = await Directory.systemTemp.createTemp('row_comment_profiles_');
    // Reading the default manager initializes its on-disk metadata eagerly.
    // Keep that initialization on the real clock and inside our isolated
    // temporary directory, before substituting the photo-only test cache.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temporary.path,
    );
    previousCache = CachedNetworkImageProvider.defaultCacheManager;
    await previousCache.getFileFromCache('unused-profile-test-entry');
    for (final (url, color) in [
      (_redUrl, const Color(0xFFFF0000)),
      (_blueUrl, const Color(0xFF0000FF)),
    ]) {
      // FileInfo requires package:file's File, not dart:io's File.
      final file = const LocalFileSystem().file(
        '${temporary.path}/${Uri.parse(url).pathSegments.last}',
      );
      await file.writeAsBytes(await _solidPng(color));
      photos[url] = FileInfo(file, FileSource.Cache, DateTime.utc(2100), url);
    }
  });
  setUp(() {
    _clearImages();
    cache = _PhotoCache(photos);
    CachedNetworkImageProvider.defaultCacheManager = cache;
  });
  tearDown(() {
    CachedNetworkImageProvider.defaultCacheManager = previousCache;
    _clearImages();
  });
  tearDownAll(() async {
    await previousCache.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await temporary.delete(recursive: true);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets('$mode: omitted profile paints the workspace photo pixels',
        (tester) async {
      final fixture = _Fixture(_profile());
      final before = _documentJson(fixture);
      try {
        await _mount(tester, fixture, mode: mode);
        expect(
          tester
              .widget<RowCommentSection>(find.byType(RowCommentSection))
              .userProfile,
          isNull,
        );
        await _expectPhoto(tester, red: true);
        final context = tester.element(find.byKey(_avatarKey));
        expect(PaperTheme.isEnabled(context), mode == 'paper');
        expect(
          Theme.of(context).brightness,
          mode == 'dark' ? Brightness.dark : Brightness.light,
        );
        expect(cache.requests, [_redUrl]);
        expect(_documentJson(fixture), before);
        expect(fixture.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('$mode: asynchronous photo update preserves draft and caret',
        (tester) async {
      final fixture = _Fixture(_profile());
      final before = _documentJson(fixture);
      const draft = TextEditingValue(
        text: 'Keep this unfinished comment',
        selection: TextSelection.collapsed(offset: 9),
      );
      try {
        await _mount(tester, fixture, mode: mode);
        await _expectPhoto(tester, red: true);
        await tester.enterText(find.byKey(_inputKey), draft.text);
        final controller = _field(tester).controller!;
        final focus = _field(tester).focusNode!;
        controller.value = draft;
        await _settle(tester);
        expect(focus.hasFocus, isTrue);

        // Same user, fresh protobuf, delivered asynchronously; no parent
        // pumpWidget/BlocBuilder may mask a missing context.select dependency.
        await tester.runAsync(
          () => Future<void>(
            () => fixture.bloc!.updateProfile(_profile(iconUrl: _blueUrl)),
          ),
        );
        await _expectPhoto(tester, red: false);
        expect(_field(tester).controller, same(controller));
        expect(_field(tester).focusNode, same(focus));
        expect(controller.value, draft);
        expect(focus.hasFocus, isTrue);
        expect(cache.requests, containsAll([_redUrl, _blueUrl]));
        expect(_documentJson(fixture), before);
        expect(fixture.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('Post resolves the latest ambient author even before rebuild',
      (tester) async {
    final fixture = _Fixture(_profile());
    try {
      await _mount(tester, fixture);
      await _expectPhoto(tester, red: true);
      await tester.enterText(find.byKey(_inputKey), '  From the active user  ');
      await _settle(tester);
      final post = tester.widget<IconButton>(find.byKey(_postKey)).onPressed!;
      final current = _profile(id: 8, name: 'Grace Hopper', iconUrl: _blueUrl);
      fixture.bloc!.updateProfile(current);
      post(); // Deliberately use the action captured before the bloc update.
      await _settle(tester);

      final saved = rowCommentsOf(fixture.editor.document).single;
      expect(saved.authorId, current.id.toString());
      expect(saved.author, current.name);
      expect(saved.avatar, current.iconUrl);
      expect(saved.text, 'From the active user');
      expect(saved.id, isNotEmpty);
      expect(
        rowCommentNodeOf(fixture.editor.document)!
            .attributes[RowCommentKeys.comments],
        [saved.toJson()],
      );
      expect(fixture.writes, 1);
      expect(_field(tester).controller!.text, isEmpty);
      await _expectPhoto(tester, red: false);
      await _expectPhoto(
        tester,
        red: false,
        within: find.byKey(ValueKey('row-comment-${saved.id}')),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('new owner can delete; other authors and stale actions cannot',
      (tester) async {
    // Identical names must not confer ownership, including legacy no-ID rows.
    final other = _comment('other', authorId: '8');
    final legacy = _comment('legacy', authorId: '');
    final fixture = _Fixture(
      _profile(iconUrl: ''),
      comments: [other, legacy],
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _mount(tester, fixture);
      await _post(tester, 'My new comment');
      final mine = rowCommentsOf(fixture.editor.document).last;
      final delete = tester.widget<IconButton>(_delete(mine.id)).onPressed!;
      expect(_delete(other.id), findsNothing);
      expect(_delete(legacy.id), findsNothing);
      expect(fixture.writes, 1);
      final beforeSwitch = _documentJson(fixture);

      fixture.bloc!.updateProfile(_profile(id: 8, iconUrl: ''));
      delete(); // Still-visible callback must recheck the current identity.
      await _settle(tester);
      expect(fixture.writes, 1);
      expect(_documentJson(fixture), beforeSwitch);
      expect(_delete(mine.id), findsNothing);
      expect(_delete(legacy.id), findsNothing);
      expect(_delete(other.id), findsOneWidget);

      expect(_delete(other.id).hitTestable(), findsNothing);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(find.byKey(ValueKey('row-comment-${other.id}'))),
      );
      await _settle(tester);
      await tester.tap(_delete(other.id));
      await _settle(tester);
      expect(fixture.writes, 2);
      expect(
        rowCommentsOf(fixture.editor.document)
            .map((comment) => comment.toJson()),
        [legacy.toJson(), mine.toJson()],
      );
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets('explicit profile wins without rewriting stored authors/photos',
      (tester) async {
    final historical = _comment(
      'historical',
      authorId: '11',
      author: 'Before the rename',
      avatar: _redUrl,
    );
    final ambient = _comment('ambient', authorId: '8', avatar: _redUrl);
    final fixture = _Fixture(_profile(), comments: [historical, ambient]);
    final explicit =
        _profile(id: 11, name: 'Explicit author', iconUrl: _blueUrl);
    final before = _documentJson(fixture);
    try {
      await _mount(tester, fixture, explicitProfile: explicit);
      await _expectPhoto(tester, red: false);
      expect(_delete(historical.id), findsOneWidget);
      expect(_delete(ambient.id), findsNothing);

      fixture.bloc!.updateProfile(_profile(id: 8, name: 'Ambient replacement'));
      await _settle(tester);
      await _expectPhoto(tester, red: false);
      await _expectPhoto(
        tester,
        red: true,
        within: find.byKey(const ValueKey('row-comment-historical')),
      );
      expect(_documentJson(fixture), before);
      expect(fixture.writes, 0);
      expect(_delete(ambient.id), findsNothing);

      await _post(tester, 'Explicitly attributed');
      final saved = rowCommentsOf(fixture.editor.document);
      expect(saved.take(2).map((comment) => comment.toJson()), [
        historical.toJson(),
        ambient.toJson(),
      ]);
      expect(saved.last.authorId, explicit.id.toString());
      expect(saved.last.author, explicit.name);
      expect(saved.last.avatar, explicit.iconUrl);
      expect(_delete(saved.last.id), findsOneWidget);
      expect(fixture.writes, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('no profile and no bloc retain safe anonymous posting behavior',
      (tester) async {
    final fixture = _Fixture(null, comments: [_comment('someone')]);
    try {
      await _mount(tester, fixture);
      expect(find.byType(IconButton), findsNothing);
      expect(
        find.descendant(of: find.byKey(_avatarKey), matching: find.text('')),
        findsOneWidget,
      );
      await _post(tester, 'Anonymous note');
      final saved = rowCommentsOf(fixture.editor.document).last;
      expect(saved.text, 'Anonymous note');
      expect(saved.authorId, isEmpty);
      expect(saved.author, isEmpty);
      expect(saved.avatar, isEmpty);
      expect(saved.toJson().containsKey('author_id'), isFalse);
      expect(saved.toJson().containsKey('avatar'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('row-comments-thread')),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(cache.requests, isEmpty);
      expect(fixture.writes, 1);
      expect(_field(tester).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('missing photo URL renders a meaningful workspace-name initial',
      (tester) async {
    final fixture = _Fixture(_profile(name: '  ada Lovelace  ', iconUrl: ''));
    final before = _documentJson(fixture);
    try {
      await _mount(tester, fixture, mode: 'paper');
      final avatar = find.byKey(_avatarKey);
      expect(
        find.descendant(of: avatar, matching: find.byType(UserAvatar)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatar, matching: find.text('A')),
        findsOneWidget,
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(RawEmojiIconWidget), findsNothing);
      expect(cache.requests, isEmpty);
      expect(_documentJson(fixture), before);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

UserProfilePB _profile({
  int id = 7,
  String name = 'Ada Lovelace',
  String iconUrl = _redUrl,
}) =>
    UserProfilePB(id: Int64(id), name: name, iconUrl: iconUrl);

RowComment _comment(
  String id, {
  String authorId = '7',
  String author = 'Ada Lovelace',
  String avatar = '',
}) =>
    RowComment(
      id: id,
      authorId: authorId,
      author: author,
      avatar: avatar,
      text: 'Stored comment $id',
      createdAt: DateTime.utc(2024, 3, 14),
    );

/// Real Cubit notifications without UserWorkspaceBloc's native user listener.
class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(UserProfilePB profile)
      : super(UserWorkspaceState.initial(profile));

  void updateProfile(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real editor transactions, with neither DocumentBloc nor backend adapters.
class _Fixture {
  _Fixture(UserProfilePB? profile, {List<RowComment> comments = const []})
      : bloc = profile == null ? null : _WorkspaceBloc(profile),
        editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                paragraphNode(text: 'The page body is not a comment.'),
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
    // Record only: stream callbacks can run outside a guarded tester action.
    _subscription = editor.transactionStream.listen(transactions.add);
  }

  final _WorkspaceBloc? bloc;
  final EditorState editor;
  final transactions = <EditorTransactionValue>[];
  late final StreamSubscription<EditorTransactionValue> _subscription;

  int get writes =>
      transactions.where((event) => event.$1 == TransactionTime.after).length;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(_subscription.cancel);
    if (bloc != null) {
      await tester.runAsync(bloc!.close);
    }
    editor.dispose();
    await tester.pump();
  }
}

/// Only the verified cached-image IO API is implemented. Unexpected cache
/// operations throw via Fake, and unknown URLs never fall through to HTTP.
class _PhotoCache extends Fake implements BaseCacheManager {
  _PhotoCache(this.photos);

  final Map<String, FileInfo> photos;
  final requests = <String>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requests.add(url);
    final photo = photos[url];
    if (photo == null || (headers?.isNotEmpty ?? false)) {
      return Stream<FileResponse>.error(
        StateError('Unexpected photo request or authentication headers: $url'),
      );
    }
    return Stream<FileResponse>.value(photo);
  }
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_inputKey));
Finder _delete(String id) => find.byKey(ValueKey('row-comment-delete-$id'));
String _documentJson(_Fixture fixture) =>
    jsonEncode(fixture.editor.document.toJson());

Future<int> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );

Future<void> _post(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_inputKey), text);
  await _settle(tester);
  await tester.tap(find.byKey(_postKey));
  await _settle(tester);
}

Future<void> _finishPhotos(WidgetTester tester) async {
  await tester.pump();
  final images = tester
      .widgetList<Image>(
        find.descendant(
          of: find.byType(UserAvatar),
          matching: find.byType(Image),
        ),
      )
      .toList();
  expect(images, isNotEmpty, reason: 'Real avatars must mount their Image');
  var completed = 0;
  final errors = <Object>[];
  final listeners = <(ImageStream, ImageStreamListener)>[];
  for (final image in images) {
    var finished = false;
    void finish() {
      if (!finished) completed++;
      finished = true;
    }

    // Resolve the mounted Image's own provider, not an assumed cache key.
    final stream = image.image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        finish();
      },
      onError: (Object error, StackTrace? stack) {
        errors.add(error);
        finish();
      },
    );
    stream.addListener(listener);
    listeners.add((stream, listener));
  }
  try {
    // IO starts on the fake clock. Alternate real IO turns and pumps so each
    // file/buffer/codec continuation can progress; never await Future.wait.
    for (var attempt = 0;
        completed < images.length && attempt < 200;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(completed, images.length, reason: 'Photo decoding must finish');
    expect(errors, isEmpty);
  } finally {
    for (final (stream, listener) in listeners) {
      stream.removeListener(listener);
    }
  }
  await _settle(tester); // Finish the real cached-image fade before inspection.
}

Future<void> _expectPhoto(
  WidgetTester tester, {
  required bool red,
  Finder? within,
}) async {
  await _finishPhotos(tester);
  final avatar = within ?? find.byKey(_avatarKey);
  expect(
    find.descendant(of: avatar, matching: find.byType(UserAvatar)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: avatar, matching: find.byType(CachedNetworkImage)),
    findsOneWidget,
  );
  expect(find.byType(RawEmojiIconWidget), findsNothing);
  final raw = tester.widget<RawImage>(
    find.descendant(of: avatar, matching: find.byType(RawImage)),
  );
  expect(raw.fit, BoxFit.cover);
  expect(raw.image, isNotNull, reason: 'An avatar URL alone is not a photo');
  final image = raw.image!.clone();
  try {
    expect(image.width, 32);
    expect(image.height, 32);
    final bytes = await tester.runAsync(
      () => image.toByteData(),
    );
    expect(bytes, isNotNull);
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    expect(bytes!.getUint8(offset), red ? 255 : 0);
    expect(bytes.getUint8(offset + 1), 0);
    expect(bytes.getUint8(offset + 2), red ? 0 : 255);
    expect(bytes.getUint8(offset + 3), 255);
  } finally {
    image.dispose();
  }
}

void _clearImages() {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

Future<List<int>> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String mode = 'light',
  UserProfilePB? explicitProfile,
}) async {
  final theme = DesktopAppearance().getThemeData(
    mode == 'paper'
        ? AppTheme.builtins.firstWhere((t) => t.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    mode == 'dark' ? Brightness.dark : Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  // Match popup hosts that provide the existing bloc but OMIT userProfile.
  final section = explicitProfile == null
      ? RowCommentSection(editorState: fixture.editor)
      : RowCommentSection(
          editorState: fixture.editor,
          userProfile: explicitProfile,
        );
  await tester.pumpWidget(
    EasyLocalization(
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
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: fixture.bloc == null
                      ? section
                      : BlocProvider<UserWorkspaceBloc>.value(
                          value: fixture.bloc!,
                          child: section,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}
