import 'dart:async';

import 'package:appflowy/ai/providers/ai_providers.dart';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check_settings.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_settings.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/language.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// Settings that are only known after reading them from disk, kept here so
/// the palette can show them without waiting every time it opens.
abstract final class PaletteSettingSources {
  /// The application's zoom, or null until it has been read.
  static final ValueNotifier<double?> zoom = ValueNotifier(null);

  /// How new pages get their cover, or null until it has been read.
  static final ValueNotifier<AutomaticViewCoverSettings?> covers =
      ValueNotifier(null);

  /// Everything the settings rows read that is not a bloc, so one listener
  /// can redraw them when any of it changes.
  static final Listenable changes = Listenable.merge([
    zoom,
    covers,
    SpellCheckSettings.instance,
    DefaultIconStyleStore.instance,
    PageVersionSettings.instance,
    EncryptionVault.instance,
    DartExtensionHost.instance,
    ExtensionStore.instance,
    CustomAIProviderStore.instance,
    ExtensionThemeRegistry.changes,
  ]);

  /// Reads again what may have changed while the palette was closed — the
  /// zoom follows Ctrl +/- too. Failures leave the last known value alone.
  static void refresh() {
    unawaited(_guard(_readZoom));
    unawaited(_guard(_readCovers));
    unawaited(_guard(SpellCheckSettings.instance.ensureLoaded));
    unawaited(_guard(PageVersionSettings.instance.ensureLoaded));
    unawaited(_guard(CustomAIProviderStore.instance.ensureLoaded));
    unawaited(_guard(DefaultIconStyleStore.instance.ensureLoaded));
  }

  static Future<void> _readZoom() async {
    if (!getIt.isRegistered<KeyValueStorage>()) return;
    zoom.value = await WindowSizeManager().getScaleFactor();
  }

  static Future<void> _readCovers() async {
    covers.value = await AutomaticViewCoverPreferences.load();
  }

  static Future<void> _guard(Future<void> Function() read) async {
    try {
      await read();
    } on Object {
      // A setting that cannot be read is simply not offered yet.
    }
  }
}

