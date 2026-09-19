import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_banner_bloc.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/grid/application/row/row_detail_bloc.dart';
import 'package:appflowy/plugins/database/widgets/row/row_banner.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail_scroll_surface.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';

const _viewId = 'row-cover-test-view';
const _rowId = 'row-cover-test-row';
const _actions = ValueKey('row-cover-test-actions');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousDisableLog = Log.shared.disableLog;

  setUpAll(() async {
    // Expected refusal must not invoke the native logger in any build mode.
    Log.shared.disableLog = true;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() async {
    Log.shared.disableLog = previousDisableLog;
    await RustStreamReceiver.shared.dispose();
  });

  test('only an absent cover gets a deterministic new-row default', () {
    final row = _row();
    final bytes = row.writeToBuffer();
    final cover = effectiveRowCover(row)!;
    expect(cover.coverType, CoverTypePB.GradientCover);
    expect(cover, defaultRowCover(_rowId));
    expect(effectiveRowCover(_roundTrip(row)), cover);
    expect(rowCoverHeightFor(row), rowCoverHeight);
    expect(row.hasCover(), isFalse);
    expect(row.writeToBuffer(), bytes, reason: 'rendering must not persist');
  });

  for (final type in CoverTypePB.values) {
    test('an empty $type remains removed after a wire round-trip', () {
      final row = _roundTrip(_row(cover: RowCoverPB(coverType: type)));
      expect(row.hasCover(), isTrue);
      expect(row.cover.data, isEmpty);
      expect(effectiveRowCover(row), isNull);
      expect(rowCoverHeightFor(row), 0);
    });
  }

  for (final cover in [
    RowCoverPB(data: '0xffb9a6d6', coverType: CoverTypePB.ColorCover),
    RowCoverPB(data: '1', coverType: CoverTypePB.AssetCover),
    defaultRowCover(_rowId),
    for (final upload in FileUploadTypePB.values)
      RowCoverPB(
        data: 'existing-cover.png',
        coverType: CoverTypePB.FileCover,
        uploadType: upload,
      ),
  ]) {
    test('chosen ${cover.coverType}/${cover.uploadType} is not replaced', () {
      final row = _row(cover: cover);
      expect(effectiveRowCover(row), same(row.cover));
      expect(effectiveRowCover(_roundTrip(row)), cover);
      expect(rowCoverHeightFor(row), rowCoverHeight);
    });
  }

  test('banner equality distinguishes absent, removed, type and upload', () {
    final absent = RowBannerState.initial(_row());
    final removed = absent.copyWith(rowMeta: _row(cover: RowCoverPB()));
    expect(removed, isNot(absent));
    final color = absent.copyWith(
      rowMeta: _row(
        cover: RowCoverPB(data: '1', coverType: CoverTypePB.ColorCover),
      ),
    );
    final asset = color.copyWith(
      rowMeta: _row(
        cover: RowCoverPB(data: '1', coverType: CoverTypePB.AssetCover),
      ),
    );
    final local = color.copyWith(
      rowMeta: _row(
        cover: RowCoverPB(data: '1', coverType: CoverTypePB.FileCover),
      ),
    );
    final cloud = local.copyWith(
      rowMeta: _row(
        cover: RowCoverPB(
          data: '1',
          coverType: CoverTypePB.FileCover,
          uploadType: FileUploadTypePB.CloudFile,
        ),
      ),
    );
    expect(asset, isNot(color));
    expect(cloud, isNot(local));
    expect(removed.copyWith(rowMeta: _roundTrip(removed.rowMeta)), removed);
  });

  test('reopening adopts the controller metadata for the action overlay',
      () async {
    final stored = _roundTrip(_row(cover: RowCoverPB()));
    final controller = _RefreshingRowController(_row(), stored);
    final bloc = RowDetailBloc(
      fieldController: _EmptyFields(),
      rowController: controller,
    );
    try {
      expect(rowCoverHeightFor(bloc.state.rowMeta), rowCoverHeight);
      await controller.initialized.future;
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.rowMeta, stored);
      expect(rowCoverHeightFor(bloc.state.rowMeta), 0);

      final chosen = _row(cover: defaultRowCover(_rowId));
      controller.adopt(chosen);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.rowMeta, chosen);
      expect(rowCoverHeightFor(bloc.state.rowMeta), rowCoverHeight);
    } finally {
      await bloc.close();
    }
    // A queued controller completion after the popup closes must be harmless.
    controller.adopt(stored);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final kind in ['generated', 'color', 'gradient']) {
      testWidgets('$mode: remove $kind, reopen, add and remove again',
          (tester) async {
        final store = _MemoryRows(
          _row(
            cover: switch (kind) {
              'color' => RowCoverPB(
                  data: '0xffb9a6d6',
                  coverType: CoverTypePB.ColorCover,
                ),
              'gradient' => defaultRowCover(_rowId),
              _ => null,
            },
          ),
        );
        var bloc = _banner(store);
        final scroll = ScrollController();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        var presses = 0;
        try {
          await tester.pumpWidget(
            _fixture(mode, bloc, scroll, () => presses++),
          );
          await tester.pumpAndSettle();
          expect(find.byType(RowCover), findsOneWidget);
          expect(
            tester.widget<RowCover>(find.byType(RowCover)).cover,
            effectiveRowCover(store.read()),
          );
          final top = tester.getTopLeft(find.byType(RowDetailScrollSurface)).dy;
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 262);
          await mouse.addPointer();
          await _removeCover(tester, mouse);
          _expectCoverless(tester, store);
          expect(store.removeCalls, 1);
          expect(tester.getSize(find.byType(RowBannerHeader)).height, 40);
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);
          await tester.tap(find.byKey(_actions));
          await tester.pumpAndSettle();
          expect(presses, 1);

          scroll.jumpTo(100);
          await tester.pump();
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);
          scroll.jumpTo(0);
          await tester.pumpAndSettle();

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(bloc.close);
          bloc = _banner(store);
          await tester.pumpWidget(
            _fixture(mode, bloc, scroll, () => presses++),
          );
          await tester.pumpAndSettle();
          _expectCoverless(tester, store);
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);

          await tester.tap(_addCover());
          await tester.pumpAndSettle();
          expect(find.byType(RowCover), findsOneWidget);
          expect(store.read().cover.coverType, CoverTypePB.AssetCover);
          expect(store.read().cover.data, isNotEmpty);
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 262);
          await _removeCover(tester, mouse);
          _expectCoverless(tester, store);
          expect(store.removeCalls, 2);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(bloc.close);
          scroll.dispose();
        }
      });
    }

    testWidgets('$mode: a coverless icon and Add Cover stay inside the header',
        (tester) async {
      final store = _MemoryRows(_row(cover: RowCoverPB(), icon: '📘'));
      final bloc = _banner(store);
      final scroll = ScrollController();
      try {
        await tester.pumpWidget(_fixture(mode, bloc, scroll, () {}));
        await tester.pumpAndSettle();
        _expectCoverless(tester, store);
        final header = tester.getRect(find.byType(RowBannerHeader));
        final icon = tester.getRect(find.byType(RowIcon));
        final add = tester.getRect(_addCover());
        expect(icon.top, greaterThanOrEqualTo(header.top));
        expect(icon.bottom, lessThanOrEqualTo(add.top));
        expect(add.bottom, lessThanOrEqualTo(header.bottom));
        expect(header.height, lessThan(rowCoverHeight));
        final context = tester.element(find.byType(RowBannerHeader));
        expect(PaperTheme.isEnabled(context), mode == 'paper');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(bloc.close);
        scroll.dispose();
      }
    });
  }

  testWidgets('pending and failed removal never hide the stored cover',
      (tester) async {
    final chosen = defaultRowCover(_rowId);
    final store = _MemoryRows(_row(cover: chosen));
    final gate = Completer<bool>();
    store.removalAllowed = gate.future;
    final bloc = _banner(store);
    final scroll = ScrollController();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(_fixture('paper', bloc, scroll, () {}));
      await tester.pumpAndSettle();
      await mouse.addPointer();
      await _removeCover(tester, mouse);
      expect(store.removeCalls, 1);
      expect(store.read().cover, chosen);
      expect(find.byType(RowCover), findsOneWidget);
      gate.complete(false);
      await tester.pumpAndSettle();
      expect(store.read().cover, chosen);
      expect(bloc.state.rowMeta.cover, chosen);
      expect(find.byType(RowCover), findsOneWidget);
      expect(_addCover(), findsNothing);

      store.removalAllowed = null;
      await _removeCover(tester, mouse);
      _expectCoverless(tester, store);
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete(false);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bloc.close);
      scroll.dispose();
    }
  });
}

