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
    expect(defaults.enabled, isFalse);
    expect(defaults.theme, AutomaticViewCoverSettings.defaultTheme);

    await AutomaticViewCoverPreferences.save(
      const AutomaticViewCoverSettings(
        enabled: true,
        theme: '  warm minimal  ',
      ),
    );
    AutomaticViewCoverPreferences.resetCache();

    final saved = await AutomaticViewCoverPreferences.load();
    expect(saved.enabled, isTrue);
    expect(saved.theme, 'warm minimal');
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
    expect(int.parse(first.value), inInclusiveRange(1, 6));
  });

  test('creates a deterministic default workspace cover', () {
    final first = AutomaticViewCover.forWorkspace(name: 'My Workspace');
    final second = AutomaticViewCover.forWorkspace(name: 'My Workspace');

    expect(first, second);
    expect(first.type, PageStyleCoverImageType.builtInImage);
    expect(int.parse(first.value), inInclusiveRange(1, 6));
  });

  test('targets pages, folders, and full-page tables only', () {
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
    expect(
      AutomaticViewCover.supports(
        layout: ViewLayoutPB.Grid,
        extra: '',
        creationMetadata: const {},
      ),
      isTrue,
    );
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
      orderedEquals(['page', 'folder', 'table']),
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