/// Every setting the palette can change in place, in the order they read
/// best.
///
/// Called while building, so the rows show what is true now: the blocs are
/// watched here, and the rest is redrawn through
/// [PaletteSettingSources.changes]. A cubit that is not provided — in a test,
/// say — simply leaves its settings out.
List<PaletteSetting> buildPaletteSettings(BuildContext context) {
  final appearanceCubit = context.watch<AppearanceSettingsCubit?>();
  final documentCubit = context.watch<DocumentAppearanceCubit?>();
  final notificationCubit = context.watch<NotificationSettingsCubit?>();
  final appearance = appearanceCubit?.state;
  final document = documentCubit?.state;

  return [
    if (appearanceCubit != null && appearance != null) ...[
      PaletteSetting(
        id: 'theme_mode',
        title: LocaleKeys.commandPalette_setting_themeMode.tr(),
        description: LocaleKeys.commandPalette_setting_themeModeHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.dark_mode_rounded,
        keywords: const ['dark mode', 'light mode', 'night', 'brightness'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: ThemeMode.system.name,
              label: LocaleKeys.settings_workspacePage_appearance_options_system
                  .tr(),
              icon: Icons.computer_rounded,
            ),
            PaletteSettingOption(
              id: ThemeMode.light.name,
              label: LocaleKeys.settings_workspacePage_appearance_options_light
                  .tr(),
              icon: Icons.wb_sunny_rounded,
            ),
            PaletteSettingOption(
              id: ThemeMode.dark.name,
              label: LocaleKeys.settings_workspacePage_appearance_options_dark
                  .tr(),
              icon: Icons.dark_mode_rounded,
            ),
          ],
          selectedId: appearance.themeMode.name,
          onSelected: (option) =>
              appearanceCubit.setThemeMode(ThemeMode.values.byName(option.id)),
        ),
      ),
      PaletteSetting(
        id: 'theme',
        title: LocaleKeys.commandPalette_setting_theme.tr(),
        description: LocaleKeys.commandPalette_setting_themeHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.palette_rounded,
        keywords: const ['colors', 'colours', 'skin', 'style'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            for (final theme in _themes(appearance.appTheme))
              PaletteSettingOption(
                id: theme.themeName,
                label: theme.themeName,
                icon: PaperTheme.isPaper(theme)
                    ? Icons.menu_book_rounded
                    : Icons.palette_outlined,
              ),
          ],
          selectedId: appearance.appTheme.themeName,
          onSelected: (option) => appearanceCubit.setTheme(option.id),
        ),
      ),
      PaletteSetting(
        id: 'paper_mode',
        title: LocaleKeys.commandPalette_setting_paperMode.tr(),
        description: LocaleKeys.commandPalette_setting_paperModeHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.menu_book_rounded,
        keywords: const ['paper', 'warm', 'sepia', 'reading', 'cream'],
        settingsPage: SettingsPage.workspace,
        control: PaletteToggle(
          value: PaperTheme.isPaper(appearance.appTheme),
          onChanged: (on) => appearanceCubit.setTheme(
            on ? BuiltInTheme.paper : BuiltInTheme.defaultTheme,
          ),
        ),
      ),
    ],
    if (UniversalPlatform.isDesktop)
      PaletteSetting(
        id: 'zoom',
        title: LocaleKeys.commandPalette_setting_zoom.tr(),
        description: LocaleKeys.commandPalette_setting_zoomHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.zoom_in_rounded,
        keywords: const ['scale', 'bigger', 'smaller', 'magnify', 'size'],
        control: PaletteStepper(
          value: PaletteSettingSources.zoom.value ?? 1,
          min: WindowSizeManager.minScaleFactor,
          max: WindowSizeManager.maxScaleFactor,
          step: 0.1,
          label: _percent,
          onChanged: (value) async {
            PaletteSettingSources.zoom.value = value;
            await scaleApp(value);
          },
        ),
      ),
    if (appearanceCubit != null && appearance != null) ...[
      PaletteSetting(
        id: 'text_size',
        title: LocaleKeys.commandPalette_setting_textSize.tr(),
        description: LocaleKeys.commandPalette_setting_textSizeHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.format_size_rounded,
        keywords: const ['font', 'scale', 'smaller', 'readability'],
        control: PaletteStepper(
          value: appearance.textScaleFactor,
          min: 0.7,
          max: 1,
          step: 0.05,
          label: _percent,
          onChanged: appearanceCubit.setTextScaleFactor,
        ),
      ),
    ],
    PaletteSetting(
      id: 'icon_style',
      title: LocaleKeys.commandPalette_setting_iconStyle.tr(),
      description: LocaleKeys.commandPalette_setting_iconStyleHint.tr(),
      section: PaletteSettingSection.appearance,
      icon: Icons.emoji_symbols_rounded,
      keywords: const ['icons', 'glyphs', 'colorful', 'outline'],
      settingsPage: SettingsPage.workspace,
      control: PaletteChoice(
        options: [
          PaletteSettingOption(
            id: DefaultIconStyle.vivid.name,
            label: LocaleKeys.commandPalette_setting_iconStyleVivid.tr(),
            icon: Icons.auto_awesome_rounded,
          ),
          PaletteSettingOption(
            id: DefaultIconStyle.monochrome.name,
            label: LocaleKeys.commandPalette_setting_iconStyleMonochrome.tr(),
            icon: Icons.circle_outlined,
          ),
        ],
        selectedId: DefaultIconStyleStore.instance.value.name,
        onSelected: (option) => DefaultIconStyleStore.instance
            .setStyle(DefaultIconStyle.values.byName(option.id)),
      ),
    ),
    if (appearanceCubit != null && appearance != null)
      PaletteSetting(
        id: 'kinetic_scrolling',
        title: LocaleKeys.settings_appearance_kineticScrolling_label.tr(),
        description: LocaleKeys.settings_appearance_kineticScrolling_hint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.swipe_up_alt_rounded,
        keywords: const ['scroll', 'smooth', 'momentum', 'inertia'],
        settingsPage: SettingsPage.workspace,
        control: PaletteToggle(
          value: appearance.enableKineticScrolling,
          onChanged: appearanceCubit.setKineticScrolling,
        ),
      ),
    if (PaletteSettingSources.covers.value case final covers?) ...[
      PaletteSetting(
        id: 'automatic_covers',
        title: LocaleKeys.settings_appearance_automaticCovers_label.tr(),
        description: LocaleKeys.settings_appearance_automaticCovers_hint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.landscape_rounded,
        keywords: const ['cover', 'banner', 'picture', 'image', 'new page'],
        settingsPage: SettingsPage.workspace,
        control: PaletteToggle(
          value: covers.enabled,
          onChanged: (on) => _saveCovers(covers.copyWith(enabled: on)),
        ),
      ),
      PaletteSetting(
        id: 'cover_set',
        title: LocaleKeys.settings_appearance_automaticCovers_setLabel.tr(),
        description: LocaleKeys.commandPalette_setting_coverSetHint.tr(),
        section: PaletteSettingSection.appearance,
        icon: Icons.collections_rounded,
        keywords: const ['cover', 'banner', 'picture', 'nature', 'abstract'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: ViewCoverSet.nature.id,
              label:
                  LocaleKeys.settings_appearance_automaticCovers_setNature.tr(),
              icon: Icons.landscape_rounded,
            ),
            PaletteSettingOption(
              id: ViewCoverSet.abstract.id,
              label: LocaleKeys.settings_appearance_automaticCovers_setAbstract
                  .tr(),
              icon: Icons.blur_on_rounded,
            ),
          ],
          selectedId: covers.set.id,
          onSelected: (option) => _saveCovers(
            covers.copyWith(set: ViewCoverSet.fromId(option.id)),
          ),
        ),
      ),
    ],
    PaletteSetting(
      id: 'spell_check',
      title: LocaleKeys.document_spellCheck_enable.tr(),
      description: LocaleKeys.document_spellCheck_enableHint.tr(),
      section: PaletteSettingSection.editor,
      icon: Icons.spellcheck_rounded,
      keywords: const ['spelling', 'typos', 'proofread', 'dictionary'],
      settingsPage: SettingsPage.editor,
      control: PaletteToggle(
        value: SpellCheckSettings.instance.spellingEnabled,
        onChanged: SpellCheckSettings.instance.setSpellingEnabled,
      ),
    ),
    PaletteSetting(
      id: 'grammar_check',
      title: LocaleKeys.document_spellCheck_enableGrammar.tr(),
      description: LocaleKeys.document_spellCheck_enableGrammarHint.tr(),
      section: PaletteSettingSection.editor,
      icon: Icons.rule_rounded,
      keywords: const ['grammar', 'proofread', 'style'],
      settingsPage: SettingsPage.editor,
      control: PaletteToggle(
        value: SpellCheckSettings.instance.grammarEnabled,
        onChanged: SpellCheckSettings.instance.setGrammarEnabled,
      ),
    ),
    if (documentCubit != null && document != null) ...[
      PaletteSetting(
        id: 'page_width',
        title: LocaleKeys.commandPalette_setting_pageWidth.tr(),
        description: LocaleKeys.commandPalette_setting_pageWidthHint.tr(),
        section: PaletteSettingSection.editor,
        icon: Icons.width_normal_rounded,
        keywords: const ['width', 'wide', 'full width', 'narrow', 'layout'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: DocumentWidthPreset.reading.name,
              label: LocaleKeys.commandPalette_setting_pageWidthReading.tr(),
              icon: Icons.width_normal_rounded,
            ),
            PaletteSettingOption(
              id: DocumentWidthPreset.wide.name,
              label: LocaleKeys.commandPalette_setting_pageWidthWide.tr(),
              icon: Icons.width_wide_rounded,
            ),
            PaletteSettingOption(
              id: DocumentWidthPreset.full.name,
              label: LocaleKeys.commandPalette_setting_pageWidthFull.tr(),
              icon: Icons.fullscreen_rounded,
            ),
          ],
          selectedId: DocumentWidthPreset.forWidth(document.width)?.name,
          onSelected: (option) => documentCubit.syncWidth(
            DocumentWidthPreset.values.byName(option.id).width,
          ),
        ),
      ),
      PaletteSetting(
        id: 'page_font_size',
        title: LocaleKeys.commandPalette_setting_fontSize.tr(),
        description: LocaleKeys.commandPalette_setting_fontSizeHint.tr(),
        section: PaletteSettingSection.editor,
        icon: Icons.text_fields_rounded,
        keywords: const ['font size', 'text', 'bigger', 'smaller'],
        control: PaletteStepper(
          value: document.fontSize,
          min: 10,
          max: 24,
          step: 1,
          label: (value) => '${value.round()} px',
          onChanged: documentCubit.syncFontSize,
        ),
      ),
    ],
    if (appearanceCubit != null && appearance != null) ...[
      PaletteSetting(
        id: 'text_direction',
        title: LocaleKeys.commandPalette_setting_textDirection.tr(),
        description: LocaleKeys.commandPalette_setting_textDirectionHint.tr(),
        section: PaletteSettingSection.editor,
        icon: Icons.format_align_left_rounded,
        keywords: const ['rtl', 'ltr', 'right to left', 'arabic', 'hebrew'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: AppFlowyTextDirection.ltr.name,
              label: LocaleKeys.settings_workspacePage_textDirection_leftToRight
                  .tr(),
              icon: Icons.format_align_left_rounded,
            ),
            PaletteSettingOption(
              id: AppFlowyTextDirection.rtl.name,
              label: LocaleKeys.settings_workspacePage_textDirection_rightToLeft
                  .tr(),
              icon: Icons.format_align_right_rounded,
            ),
            PaletteSettingOption(
              id: AppFlowyTextDirection.auto.name,
              label: LocaleKeys.settings_workspacePage_textDirection_auto.tr(),
              icon: Icons.swap_horiz_rounded,
            ),
          ],
          selectedId: appearance.textDirection.name,
          onSelected: (option) async {
            final direction = AppFlowyTextDirection.values.byName(option.id);
            appearanceCubit.setTextDirection(direction);
            await documentCubit?.syncDefaultTextDirection(direction.name);
          },
        ),
      ),
      PaletteSetting(
        id: 'rtl_toolbar',
        title:
            LocaleKeys.settings_workspacePage_textDirection_enableRTLItems.tr(),
        description: LocaleKeys.commandPalette_setting_rtlToolbarHint.tr(),
        section: PaletteSettingSection.editor,
        icon: Icons.format_align_right_rounded,
        keywords: const ['rtl', 'toolbar', 'right to left'],
        settingsPage: SettingsPage.workspace,
        control: PaletteToggle(
          value: appearance.enableRtlToolbarItems,
          onChanged: appearanceCubit.setEnableRTLToolbarItems,
        ),
      ),
    ],
    PaletteSetting(
      id: 'page_versions',
      title: LocaleKeys.commandPalette_setting_pageVersions.tr(),
      description: LocaleKeys.commandPalette_setting_pageVersionsHint.tr(),
      section: PaletteSettingSection.editor,
      icon: Icons.history_rounded,
      keywords: const ['history', 'snapshots', 'versions', 'backup', 'undo'],
      settingsPage: SettingsPage.pageVersions,
      control: PaletteToggle(
        value: PageVersionSettings.instance.policy.captureAutomatically,
        onChanged: (on) => PageVersionSettings.instance.update(
          PageVersionSettings.instance.policy
              .copyWith(captureAutomatically: on),
        ),
      ),
    ),
    if (appearanceCubit != null && appearance != null) ...[
      if (EasyLocalization.of(context)?.supportedLocales case final locales?)
        PaletteSetting(
          id: 'language',
          title: LocaleKeys.commandPalette_setting_language.tr(),
          description: LocaleKeys.commandPalette_setting_languageHint.tr(),
          section: PaletteSettingSection.language,
          icon: Icons.translate_rounded,
          keywords: const ['locale', 'translation', 'english'],
          settingsPage: SettingsPage.workspace,
          control: PaletteChoice(
            options: [
              for (final locale in locales)
                PaletteSettingOption(
                  id: locale.toLanguageTag(),
                  label: languageFromLocale(locale),
                  keywords: [locale.languageCode, locale.toLanguageTag()],
                ),
            ],
            selectedId: appearance.locale.toLanguageTag(),
            onSelected: (option) {
              final locale = locales.firstWhere(
                (locale) => locale.toLanguageTag() == option.id,
              );
              if (context.mounted) {
                appearanceCubit.setLocale(context, locale);
              }
            },
          ),
        ),
      PaletteSetting(
        id: 'layout_direction',
        title: LocaleKeys.commandPalette_setting_layoutDirection.tr(),
        description: LocaleKeys.commandPalette_setting_layoutDirectionHint.tr(),
        section: PaletteSettingSection.language,
        icon: Icons.view_sidebar_rounded,
        keywords: const ['rtl', 'ltr', 'mirror', 'sidebar side'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: LayoutDirection.ltrLayout.name,
              label: LocaleKeys
                  .settings_workspacePage_layoutDirection_leftToRight
                  .tr(),
              icon: Icons.align_horizontal_left_rounded,
            ),
            PaletteSettingOption(
              id: LayoutDirection.rtlLayout.name,
              label: LocaleKeys
                  .settings_workspacePage_layoutDirection_rightToLeft
                  .tr(),
              icon: Icons.align_horizontal_right_rounded,
            ),
          ],
          selectedId: appearance.layoutDirection.name,
          onSelected: (option) => appearanceCubit
              .setLayoutDirection(LayoutDirection.values.byName(option.id)),
        ),
      ),
      PaletteSetting(
        id: 'date_format',
        title: LocaleKeys.commandPalette_setting_dateFormat.tr(),
        description: LocaleKeys.commandPalette_setting_dateFormatHint.tr(),
        section: PaletteSettingSection.language,
        icon: Icons.event_rounded,
        keywords: const ['date', 'calendar', 'format', 'region'],
        settingsPage: SettingsPage.workspace,
        control: PaletteChoice(
          options: [
            for (final format in UserDateFormatPB.values)
              PaletteSettingOption(
                id: format.name,
                label: _dateFormatLabel(format),
              ),
          ],
          selectedId: appearance.dateFormat.name,
          onSelected: (option) => appearanceCubit.setDateFormat(
            UserDateFormatPB.values
                .firstWhere((format) => format.name == option.id),
          ),
        ),
      ),
      PaletteSetting(
        id: 'time_format',
        title: LocaleKeys.settings_workspacePage_dateTime_24HourTime.tr(),
        description: LocaleKeys.commandPalette_setting_timeFormatHint.tr(),
        section: PaletteSettingSection.language,
        icon: Icons.schedule_rounded,
        keywords: const ['clock', 'time', '24 hour', 'am pm'],
        settingsPage: SettingsPage.workspace,
        control: PaletteToggle(
          value: appearance.timeFormat == UserTimeFormatPB.TwentyFourHour,
          onChanged: (on) => appearanceCubit.setTimeFormat(
            on ? UserTimeFormatPB.TwentyFourHour : UserTimeFormatPB.TwelveHour,
          ),
        ),
      ),
    ],
    _aiModelSetting(),
    if (notificationCubit != null)
      PaletteSetting(
        id: 'notifications',
        title: LocaleKeys.settings_notifications_enableNotifications_label.tr(),
        description:
            LocaleKeys.settings_notifications_enableNotifications_hint.tr(),
        section: PaletteSettingSection.notifications,
        icon: Icons.notifications_rounded,
        keywords: const ['alerts', 'reminders', 'notify', 'mute'],
        settingsPage: SettingsPage.notifications,
        control: PaletteToggle(
          value: notificationCubit.state.isNotificationsEnabled,
          onChanged: (on) async {
            if (on != notificationCubit.state.isNotificationsEnabled) {
              await notificationCubit.toggleNotificationsEnabled();
            }
          },
        ),
      ),
    if (EncryptionVault.instance.isConfigured &&
        !EncryptionVault.instance.isLocked)
      PaletteSetting(
        id: 'lock_encrypted',
        title: LocaleKeys.commandPalette_setting_lockEncrypted.tr(),
        description: LocaleKeys.commandPalette_setting_lockEncryptedHint.tr(),
        section: PaletteSettingSection.privacy,
        icon: Icons.lock_rounded,
        keywords: const ['encryption', 'lock', 'private', 'passphrase'],
        settingsPage: SettingsPage.encryption,
        control: PaletteAction(
          label: LocaleKeys.commandPalette_setting_lockNow.tr(),
          run: EncryptionVault.instance.lock,
        ),
      ),
    if (ExtensionThemeRegistry.all().isNotEmpty)
      PaletteSetting(
        id: 'extension_theme',
        title: LocaleKeys.commandPalette_setting_extensionTheme.tr(),
        description: LocaleKeys.commandPalette_setting_extensionThemeHint.tr(),
        section: PaletteSettingSection.extensions,
        icon: Icons.brush_rounded,
        keywords: const ['theme', 'extension', 'colors'],
        settingsPage: SettingsPage.extensions,
        control: PaletteChoice(
          options: [
            PaletteSettingOption(
              id: '',
              label: LocaleKeys.commandPalette_setting_none.tr(),
            ),
            for (final theme in ExtensionThemeRegistry.all())
              PaletteSettingOption(
                id: ExtensionThemeRegistry.keyOf(theme),
                label: theme.name,
                icon: Icons.brush_rounded,
              ),
          ],
          selectedId: ExtensionThemeRegistry.selected.value,
          onSelected: (option) =>
              DartExtensionHost.instance.selectTheme(option.id),
        ),
      ),
  ];
}

