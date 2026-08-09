import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Settings ▸ Editor: whether writing is checked, and the words this person
/// has taught AppFlowy.
class SettingsEditorView extends StatefulWidget {
  const SettingsEditorView({super.key});

  @override
  State<SettingsEditorView> createState() => _SettingsEditorViewState();
}

class _SettingsEditorViewState extends State<SettingsEditorView> {
  final TextEditingController _newWord = TextEditingController();
  final TextEditingController _search = TextEditingController();

  SpellCheckSettings get _settings => SpellCheckSettings.instance;
  DictionaryService get _dictionary => DictionaryService.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChanged);
    _dictionary.addListener(_onChanged);
    _search.addListener(_onChanged);
    unawaited(_settings.ensureLoaded());
    unawaited(_dictionary.ensureLoaded());
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
    _dictionary.removeListener(_onChanged);
    _search.dispose();
    _newWord.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(
      title: LocaleKeys.settings_editorPage_menuLabel.tr(),
      description: LocaleKeys.settings_editorPage_description.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.document_spellCheck_title.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.document_spellCheck_enable.tr(),
              description: LocaleKeys.document_spellCheck_enableHint.tr(),
              value: _settings.spellingEnabled,
              onChanged: (value) =>
                  unawaited(_settings.setSpellingEnabled(value)),
            ),
            const SizedBox(height: 6),
            _Toggle(
              label: LocaleKeys.document_spellCheck_enableGrammar.tr(),
              description:
                  LocaleKeys.document_spellCheck_enableGrammarHint.tr(),
              value: _settings.grammarEnabled,
              onChanged: (value) =>
                  unawaited(_settings.setGrammarEnabled(value)),
            ),
            const SizedBox(height: 10),
            _Note(
              text: LocaleKeys.document_spellCheck_privacyNote.tr(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsCategory(
          title: LocaleKeys.document_spellCheck_dictionaryTitle.tr(),
          description: LocaleKeys.document_spellCheck_dictionaryHint.tr(),
          children: [_buildDictionary(context)],
        ),
      ],
    );
  }

  Widget _buildDictionary(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final query = _search.text.trim().toLowerCase();
    final words = _dictionary.userWords
        .where((word) => query.isEmpty || word.contains(query))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newWord,
                onSubmitted: _add,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText:
                      LocaleKeys.document_spellCheck_dictionaryAddHint.tr(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => _add(_newWord.text),
              child: Text(LocaleKeys.button_add.tr()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            border: const OutlineInputBorder(),
            hintText: LocaleKeys.document_spellCheck_dictionarySearchHint.tr(),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: premium.mutedSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: premium.border.withValues(alpha: 0.6)),
          ),
          child: words.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  child: Text(
                    query.isEmpty
                        ? LocaleKeys.document_spellCheck_dictionaryEmpty.tr()
                        : LocaleKeys.document_spellCheck_dictionaryNoMatch.tr(),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: premium.textMuted,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: words.length,
                  itemBuilder: (_, index) => _WordRow(
                    word: words[index],
                    onRemove: () =>
                        unawaited(_dictionary.removeWord(words[index])),
                  ),
                ),
        ),
      ],
    );
  }

  void _add(String value) {
    final word = value.trim();
    if (word.isEmpty) {
      return;
    }
    unawaited(_dictionary.addWord(word));
    _newWord.clear();
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: premium.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: premium.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: premium.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: premium.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({required this.word, required this.onRemove});

  final String word;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              word,
              style: TextStyle(fontSize: 13, color: premium.textPrimary),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: LocaleKeys.button_remove.tr(),
            icon: Icon(Icons.close_rounded, color: premium.textMuted),
          ),
        ],
      ),
    );
  }
}
