import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/mobile/presentation/notifications/widgets/settings_popup_menu.dart';
import 'package:appflowy/plugins/shared/share/export_tab.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/launch_configuration.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/feature_flag_task.dart';
import 'package:appflowy/startup/tasks/load_plugin.dart';
import 'package:appflowy/user/application/billing_policy.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_type.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/setting_cloud.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    show ViewLayoutPB, ViewPB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const buildModeFeatureParityCaseCount = 25;

void main() => runBuildModeFeatureParityTests();

/// Runs unchanged in the unit runner and the actual Debug/Release Windows
/// engines. No normal startup, native backend, account or live preferences.
void runBuildModeFeatureParityTests() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  late _MemoryStorage storage;
  setUp(() {
    getIt.pushNewScope();
    storage = _MemoryStorage();
    getIt.registerSingleton<KeyValueStorage>(storage);
  });
  tearDown(() async {
    await FeatureFlag.clear();
    await getIt.popScope();
  });

  for (final mode in [IntegrationMode.develop, IntegrationMode.release]) {
    testWidgets('${mode.name}: launch task restores saved feature flags',
        (tester) async {
      await storage.set(
        KVKeys.featureFlag,
        jsonEncode({'sharedSection': true, 'search': false}),
      );
      await const FeatureFlagTask().initialize(_launchContext(mode));
      expect(FeatureFlag.sharedSection.isOn, isTrue);
      expect(FeatureFlag.data[FeatureFlag.sharedSection], isTrue);
      // Already-released capabilities keep their established always-on policy.
      expect(FeatureFlag.search.isOn, isTrue);
      await storage.set(KVKeys.featureFlag, '{"sharedSection":false}');
      await const FeatureFlagTask().initialize(_launchContext(mode));
      expect(FeatureFlag.sharedSection.isOn, isFalse);
    });
  }

  testWidgets('all application plugins and built-in extensions are registered',
      (tester) async {
    final sandbox = PluginSandbox();
    getIt.registerSingleton<PluginSandbox>(sandbox);
    await const PluginLoadTask().initialize(
      _launchContext(IntegrationMode.unitTest),
    );
    expect(sandbox.supportPluginTypes.toSet(), PluginType.values.toSet());
    expect(
      builtInDartExtensions().map((extension) => extension.info.id).toSet(),
      {'data', 'glass', 'tally', 'stock', 'news', 'astrology'},
    );
  });

  testWidgets('billing uses the same restricted server list', (tester) async {
    for (final url in [
      'https://beta.appflowy.cloud',
      'https://test.appflowy.cloud',
    ]) {
      expect(BillingPolicy.supportsServer(url), isTrue);
    }
    for (final url in [
      '',
      'http://localhost:8000',
      'https://self-hosted.example',
      'https://test.appflowy.cloud.example',
      'http://test.appflowy.cloud',
    ]) {
      expect(BillingPolicy.supportsServer(url), isFalse, reason: url);
    }
  });

  testWidgets('billing management still requires a cloud workspace owner',
      (tester) async {
    for (final workspace in WorkspaceTypePB.values) {
      for (final role in [null, ...AFRolePB.values]) {
        expect(
          BillingPolicy.canManageWorkspace(workspace, role),
          workspace == WorkspaceTypePB.ServerW && role == AFRolePB.Owner,
        );
      }
    }
  });

  testWidgets('payment return follows configured domain, not compiler mode',
      (tester) async {
    for (final domain in [
      'https://appflowy.com',
      'https://beta.appflowy.com',
      'test.appflowy.com',
      'http://localhost:8080',
    ]) {
      final base = domain.contains('://') ? domain : 'https://$domain';
      expect(
        BillingPolicy.paymentSuccessUrl(domain, SubscriptionPlanPB.Pro),
        '$base/after-payment?plan=pro',
      );
    }
    expect(
      BillingPolicy.paymentSuccessUrl(
        'https://example.test/workspace/?old=value#section',
        SubscriptionPlanPB.AiMax,
      ),
      'https://example.test/workspace/after-payment?plan=ai_max',
    );
  });

  testWidgets('payment returns reject non-web origins and embedded credentials',
      (tester) async {
    for (final domain in [
      '',
      'file:///tmp/page',
      'javascript:alert(1)',
      'https://user@example.test',
    ]) {
      expect(
        () => BillingPolicy.paymentSuccessUrl(domain, SubscriptionPlanPB.Pro),
        throwsArgumentError,
      );
    }
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: settings parity preserves role restrictions',
        (tester) async {
      for (final scenario in [
        (WorkspaceTypePB.ServerW, AFRolePB.Owner, true),
        (WorkspaceTypePB.ServerW, AFRolePB.Guest, false),
        (WorkspaceTypePB.LocalW, null, false),
      ]) {
        SettingsPage? selected;
        await _pump(
          tester,
          appearance,
          SettingsMenu(
            changeSelectedPage: (SettingsPage page) => selected = page,
            currentPage: SettingsPage.account,
            userProfile: UserProfilePB(workspaceType: scenario.$1),
            currentUserRole: scenario.$2,
            isBillingEnabled: scenario.$3,
          ),
        );
        final pages = tester
            .widgetList<SettingsMenuElement>(find.byType(SettingsMenuElement))
            .map((entry) => entry.page)
            .toSet();
        expect(
          pages,
          SettingsPage.values.toSet().difference(
                scenario.$3
                    ? {}
                    : {
                        SettingsPage.member,
                        SettingsPage.sites,
                        SettingsPage.plan,
                        SettingsPage.billing,
                      },
              ),
        );
        final flags = find.text('Feature Flags');
        await tester.ensureVisible(flags);
        await tester.pumpAndSettle();
        await tester.tap(flags);
        expect(selected, SettingsPage.featureFlags);
        expect(tester.takeException(), isNull);
      }
    });

    for (final layout in [ViewLayoutPB.Document, ViewLayoutPB.Grid]) {
      testWidgets('$appearance: ${layout.name} includes lossless export',
          (tester) async {
        final bloc = _ExportBloc(ViewPB(name: 'Parity', layout: layout));
        final picker = _FilePicker()..nextPath = 'isolated-export.json';
        getIt.registerSingleton<FilePickerService>(picker);
        try {
          await _pump(
            tester,
            appearance,
            BlocProvider<ShareBloc>.value(
              value: bloc,
              child: const ExportTab(),
            ),
          );
          final label =
              layout == ViewLayoutPB.Document ? 'JSON' : 'Raw Database Data';
          expect(find.text(label), findsOneWidget);
          await tester.tap(find.text(label));
          await tester.pump();
          expect(picker.fileNames, ['Parity.json']);
          expect(
            bloc.events,
            [
              ShareEvent.share(
                layout == ViewLayoutPB.Document
                    ? ShareType.json
                    : ShareType.rawDatabaseData,
                'isolated-export.json',
              ),
            ],
          );
          // Cancelling the picker must not enqueue an export.
          picker.nextPath = null;
          await tester.tap(find.text(label));
          await tester.pump();
          expect(bloc.events, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await bloc.close();
        }
      });
    }

    testWidgets('$appearance: every supported import is available',
        (tester) async {
      await _pump(
        tester,
        appearance,
        ImportPanel(parentViewId: '', importCallback: (_, __, ___) {}),
      );
      for (final type in ImportType.values) {
        expect(type.enableOnRelease, isTrue);
        expect(find.text(type.toString()), findsOneWidget);
        expect(type.allowedExtensions, isNotEmpty);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: cloud selector offers every configured provider',
        (tester) async {
      // Inspect the real selector's options without mounting a settings bloc
      // or contacting any of the cloud choices.
      late SettingsDropdown<AuthenticatorType> dropdown;
      await _pump(
        tester,
        appearance,
        Builder(
          builder: (context) {
            dropdown = CloudTypeSwitcher(
              cloudType: AuthenticatorType.local,
              onSelected: (_) {},
            ).build(context) as SettingsDropdown<AuthenticatorType>;
            return const SizedBox();
          },
        ),
      );
      expect(
        dropdown.options.map((entry) => entry.value).toSet(),
        AuthenticatorType.values.toSet(),
      );
    });

    testWidgets('$appearance: notification menu offers unarchive all',
        (tester) async {
      await _pump(tester, appearance, const NotificationSettingsPopupMenu());
      await tester.tap(find.byType(NotificationSettingsPopupMenu));
      await tester.pumpAndSettle();
      expect(find.text('Unarchive all'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

LaunchContext _launchContext(IntegrationMode mode) => LaunchContext(
      getIt,
      mode,
      const LaunchConfiguration(version: 'parity-test', rustEnvs: {}),
    );

Future<void> _pump(
  WidgetTester tester,
  String appearance,
  Widget child,
) async {
  await tester.pumpWidget(_app(appearance, const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(_app(appearance, child));
  await tester.pumpAndSettle();
  expect(
    PaperTheme.isEnabled(tester.element(find.byType(Scaffold))),
    appearance == 'paper',
  );
}

Widget _app(String appearance, Widget child) {
  final brightness = appearance == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins.firstWhere((t) => t.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final builder = AppFlowyDefaultTheme();
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    useFallbackTranslations: true,
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: brightness == Brightness.dark
                ? builder.dark()
                : builder.light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: brightness,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: 640, height: 500, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemoryStorage implements KeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> set(String key, String value) async => values[key] = value;
  @override
  Future<String?> get(String key) async => values[key];
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> clear() async => values.clear();
  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}

class _FilePicker extends FilePickerService {
  String? nextPath;
  final fileNames = <String?>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    fileNames.add(fileName);
    return nextPath;
  }
}

class _ExportBloc extends Cubit<ShareState> implements ShareBloc {
  _ExportBloc(this.view)
      : super(ShareState.initial().copyWith(viewName: view.name));

  @override
  final ViewPB view;
  final events = <ShareEvent>[];

  @override
  void add(ShareEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