/// Every extension, as a switch. Both the compiled-in kind and the kind read
/// from the extensions folder.
List<PaletteSetting> buildPaletteExtensionSettings() {
  final host = DartExtensionHost.instance;
  final store = ExtensionStore.instance;
  return [
    for (final extension in host.extensions)
      PaletteSetting(
        id: 'extension_${extension.info.id}',
        title: extension.info.name,
        description: extension.info.description.isEmpty
            ? LocaleKeys.commandPalette_setting_extensionVersion
                .tr(args: [extension.info.version])
            : extension.info.description,
        section: PaletteSettingSection.extensions,
        icon: Icons.extension_rounded,
        keywords: ['extension', 'plugin', 'add-on', extension.info.id],
        settingsPage: SettingsPage.extensions,
        control: PaletteToggle(
          value: host.isEnabled(extension.info.id),
          onChanged: (on) => host.setEnabled(extension.info.id, on),
        ),
      ),
    for (final extension in store.extensions)
      PaletteSetting(
        id: 'extension_folder_${extension.id}',
        title: extension.manifest.name.isEmpty
            ? extension.id
            : extension.manifest.name,
        description: extension.manifest.description.isEmpty
            ? LocaleKeys.commandPalette_setting_extensionVersion
                .tr(args: [extension.manifest.version])
            : extension.manifest.description,
        section: PaletteSettingSection.extensions,
        icon: Icons.extension_outlined,
        keywords: ['extension', 'plugin', 'add-on', extension.id],
        settingsPage: SettingsPage.extensions,
        control: PaletteToggle(
          value: store.isEnabled(extension.id),
          onChanged: (on) => store.setEnabled(extension.id, on),
        ),
      ),
  ];
}