RowMetaPB _row({RowCoverPB? cover, String icon = ''}) => RowMetaPB(
      id: _rowId,
      documentId: 'row-cover-test-document',
      icon: icon,
      cover: cover,
    );

RowMetaPB _roundTrip(RowMetaPB row) =>
    RowMetaPB.fromBuffer(row.writeToBuffer());

RowBannerBloc _banner(_MemoryRows store) {
  final bloc = RowBannerBloc(
    viewId: _viewId,
    fieldController: _EmptyFields(),
    rowMeta: store.read(),
    rowBackendService: store,
  );
  store.onMetaChanged =
      (row) => bloc.add(RowBannerEvent.didReceiveRowMeta(row));
  // Emit once before removal. Bloc permits an equal first emission, which
  // otherwise masks the absent-cover versus empty-cover equality regression.
  bloc.add(RowBannerEvent.didReceiveFieldUpdate(FieldPB(id: 'primary')));
  // Deliberately do not initialize native profile/field services in this test.
  return bloc;
}

Finder _addCover() =>
    find.text(LocaleKeys.document_plugins_cover_addCover.tr());

Future<void> _removeCover(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(tester.getCenter(find.byType(RowCover)));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DeleteCoverButton));
  await tester.pumpAndSettle();
}

void _expectCoverless(WidgetTester tester, _MemoryRows store) {
  expect(store.read().hasCover(), isTrue);
  expect(store.read().cover.data, isEmpty);
  expect(find.byType(RowCover), findsNothing);
  expect(find.byType(DesktopRowCover), findsNothing);
  expect(find.byType(AFImage), findsNothing);
  expect(_addCover().hitTestable(), findsOneWidget);
  expect(
    tester.widget<RowHeaderToolbar>(find.byType(RowHeaderToolbar)).hasCover,
    isFalse,
  );
}

