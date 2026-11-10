// Two computers syncing one workspace through a folder, end to end: the real
// application, the real backend, and a real restart in place.
//
// One computer per process, so each step is run on its own, with its own HOME
// so the two never share settings — run_workspace_sync_e2e.sh beside this file
// runs the steps in order:
//
//   a1  A chooses some settings and starts syncing its workspace into the
//       folder.
//   b1  B, with a workspace of its own, joins the folder, has A's settings,
//       edits the page and changes a setting.
//   a2  A opens again and takes B's edit and B's setting in, live.
//   a3  A takes a backup, edits, and restores the backup on every computer.
//   b2  B sees the restore, loads it, and has the restored page.

import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/startup/entry_point.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/sign_in_anonymous_button.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/user/presentation/screens/skip_log_in_screen.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/prelude.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/workspace_sync_host.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/common_operations.dart';

const _step = String.fromEnvironment('SYNC_E2E_STEP');
const _root = String.fromEnvironment('SYNC_E2E_ROOT');
const _passphrase = 'an e2e sync passphrase';
const _mapsKey = 'e2e-maps-key-0123456789';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('workspace sync, step $_step', (tester) async {
    expect(_root, isNotEmpty, reason: 'pass --dart-define=SYNC_E2E_ROOT');
    final world = _World(Directory(_root));
    switch (_step) {
      case 'a1':
        await _a1(tester, world);
      case 'b1':
        await _b1(tester, world);
      case 'a2':
        await _a2(tester, world);
      case 'a3':
        await _a3(tester, world);
      case 'b2':
        await _b2(tester, world);
      default:
        fail('pass --dart-define=SYNC_E2E_STEP=a1|b1|a2|a3|b2');
    }
  });
}

WorkspaceSyncEngine get _sync => WorkspaceSyncEngine.instance;

Future<void> _a1(WidgetTester tester, _World world) async {
  await _launch(tester, world.aData, signIn: true);
  await _waitForSync(tester, null);
  final workspaceId = await _currentWorkspaceId();
  final page = await ViewBackendService.createView(
    layoutType: ViewLayoutPB.Document,
    parentViewId: workspaceId,
    name: 'Shared plan',
    initialDataBytes: DocumentDataPBFromTo.fromDocument(
      DocumentToolkit().parseMarkdown('From A'),
    )!
        .writeToBuffer(),
  ).then((result) => result.fold((view) => view, (error) => throw error));

  // A picture attached on A has to reach B as well.
  final dataPath = await getIt<ApplicationDataStorage>().getPath();
  File(p.join(dataPath, 'images', 'shared.png'))
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.generate(2048, (i) => i % 256));

  // So do the settings chosen on A, through the screens that keep them.
  final appearance = _appearance(tester);
  appearance
    ..setDateFormat(UserDateFormatPB.ISO)
    ..setThemeMode(ThemeMode.dark);
  await (await SharedPreferences.getInstance())
      .setDouble(KVKeys.kDocumentAppearanceFontSize, 19.0);
  await _settingsSaved(
    tester,
    (appearance, dateTime) =>
        dateTime.dateFormat == UserDateFormatPB.ISO &&
        appearance.themeMode == ThemeModePB.Dark,
  );

  // A key typed on A is one of the things B should not have to type again.
  await MapsSettings.instance.ensureLoaded();
  await MapsSettings.instance.setApiKey(_mapsKey);

  // The AppFlowy password, chosen here, is what seals the folder.
  await AppPassword.instance.choose(_passphrase);
  await _sync.startNew(world.destination);
  expect(_sync.isSealed, isTrue);
  expect(_sync.isBoundHere, isTrue);
  expect(
    world.folder.listSync().map((entity) => p.basename(entity.path)),
    contains(predicate<String>((name) => name.endsWith('_base.json'))),
  );
  world.save({'page': page.id, 'workspace': workspaceId});
}