/// The heading a section of settings is listed under.
String paletteSettingSectionLabel(PaletteSettingSection section) =>
    switch (section) {
      PaletteSettingSection.appearance =>
        LocaleKeys.commandPalette_settingSection_appearance.tr(),
      PaletteSettingSection.editor =>
        LocaleKeys.commandPalette_settingSection_editor.tr(),
      PaletteSettingSection.language =>
        LocaleKeys.commandPalette_settingSection_language.tr(),
      PaletteSettingSection.ai =>
        LocaleKeys.commandPalette_settingSection_ai.tr(),
      PaletteSettingSection.notifications =>
        LocaleKeys.commandPalette_settingSection_notifications.tr(),
      PaletteSettingSection.privacy =>
        LocaleKeys.commandPalette_settingSection_privacy.tr(),
      PaletteSettingSection.extensions =>
        LocaleKeys.commandPalette_settingSection_extensions.tr(),
    };

/// How a setting's current value reads, for a row too narrow to show its
/// control, and for screen readers.
String paletteSettingValueLabel(PaletteSetting setting) =>
    switch (setting.control) {
      PaletteToggle(:final value) => value
          ? LocaleKeys.commandPalette_setting_on.tr()
          : LocaleKeys.commandPalette_setting_off.tr(),
      final PaletteChoice choice => choice.selected?.label ?? '',
      PaletteStepper(:final value, :final label) => label(value),
      PaletteAction(:final label) => label,
    };

