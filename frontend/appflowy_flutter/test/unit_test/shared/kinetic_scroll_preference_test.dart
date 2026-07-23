import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (getIt.isRegistered<KeyValueStorage>()) {
      await getIt.unregister<KeyValueStorage>();
    }
    getIt.registerSingleton<KeyValueStorage>(DartKeyValue());
  });

  tearDown(() async {
    if (getIt.isRegistered<KeyValueStorage>()) {
      await getIt.unregister<KeyValueStorage>();
    }
  });

  test('kinetic scrolling preference persists and is restored', () async {
    final appearance = _appearanceSettings();
    final dateTime = DateTimeSettingsPB();
    final first = AppearanceSettingsCubit(
      appearance,
      dateTime,
      AppTheme.fallback,
    );
    await Future<void>.delayed(Duration.zero);

    await first.setKineticScrolling(false);
    expect(first.state.enableKineticScrolling, isFalse);
    expect(
      await getIt<KeyValueStorage>().get(KVKeys.enableKineticScrolling),
      'false',
    );
    await first.close();

    final restored = AppearanceSettingsCubit(
      appearance,
      dateTime,
      AppTheme.fallback,
    );
    await Future<void>.delayed(Duration.zero);

    expect(restored.state.enableKineticScrolling, isFalse);
    await restored.close();
  });

  test('kinetic scrolling defaults to enabled', () async {
    final cubit = AppearanceSettingsCubit(
      _appearanceSettings(),
      DateTimeSettingsPB(),
      AppTheme.fallback,
    );
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.enableKineticScrolling, isTrue);
    await cubit.close();
  });
}

AppearanceSettingsPB _appearanceSettings() => AppearanceSettingsPB(
      locale: LocaleSettingsPB(
        languageCode: 'en',
        countryCode: 'US',
      ),
    );