Future<void> _b1(WidgetTester tester, _World world) async {
  await _launch(tester, world.bData, signIn: true);
  await _waitForSync(tester, null);
  final mine = await _currentWorkspaceId();
  final shared = world.load();
  expect(mine, isNot(shared['workspace']));

  // Sealed: nothing is told about the folder before the passphrase.
  final sealed = await _sync.inspect(world.destination);
  expect(sealed.state, SyncFolderState.locked);
  await expectLater(
    _sync.unlockFolder(world.destination, sealed, 'not the passphrase'),
    throwsA(isA<SyncError>()),
  );
  final inspection =
      await _sync.unlockFolder(world.destination, sealed, _passphrase);
  expect(inspection.state, SyncFolderState.otherWorkspace);
  expect(inspection.epoch!.workspaceId, shared['workspace']);

  // Joining restarts the application in place, and the password that opened
  // the folder is this computer's AppFlowy password from then on.
  await _sync.join(world.destination, inspection);
  await _waitForRestore(tester, shared['workspace']!);
  expect(await AppPassword.instance.current(), _passphrase);

  expect(await _pageText(shared['page']!), contains('From A'));
  final dataPath = await getIt<ApplicationDataStorage>().getPath();
  expect(
    File(p.join(dataPath, 'images', 'shared.png')).lengthSync(),
    2048,
  );

  // A's settings, and the key A typed, came with the workspace.
  await MapsSettings.instance.reload();
  expect(MapsSettings.instance.apiKey, _mapsKey);
  final appearance = _appearance(tester);
  expect(appearance.state.dateFormat, UserDateFormatPB.ISO);
  expect(appearance.state.themeMode, ThemeMode.dark);
  expect(
    (await SharedPreferences.getInstance())
        .getDouble(KVKeys.kDocumentAppearanceFontSize),
    19.0,
  );

  await _append(shared['page']!, 'From B');
  // Both away from what they are by default, so each is a real change.
  appearance.setTimeFormat(UserTimeFormatPB.TwelveHour);
  await _documentAppearance(tester).syncFontSize(21.0);
  await _settingsSaved(
    tester,
    (_, dateTime) => dateTime.timeFormat == UserTimeFormatPB.TwelveHour,
  );
  await _sync.syncNow();
  expect(_sync.phase, SyncPhase.idle, reason: _sync.binding?.lastError);
}

Future<void> _a2(WidgetTester tester, _World world) async {
  final shared = world.load();
  await _launch(tester, world.aData);
  await _waitForSync(tester, shared['workspace']);
  await _sync.syncNow();
  expect(_sync.phase, SyncPhase.idle, reason: _sync.binding?.lastError);
  final text = await _pageText(shared['page']!);
  expect(text, contains('From A'));
  expect(text, contains('From B'));
  expect(_sync.devices.length, 2);

  // B's settings are on screen here without a restart, and kept.
  await tester.pumpUntil(
    () =>
        _appearance(tester).state.timeFormat == UserTimeFormatPB.TwelveHour &&
        _documentAppearance(tester).state.fontSize == 21.0,
  );
  expect(_appearance(tester).state.dateFormat, UserDateFormatPB.ISO);
  expect(_appearance(tester).state.themeMode, ThemeMode.dark);
  await _settingsSaved(
    tester,
    (_, dateTime) => dateTime.timeFormat == UserTimeFormatPB.TwelveHour,
  );
  expect(
    (await SharedPreferences.getInstance())
        .getDouble(KVKeys.kDocumentAppearanceFontSize),
    21.0,
  );
}

