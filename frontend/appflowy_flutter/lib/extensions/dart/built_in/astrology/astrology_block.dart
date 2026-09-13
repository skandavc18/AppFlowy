import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'astrology_birth_form.dart';
import 'astrology_chart_panel.dart';
import 'astrology_model.dart';
import 'astrology_style.dart';

const astrologyBlockType = 'extension_astrology';

Node astrologyNode({
  String type = astrologyBlockType,
  AstrologyView view = AstrologyView.chart,
  AstrologyInput input = const AstrologyInput(),
  int division = 1,
}) =>
    Node(
      type: type,
      attributes: {
        'profile': input.toJson(),
        'view': view.name,
        'division': division,
      },
    );

/// Keep the complete configuration in a fenced export rather than silently
/// dropping the block or pretending a static image is an interactive chart.
class AstrologyNodeParser extends NodeParser {
  AstrologyNodeParser(this.type);
  final String type;
  @override
  String get id => type;
  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) =>
      '\n```astrology\n${jsonEncode(node.attributes)}\n```\n';
}

class AstrologyBlockBuilder extends BlockComponentBuilder {
  AstrologyBlockBuilder({super.configuration});
  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) =>
      AstrologyBlock(
        key: blockComponentContext.node.key,
        node: blockComponentContext.node,
        configuration: configuration,
        showActions: showActions(blockComponentContext.node),
        actionBuilder: (_, state) =>
            actionBuilder(blockComponentContext, state),
      );
}

class AstrologyBlock extends BlockComponentStatefulWidget {
  const AstrologyBlock({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });
  @override
  State<AstrologyBlock> createState() => _AstrologyBlockState();
}

class _AstrologyBlockState extends State<AstrologyBlock>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;
  @override
  BlockComponentConfiguration get configuration => widget.configuration;
  EditorState get editor => context.read<EditorState>();

  Future<void> _write(Map<String, Object?> values) async {
    if (!mounted ||
        !editor.editable ||
        editor.isDisposed ||
        node.parent == null) {
      return;
    }
    await editor.apply(editor.transaction..updateNode(node, values));
    if (mounted) setState(() {});
  }

  Future<void> _configure() async {
    final input = AstrologyInput.fromJson(
      astrologyMap(node.attributes['profile']),
    );
    final result = await showAstrologyInputDialog(context, input: input);
    if (result != null && mounted) await _write({'profile': result.toJson()});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    AstrologyInput input;
    try {
      input = AstrologyInput.fromJson(astrologyMap(node.attributes['profile']));
    } on Object catch (error) {
      return Padding(
        padding: padding,
        child: Text('This horoscope could not be read: $error'),
      );
    }
    final view = AstrologyView.fromValue(node.attributes['view']);
    final rawDivision = (node.attributes['division'] as num?)?.toInt() ?? 1;
    final division =
        astrologyDivisions.containsKey(rawDivision) ? rawDivision : 1;
    return decorateInteractiveBlock(
      widget: widget,
      editorState: editor,
      padding: padding,
      child: ResizableMedia(
        width: (node.attributes['width'] as num?)?.toDouble() ?? 740,
        height: ((node.attributes['height'] as num?)?.toDouble() ?? 520)
            .clamp(300, 1200),
        minWidth: 280,
        minHeight: 300,
        editable: editor.editable,
        alignment: blockEmbedAlignment(node),
        onResize: (value) => unawaited(_write({'width': value})),
        onResizeHeight: (value) => unawaited(_write({'height': value})),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: InteractiveFocusGuard(
            child: ScrollActivationRegion(
              child: Material(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * 0.5,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Vedic astrology',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    if (editor.editable)
                                      TextButton.icon(
                                        onPressed: () =>
                                            unawaited(_configure()),
                                        icon: const Icon(
                                          Icons.tune_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Birth details'),
                                      ),
                                    SizedBox(
                                      width: 230,
                                      child: DropdownButton<AstrologyView>(
                                        isExpanded: true,
                                        value: view,
                                        dropdownColor: palette.raised,
                                        items: [
                                          for (final option
                                              in AstrologyView.values)
                                            DropdownMenuItem(
                                              value: option,
                                              child: Text(
                                                option.label,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: !editor.editable
                                            ? null
                                            : (value) {
                                                if (value != null) {
                                                  unawaited(
                                                    _write(
                                                        {'view': value.name}),
                                                  );
                                                }
                                              },
                                      ),
                                    ),
                                  ],
                                ),
                                if (view == AstrologyView.chart ||
                                    view == AstrologyView.ashtakavarga)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      for (final style
                                          in IndianChartStyle.values)
                                        ChoiceChip(
                                          label: Text(style.label),
                                          selected: input.style == style,
                                          onSelected: !editor.editable
                                              ? null
                                              : (_) => unawaited(
                                                    _write(
                                                      {
                                                        'profile': input
                                                            .copyWith(
                                                              style: style,
                                                            )
                                                            .toJson(),
                                                      },
                                                    ),
                                                  ),
                                        ),
                                      if (view == AstrologyView.chart)
                                        SizedBox(
                                          width: 230,
                                          child: DropdownButton<int>(
                                            isExpanded: true,
                                            value: division,
                                            dropdownColor: palette.raised,
                                            items: [
                                              for (final option
                                                  in astrologyDivisions.entries)
                                                DropdownMenuItem(
                                                  value: option.key,
                                                  child: Text(
                                                    option.value,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                            onChanged: !editor.editable
                                                ? null
                                                : (value) {
                                                    if (value != null) {
                                                      unawaited(
                                                        _write(
                                                          {'division': value},
                                                        ),
                                                      );
                                                    }
                                                  },
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: AstrologyChartPanel(
                            input: input,
                            view: view,
                            division: division,
                            preview: !editor.editable,
                            onConfigure: editor.editable
                                ? () => unawaited(_configure())
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<AstrologyInput?> showAstrologyInputDialog(
  BuildContext context, {
  required AstrologyInput input,
}) =>
    showDialog<AstrologyInput>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AstrologyPalette.of(dialogContext).surface,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close birth details',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AstrologyRuntime.active,
                  builder: (_, active, __) => AstrologyBirthForm(
                    input: input,
                    enabled: active,
                    onGenerate: (value) async =>
                        Navigator.of(dialogContext).pop(value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
