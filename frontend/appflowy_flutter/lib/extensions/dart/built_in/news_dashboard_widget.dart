import 'dart:async';

import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/built_in/news_extension.dart';
import 'package:appflowy/extensions/dart/built_in/news_views.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:flutter/material.dart';

/// The dashboard card for a news feed.
const newsWidgetType = 'ext.news.feed';

const _keyUrl = 'url';
const _keyLabel = 'label';
const _keyCount = 'count';
const _keyShowSummary = 'showSummary';
const _keyShowImages = 'showImages';

DashboardWidgetDefinition newsDashboardWidget() => DashboardWidgetDefinition(
      type: newsWidgetType,
      extensionId: 'news',
      label: () => 'News feed',
      description: () => 'Headlines from any RSS or Atom feed',
      icon: Icons.newspaper_rounded,
      group: DashboardWidgetGroup.info,
      defaultColumnSpan: 5,
      defaultRowSpan: 7,
      minimumColumnSpan: 3,
      minimumRowSpan: 3,
      showsTitleByDefault: false,
      keywords: const ['news', 'feed', 'rss', 'atom', 'headlines', 'articles'],
      defaultSettings: {
        _keyUrl: newsSources.first.url,
        _keyLabel: newsSources.first.name,
        _keyCount: 8,
        _keyShowSummary: false,
        _keyShowImages: true,
      },
      builder: (context) => _NewsCard(context: context),
      configure: (context) => [
        DashboardConfigText(
          label: 'Feed address',
          value: context.spec.setting(_keyUrl),
          placeholder: 'https://example.com/rss.xml',
          hint: 'Any RSS or Atom feed',
          onChanged: (value) => context.setSettings({_keyUrl: value.trim()}),
        ),
        DashboardConfigChoice(
          label: 'Or pick one',
          value: context.spec.setting(_keyUrl),
          choices: [
            for (final source in newsSources)
              DashboardChoice(value: source.url, label: source.name),
          ],
          onChanged: (value) => context.setSettings({
            _keyUrl: value,
            _keyLabel: newsSources
                .firstWhere(
                  (source) => source.url == value,
                  orElse: () => const NewsSource('', ''),
                )
                .name,
          }),
        ),
        DashboardConfigText(
          label: 'Heading',
          value: context.spec.setting(_keyLabel),
          placeholder: "The feed's own title",
          onChanged: (value) => context.setSettings({_keyLabel: value}),
        ),
        DashboardConfigNumber(
          label: 'Headlines',
          value: context.spec.integer(_keyCount, fallback: 8).toDouble(),
          minimum: 1,
          maximum: 20,
          onChanged: (value) =>
              context.setSettings({_keyCount: value.round()}),
        ),
        DashboardConfigToggle(
          label: 'Show a line of summary',
          value: context.spec.flag(_keyShowSummary),
          onChanged: (value) => context.setSettings({_keyShowSummary: value}),
        ),
        DashboardConfigToggle(
          label: 'Show image thumbnails',
          hint: 'Only feeds that carry pictures show one',
          value: context.spec.flag(_keyShowImages, fallback: true),
          onChanged: (value) => context.setSettings({_keyShowImages: value}),
        ),
      ],
    );

class _NewsCard extends StatefulWidget {
  const _NewsCard({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard> {
  String get _url => widget.context.spec.setting(_keyUrl);

  @override
  void initState() {
    super.initState();
    _ensureFresh();
  }

  @override
  void didUpdateWidget(_NewsCard old) {
    super.didUpdateWidget(old);
    _ensureFresh();
  }

  void _ensureFresh() {
    final feed = NewsFeed.active;
    if (feed == null || _url.isEmpty) {
      return;
    }
    unawaited(feed.watch(_url));
    unawaited(feed.refresh(_url));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: ExtensionDataStore.instance.revision,
        builder: (context, _, __) => _build(context),
      );

  Widget _build(BuildContext context) {
    final spec = widget.context.spec;
    final tone = widget.context.tone;
    final url = _url;

    if (url.isEmpty) {
      return Center(
        child: Text(
          'Choose a feed in the panel on the right.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tone.inkSoft),
        ),
      );
    }

    final entry =
        ExtensionDataStore.instance.entryFor(NewsFeed.qualifiedKeyFor(url));
    final stored = entry?.value;
    final channel = stored is Map
        ? NewsChannel.fromJson(Map<String, Object?>.from(stored))
        : null;
    final label = spec.setting(_keyLabel);

    return NewsBody(
      channel: channel,
      heading: label.isNotEmpty ? label : channel?.title ?? '',
      count: spec.integer(_keyCount, fallback: 8),
      showSummary: spec.flag(_keyShowSummary),
      showImages: spec.flag(_keyShowImages, fallback: true),
      fetchedAt: entry?.writtenAt,
      ink: tone.ink,
      muted: tone.inkSoft,
    );
  }
}
