import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Where the key that unlocks Google's own maps is entered.
class SettingsMapsView extends StatefulWidget {
  const SettingsMapsView({super.key});

  @override
  State<SettingsMapsView> createState() => _SettingsMapsViewState();
}

class _SettingsMapsViewState extends State<SettingsMapsView> {
  final TextEditingController _controller = TextEditingController();
  String _note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await MapsSettings.instance.ensureLoaded();
    if (mounted) {
      _controller.text = MapsSettings.instance.apiKey;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    await MapsSettings.instance.setApiKey(value);
    if (mounted) {
      setState(() {
        _note = value.isEmpty
            ? LocaleKeys.map_apiKeyCleared.tr()
            : LocaleKeys.map_apiKeySaved.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsBody(
      title: LocaleKeys.map_settingsTitle.tr(),
      description: LocaleKeys.map_settingsSubtitle.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.map_apiKeyLabel.tr(),
          children: [
            TextField(
              controller: _controller,
              obscureText: true,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: LocaleKeys.map_apiKeyHint.tr(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _save,
                  child: Text(LocaleKeys.button_save.tr()),
                ),
                const SizedBox(width: 12),
                if (_note.isNotEmpty)
                  Text(
                    _note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
