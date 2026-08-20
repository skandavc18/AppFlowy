import 'package:appflowy/extensions/dart/built_in/news_extension.dart';
import 'package:flutter/material.dart';

/// The headline list, shared by the document block and the dashboard card.
class NewsBody extends StatelessWidget {
  const NewsBody({
    super.key,
    required this.channel,
    required this.heading,
    required this.count,
    required this.showSummary,
    this.showImages = true,
    this.fetchedAt,
    this.onConfigure,
    this.ink,
    this.muted,
  });

  final NewsChannel? channel;
  final String heading;
  final int count;
  final bool showSummary;
  final bool showImages;
  final DateTime? fetchedAt;
  final VoidCallback? onConfigure;

  /// Supplied by the dashboard, which tints its cards; null uses the theme.
  final Color? ink;
  final Color? muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soft = muted ?? theme.colorScheme.onSurfaceVariant;
    final feed = channel;

    if (feed != null && feed.error.isNotEmpty) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: feed.error,
        color: theme.colorScheme.error,
        onConfigure: onConfigure,
      );
    }
    if (feed == null) {
      return _Message(
        icon: Icons.newspaper_rounded,
        text: 'Fetching headlines…',
        color: soft,
        spinner: true,
        onConfigure: onConfigure,
      );
    }

    final items = feed.items.take(count).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                heading.isEmpty ? 'Headlines' : heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (fetchedAt != null)
              Text(
                newsAgeLabel(fetchedAt),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: soft, fontSize: 11),
              ),
            if (onConfigure != null)
              IconButton(
                onPressed: onConfigure,
                icon: const Icon(Icons.tune_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                color: soft,
                tooltip: 'Feed and headline count',
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              height: 13,
              thickness: 0.6,
              color: soft.withValues(alpha: 0.22),
            ),
            itemBuilder: (context, index) => _Headline(
              item: items[index],
              showSummary: showSummary,
              showImages: showImages,
              ink: ink,
              muted: soft,
            ),
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.item,
    required this.showSummary,
    required this.showImages,
    required this.ink,
    required this.muted,
  });

  final NewsItem item;
  final bool showSummary;
  final bool showImages;
  final Color? ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ink,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        if (showSummary && item.summary.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
        if (item.publishedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            newsAgeLabel(item.publishedAt),
            style:
                theme.textTheme.bodySmall?.copyWith(color: muted, fontSize: 11),
          ),
        ],
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: item.link.isEmpty ? null : () => openNewsLink(item.link),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        // A feed with no picture must not leave a hole where one would be, so
        // the thumbnail is only a row when there is something to put in it.
        child: showImages && item.hasImage
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumbnail(url: item.image, muted: muted),
                  const SizedBox(width: 10),
                  Expanded(child: words),
                ],
              )
            : words,
      ),
    );
  }
}

/// ⚠️ A thumbnail must never be able to break the card: a feed can point at
/// anything, so a failed or slow image collapses to a quiet placeholder rather
/// than an exception box or a jumping row.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.muted});

  static const _size = 56.0;

  final String url;
  final Color muted;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            // Feeds are third-party; a broken URL is ordinary, not exceptional.
            errorBuilder: (context, _, __) => _placeholder(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _placeholder(),
          ),
        ),
      );

  Widget _placeholder() => ColoredBox(
        color: muted.withValues(alpha: 0.12),
        child: Icon(
          Icons.image_outlined,
          size: 16,
          color: muted.withValues(alpha: 0.7),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.color,
    this.spinner = false,
    this.onConfigure,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool spinner;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (onConfigure != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('Choose a feed'),
            ),
          ],
        ],
      ),
    );
  }
}

/// ⚠️ Owns its controllers. Creating them in `build` loses the caret on every
/// keystroke.
class NewsDialog extends StatefulWidget {
  const NewsDialog({
    super.key,
    required this.url,
    required this.label,
    required this.count,
    required this.showSummary,
    required this.showImages,
  });

  final String url;
  final String label;
  final int count;
  final bool showSummary;
  final bool showImages;

  @override
  State<NewsDialog> createState() => _NewsDialogState();
}

class _NewsDialogState extends State<NewsDialog> {
  late final _url = TextEditingController(text: widget.url);
  late final _label = TextEditingController(text: widget.label);
  late var _count = widget.count;
  late var _showSummary = widget.showSummary;
  late var _showImages = widget.showImages;

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(
        (
          url: _url.text.trim(),
          label: _label.text.trim(),
          count: _count,
          showSummary: _showSummary,
          showImages: _showImages,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('News feed'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Feed address',
                  hintText: 'https://example.com/rss.xml',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              Text(
                'Or pick one',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final source in newsSources)
                    ChoiceChip(
                      label: Text(source.name),
                      selected: _url.text.trim() == source.url,
                      onSelected: (_) => setState(() {
                        _url.text = source.url;
                        if (_label.text.isEmpty) {
                          _label.text = source.name;
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Heading',
                  hintText: "Optional — the feed's own title is used",
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Headlines', style: theme.textTheme.labelMedium),
                  const Spacer(),
                  Text('$_count', style: theme.textTheme.bodyMedium),
                ],
              ),
              Slider(
                value: _count.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                onChanged: (value) => setState(() => _count = value.round()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show a line of summary'),
                value: _showSummary,
                onChanged: (value) => setState(() => _showSummary = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show image thumbnails'),
                subtitle: const Text('Only feeds that carry pictures show one'),
                value: _showImages,
                onChanged: (value) => setState(() => _showImages = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
