import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AutomaticViewCoverPreferences.resetCache();
  });

  test('persists automatic cover preferences', () async {
    final defaults = await AutomaticViewCoverPreferences.load();
    expect(defaults.enabled, isTrue, reason: 'a new page arrives dressed');
    expect(defaults.theme, AutomaticViewCoverSettings.defaultTheme);
    expect(defaults.set, ViewCoverSet.nature);

    await AutomaticViewCoverPreferences.save(
      const AutomaticViewCoverSettings(
        enabled: false,
        theme: '  warm minimal  ',
        set: ViewCoverSet.abstract,
      ),
    );
    AutomaticViewCoverPreferences.resetCache();

    final saved = await AutomaticViewCoverPreferences.load();
    expect(saved.enabled, isFalse);
    expect(saved.theme, 'warm minimal');
    expect(saved.set, ViewCoverSet.abstract);
  });

  test('resolves both picture sets to files that ship with the app', () {
    expect(natureCoverValues, hasLength(builtInCoverCount));
    expect(abstractCoverValues, hasLength(builtInCoverCount));
    expect(
      builtInCoverValues,
      orderedEquals([...natureCoverValues, ...abstractCoverValues]),
    );
    expect(
      PageStyleCoverImageType.builtInImagePath('n3'),
      'assets/images/built_in_cover_images/nature_cover_image_3.png',
    );
    expect(
      PageStyleCoverImageType.builtInImagePath('3'),
      'assets/images/built_in_cover_images/m_cover_image_3.png',
      reason: 'pages already wearing an abstract cover keep it',
    );
  });

  test('creates deterministic bundled photo covers', () {
    final first = AutomaticViewCover.forNewView(
      theme: 'calm nature',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );
    final second = AutomaticViewCover.forNewView(
      theme: 'calm nature',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );

    expect(first, second);
    expect(first.type, PageStyleCoverImageType.builtInImage);
    expect(natureCoverValues, contains(first.value));

    final abstractCover = AutomaticViewCover.forNewView(
      theme: 'calm nature',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
      set: ViewCoverSet.abstract,
    );
    expect(abstractCoverValues, contains(abstractCover.value));
  });

  test('creates a deterministic default workspace cover', () {
    final first = AutomaticViewCover.forWorkspace(name: 'My Workspace');
    final second = AutomaticViewCover.forWorkspace(name: 'My Workspace');

    expect(first, second);
    expect(first.type, PageStyleCoverImageType.builtInImage);
    expect(natureCoverValues, contains(first.value));
  });

  test('targets pages and folders, never tables', () {
    final folderExtra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
    final fileExtra = const WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.collaborativeText,
    ).mergeIntoExtra('');

    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Document,
        extra: '',
        creationMetadata: const {},
      ),
      isTrue,
    );
    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Document,
        extra: folderExtra,
        creationMetadata: const {},
      ),
      isTrue,
    );
    for (final layout in const [
      ViewLayoutPB.Grid,
      ViewLayoutPB.Board,
      ViewLayoutPB.Calendar,
    ]) {
      expect(
        AutomaticViewCover.supports(
          layout: layout,
          extra: '',
          creationMetadata: const {},
        ),
        isFalse,
        reason: '$layout is data, so it starts without a cover',
      );
    }
    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Document,
        extra: fileExtra,
        creationMetadata: const {},
      ),
      isFalse,
    );
    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Grid,
        extra: '',
        creationMetadata: const {'database_id': 'linked'},
      ),
      isFalse,
    );
    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Chat,
        extra: '',
        creationMetadata: const {},
      ),
      isFalse,
    );
  });

  test('plans covers only for eligible existing views without covers', () {
    final existingCover = ViewCoverCodec.mergeCover(
      '',
      const PageStyleCover(
        type: PageStyleCoverImageType.builtInImage,
        value: '2',
      ),
    );
    final folderExtra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
    final fileExtra = const WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.collaborativeText,
    ).mergeIntoExtra('');
    final views = [
      ViewPB(
        id: 'page',
        parentViewId: 'space',
        name: 'Page',
        layout: ViewLayoutPB.Document,
      ),
      ViewPB(
        id: 'folder',
        parentViewId: 'space',
        name: 'Folder',
        layout: ViewLayoutPB.Document,
        extra: folderExtra,
      ),
      ViewPB(
        id: 'table',
        parentViewId: 'space',
        name: 'Table',
        layout: ViewLayoutPB.Grid,
      ),
      ViewPB(
        id: 'covered',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
        extra: existingCover,
      ),
      ViewPB(
        id: 'file',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
        extra: fileExtra,
      ),
      ViewPB(
        id: 'space',
        parentViewId: 'workspace',
        layout: ViewLayoutPB.Document,
        extra: '{"is_space":true}',
      ),
      ViewPB(
        id: 'workspace',
        layout: ViewLayoutPB.Document,
      ),
      ViewPB(
        id: 'chat',
        parentViewId: 'space',
        layout: ViewLayoutPB.Chat,
      ),
    ];

    final updates = AutomaticViewCover.updatesForExistingViews(
      views: views,
      theme: 'warm minimal',
    );

    expect(
      updates.map((update) => update.viewId),
      orderedEquals(['page', 'folder']),
    );
    for (final update in updates) {
      expect(ViewCoverCodec.decodeCover(update.extra)?.isNone, isFalse);
    }
    expect(ViewCoverCodec.decodeCover(existingCover)?.value, '2');
  });

  test('surfaces malformed metadata while planning existing covers', () {
    final view = ViewPB(
      id: 'page',
      parentViewId: 'space',
      layout: ViewLayoutPB.Document,
      extra: '{invalid',
    );

    expect(
      () => AutomaticViewCover.updatesForExistingViews(
        views: [view],
        theme: 'calm',
      ),
      throwsFormatException,
    );
  });
}