Future<void> _a3(WidgetTester tester, _World world) async {
  // A's last step: nothing it kept stays in the keyring afterwards.
  addTearDown(_clearKeyring);
  final shared = world.load();
  await _launch(tester, world.aData);
  await _waitForSync(tester, shared['workspace']);
  await _sync.syncNow();

  final settings = BackupSettings.instance;
  await settings.ensureLoaded();
  await settings.update(
    settings.policy.copyWith(
      destination: BackupDestination(
        kind: BackupDestinationKind.folder,
        localPath: world.backups.path,
      ),
    ),
  );
  final taken = await BackupService.instance.runNow();
  expect(taken.succeeded, isTrue, reason: taken.detail);

  await _append(shared['page']!, 'Written after the backup');
  await _sync.syncNow();
  expect(await _pageText(shared['page']!), contains('Written after'));

  final copy = (await BackupService.instance.listCopies()).first;
  expect(copy.manifest!.hasWorkspaceSnapshot, isTrue);
  final restored = await BackupService.instance.restoreInPlace(copy: copy);
  expect(restored.syncedEverywhere, isTrue, reason: restored.syncDetail);

  _sync.detach();
  await runAppFlowy();
  await _waitForRestore(tester, shared['workspace']!);

  final text = await _pageText(shared['page']!);
  expect(text, contains('From B'));
  expect(text, isNot(contains('Written after')));
  final safety = await BackupService.instance.listLocalCopies();
  expect(
    safety.where((copy) => copy.manifest?.reason == BackupReason.beforeRestore),
    isNotEmpty,
  );
}

Future<void> _b2(WidgetTester tester, _World world) async {
  addTearDown(_clearKeyring);
  final shared = world.load();
  await _launch(tester, world.bData);
  await _waitForSync(tester, shared['workspace']);
  // The round notices the restore instead of merging anything: what A wrote
  // after its backup, and then restored away, never reaches B.
  await _sync.syncNow();
  await tester.pumpUntil(
    () => _sync.phase == SyncPhase.restoredElsewhere,
  );
  expect(_sync.restoredElsewhere!.reason.name, 'restored');
  final before = await _pageText(shared['page']!);
  expect(before, allOf(contains('From A'), contains('From B')));
  expect(before, isNot(contains('Written after')));

  await _sync.loadRestoredWorkspace();
  await _waitForRestore(tester, shared['workspace']!);
  await _sync.syncNow();
  expect(_sync.phase, SyncPhase.idle, reason: _sync.binding?.lastError);
  final text = await _pageText(shared['page']!);
  expect(text, allOf(contains('From A'), contains('From B')));
  expect(text, isNot(contains('Written after')));
  final safety = await BackupService.instance.listLocalCopies();
  expect(
    safety.where((copy) => copy.manifest?.reason == BackupReason.beforeRestore),
    isNotEmpty,
  );
}

// --- Helpers -------------------------------------------------------------------

class _World {
  _World(this.root);

  final Directory root;

  Directory get folder =>
      Directory(p.join(root.path, 'sync-folder'))..createSync(recursive: true);

  Directory get backups =>
      Directory(p.join(root.path, 'backups'))..createSync(recursive: true);

  Directory get aData =>
      Directory(p.join(root.path, 'a-data'))..createSync(recursive: true);

  Directory get bData =>
      Directory(p.join(root.path, 'b-data'))..createSync(recursive: true);

  BackupDestination get destination => BackupDestination(
        kind: BackupDestinationKind.folder,
        localPath: folder.path,
      );

  File get _notes => File(p.join(root.path, 'shared.json'));

  void save(Map<String, String> values) =>
      _notes.writeAsStringSync(jsonEncode(values));

  Map<String, String> load() =>
      Map<String, String>.from(jsonDecode(_notes.readAsStringSync()) as Map);
}

Future<void> _launch(
  WidgetTester tester,
  Directory data, {
  bool signIn = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1200));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('hotkey_manager'),
    (_) async => null,
  );
  MockApplicationDataStorage.initialPath = data.path;
  await FlowyRunner.run(AppFlowyApplication(), IntegrationMode.integrationTest);
  if (signIn) {
    await tester.pumpUntil(
      () =>
          find.byType(GoButton).evaluate().isNotEmpty ||
          find.byType(SignInAnonymousButtonV2).evaluate().isNotEmpty,
    );
    await tester.tapAnonymousSignInButton();
  }
}

