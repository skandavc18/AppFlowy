import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  group('DocumentAppearanceCubit', () {
    late SharedPreferences preferences;
    late DocumentAppearanceCubit cubit;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      preferences = await SharedPreferences.getInstance();
      cubit = DocumentAppearanceCubit();
    });

    tearDown(() async {
      await preferences.clear();
      await cubit.close();
    });

    test('Initial state', () {
      expect(cubit.state.fontSize, 16.0);
      expect(cubit.state.fontFamily, defaultFontFamily);
    });

    test('Fetch document appearance from SharedPreferences', () async {
      await preferences.setDouble(KVKeys.kDocumentAppearanceFontSize, 18.0);
      await preferences.setString(
        KVKeys.kDocumentAppearanceFontFamily,
        'Arial',
      );

      await cubit.fetch();

      expect(cubit.state.fontSize, 18.0);
      expect(cubit.state.fontFamily, 'Arial');
    });

    test('Sync font size to SharedPreferences', () async {
      await cubit.syncFontSize(20.0);

      final fontSize =
          preferences.getDouble(KVKeys.kDocumentAppearanceFontSize);
      expect(fontSize, 20.0);
      expect(cubit.state.fontSize, 20.0);
    });

    test('Sync font family to SharedPreferences', () async {
      await cubit.syncFontFamily('Helvetica');

      final fontFamily =
          preferences.getString(KVKeys.kDocumentAppearanceFontFamily);
      expect(fontFamily, 'Helvetica');
      expect(cubit.state.fontFamily, 'Helvetica');
    });

    test('existing custom widths are kept when appearance is loaded', () async {
      await preferences.setDouble(KVKeys.kDocumentAppearanceWidth, 1111);
      await cubit.fetch();
      expect(cubit.state.width, 1111);
      expect(DocumentWidthPreset.forWidth(cubit.state.width), isNull);
    });

    test('each width preset uses the existing persisted width setting',
        () async {
      for (final preset in DocumentWidthPreset.values) {
        await cubit.syncWidth(preset.width);
        expect(cubit.state.width, preset.width);
        expect(
          preferences.getDouble(KVKeys.kDocumentAppearanceWidth),
          preset.width,
        );
        expect(DocumentWidthPreset.forWidth(cubit.state.width), preset);
      }
      await cubit.syncWidth(null);
      expect(cubit.state.width, DocumentWidthPreset.full.width);
    });
  });
}
