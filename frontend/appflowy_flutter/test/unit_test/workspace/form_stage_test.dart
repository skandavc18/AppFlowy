import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/encryption/sensitive_clipboard.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/table_views/form_field_tile.dart';
import 'package:appflowy/shared/table_views/form_stage.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';
import 'form_test_backend.dart';

void main() {
  String? clipboard;
  late MemoryFormBackend backend;
  late MemoryFormSource source;
  final vault = EncryptionVault.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['light', 'dark', 'paper']
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  setUp(() {
    clipboard = null;
    backend = MemoryFormBackend();
    backend.rows['work'] = {
      'title': 'Work account',
      'username': 'ada@example.test',
      'password': '  secret\n ',
    };
    backend.rows['home'] = {
      'title': 'Home account',
      'username': 'grace',
      'password': 'another secret',
    };
    source = MemoryFormSource(backend);
    vault.seedForTest();
    EncryptedColumnRegistry.instance.seedForTest('', const EncryptedColumns());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
  });

  tearDown(() {
    SensitiveClipboard.instance.resetForTest();
    source.dispose();
    vault.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    String appearance = 'light',
    FormSpec spec = const FormSpec(maskedColumns: ['password']),
    bool editable = true,
    Future<bool> Function(BuildContext)? authorize,
    FormSubmit? submit,
    double width = 1100,
    double scale = 1,
    ValueChanged<FormSpec>? onSpec,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        appearance,
        StatefulBuilder(
          builder: (context, setHostState) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: FormStage(
              viewId: '',
              title: 'Accounts',
              source: source,
              entryService: FormEntryService(viewId: '', backend: backend),
              spec: spec,
              editable: editable,
              authorize: authorize,
              onSubmit: submit,
              onSpecChanged: (next) {
                onSpec?.call(next);
                setHostState(() => spec = next);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: copy is exact and does not reveal hidden text',
        (tester) async {
      await pumpForm(tester, appearance: appearance);
      expect(find.byType(FormFieldTile), findsNWidgets(3));
      expect(find.text('  secret\n '), findsNothing);
      await tester.tap(_key('form-copy-password'));
      await tester.pumpAndSettle();
      expect(clipboard, '  secret\n ');
      expect(find.text('  secret\n '), findsNothing);
      expect(find.text('Hidden · not encrypted'), findsOneWidget);
      await tester.tap(_key('form-reveal-password'));
      await tester.pumpAndSettle();
      expect(find.text('  secret\n '), findsOneWidget);
      await tester.tap(_key('form-reveal-password'));
      await tester.pumpAndSettle();
      expect(find.text('  secret\n '), findsNothing);
      if (appearance == 'paper') {
        final context = tester.element(_key('form-field-password'));
        expect(PaperTheme.isEnabled(context), isTrue);
        final decoration = tester
            .widget<Container>(_key('form-field-password'))
            .decoration as BoxDecoration;
        expect(decoration.color, tableViewPaletteOf(context).raised);
        expect(decoration.color, isNot(Colors.white));
      }
      await tester.pump(const Duration(seconds: 30));
      expect(clipboard, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance: edit, cancel and save target one entry only',
        (tester) async {
      await pumpForm(tester, appearance: appearance);
      await tester.tap(_key('form-edit-username'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('form-input-username'), '  changed  ');
      await tester.tap(_key('form-cancel-username'));
      await tester.pumpAndSettle();
      expect(backend.writes, isEmpty);
      expect(find.text('ada@example.test'), findsOneWidget);
      await tester.tap(_key('form-edit-username'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('form-input-username'), '  changed  ');
      await tester.tap(_key('form-save-username'));
      await tester.pumpAndSettle();
      expect(backend.rows['work']!['username'], '  changed  ');
      expect(backend.rows['home']!['username'], 'grace');
      expect(find.text('  changed  '), findsOneWidget);
      expect(_key('form-input-username'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$appearance: encrypted copy and edit keep the stored value sealed',
        (tester) async {
      vault.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'test',
          verifier: 'test',
        ),
        key: randomBytes(32),
      );
      final sealed = vault.seal(' private ', context: encryptedCellContext);
      backend.rows['work']!['password'] = sealed;
      backend.protection = const EncryptedColumns(fieldIds: {'password'});
      EncryptedColumnRegistry.instance.seedForTest('', backend.protection);
      source.refresh();
      await pumpForm(
        tester,
        appearance: appearance,
        authorize: (_) async => true,
      );
      expect(find.text(sealed), findsNothing);
      expect(find.text(' private '), findsNothing);
      expect(vault.isUnlocked, isTrue);
      expect(vault.tryOpen(sealed, context: encryptedCellContext), ' private ');
      await tester.tap(_key('form-copy-password'));
      await tester.pumpAndSettle();
      expect(clipboard, ' private ');
      expect(backend.rows['work']!['password'], sealed);
      await tester.tap(_key('form-edit-password'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_key('form-input-password')).obscureText,
        isTrue,
      );
      await tester.enterText(_key('form-input-password'), ' replacement ');
      await tester.tap(_key('form-save-password'));
      await tester.pumpAndSettle();
      final stored = backend.rows['work']!['password']!;
      expect(looksSealed(stored), isTrue);
      expect(
        vault.open(stored, context: encryptedCellContext),
        ' replacement ',
      );
      expect(find.text(' replacement '), findsNothing);
      await tester.tap(_key('form-reveal-password'));
      await tester.pumpAndSettle();
      expect(find.text(' replacement '), findsOneWidget);
      vault.lock();
      await tester.pumpAndSettle();
      expect(find.text(' replacement '), findsNothing);
      expect(clipboard, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance: hidden fields can be restored after hiding all',
        (tester) async {
      await pumpForm(
        tester,
        appearance: appearance,
        spec: const FormSpec(hiddenColumns: ['title', 'username', 'password']),
      );
      expect(find.byType(FormFieldTile), findsNothing);
      await tester.tap(_key('form-show-hidden'));
      await tester.pumpAndSettle();
      expect(find.byType(FormFieldTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance: narrow, enlarged text remains usable',
        (tester) async {
      backend.columns.last.name =
          'A very long custom field label that must wrap';
      await pumpForm(tester, appearance: appearance, width: 360, scale: 1.6);
      await tester.ensureVisible(_key('form-copy-password'));
      await tester.pumpAndSettle();
      await tester.tap(_key('form-copy-password'));
      await tester.pumpAndSettle();
      expect(clipboard, '  secret\n ');
      expect(tester.takeException(), isNull);
      await SensitiveClipboard.instance.clear();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a custom hidden field is real, named, and persisted in the form',
      (tester) async {
    FormSpec? saved;
    await pumpForm(tester, onSpec: (spec) => saved = spec);
    await tester.tap(_key('form-add-field'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-custom-name'), 'Recovery code');
    await tester.tap(_key('form-custom-type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden text (mask only)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('still stored as plain text'), findsOneWidget);
    await tester.tap(_key('form-custom-save'));
    await tester.pumpAndSettle();
    expect(backend.columns.last.name, 'Recovery code');
    expect(backend.columns.last.fieldType, FieldType.RichText);
    expect(saved!.isMasked(backend.columns.last.id), isTrue);
    expect(_key('form-field-${backend.columns.last.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed submission keeps exact draft and allows retry',
      (tester) async {
    backend.rows.clear();
    source.refresh();
    var attempts = 0;
    Map<String, String>? answers;
    await pumpForm(
      tester,
      submit: (values) async {
        attempts++;
        answers = values;
        throw StateError('do not show secret backend response');
      },
    );
    await tester.enterText(_key('form-draft-title'), 'New');
    await tester.enterText(_key('form-draft-password'), '  exact  ');
    await tester.tap(_key('form-submit'));
    await tester.pumpAndSettle();
    expect(answers!['password'], '  exact  ');
    expect(
      tester.widget<TextField>(_key('form-draft-password')).controller!.text,
      '  exact  ',
    );
    expect(find.textContaining('Your draft has been kept'), findsOneWidget);
    expect(find.textContaining('secret backend'), findsNothing);
    await tester.tap(_key('form-submit'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'encrypted custom-field dialog creates a protected editable field',
      (tester) async {
    vault.seedForTest(
      policy:
          const EncryptionPolicy(enabled: true, salt: 'test', verifier: 'test'),
      key: randomBytes(32),
    );
    await pumpForm(tester, authorize: (_) async => true);
    await tester.tap(_key('form-add-field'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-custom-name'), 'Recovery code');
    await tester.tap(_key('form-custom-type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encrypted text').last);
    await tester.pumpAndSettle();
    await tester.tap(_key('form-custom-save'));
    await tester.pumpAndSettle();
    final id = backend.columns.last.id;
    expect(backend.protection.contains(id), isTrue);
    await tester.ensureVisible(_key('form-edit-$id'));
    await tester.tap(_key('form-edit-$id'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-input-$id'), '  recovery  ');
    await tester.tap(_key('form-save-$id'));
    await tester.pumpAndSettle();
    final stored = backend.rows['work']![id]!;
    expect(looksSealed(stored), isTrue);
    expect(vault.open(stored, context: encryptedCellContext), '  recovery  ');
    expect(find.text('  recovery  '), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation asks before discarding an entry edit',
      (tester) async {
    await pumpForm(tester);
    await tester.tap(_key('form-edit-username'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-input-username'), 'unsaved');
    await tester.tap(_key('form-entry-home'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this draft?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_key('form-input-username')).controller!.text,
      'unsaved',
    );
    expect(backend.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling authorization never copies or reveals',
      (tester) async {
    backend.rows['work']!['password'] = 'af1.not-readable.ciphertext';
    source.refresh();
    await pumpForm(tester, authorize: (_) async => false);
    await tester.tap(_key('form-copy-password'));
    await tester.pumpAndSettle();
    expect(clipboard, isNull);
    expect(find.text('af1.not-readable.ciphertext'), findsNothing);
    expect(backend.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read only keeps copy but removes mutation affordances',
      (tester) async {
    await pumpForm(tester, editable: false);
    expect(_key('form-add-field'), findsNothing);
    expect(_key('form-new-entry'), findsNothing);
    expect(_key('form-edit-username'), findsNothing);
    expect(_key('form-field-menu-username'), findsNothing);
    await tester.tap(_key('form-copy-username'));
    await tester.pumpAndSettle();
    expect(clipboard, 'ada@example.test');
    expect(backend.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the app conceals revealed text', (tester) async {
    await pumpForm(tester);
    await tester.tap(_key('form-reveal-password'));
    await tester.pumpAndSettle();
    expect(find.text('  secret\n '), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('  secret\n '), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('  secret\n '), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resizing across the entry-list breakpoint keeps the draft',
      (tester) async {
    await pumpForm(tester);
    await tester.tap(_key('form-edit-username'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-input-username'), 'unsaved draft');
    final controller =
        tester.widget<TextField>(_key('form-input-username')).controller;
    for (final width in [700.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_key('form-input-username')).controller,
          same(controller));
      expect(controller!.text, 'unsaved draft');
    }
    expect(backend.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a settings action never silently discards a field draft',
      (tester) async {
    await pumpForm(tester);
    await tester.tap(_key('form-edit-username'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('form-input-username'), 'unsaved draft');
    await tester.tap(_key('form-add-field'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.text(
            'Save or cancel the current field edit before changing fields.'),
        findsOneWidget);
    expect(
        tester.widget<TextField>(_key('form-input-username')).controller!.text,
        'unsaved draft');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching to a destination app keeps copied text until expiry',
      (tester) async {
    await pumpForm(tester);
    await tester.tap(_key('form-copy-password'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(clipboard, '  secret\n ');
    await tester.pump(const Duration(seconds: 30));
    expect(clipboard, '');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('form visual reference in light, dark and paper', (tester) async {
    tester.view.physicalSize = const Size(1260, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        'light',
        RepaintBoundary(
          key: const ValueKey('form-visual'),
          child: Row(
            children: [
              for (final appearance in ['light', 'dark', 'paper'])
                Expanded(
                  child: Theme(
                    data: _theme(appearance),
                    child: Builder(
                      builder: (context) => Material(
                        color: tableViewPaletteOf(context).canvas,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Work account',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 20),
                              FormFieldTile(
                                field: backend.columns[1],
                                value: 'ada@example.test',
                                onRead: () async => 'ada@example.test',
                                onSave: (_) async {},
                              ),
                              FormFieldTile(
                                field: backend.columns[2],
                                value: 'opaque',
                                encrypted: true,
                                onRead: () async => null,
                                onSave: (_) async {},
                              ),
                              TextButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add custom field'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      _key('form-visual'),
      matchesGoldenFile('../../widget_test/goldens/form_fields.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}

Finder _key(String value) => find.byKey(ValueKey(value));

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
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
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