/// Waits until the home screen is up and sync has attached — bound to
/// [workspaceId] when one is given.
Future<void> _waitForSync(WidgetTester tester, String? workspaceId) async {
  await tester.pumpUntil(
    () =>
        _sync.canSyncThisWorkspace &&
        (workspaceId == null || _sync.isBoundHere),
    timeout: const Duration(seconds: 90),
  );
  if (workspaceId != null) {
    expect(await _currentWorkspaceId(), workspaceId);
  }
}

/// Waits for the application that restarted to say how its restore went.
///
/// ⚠️ Not just [_waitForSync]: the sync engine outlives a restart in place, so
/// straight after one it still describes the attachment from before it.
Future<void> _waitForRestore(WidgetTester tester, String workspaceId) async {
  await tester.pumpUntil(
    () => _sync.lastRestore != null,
    timeout: const Duration(seconds: 90),
  );
  expect(
    _sync.lastRestore!.succeeded,
    isTrue,
    reason: _sync.lastRestore!.detail,
  );
  await _waitForSync(tester, workspaceId);
}

Future<String> _currentWorkspaceId() async {
  final workspace = await FolderEventReadCurrentWorkspace().send();
  return workspace.fold((value) => value.id, (error) => throw error);
}

Future<String> _pageText(String pageId) async {
  final data = await DocumentService()
      .getDocument(documentId: pageId)
      .then((result) => result.fold((data) => data, (error) => throw error));
  String join(Object? ops) => ops is List
      ? ops.map((op) => op is Map ? (op['insert'] ?? '').toString() : '').join()
      : '';

  // A block keeps its text either in the document's text map or, when it was
  // written whole rather than typed, in its own data.
  final lines = <String>[
    for (final delta in data.meta.textMap.values) join(jsonDecode(delta)),
    for (final block in data.blocks.values)
      if (block.data.isNotEmpty) join((jsonDecode(block.data) as Map)['delta']),
  ];
  return lines.where((line) => line.isNotEmpty).join('\n');
}

Future<void> _append(String pageId, String text) async {
  final toolkit = DocumentToolkit();
  final data = await toolkit.open(pageId);
  expect(data, isNotNull);
  final written = await toolkit.insert(
    pageId: pageId,
    nodes: toolkit.parseMarkdown(text).root.children,
    parentId: data!.pageId,
    previousId: toolkit.lastTopLevelBlockId(data),
  );
  expect(written, greaterThan(0));
}

/// Removes what this computer's profile kept in the desktop keyring: each test
/// computer is a profile of its own, and goes away with the test.
Future<void> _clearKeyring() async {
  if (LinuxKeyring.instance.isAvailable) {
    await LinuxKeyring.instance.clearProfile();
  }
}

AppearanceSettingsCubit _appearance(WidgetTester tester) => tester
    .element(find.byType(WorkspaceSyncHost).first)
    .read<AppearanceSettingsCubit>();

DocumentAppearanceCubit _documentAppearance(WidgetTester tester) => tester
    .element(find.byType(WorkspaceSyncHost).first)
    .read<DocumentAppearanceCubit>();

/// Waits until the backend holds settings for which [saved] is true: the
/// screens that keep them save without being waited on.
Future<void> _settingsSaved(
  WidgetTester tester,
  bool Function(AppearanceSettingsPB appearance, DateTimeSettingsPB dateTime)
      saved,
) async {
  const service = UserSettingsBackendService();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!saved(
    await service.getAppearanceSetting(),
    await service.getDateTimeSettings(),
  )) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The settings were not saved.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

extension on WidgetTester {
  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting.');
      }
      await pump(const Duration(milliseconds: 100));
    }
  }
}
