import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/appearance/rtl_setting.dart';
import 'package:appflowy/mobile/presentation/setting/appearance/text_scale_setting.dart';
import 'package:appflowy/mobile/presentation/setting/appearance/theme_setting.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../setting.dart';

class AppearanceSettingGroup extends StatelessWidget {
  const AppearanceSettingGroup({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MobileSettingGroup(
      groupTitle: LocaleKeys.settings_menu_appearance.tr(),
      settingItemList: const [
        ThemeSetting(),
        FontSetting(),
        DisplaySizeSetting(),
        RTLSetting(),
        _KineticScrollingSetting(),
      ],
    );
  }
}

class _KineticScrollingSetting extends StatelessWidget {
  const _KineticScrollingSetting();

  @override
  Widget build(BuildContext context) {
    final enabled =
        context.watch<AppearanceSettingsCubit>().state.enableKineticScrolling;
    return MobileSettingItem(
      name: LocaleKeys.settings_appearance_kineticScrolling_label.tr(),
      subtitle: Text(
        LocaleKeys.settings_appearance_kineticScrolling_hint.tr(),
      ),
      trailing: Toggle(
        value: enabled,
        onChanged: context.read<AppearanceSettingsCubit>().setKineticScrolling,
      ),
    );
  }
}