PaletteSetting _aiModelSetting() {
  final store = CustomAIProviderStore.instance;
  final custom = store.models;
  return PaletteSetting(
    id: 'ai_model',
    title: LocaleKeys.commandPalette_setting_aiModel.tr(),
    description: LocaleKeys.commandPalette_setting_aiModelHint.tr(),
    section: PaletteSettingSection.ai,
    icon: Icons.auto_awesome_rounded,
    keywords: const ['model', 'provider', 'llm', 'gpt', 'assistant', 'ai'],
    settingsPage: SettingsPage.ai,
    control: PaletteChoice(
      options: [
        PaletteSettingOption(
          id: '',
          label: LocaleKeys.commandPalette_ai_appflowyModel.tr(),
          icon: Icons.auto_awesome_rounded,
        ),
        for (final model in custom)
          PaletteSettingOption(
            id: model.name,
            label: CustomAIModelName.decode(model.name)?.model ?? model.name,
            description: model.desc,
            icon: model.isLocal ? Icons.computer_rounded : Icons.cloud_rounded,
            keywords: [model.desc],
          ),
      ],
      selectedId:
          store.activeSelection == null ? '' : store.selectedModelName ?? '',
      onSelected: (option) =>
          store.select(option.id.isEmpty ? null : option.id),
    ),
  );
}

