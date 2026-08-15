import 'dart:async';

import 'package:appflowy/ai/providers/ai_providers.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings ▸ AI ▸ "Your AI providers".
///
/// One place to point AppFlowy's chat at OpenAI, Claude, Gemini, GitHub or a
/// model running on this machine. Everything configured here is answered by
/// AppFlowy itself over HTTP — nothing is sent to AppFlowy Cloud.
class CustomAIProvidersSetting extends StatefulWidget {
  const CustomAIProvidersSetting({super.key});

  @override
  State<CustomAIProvidersSetting> createState() =>
      _CustomAIProvidersSettingState();
}

class _CustomAIProvidersSettingState extends State<CustomAIProvidersSetting> {
  final CustomAIProviderStore _store = CustomAIProviderStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    unawaited(
      _store.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _edit([CustomAIProvider? provider]) async {
    await showAIProviderDialog(context, provider: provider);
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final providers = _store.providers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.aiProviders_title.tr(),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontVariations: const [FontVariation.weight(600)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    LocaleKeys.aiProviders_description.tr(),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                      height: 16 / 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _PillButton(
              label: LocaleKeys.aiProviders_add.tr(),
              icon: Icons.add_rounded,
              primary: true,
              palette: palette,
              onTap: _edit,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (providers.isEmpty)
          _EmptyProviders(palette: palette, onAdd: _edit)
        else
          ...providers.map(
            (provider) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ProviderCard(
                provider: provider,
                palette: palette,
                onEdit: () => _edit(provider),
                onRemove: () => _confirmRemove(provider),
              ),
            ),
          ),
        if (!_store.keysPersist && providers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            LocaleKeys.aiProviders_sessionOnlyKeys.tr(),
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(CustomAIProvider provider) async {
    final removed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(LocaleKeys.aiProviders_removeTitle.tr()),
        content: Text(
          LocaleKeys.aiProviders_removeBody.tr(args: [provider.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.button_delete.tr()),
          ),
        ],
      ),
    );
    if (removed == true) {
      await _store.remove(provider.id);
    }
  }
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders({required this.palette, required this.onAdd});

  final FolderExplorerPalette palette;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.hub_rounded, size: 18, color: palette.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                LocaleKeys.aiProviders_empty.tr(),
                style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({
    required this.provider,
    required this.palette,
    required this.onEdit,
    required this.onRemove,
  });

  final CustomAIProvider provider;
  final FolderExplorerPalette palette;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readKeyState());
  }