Widget _fixture(
  String mode,
  RowBannerBloc bloc,
  ScrollController scroll,
  VoidCallback onAction,
) =>
    _app(
      mode,
      SizedBox(
        width: 720,
        height: 440,
        child: BlocBuilder<RowBannerBloc, RowBannerState>(
          bloc: bloc,
          builder: (context, state) => RowDetailScrollSurface(
            coverHeight: rowCoverHeightFor(state.rowMeta),
            actions: SizedBox(
              key: _actions,
              height: 24,
              width: 60,
              child: TextButton(onPressed: onAction, child: const Text('Open')),
            ),
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RowBannerHeader(
                    rowMeta: state.rowMeta,
                    onIconChanged: (icon) =>
                        bloc.add(RowBannerEvent.setIcon(icon ?? '')),
                    onCoverChanged: (cover) => bloc.add(
                      cover == null
                          ? const RowBannerEvent.removeCover()
                          : RowBannerEvent.setCover(cover),
                    ),
                  ),
                  const Text('Row title'),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      ),
    );

Widget _app(String mode, Widget child) => EasyLocalization(
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
          theme: DesktopAppearance()
              .getThemeData(
                mode == 'paper'
                    ? AppTheme.builtins.firstWhere(
                        (theme) => theme.themeName == BuiltInTheme.paper,
                      )
                    : AppTheme.fallback,
                mode == 'dark' ? Brightness.dark : Brightness.light,
                defaultFontFamily,
                builtInCodeFontFamily,
              )
              .copyWith(platform: TargetPlatform.windows),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

/// An in-memory wire store modeling RemoveCover's existing
/// Some(RowCover::default()) contract. No FFI, disk or live workspace writes.
class _MemoryRows extends RowBackendService {
  _MemoryRows(RowMetaPB row)
      : _bytes = row.writeToBuffer(),
        super(viewId: _viewId);

  List<int> _bytes;
  ValueChanged<RowMetaPB>? onMetaChanged;
  Future<bool>? removalAllowed;
  int removeCalls = 0;

  RowMetaPB read() => RowMetaPB.fromBuffer(_bytes);

  void _persist(RowMetaPB row) {
    _bytes = row.writeToBuffer();
    onMetaChanged?.call(read());
  }

  @override
  Future<FlowyResult<void, FlowyError>> removeCover(String rowId) async {
    expectSync(rowId, _rowId);
    removeCalls++;
    if (removalAllowed != null && !await removalAllowed!) {
      return FlowyResult.failure(
        FlowyError(code: ErrorCode.Internal, msg: 'test removal refused'),
      );
    }
    _persist(read()..cover = RowCoverPB());
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> updateMeta({
    required String rowId,
    String? iconURL,
    RowCoverPB? cover,
    bool? isDocumentEmpty,
  }) async {
    expectSync(rowId, _rowId);
    final row = read();
    if (cover != null) row.cover = cover;
    if (iconURL != null) row.icon = iconURL;
    if (isDocumentEmpty != null) row.isDocumentEmpty = isDocumentEmpty;
    _persist(row);
    return FlowyResult.success(null);
  }
}

class _EmptyFields extends Fake implements FieldController {
  @override
  List<FieldInfo> get fieldInfos => const [];

  @override
  void addListener({
    OnReceiveFields? onReceiveFields,
    OnReceiveUpdateFields? onFieldsChanged,
    OnReceiveFilters? onFilters,
    OnReceiveSorts? onSorts,
    bool Function()? listenWhen,
  }) {}
}

class _RefreshingRowController extends Fake implements RowController {
  _RefreshingRowController(this.rowMeta, this.refreshed);

  @override
  RowMetaPB rowMeta;
  final RowMetaPB refreshed;
  final initialized = Completer<void>();
  VoidCallback? _onMetaChanged;

  @override
  String get viewId => _viewId;

  @override
  String get rowId => rowMeta.id;

  @override
  List<CellContext> loadCells() => const [];

  @override
  void addListener({OnRowChanged? onRowChanged, VoidCallback? onMetaChanged}) {
    _onMetaChanged = onMetaChanged;
  }

  @override
  Future<void> initialize() async {
    await Future<void>.value();
    adopt(refreshed);
    initialized.complete();
  }

  void adopt(RowMetaPB row) {
    rowMeta = _roundTrip(row);
    _onMetaChanged?.call();
  }

  @override
  Future<void> dispose() async {}
}