/// The built-in themes, plus the one in use when it came from a plugin, so
/// the current choice is always on the list.
List<AppTheme> _themes(AppTheme current) {
  final themes = AppTheme.builtins.toList();
  if (!themes.any((theme) => theme.themeName == current.themeName)) {
    themes.add(current);
  }
  return themes;
}

String _percent(double value) => '${(value * 100).round()}%';

String _dateFormatLabel(UserDateFormatPB format) => switch (format) {
      UserDateFormatPB.Locally =>
        LocaleKeys.settings_workspacePage_dateTime_dateFormat_local.tr(),
      UserDateFormatPB.US =>
        LocaleKeys.settings_workspacePage_dateTime_dateFormat_us.tr(),
      UserDateFormatPB.ISO =>
        LocaleKeys.settings_workspacePage_dateTime_dateFormat_iso.tr(),
      UserDateFormatPB.Friendly =>
        LocaleKeys.settings_workspacePage_dateTime_dateFormat_friendly.tr(),
      UserDateFormatPB.DayMonthYear =>
        LocaleKeys.settings_workspacePage_dateTime_dateFormat_dmy.tr(),
      _ => format.name,
    };

Future<void> _saveCovers(AutomaticViewCoverSettings settings) async {
  PaletteSettingSources.covers.value = settings;
  await AutomaticViewCoverPreferences.save(settings);
}