  @override
  void didUpdateWidget(_ProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.id != widget.provider.id) {
      unawaited(_readKeyState());
    }
  }

  Future<void> _readKeyState() async {
    final has = await CustomAIProviderStore.instance.hasApiKey(
      widget.provider.id,
    );
    if (mounted) {
      setState(() => _hasKey = has);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final provider = widget.provider;
    final needsKey = provider.kind.needsApiKey && !_hasKey;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                provider.kind.icon,
                size: 16,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontVariations: const [FontVariation.weight(580)],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(provider, needsKey),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: needsKey ? palette.danger : palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: LocaleKeys.aiProviders_edit.tr(),
              palette: palette,
              onTap: widget.onEdit,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: LocaleKeys.button_delete.tr(),
              iconSize: 16,
              splashRadius: 16,
              onPressed: widget.onRemove,
              icon: Icon(Icons.delete_outline_rounded, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(CustomAIProvider provider, bool needsKey) {
    if (needsKey) {
      return LocaleKeys.aiProviders_needsKey.tr();
    }
    final models = provider.models.isEmpty
        ? LocaleKeys.aiProviders_noModels.tr()
        : LocaleKeys.aiProviders_modelCount
            .tr(args: ['${provider.models.length}']);
    return '${provider.normalizedBaseUrl} · $models';
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.palette,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final FolderExplorerPalette palette;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final foreground = primary ? palette.accent : palette.textSecondary;
    return Material(
      color: primary
          ? palette.accent.withValues(alpha: enabled ? 0.12 : 0.06)
          : palette.hover,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: foreground,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 14, color: foreground),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? foreground : palette.textMuted,
                  fontSize: 12.5,
                  fontVariations: const [FontVariation.weight(560)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds or edits one provider.
Future<void> showAIProviderDialog(
  BuildContext context, {
  CustomAIProvider? provider,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AIProviderDialog(provider: provider),
  );
}

class _AIProviderDialog extends StatefulWidget {
  const _AIProviderDialog({this.provider});

  final CustomAIProvider? provider;

  @override
  State<_AIProviderDialog> createState() => _AIProviderDialogState();
}

class _AIProviderDialogState extends State<_AIProviderDialog> {
  late AIProviderKind _kind =
      widget.provider?.kind ?? AIProviderKind.openAICompatible;
  late final TextEditingController _name = TextEditingController(
    text: widget.provider?.name ?? _kind.label,
  );
  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.provider?.baseUrl ?? _kind.defaultBaseUrl,
  );
  late final TextEditingController _apiKey = TextEditingController();
  late final TextEditingController _models = TextEditingController(
    text: (widget.provider?.models ?? _kind.suggestedModels).join(', '),
  );

  bool _keyStored = false;
  bool _busy = false;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.provider;
    if (existing != null) {
      unawaited(
        CustomAIProviderStore.instance.hasApiKey(existing.id).then((has) {
          if (mounted) setState(() => _keyStored = has);
        }),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _models.dispose();
    super.dispose();
  }

  void _pickKind(AIProviderKind kind) {
    setState(() {
      final previous = _kind;
      _kind = kind;
      if (_name.text.trim().isEmpty || _name.text.trim() == previous.label) {
        _name.text = kind.label;
      }
      if (_baseUrl.text.trim().isEmpty ||
          _baseUrl.text.trim() == previous.defaultBaseUrl) {
        _baseUrl.text = kind.defaultBaseUrl;
      }
      if (_models.text.trim().isEmpty ||
          _models.text.trim() == previous.suggestedModels.join(', ')) {
        _models.text = kind.suggestedModels.join(', ');
      }
    });
  }

  CustomAIProvider _draft() => CustomAIProvider(
        id: widget.provider?.id ?? '',
        kind: _kind,
        name: _name.text.trim().isEmpty ? _kind.label : _name.text.trim(),
        baseUrl: _baseUrl.text.trim().isEmpty
            ? _kind.defaultBaseUrl
            : _baseUrl.text.trim(),
        models: _models.text
            .split(RegExp(r'[,\n]'))
            .map((model) => model.trim())
            .where((model) => model.isNotEmpty)
            .toList(),
      );

  Future<String?> _keyForRequest() async {
    if (_apiKey.text.isNotEmpty) {
      return _apiKey.text;
    }
    final existing = widget.provider;
    if (existing == null) {
      return null;
    }
    return CustomAIProviderStore.instance.apiKeyFor(existing.id);
  }

  Future<void> _fetchModels() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final client = AIProviderClient(
        provider: _draft(),
        apiKey: await _keyForRequest(),
      );
      final models = await client.listModels();
      if (!mounted) return;
      setState(() {
        if (models.isEmpty) {
          _notice = LocaleKeys.aiProviders_noModelsFound.tr();
          _noticeIsError = true;
        } else {
          _models.text = models.join(', ');
          _notice = LocaleKeys.aiProviders_modelsFound
              .tr(args: ['${models.length}']);
          _noticeIsError = false;
        }
      });
    } on AIProviderException catch (error) {
      if (mounted) {
        setState(() {
          _notice = error.message;
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft.models.isEmpty) {
      setState(() {
        _notice = LocaleKeys.aiProviders_needsModel.tr();
        _noticeIsError = true;
      });
      return;
    }

    await CustomAIProviderStore.instance.upsert(
      draft,
      apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);

    return Dialog(
      backgroundColor: palette.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.provider == null
                      ? LocaleKeys.aiProviders_addTitle.tr()
                      : LocaleKeys.aiProviders_editTitle.tr(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontVariations: const [FontVariation.weight(640)],
                  ),
                ),
                const SizedBox(height: 14),
                _KindPicker(
                  kind: _kind,
                  palette: palette,
                  onChanged: _pickKind,
                ),
                const SizedBox(height: 12),
                ProviderTextField(
                  label: LocaleKeys.aiProviders_nameLabel.tr(),
                  controller: _name,
                  palette: palette,
                ),
                const SizedBox(height: 10),
                ProviderTextField(
                  label: _kind.usesTargetUri
                      ? LocaleKeys.aiProviders_targetUriLabel.tr()
                      : LocaleKeys.aiProviders_baseUrlLabel.tr(),
                  controller: _baseUrl,
                  palette: palette,
                  hint: _kind.defaultBaseUrl,
                ),
                if (_kind.usesTargetUri) ...[
                  const SizedBox(height: 5),
                  Text(
                    LocaleKeys.aiProviders_targetUriHelp.tr(),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ],
                const SizedBox(height: 10),
                ProviderTextField(
                  label: _kind.needsApiKey
                      ? LocaleKeys.aiProviders_apiKeyLabel.tr()
                      : LocaleKeys.aiProviders_apiKeyOptionalLabel.tr(),
                  controller: _apiKey,
                  palette: palette,
                  obscure: true,
                  showPasteButton: true,
                  hint: _keyStored
                      ? LocaleKeys.aiProviders_apiKeyStored.tr()
                      : '',
                ),
                if (_kind.credentialsUrl.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _LinkText(
                    label: LocaleKeys.aiProviders_getKey.tr(
                      args: [_kind.label],
                    ),
                    url: _kind.credentialsUrl,
                    palette: palette,
                  ),
                ],
                const SizedBox(height: 12),
                ProviderTextField(
                  label: _kind.usesTargetUri
                      ? LocaleKeys.aiProviders_deploymentsLabel.tr()
                      : LocaleKeys.aiProviders_modelsLabel.tr(),
                  controller: _models,
                  palette: palette,
                  hint: _kind.suggestedModels.join(', '),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _PillButton(
                      label: LocaleKeys.aiProviders_fetchModels.tr(),
                      icon: Icons.refresh_rounded,
                      palette: palette,
                      busy: _busy,
                      onTap: _fetchModels,
                    ),
                  ],
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _notice!,
                    style: TextStyle(
                      color: _noticeIsError ? palette.danger : palette.accent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _PillButton(
                      label: LocaleKeys.button_cancel.tr(),
                      palette: palette,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: LocaleKeys.button_save.tr(),
                      palette: palette,
                      primary: true,
                      onTap: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindPicker extends StatelessWidget {
  const _KindPicker({
    required this.kind,
    required this.palette,
    required this.onChanged,
  });

  final AIProviderKind kind;
  final FolderExplorerPalette palette;
  final ValueChanged<AIProviderKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.aiProviders_serviceLabel.tr(),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 11.5,
            fontVariations: const [FontVariation.weight(580)],
          ),
        ),
        const SizedBox(height: 5),
        Builder(
          builder: (buttonContext) => Material(
            color: palette.background,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => showAppMenu(
                context: buttonContext,
                globalPosition: _anchor(buttonContext),
                entries: [
                  for (final entry in AIProviderKind.values)
                    AppMenuItem(
                      label: entry.label,
                      icon: entry.icon,
                      selected: entry == kind,
                      onSelected: () => onChanged(entry),
                    ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(kind.icon, size: 15, color: palette.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kind.label,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: palette.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _anchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return Offset.zero;
    }
    return box.localToGlobal(Offset(0, box.size.height + 4));
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({
    required this.label,
    required this.url,
    required this.palette,
  });

  final String label;
  final String url;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => unawaited(
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: palette.accent,
            fontSize: 11.5,
            decoration: TextDecoration.underline,
            decorationColor: palette.accent,
          ),
        ),
      ),
    );
  }
}
