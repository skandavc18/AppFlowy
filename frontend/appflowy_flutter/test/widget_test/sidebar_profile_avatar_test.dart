import 'dart:async';

import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_uploader.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/menu/menu_user_bloc.dart';
import 'package:appflowy/workspace/application/user/settings_user_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_user.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/sidebar_workspace.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/account_user_profile.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar_button.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart' show AppFlowyPopover;
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/home_profile_test_support.dart';
import 'vivid_icon_test_support.dart';

const _oldIcon = '🐻';
const _upload = 'https://avatar-test.invalid/uploaded.png';
const _privateErrorDetail =
    r'bearer=test-only-token; C:\private-profile\avatar.png';
final _choices = <String, EmojiIconData>{
  'emoji': EmojiIconData.emoji('🌻'),
  'Default': EmojiIconData.icon(
    IconsData('appflowy_default_collections', 'book', '4283665274'),
  ),
  'Vivid': EmojiIconData.icon(IconsData(vividIconTestGroup, 'rocket', null)),
  'Upload': EmojiIconData.custom(_upload),
  'Remove': EmojiIconData.none(),
};

void main() {
  late bool recentsEnabled;
  setUpAll(() async {
    recentsEnabled = RecentIcons.enable;
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = recentsEnabled);

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance Settings -> backend ack -> broadcast -> sidebar artwork',
      (tester) async {
        final fixture = _ProfileFixture();
        final semantics = tester.ensureSemantics();
        try {
          await fixture.mount(tester, appearance);
          final button = _profileButton(AccountUserProfile);
          final node = tester.getSemantics(button);
          expect(
            node.getSemanticsData().hasFlag(SemanticsFlag.isButton),
            isTrue,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(node.label, contains('profile'));
          await tester.tap(button);
          await tester.pumpAndSettle();
          _expectPicker(PickerTabType.emoji, tester, owner: '7');
          _expectSurface(tester, appearance);
          await tester.tap(find.text(PickerTabType.icon.tr));
          await tester.pumpAndSettle();
          await tester.tap(vividIconStyleButton('Vivid'));
          await settleVividIconPictures(tester);
          await tester.tap(vividIconOption('rocket'));
          await tester.pump();

          expect(fixture.backend.writes.single.icon, _choices['Vivid']!.emoji);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
          _expectProfileIcons(tester, _oldIcon);
          fixture.backend.writes.single.succeed();
          await tester.pumpAndSettle();
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          _expectProfileIcons(tester, _oldIcon); // No fabricated local success.

          fixture.publish(_choices['Vivid']!.emoji);
          await settleVividIconPictures(tester);
          _expectProfileIcons(tester, _choices['Vivid']!.emoji);
          expect(
            fixture.menu!.state.userProfile.iconUrl,
            _choices['Vivid']!.emoji,
          );
          expect(
            fixture.settings.state.userProfile.iconUrl,
            _choices['Vivid']!.emoji,
          );
          for (final svg in tester.widgetList<FlowySvg>(
            find.descendant(
              of: find.byType(UserAvatar),
              matching: find.byType(FlowySvg),
            ),
          )) {
            expect(
              svg.svgString,
              findLoadedIcon(vividIconTestGroup, 'rocket')!.content,
            );
            expect(svg.color, isNull);
            expect(svg.blendMode, isNull);
          }
          expect(
            find.descendant(
              of: find.byType(UserAvatar),
              matching: find.byType(FlowySvg),
            ),
            findsNWidgets(2),
          );

          // The sidebar has no SettingsUserViewBloc ancestor; it uses its own
          // profile boundary, but the same action/picker as account settings.
          final sidebarContext = tester.element(find.byType(SidebarUser));
          expect(sidebarContext.read<SettingsUserViewBloc?>(), isNull);
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          _expectPicker(PickerTabType.icon, tester, owner: '7');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets(
      'sidebar avatar opens via Tab + ${key.keyLabel}',
      (tester) async {
        final fixture = _ProfileFixture();
        try {
          await fixture.mount(tester, 'paper');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          _expectPicker(PickerTabType.emoji, tester, owner: '7');
          expect(fixture.backend.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  for (final entry in _choices.entries) {
    testWidgets(
      'profile ${entry.key}: persistence, failed ack, retry and broadcast',
      (tester) async {
        final fixture = _ProfileFixture();
        try {
          await fixture.mount(tester, 'paper');
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          await _select(tester, entry.key, entry.value);
          await tester.pump();
          expect(fixture.backend.writes.single.icon, entry.value.emoji);
          expect(fixture.backend.userId, Int64(7));
          _expectProfileIcons(tester, _oldIcon);
          final callback = tester
              .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
              .onSelectedEmoji!;
          callback(entry.value.toSelectedResult()); // Ignored while saving.
          expect(fixture.backend.writes, hasLength(1));
          fixture.backend.writes.single.fail();
          await tester.pumpAndSettle();
          _expectSafeSaveError(tester);
          expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          _expectProfileIcons(tester, _oldIcon);
          callback(entry.value.toSelectedResult());
          await tester.pump();
          expect(fixture.backend.writes, hasLength(2));
          fixture.backend.writes.last.succeed();
          await tester.pumpAndSettle();
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          _expectProfileIcons(tester, _oldIcon);
          fixture.publish(entry.value.emoji);
          await tester.idle();
          expect(fixture.settings.state.userProfile.iconUrl, entry.value.emoji);
          expect(fixture.menu!.state.userProfile.iconUrl, entry.value.emoji);
          final decoded = userIconData(entry.value.emoji);
          expect(decoded.type, entry.value.type);
          expect(decoded.emoji, entry.value.emoji);
          if (entry.value.type != FlowyIconType.custom) {
            await tester.pumpAndSettle();
            _expectProfileIcons(tester, entry.value.emoji);
            await tester.tap(_profileButton(SidebarUser));
            await tester.pumpAndSettle();
            _expectPicker(entry.value.toPickerTabType()!, tester, owner: '7');
          }
          // For Upload the profile notification is asserted before a frame.
          // Unmount below instead of invoking the native/network photo loader.
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      '${entry.key} restores its current picker tab without rendering uploaded assets',
      (tester) async {
        try {
          await tester.pumpWidget(
            vividIconTestApp(
              'paper',
              AvatarPickerButton(
                identity: 'profile-7',
                label: 'Change profile picture',
                documentId: '7',
                dimension: 24,
                icon: userIconData(entry.value.emoji),
                onSelected: (_) async {},
                child: const SizedBox.square(dimension: 24),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(IconButton));
          await tester.pumpAndSettle();
          _expectPicker(entry.value.toPickerTabType()!, tester, owner: '7');
          expect(tester.takeException(), isNull);
        } finally {
          await disposeVividIconPicker(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  testWidgets(
    'keep-open selections serialize writes and survive profile broadcasts',
    (tester) async {
      final fixture = _ProfileFixture();
      try {
        await fixture.mount(tester, 'paper');
        await tester.tap(_profileButton(SidebarUser));
        await tester.pumpAndSettle();
        final callback = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .onSelectedEmoji!;
        callback(_choices['emoji']!.toSelectedResult(keepOpen: true));
        callback(_choices['Remove']!.toSelectedResult());
        await tester.pump();
        expect(fixture.backend.writes, hasLength(1));
        _expectProfileIcons(tester, _oldIcon);
        fixture.backend.writes.single.succeed();
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
        _expectProfileIcons(tester, _oldIcon);
        fixture.publish(_choices['emoji']!.emoji);
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
        _expectProfileIcons(tester, _choices['emoji']!.emoji);
        callback(_choices['Remove']!.toSelectedResult());
        await tester.pump();
        expect(fixture.backend.writes, hasLength(2));
        fixture.backend.writes.last.result.completeError(
          StateError('transport unavailable: $_privateErrorDetail'),
        );
        await tester.pumpAndSettle();
        _expectSafeSaveError(tester);
        _expectProfileIcons(tester, _choices['emoji']!.emoji);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: homeProfileTestTimeout,
  );

  for (final reason in ['user change', 'dismiss', 'dispose']) {
    testWidgets(
      'profile rejects old picker selections after $reason',
      (tester) async {
        final fixture = _ProfileFixture();
        try {
          await fixture.mount(tester, 'light');
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          final callback = tester
              .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
              .onSelectedEmoji!;
          if (reason == 'user change') {
            fixture.rebind(_profile(id: 8));
            // No frame yet: the current-user guard, not disposal, rejects this.
            callback(_choices['Vivid']!.toSelectedResult());
          } else if (reason == 'dismiss') {
            _closePicker(tester);
          } else {
            await tester.pumpWidget(const SizedBox());
          }
          await tester.pumpAndSettle();
          for (final choice in _choices.values) {
            callback(choice.toSelectedResult());
          }
          await tester.pumpAndSettle();
          expect(
            fixture.backends.values.expand((backend) => backend.writes),
            isEmpty,
          );
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          if (reason == 'user change') {
            await tester.tap(_profileButton(SidebarUser));
            await tester.pumpAndSettle();
            _expectPicker(PickerTabType.emoji, tester, owner: '8');
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  for (final succeeds in [false, true]) {
    testWidgets(
      'pending old-user success=$succeeds cannot affect a rebound sidebar or newer picker',
      (tester) async {
        final fixture = _ProfileFixture();
        try {
          await fixture.mount(tester, 'paper');
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          await _select(tester, 'emoji', _choices['emoji']!);
          await tester.pump();
          final old = fixture.backend;
          fixture.rebind(_profile(id: 8, name: 'Grace'));
          await tester.pumpAndSettle();
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          _expectPicker(PickerTabType.emoji, tester, owner: '8');
          if (succeeds) {
            old.writes.single.succeed();
          } else {
            old.writes.single.fail();
          }
          fixture.publish(
            '🌻',
            id: 7,
          ); // Deliberately broadcast a different ID.
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('avatar-save-error')), findsNothing);
          _expectPicker(PickerTabType.emoji, tester, owner: '8');
          expect(fixture.menu!.state.userProfile.id, Int64(8));
          expect(fixture.menu!.state.userProfile.iconUrl, _oldIcon);
          expect(fixture.backend.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'pending profile success=$succeeds is safe after disposal',
      (tester) async {
        final fixture = _ProfileFixture();
        try {
          await fixture.mount(tester, 'light');
          await tester.tap(_profileButton(SidebarUser));
          await tester.pumpAndSettle();
          await _select(tester, 'emoji', _choices['emoji']!);
          await tester.pump();
          final write = fixture.backend.writes.single;
          await fixture.dispose(tester);
          if (succeeds) {
            write.succeed();
          } else {
            write.fail();
          }
          await tester.pump();
          expect(fixture.backend.writes, hasLength(1));
          expect(fixture.settings.state.userProfile.iconUrl, _oldIcon);
          expect(fixture.menu!.state.userProfile.iconUrl, _oldIcon);
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          expect(find.byKey(const ValueKey('avatar-save-error')), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  testWidgets(
    'late initial profile reads and notifications after close are ignored',
    (tester) async {
      final profile = _profile();
      final listener = _ProfileListener(profile);
      final initial = Completer<FlowyResult<UserProfilePB, FlowyError>>();
      final settings = SettingsUserViewBloc(
        profile,
        userService: _ProfileBackend(profile),
        userListener: listener,
        loadUserProfile: () => initial.future,
      )..add(const SettingsUserEvent.initial());
      Future<void>? closing;
      try {
        await tester.pump();
        listener.notify(_profile(icon: '🌻'));
        initial.complete(FlowyResult.success(profile));
        await tester.pump();
        expect(settings.state.userProfile.iconUrl, '🌻');
        listener.notify(_profile(id: 8, icon: '🐈'));
        await tester.pump();
        expect(settings.state.userProfile.id, Int64(7));
        closing = settings.close();
        await pumpHomeProfileClose(tester, closing);
        listener.notify(profile);
        await tester.pump();
        expect(settings.state.userProfile.iconUrl, '🌻');
        expect(tester.takeException(), isNull);
      } finally {
        if (!initial.isCompleted) {
          initial.complete(FlowyResult.success(profile));
        }
        await pumpHomeProfileClose(tester, closing ?? settings.close());
      }
    },
    timeout: homeProfileTestTimeout,
  );

  testWidgets(
    'fixture cleanup drains active and previously closed streams',
    (tester) async {
      for (final closeWhileMounted in [false, true]) {
        final fixture = _ProfileFixture();
        late final Future<void> settingsDone;
        late final Future<void> workspaceDone;
        try {
          await fixture.mount(tester, 'light');
          settingsDone = expectLater(fixture.settings.stream, emitsDone);
          workspaceDone = expectLater(fixture.workspace.stream, emitsDone);
          if (closeWhileMounted) {
            await pumpHomeProfileClose(tester, fixture.settings.close());
            await pumpHomeProfileClose(tester, fixture.workspace.close());
          }
        } finally {
          await fixture.dispose(tester);
        }
        await settingsDone;
        await workspaceDone;
        expect(fixture.settings.isClosed, isTrue);
        expect(fixture.workspace.isClosed, isTrue);
        expect(fixture.menu!.isClosed, isTrue);
        expect(fixture.listeners.where((listener) => listener.active), isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
    timeout: homeProfileTestTimeout,
  );

  group('real cloud sidebar wiring, injected workspace repository', () {
    late UserWorkspaceBloc workspace;
    late _WorkspaceRepository repository;
    setUp(() {
      repository = _WorkspaceRepository();
    });

    Future<void> disposeSidebar(WidgetTester tester) async {
      await disposeVividIconPicker(tester);
      await pumpHomeProfileClose(
        tester,
        workspace.close(),
        description: 'Workspace sidebar fixture close',
      );
    }

    Future<void> pumpSidebar(
      WidgetTester tester, {
      AFRolePB role = AFRolePB.Owner,
    }) async {
      // Event subscriptions capture their construction zone. Build the real
      // bloc inside this widget test, not setUp's real clock, so pump delivers
      // both event handling and the following state notification to the UI.
      workspace =
          UserWorkspaceBloc(repository: repository, userProfile: _profile());
      // No initialize event: this suite never starts a native user listener.
      workspace.add(
        UserWorkspaceEvent.emitCurrentWorkspace(
          workspace: _workspace(role: role),
        ),
      );
      await tester.pumpWidget(
        vividIconTestApp(
          'paper',
          BlocProvider<UserWorkspaceBloc>.value(
            value: workspace,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: SidebarWorkspace(
                  userProfile: _profile(),
                  showUtilities: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'owner icon is separate from the name switcher and keyboard accessible',
      (tester) async {
        try {
          await pumpSidebar(tester);
          final icon = find.byType(WorkspaceIcon);
          expect(tester.widget<WorkspaceIcon>(icon).isEditable, isTrue);
          expect(
            find.ancestor(of: icon, matching: find.byType(TextButton)),
            findsNothing,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          _expectPicker(PickerTabType.emoji, tester, owner: 'workspace');
          expect(find.byType(WorkspacesMenu), findsNothing);
          expect(repository.fetches, 0);
          _closePicker(tester);
          await tester.pumpAndSettle();
          await tester
              .tap(find.byKey(const ValueKey('sidebar-workspace-switcher')));
          await tester.pumpAndSettle();
          expect(find.byType(WorkspacesMenu), findsOneWidget);
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          expect(repository.fetches, greaterThan(0));
          expect(repository.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeSidebar(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    for (final role in [AFRolePB.Member, AFRolePB.Guest]) {
      testWidgets(
        '$role sees an icon but cannot open the editor',
        (tester) async {
          try {
            await pumpSidebar(tester, role: role);
            expect(
              tester
                  .widget<WorkspaceIcon>(find.byType(WorkspaceIcon))
                  .isEditable,
              isFalse,
            );
            await tester.tap(find.byType(WorkspaceIcon));
            await tester.pumpAndSettle();
            expect(find.byType(FlowyIconEmojiPicker), findsNothing);
            expect(find.byType(WorkspacesMenu), findsNothing);
            expect(repository.writes, isEmpty);
          } finally {
            await disposeSidebar(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    for (final entry in _choices.entries) {
      testWidgets(
        'workspace ${entry.key} awaits persistence and retries failure',
        (tester) async {
          try {
            await pumpSidebar(tester);
            await tester.tap(find.byType(WorkspaceIcon));
            await tester.pumpAndSettle();
            await _select(tester, entry.key, entry.value);
            await tester.pump();
            expect(repository.writes.single.$1, 'workspace');
            expect(
              repository.writes.single.$2.icon,
              entry.value.toStorageString(),
            );
            expect(workspace.state.currentWorkspace!.icon, _oldIcon);
            expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
            repository.writes.single.$2.fail();
            await tester.pumpAndSettle();
            _expectSafeSaveError(tester);
            expect(workspace.state.currentWorkspace!.icon, _oldIcon);
            tester
                .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
                .onSelectedEmoji!(entry.value.toSelectedResult());
            await tester.pump();
            // A rename arriving during the icon write must survive its ack.
            workspace.add(
              UserWorkspaceEvent.emitCurrentWorkspace(
                workspace: _workspace(name: 'Renamed'),
              ),
            );
            await tester.pump();
            repository.writes.last.$2.succeed();
            await tester.idle();
            expect(
              workspace.state.currentWorkspace!.icon,
              entry.value.toStorageString(),
            );
            expect(workspace.state.currentWorkspace!.name, 'Renamed');
            expect(
              workspace.state.workspaces.single.icon,
              entry.value.toStorageString(),
            );
            if (entry.value.type != FlowyIconType.custom) {
              await tester.pumpAndSettle();
              expect(find.byType(FlowyIconEmojiPicker), findsNothing);
              await tester.tap(find.byType(WorkspaceIcon));
              await tester.pumpAndSettle();
              _expectPicker(
                entry.value.toPickerTabType()!,
                tester,
                owner: 'workspace',
              );
            }
            // Uploaded artwork deliberately isn't mounted: its native image
            // transport is outside this offline persistence/interaction boundary.
          } finally {
            await disposeSidebar(tester);
          }
          expect(tester.takeException(), isNull);
        },
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'permission changes reject every stale type before a write starts',
      (tester) async {
        try {
          await pumpSidebar(tester);
          await tester.tap(find.byType(WorkspaceIcon));
          await tester.pumpAndSettle();
          final callback = tester
              .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
              .onSelectedEmoji!;
          workspace.add(
            UserWorkspaceEvent.emitCurrentWorkspace(
              workspace: _workspace(role: AFRolePB.Member),
            ),
          );
          await tester
              .idle(); // State changed; the old picker is still mounted.
          for (final choice in _choices.values) {
            callback(choice.toSelectedResult());
          }
          expect(repository.writes, isEmpty);
          await tester.pumpAndSettle();
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeSidebar(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    for (final change in ['workspace', 'user', 'permission', 'dispose']) {
      testWidgets(
        'workspace selection/save rejects $change rebinding',
        (tester) async {
          try {
            await pumpSidebar(tester);
            await tester.tap(find.byType(WorkspaceIcon));
            await tester.pumpAndSettle();
            final callback = tester
                .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
                .onSelectedEmoji!;
            callback(_choices['emoji']!.toSelectedResult());
            await tester.pump();
            if (change == 'workspace') {
              workspace.add(
                UserWorkspaceEvent.emitCurrentWorkspace(
                  workspace: _workspace(id: 'new-workspace'),
                ),
              );
            } else if (change == 'user') {
              workspace.add(
                UserWorkspaceEvent.emitUserProfile(
                  userProfile: _profile(id: 8),
                ),
              );
            } else if (change == 'permission') {
              workspace.add(
                UserWorkspaceEvent.emitCurrentWorkspace(
                  workspace: _workspace(role: AFRolePB.Member),
                ),
              );
            } else {
              await tester.pumpWidget(const SizedBox());
            }
            await tester.idle();
            callback(_choices['Vivid']!.toSelectedResult());
            repository.writes.single.$2.fail();
            await tester.pumpAndSettle();
            expect(repository.writes, hasLength(1));
            expect(workspace.state.currentWorkspace!.icon, _oldIcon);
            expect(
              find.byKey(const ValueKey('avatar-save-error')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await disposeSidebar(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }
  });
}

Finder _profileButton(Type host) => find.descendant(
      of: find.descendant(
        of: find.byType(host),
        matching: find.byType(UserAvatarButton),
      ),
      matching: find.byType(IconButton),
    );

void _expectSafeSaveError(WidgetTester tester) {
  final error = find.byKey(const ValueKey('avatar-save-error'));
  expect(error, findsOneWidget);
  final message = LocaleKeys.workspaceFolderExplorer_operationFailed.tr();
  expect(message, 'The operation could not be completed.');
  expect(tester.widget<Text>(error).data, message);
  expect(find.textContaining('offline rejected'), findsNothing);
  expect(find.textContaining('transport unavailable'), findsNothing);
  expect(find.textContaining('test-only-token'), findsNothing);
  expect(find.textContaining(r'C:\private-profile'), findsNothing);
}

void _expectPicker(
  PickerTabType type,
  WidgetTester tester, {
  required String owner,
}) {
  expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
  final picker =
      tester.widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker));
  expect(picker.documentId, owner);
  expect(picker.tabs, kAllIconPickerTabs);
  final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
  expect(tabs.tabs, [
    PickerTabType.emoji,
    PickerTabType.defaultIcons,
    PickerTabType.icon,
    PickerTabType.custom,
  ]);
  expect(tabs.tabs[tabs.controller.index], type);
}

void _expectSurface(WidgetTester tester, String appearance) {
  final picker = find.byType(FlowyIconEmojiPicker);
  final context = tester.element(picker);
  final surface = tester.widget<Container>(
    find
        .ancestor(
          of: picker,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is ShapeDecoration,
          ),
        )
        .first,
  );
  expect(
    (surface.decoration! as ShapeDecoration).color,
    Theme.of(context).cardColor,
  );
  expect(PaperTheme.isEnabled(context), appearance == 'paper');
  if (appearance == 'paper') {
    expect(Theme.of(context).cardColor, isNot(Colors.white));
  }
}

void _expectProfileIcons(WidgetTester tester, String value) {
  final avatars =
      tester.widgetList<UserAvatar>(find.byType(UserAvatar)).toList();
  expect(avatars, hasLength(2));
  expect(avatars.map((avatar) => avatar.iconUrl), [value, value]);
  if (value.isNotEmpty) {
    final rendered = tester
        .widgetList<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget))
        .toList();
    expect(rendered, hasLength(2));
    expect(rendered.map((icon) => icon.emoji.emoji), [value, value]);
  } else {
    expect(find.byType(RawEmojiIconWidget), findsNothing);
    expect(find.text('A'), findsNWidgets(2));
  }
}

Future<void> _select(
  WidgetTester tester,
  String name,
  EmojiIconData value,
) async {
  if (name == 'Upload') {
    await tester.tap(find.text(PickerTabType.custom.tr));
    await tester.pumpAndSettle();
    tester.widget<IconUploader>(find.byType(IconUploader)).onUrl(value.emoji);
  } else if (name == 'Remove') {
    await tester.tap(find.text('Remove'));
  } else {
    tester
        .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
        .onSelectedEmoji!(value.toSelectedResult());
  }
}

void _closePicker(WidgetTester tester) {
  tester
      .widget<AppFlowyPopover>(
        find
            .descendant(
              of: find.byType(AvatarPickerButton),
              matching: find.byType(AppFlowyPopover),
            )
            .first,
      )
      .controller!
      .close();
}

UserProfilePB _profile({
  int id = 7,
  String name = 'Ada',
  String icon = _oldIcon,
}) =>
    UserProfilePB(id: Int64(id), name: name, iconUrl: icon);
UserWorkspacePB _workspace({
  String id = 'workspace',
  String name = 'Workspace',
  AFRolePB role = AFRolePB.Owner,
}) =>
    UserWorkspacePB(workspaceId: id, name: name, icon: _oldIcon, role: role);

class _Write {
  _Write(this.icon);
  final String icon;
  final result = Completer<FlowyResult<void, FlowyError>>();
  void succeed() => result.complete(FlowyResult.success(null));
  void fail() => result.complete(
        FlowyResult.failure(
          FlowyError(
            code: ErrorCode.Internal,
            msg: 'offline rejected: $_privateErrorDetail',
          ),
        ),
      );
}

class _ProfileBackend extends UserBackendService {
  _ProfileBackend(UserProfilePB profile) : super(userId: profile.id);
  final writes = <_Write>[];
  @override
  Future<FlowyResult<void, FlowyError>> initUser() async =>
      FlowyResult.success(null);
  @override
  Future<FlowyResult<void, FlowyError>> updateUserProfile({
    String? name,
    String? password,
    String? email,
    String? iconUrl,
  }) {
    // This boundary runs inside guarded tap/pump callbacks. Normal expect()
    // would throw a guard conflict that the real picker catches as save failure.
    expectSync(name, isNull);
    expectSync(password, isNull);
    expectSync(email, isNull);
    expectSync(iconUrl, isNotNull);
    final write = _Write(iconUrl!);
    writes.add(write);
    return write.result.future;
  }
}

class _ProfileListener extends UserListener {
  _ProfileListener(UserProfilePB profile) : super(userProfile: profile);
  void Function(UserProfileNotifyValue)? callback;
  bool active = false;
  @override
  void start({
    void Function(UserProfileNotifyValue)? onProfileUpdated,
    DidUpdateUserWorkspacesCallback? onUserWorkspaceListUpdated,
    void Function(UserWorkspacePB)? onUserWorkspaceUpdated,
    DidUpdateUserWorkspaceSetting? onUserWorkspaceSettingUpdated,
  }) {
    callback = onProfileUpdated;
    active = true;
  }

  void notify(UserProfilePB profile) =>
      callback?.call(FlowyResult.success(profile));
  @override
  Future<void> stop() async {
    active = false;
  }
}

class _AmbientWorkspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _AmbientWorkspace(UserProfilePB profile)
      : super(
          UserWorkspaceState.initial(profile)
              .copyWith(currentWorkspace: _workspace()),
        );
  void profileChanged(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileFixture {
  _ProfileFixture() {
    workspace = _AmbientWorkspace(profile);
    _bindSettings();
  }
  UserProfilePB profile = _profile();
  late _AmbientWorkspace workspace;
  late SettingsUserViewBloc settings;
  MenuUserBloc? menu;
  final settingsBlocs = <SettingsUserViewBloc>[];
  final listeners = <_ProfileListener>[];
  final backends = <Int64, _ProfileBackend>{};
  StateSetter? _rebuild;
  _ProfileBackend get backend => backends[profile.id]!;

  _ProfileListener listener(UserProfilePB user) {
    final listener = _ProfileListener(user);
    listeners.add(listener);
    return listener;
  }

  void _bindSettings() {
    backends.putIfAbsent(profile.id, () => _ProfileBackend(profile));
    final initial = profile;
    settings = SettingsUserViewBloc(
      initial,
      userService: backend,
      userListener: listener(initial),
      loadUserProfile: () async => FlowyResult.success(initial),
    )..add(const SettingsUserEvent.initial());
    settingsBlocs.add(settings);
  }

  void rebind(UserProfilePB user) {
    profile = user;
    workspace.profileChanged(user);
    _bindSettings();
    _rebuild!(() {});
  }

  void publish(String icon, {int? id}) {
    final updated =
        _profile(id: id ?? profile.id.toInt(), name: profile.name, icon: icon);
    // Deliberately deliver to every subscription. Each real bloc must reject
    // the wrong user, rather than relying on this fake to hide bad delivery.
    for (final listener in listeners) {
      if (listener.active) listener.notify(updated);
    }
  }

  Future<void> mount(WidgetTester tester, String appearance) async {
    final material = vividIconTestTheme(appearance);
    final defaults = AppFlowyDefaultTheme();
    await tester.pumpWidget(
      vividIconTestApp(
        appearance,
        AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: appearance == 'dark' ? defaults.dark() : defaults.light(),
            palette: material.extension<PremiumThemeExtension>()!,
            brightness: material.brightness,
          ),
          child: BlocProvider<UserWorkspaceBloc>.value(
            value: workspace,
            child: StatefulBuilder(
              builder: (context, rebuild) {
                _rebuild = rebuild;
                return Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SidebarUser(
                            userProfile: profile,
                            showUtilities: false,
                            createUserBloc: (user, workspaceId) =>
                                menu = MenuUserBloc(
                              user,
                              workspaceId,
                              userService: backends[user.id]!,
                              userListener: listener(user),
                            ),
                          ),
                          const SizedBox(height: 24),
                          BlocProvider<SettingsUserViewBloc>.value(
                            key: ValueKey(profile.id),
                            value: settings,
                            child: AccountUserProfile(
                              name: profile.name,
                              iconUrl: profile.iconUrl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await disposeVividIconPicker(tester);
    for (final bloc in settingsBlocs) {
      await pumpHomeProfileClose(
        tester,
        bloc.close(),
        description: 'Settings profile fixture close',
      );
    }
    await pumpHomeProfileClose(
      tester,
      workspace.close(),
      description: 'Ambient profile workspace close',
    );
    expect(listeners.where((listener) => listener.active), isEmpty);
  }
}

class _WorkspaceRepository extends Fake implements WorkspaceRepository {
  final writes = <(String, _Write)>[];
  int fetches = 0;
  @override
  Future<FlowyResult<void, FlowyError>> updateWorkspaceIcon({
    required String workspaceId,
    required String icon,
  }) {
    final write = _Write(icon);
    writes.add((workspaceId, write));
    return write.result.future;
  }

  @override
  Future<FlowyResult<WorkspacePB, FlowyError>> getCurrentWorkspace() async =>
      FlowyResult.failure(FlowyError(code: ErrorCode.Internal));
  @override
  Future<FlowyResult<List<UserWorkspacePB>, FlowyError>> getWorkspaces() async {
    fetches++;
    return FlowyResult.success([]);
  }
}
