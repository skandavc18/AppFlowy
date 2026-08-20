import 'dart:convert';

import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_boundary.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows a value an action worked out, live.
///
/// This is the worked example for the Dart tier, and it is the missing half of
/// the stock-price story: an action fetches on a schedule and writes to
/// `af.data`; this draws whatever is there and redraws the moment it changes.
/// The document stores only WHICH key — never the value.
class DataBlockExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'data',
        name: 'Live values',
        description:
            'A block that shows a value an action keeps up to date, and a '
            'command that lists what has been stored.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;

    ctx.blocks.define(
      type: LiveValueBlockKeys.type,
      builder: (configuration) =>
          LiveValueBlockComponentBuilder(configuration: configuration),
      parser: LiveValueNodeParser(),
      slashName: 'Live value',
      slashKeywords: const ['live', 'value', 'data', 'metric', 'price'],
      slashIcon: Icons.speed_rounded,
      slashDescription: 'Show a value an action keeps up to date',
      newNode: liveValueNode,
    );

    ctx.commands.add(
      id: 'list_values',
      name: 'Extensions: list stored values',
      description: 'Every key actions have written to af.data',
      keywords: const ['data', 'value', 'key', 'store', 'debug'],
      icon: Icons.storage_rounded,
      run: _showStoredValues,
    );
  }

  Future<void> _showStoredValues(BuildContext context) async {
    final store = ExtensionDataStore.instance;
    await store.ensureLoaded();
    final keys = store.allKeys();
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stored values'),
        content: SizedBox(
          width: 420,
          child: keys.isEmpty
              ? const Text('No action has written anything yet.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final key in keys)
                      ListTile(
                        dense: true,
                        title: Text(key),
                        subtitle: Text(
                          jsonEncode(store.read(key)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class LiveValueBlockKeys {
  const LiveValueBlockKeys._();

  static const String type = 'extension_live_value';

  /// The full `af.data` key, extension prefix and all.
  static const String dataKey = 'key';
  static const String label = 'label';
  static const String suffix = 'suffix';
}

Node liveValueNode({
  String dataKey = '',
  String label = '',
  String suffix = '',
}) =>
    Node(
      type: LiveValueBlockKeys.type,
      attributes: {
        LiveValueBlockKeys.dataKey: dataKey,
        LiveValueBlockKeys.label: label,
        LiveValueBlockKeys.suffix: suffix,
      },
    );

class LiveValueNodeParser extends NodeParser {
  @override
  String get id => LiveValueBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final key = node.attributes[LiveValueBlockKeys.dataKey] as String? ?? '';
    final label = node.attributes[LiveValueBlockKeys.label] as String? ?? '';
    final value = ExtensionDataStore.instance.read(key);
    final name = label.isEmpty ? key : label;
    return '$name: ${value ?? ''}\n';
  }
}

class LiveValueBlockComponentBuilder extends BlockComponentBuilder {
  LiveValueBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return LiveValueBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class LiveValueBlockComponent extends BlockComponentStatefulWidget {
  const LiveValueBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<LiveValueBlockComponent> createState() =>
      _LiveValueBlockComponentState();
}

class _LiveValueBlockComponentState extends State<LiveValueBlockComponent>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  String get _dataKey =>
      node.attributes[LiveValueBlockKeys.dataKey] as String? ?? '';

  String get _label =>
      node.attributes[LiveValueBlockKeys.label] as String? ?? '';

  String get _suffix =>
      node.attributes[LiveValueBlockKeys.suffix] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    Widget child = ExtensionBoundary(
      extensionId: 'data',
      label: 'a live value',
      child: ValueListenableBuilder<int>(
        valueListenable: ExtensionDataStore.instance.revision,
        builder: (context, _, __) => _buildCard(context),
      ),
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return Align(
      alignment: defaultBlockAlignment(node),
      child: child,
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final key = _dataKey;
    final entry =
        key.isEmpty ? null : ExtensionDataStore.instance.entryFor(key);
    final stale = entry?.isStale(DateTime.now()) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _configure(context),
      child: Container(
        constraints: const BoxConstraints(minWidth: 180),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _label.isEmpty ? (key.isEmpty ? 'Live value' : key) : _label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (stale) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'This value is older than it should be.',
                    child: Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _describe(entry?.value) + (_suffix.isEmpty ? '' : ' $_suffix'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(Object? value) => switch (value) {
        null => '—',
        final num number => '$number',
        final String text => text,
        _ => jsonEncode(value),
      };

  Future<void> _configure(BuildContext context) async {
    final editorState = context.read<EditorState>();
    if (!editorState.editable) {
      return;
    }
    final chosen = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _LiveValueDialog(
        dataKey: _dataKey,
        label: _label,
        suffix: _suffix,
      ),
    );
    if (chosen == null) {
      return;
    }
    final transaction = editorState.transaction
      ..updateNode(node, {
        LiveValueBlockKeys.dataKey: chosen['key'] ?? '',
        LiveValueBlockKeys.label: chosen['label'] ?? '',
        LiveValueBlockKeys.suffix: chosen['suffix'] ?? '',
      });
    await editorState.apply(transaction);
  }
}

/// Owns its controllers, because a dialog that disposes them in
/// `whenComplete` reads a disposed controller during the closing animation.
class _LiveValueDialog extends StatefulWidget {
  const _LiveValueDialog({
    required this.dataKey,
    required this.label,
    required this.suffix,
  });

  final String dataKey;
  final String label;
  final String suffix;

  @override
  State<_LiveValueDialog> createState() => _LiveValueDialogState();
}

class _LiveValueDialogState extends State<_LiveValueDialog> {
  late final TextEditingController _key =
      TextEditingController(text: widget.dataKey);
  late final TextEditingController _label =
      TextEditingController(text: widget.label);
  late final TextEditingController _suffix =
      TextEditingController(text: widget.suffix);

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _suffix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = ExtensionDataStore.instance.keysUnder('');
    return AlertDialog(
      title: const Text('Live value'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'finance.quote.AAPL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (known.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final key in known.take(24))
                        ActionChip(
                          label:
                              Text(key, style: const TextStyle(fontSize: 11)),
                          onPressed: () => setState(() => _key.text = key),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _suffix,
              decoration: const InputDecoration(
                labelText: 'Suffix',
                hintText: 'USD',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'key': _key.text.trim(),
            'label': _label.text.trim(),
            'suffix': _suffix.text.trim(),
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
