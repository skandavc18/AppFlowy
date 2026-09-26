import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/collections/collection.dart'
    show CollectionKind;
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Design-system name for the shared default artwork renderer, not another
/// icon family. Saved/custom icons keep their own renderer and chosen style.
typedef DSWorkspaceGlyph = WorkspaceGlyph;

/// One quiet ink for default chrome, independent of selection and hover.
/// Custom/saved icon renderers deliberately do not use this function.
Color workspaceGlyphInk(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness != Brightness.dark && PaperTheme.isEnabled(context)) {
    return PaperTheme.textSecondary;
  }
  return PremiumThemeExtension.maybeOf(context)?.textSecondary ??
      theme.colorScheme.onSurfaceVariant;
}

/// A single theme accent for meanings without a matching Vivid illustration.
/// Never hash a name into a random colour or replace it with unrelated artwork.
Color workspaceGlyphAccent(BuildContext context) =>
    PremiumThemeExtension.maybeOf(context)?.accent ??
    (PaperTheme.isEnabled(context) &&
            Theme.of(context).brightness == Brightness.light
        ? PaperTheme.accent
        : Theme.of(context).colorScheme.primary);

enum WorkspaceGlyphRole {
  standard,

  /// Disabled/destructive/status ink wins over the device style. Draw the
  /// original outline in that ink, never a red/grey filter over an illustration.
  preserveInk,
}

/// Optional injection for previews/tests and independent windows. The normal
/// application needs no root wrapper: each glyph observes the device store.
/// As an InheritedTheme, this source survives captured popup/dialog themes.
class DefaultIconStyleScope extends InheritedTheme {
  const DefaultIconStyleScope({
    super.key,
    required this.styles,
    required super.child,
  });

  final ValueListenable<DefaultIconStyle> styles;

  static ValueListenable<DefaultIconStyle> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DefaultIconStyleScope>()
          ?.styles ??
      DefaultIconStyleStore.instance.styles;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      DefaultIconStyleScope(styles: styles, child: child);

  @override
  bool updateShouldNotify(DefaultIconStyleScope oldWidget) =>
      oldWidget.styles != styles;
}

/// A default UI symbol, never a renderer for a saved IconPB or uploaded image.
///
/// The source is synchronous, compiled-in original artwork: no font glyph,
/// asset lookup, network request, or picker-pack initialization. Unlike
/// FlowySvg, text scaling cannot paint outside this explicit icon slot.
/// Unmapped future callers retain their source renderer instead of a question
/// mark; add a semantic alias below when matching compiled artwork exists.
class WorkspaceGlyph extends StatelessWidget {
  const WorkspaceGlyph(
    IconData this.icon, {
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
    this.style,
    this.role,
  })  : data = null,
        _name = null;

  const WorkspaceGlyph.svg(
    FlowySvgData this.data, {
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
    this.style,
    this.role,
  })  : icon = null,
        _name = null;

  const WorkspaceGlyph.named(
    String name, {
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
    this.style,
    this.role,
  })  : _name = name,
        icon = null,
        data = null;

  /// File identity, not a generic action with the same Material glyph. For
  /// example, a CSV and a table share IconData but are different objects.
  factory WorkspaceGlyph.file(
    String? fileName, {
    Key? key,
    double size = 18,
    Color? color,
    String? semanticLabel,
    DefaultIconStyle? style,
    WorkspaceGlyphRole? role,
  }) =>
      WorkspaceGlyph.named(
        WorkspaceGlyphs.nameForFile(fileName),
        key: key,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        style: style,
        role: role,
      );

  /// Collection identity, independent of the registry's action IconData.
  /// Only the collection model is needed, not its registry or sidebar UI.
  factory WorkspaceGlyph.collection(
    CollectionKind kind, {
    Key? key,
    double size = 18,
    Color? color,
    String? semanticLabel,
    DefaultIconStyle? style,
    WorkspaceGlyphRole? role,
  }) =>
      WorkspaceGlyph.named(
        WorkspaceGlyphs.nameForCollection(kind),
        key: key,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        style: style,
        role: role,
      );

  final IconData? icon;
  final FlowySvgData? data;
  final String? _name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  /// Explicit only for side-by-side style previews. Normal glyphs follow the
  /// device preference, including when already mounted in another route.
  final DefaultIconStyle? style;
  final WorkspaceGlyphRole? role;

  /// The resolved artwork identity, also useful for coverage diagnostics.
  String get name {
    final requested = _name ??
        (icon != null
            ? WorkspaceGlyphs.nameForIcon(icon!)
            : WorkspaceGlyphs.nameForSvg(data!));
    if (requested != null && defaultIconSvg(requested) != null) {
      return requested;
    }
    assert(() {
      WorkspaceGlyphs._reportUnknown(
        _name ??
            (data == null
                ? null
                : 'svg:${WorkspaceGlyphs._svgStem(data!.path)}') ??
            '${icon!.fontFamily}/${icon!.codePoint.toRadixString(16)}',
      );
      return true;
    }());
    // This is a diagnostic identity, not the artwork: an unmapped caller keeps
    // its supplied icon/SVG instead of showing a question mark for a new action.
    return 'unknown';
  }

  /// Adapts only default UI leaves. Saved IconWidget/RawEmojiIconWidget objects,
  /// multicolor SVGs and inline SVG strings retain their original renderer,
  /// artwork and color. This is not a blanket ColorFiltered wrapper.
  static Widget adapt(
    Widget child, {
    double size = 18,
    Color? color,
    String? semanticLabel,
    WorkspaceGlyphRole? role,
  }) {
    if (child is WorkspaceGlyph) {
      if (child.icon != null) {
        return WorkspaceGlyph(
          child.icon!,
          key: child.key,
          size: size,
          color: color ?? child.color,
          semanticLabel: semanticLabel ?? child.semanticLabel,
          style: child.style,
          role: role ?? child.role,
        );
      }
      if (child.data != null) {
        return WorkspaceGlyph.svg(
          child.data!,
          key: child.key,
          size: size,
          color: color ?? child.color,
          semanticLabel: semanticLabel ?? child.semanticLabel,
          style: child.style,
          role: role ?? child.role,
        );
      }
      return WorkspaceGlyph.named(
        child._name!,
        key: child.key,
        size: size,
        color: color ?? child.color,
        semanticLabel: semanticLabel ?? child.semanticLabel,
        style: child.style,
        role: role ?? child.role,
      );
    }
    if (child is Icon && child.icon != null) {
      return WorkspaceGlyph(
        child.icon!,
        key: child.key,
        size: size,
        color: color ?? child.color,
        semanticLabel: semanticLabel ?? child.semanticLabel,
        role: role,
      );
    }
    if (child is FlowySvg &&
        child.svgString == null &&
        child.blendMode != null &&
        child.svg.path.startsWith('assets/flowy_icons/')) {
      return WorkspaceGlyph.svg(
        child.svg,
        key: child.key,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        role: role,
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final previewStyle = style;
    if (previewStyle != null) return _buildGlyph(context, previewStyle);
    return ValueListenableBuilder<DefaultIconStyle>(
      valueListenable: DefaultIconStyleScope.of(context),
      builder: (context, style, _) => _buildGlyph(context, style),
    );
  }

  Widget _buildGlyph(BuildContext context, DefaultIconStyle style) {
    final scope = WorkspaceGlyphScope.maybeOf(context);
    final scopedStateInk = scope?.role == WorkspaceGlyphRole.preserveInk;
    final preserveInk =
        scopedStateInk || role == WorkspaceGlyphRole.preserveInk;
    final vivid = style == DefaultIconStyle.vivid && !preserveInk;
    final ink = vivid
        ? workspaceGlyphAccent(context)
        : scopedStateInk
            ? scope!.color
            : color ?? scope?.color ?? workspaceGlyphInk(context);
    final resolvedName = name;
    final vividName = vivid ? WorkspaceGlyphs.vividNameFor(resolvedName) : null;
    final illustration = vividName == null ? null : vividIconSvg(vividName);
    final filter =
        illustration == null ? ColorFilter.mode(ink, BlendMode.srcIn) : null;

    Widget artwork;
    if (resolvedName == 'unknown' && icon != null) {
      artwork = MediaQuery.withNoTextScaling(
        child: Icon(icon, size: size, color: ink, semanticLabel: semanticLabel),
      );
    } else if (resolvedName == 'unknown' && data != null) {
      artwork = SvgPicture.asset(
        data!.path,
        width: size,
        height: size,
        colorFilter: filter,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      );
    } else {
      artwork = SvgPicture.string(
        illustration ??
            defaultIconSvg(resolvedName == 'unknown' ? 'file' : resolvedName)!,
        width: size,
        height: size,
        colorFilter: filter,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        matchTextDirection: icon?.matchTextDirection ?? false,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: artwork,
    );
  }
}

/// Carries disabled/destructive ink through a deferred slash icon builder
/// without tinting arbitrary user artwork in the same menu. A preserveInk
/// scope outranks decorative default-glyph colours/roles inside a builder;
/// saved artwork is not a WorkspaceGlyph and never consults this scope.
class WorkspaceGlyphScope extends InheritedWidget {
  const WorkspaceGlyphScope({
    super.key,
    required this.color,
    this.role = WorkspaceGlyphRole.standard,
    required super.child,
  });

  final Color color;
  final WorkspaceGlyphRole role;

  static WorkspaceGlyphScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceGlyphScope>();

  @override
  bool updateShouldNotify(WorkspaceGlyphScope oldWidget) =>
      oldWidget.color != color || oldWidget.role != role;
}

/// Central semantic aliases for settings, slash items and AppMenu callers.
/// Aliases intentionally join different font cuts of the *same* meaning, not
/// unrelated actions. New built-in callers should add an alias here.
abstract final class WorkspaceGlyphs {
  static String? nameForIcon(IconData icon) => _materialNames[icon];

  /// Stable collection identities matching the sidebar's existing artwork.
  /// Registry icons are also used for actions: code and folder-copy must not
  /// redefine repository and folder identities (or vice versa).
  static String nameForCollection(CollectionKind kind) => switch (kind) {
        CollectionKind.book => 'book-open',
        CollectionKind.album => 'images',
        CollectionKind.repository => 'git-branch',
        CollectionKind.folder => 'folder',
        CollectionKind.database => 'database',
        CollectionKind.bookmark => 'link-simple',
        CollectionKind.email => 'envelope-simple',
      };

  /// Refines the existing file classifier only for visual identities that
  /// share an action glyph. It does not change supported formats or viewers.
  static String nameForFile(String? fileName) {
    if (fileName == null || fileName.isEmpty) return 'file';
    final uri = Uri.tryParse(fileName);
    final path = uri != null &&
            const {'http', 'https', 'file'}.contains(uri.scheme.toLowerCase())
        ? uri.path
        : fileName;
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (const {'xls', 'xlsx', 'ods'}.contains(extension)) return 'file-xls';
    return switch (filePreviewKindFromName(name)) {
      FilePreviewKind.html => 'file-html',
      FilePreviewKind.markdown => 'file-markdown',
      FilePreviewKind.csv => 'file-csv',
      FilePreviewKind.json => 'file-json',
      FilePreviewKind.notebook => 'file-notebook',
      FilePreviewKind.code => 'file-code',
      _ => nameForIcon(fileIconForName(name)) ?? 'file',
    };
  }

  /// Object illustrations where available, otherwise the same semantic mark
  /// in a vivid gradient. No known default falls back to paper's brown ink.
  /// Saved pack choices never enter this resolver and are never rewritten.
  static String? vividNameFor(String name) =>
      _vividNames[name] ??
      (name != 'unknown' && defaultIconSvg(name) != null
          ? 'utility-$name'
          : null);

  static const _vividNames = <String, String>{
    'magnifying-glass': 'search',
    'gear': 'settings',
    'bell': 'bell',
    'trash': 'trash',
    'puzzle-piece': 'puzzle',
    'plus': 'plus',
    'copy': 'copy',
    'download': 'download',
    'upload': 'upload',
    'pen': 'pen',
    'note-pencil': 'pen',
    'push-pin': 'pin',
    'history': 'history',
    'clock': 'clock',
    'user': 'user',
    'users': 'users',
    'workspace': 'workspace',
    'lock': 'lock',
    'shield': 'shield',
    'text': 'text',
    'hash': 'number',
    'checkbox': 'checkbox',
    'select': 'select',
    'connections': 'connections',
    'attachment': 'attachment',
    'sigma': 'sigma',
    'keyboard': 'keyboard',
    'filter': 'filter',
    'sort': 'sort',
    'refresh': 'refresh',
    'scissors': 'scissors',
    'paste': 'clipboard',
    'house': 'home',
    'book-open': 'book',
    'folder': 'folder',
    'folder-open': 'folder',
    'images': 'album',
    'image': 'image',
    'film-strip': 'video',
    'file-text': 'page',
    'file': 'file',
    'file-pdf': 'pdf',
    'file-doc': 'document',
    'file-xls': 'spreadsheet',
    'file-ppt': 'presentation',
    'file-zip': 'archive',
    'file-code': 'code-file',
    'file-csv': 'csv',
    'file-markdown': 'markdown',
    'file-html': 'html-file',
    'file-json': 'json-file',
    'file-notebook': 'notebook',
    'git-branch': 'repository',
    'database': 'database',
    'link-simple': 'bookmark',
    'envelope-simple': 'mail',
    'inbox': 'mail',
    'table': 'table',
    'kanban': 'board',
    'chat-circle': 'chat',
    'ai-chat': 'ai-chat',
    'map-trifold': 'map',
    'presentation-chart': 'slides',
    'graph': 'timeline',
    'article': 'feed',
    'list-checks': 'form',
    'squares-four': 'gallery',
    'layout': 'dashboard',
    'canvas': 'canvas',
    'camera': 'camera',
    'music-note': 'music',
    'calendar-blank': 'calendar',
    'chart-bar': 'chart',
    'globe': 'globe',
    'palette': 'palette',
    'sparkles': 'sparkles',
    'target': 'target',
    'rocket': 'rocket',
    'bulb': 'bulb',
    'cloud': 'cloud',
    'compass': 'compass',
    'bolt': 'bolt',
  };

  static String? nameForSvg(FlowySvgData data) =>
      _svgNames[_svgStem(data.path)];

  static String _svgStem(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .last
      .toLowerCase()
      .replaceAll(_svgSeparators, '_')
      .replaceFirst(_svgExtension, '')
      .replaceFirst(_svgSizeSuffix, '');

  static final _svgExtension = RegExp(r'\.svg$');
  static final _svgSeparators = RegExp('[ -]');
  static final _svgSizeSuffix = RegExp(r'_(?:s|m|l|xl)$');

  static Iterable<IconData> get mappedIcons => _materialNames.keys;
  static Iterable<String> get mappedSvgNames => _svgNames.keys;

  /// Debug-only, bounded and contains symbolic identities, never row labels,
  /// document contents, storage URLs or profile data.
  static Set<String> get unknownMappings => Set.unmodifiable(_unknown);
  static final _unknown = <String>{};

  @visibleForTesting
  static void clearUnknownMappings() => _unknown.clear();

  static void _reportUnknown(String identity) {
    if (_unknown.length < 64 && _unknown.add(identity)) {
      debugPrint('WorkspaceGlyph: unmapped default icon $identity');
    }
  }

  // IconData has value equality: this is deliberately not a const map.
  static final Map<IconData, String> _materialNames = {
    for (final entry in _materialAliases.entries)
      for (final icon in entry.value) icon: entry.key,
  };

  static final _materialAliases = <String, List<IconData>>{
    'user': [Icons.person_rounded, Icons.person_outline_rounded],
    'users': [Icons.people_rounded, Icons.groups_rounded, Icons.group_rounded],
    'workspace': [Icons.business_rounded],
    'house': [Icons.home_rounded, Icons.home_outlined],
    'gear': [Icons.settings_rounded, Icons.settings_outlined],
    'cloud': [
      Icons.cloud_rounded,
      Icons.cloud_queue_rounded,
      Icons.cloud_outlined,
    ],
    'cloud-upload': [Icons.backup_rounded, Icons.cloud_upload_rounded],
    'cloud-download': [Icons.cloud_download_rounded],
    'cloud-off': [Icons.cloud_off_rounded],
    'keyboard': [Icons.keyboard_rounded],
    'sparkles': [Icons.auto_awesome_rounded, Icons.auto_fix_high_rounded],
    'globe': [
      Icons.language_rounded,
      Icons.public_rounded,
      Icons.g_mobiledata_rounded,
    ],
    'credit-card': [Icons.credit_card_rounded, Icons.payment_rounded],
    'plan': [Icons.workspace_premium_rounded],
    'history': [
      Icons.history_rounded,
      Icons.restore_rounded,
      Icons.settings_backup_restore_rounded,
    ],
    'clock': [
      Icons.schedule_rounded,
      Icons.access_time_rounded,
      Icons.timer_rounded,
    ],
    'lock': [Icons.lock_rounded, Icons.lock_outline_rounded],
    'lock-open': [Icons.lock_open_rounded],
    'shield': [
      Icons.shield_rounded,
      Icons.shield_outlined,
      Icons.security_rounded,
    ],
    'connections': [Icons.hub_rounded],
    'flag': [Icons.flag, Icons.flag_rounded, Icons.outlined_flag_rounded],
    'scan-document': [
      Icons.document_scanner_rounded,
      Icons.document_scanner_outlined,
      Icons.document_scanner,
    ],
    'file-text': [Icons.description_rounded, Icons.description_outlined],
    'article': [
      Icons.article_rounded,
      Icons.feed_rounded,
      Icons.newspaper_rounded,
    ],
    'input': [Icons.edit_note_rounded, Icons.text_fields_rounded],
    'text': [
      Icons.title_rounded,
      Icons.text_format_rounded,
      Icons.format_size_rounded,
      Icons.format_size_sharp,
      Icons.font_download_rounded,
    ],
    'bullets': [Icons.format_list_bulleted_rounded, Icons.list_rounded],
    'line-numbers': [Icons.format_list_numbered_rounded],
    'line-numbers-off': [Icons.subject_rounded],
    // Verified against Flutter's material/icons.dart, not guessed code points:
    // toc=f023e, queue_music=f00d0, apps=f56d, reorder=f00f3 (rounded cuts).
    'table-of-contents': [Icons.toc_rounded],
    'music-list': [Icons.queue_music_rounded],
    'squares-nine': [Icons.apps_rounded],
    'reorder': [Icons.reorder_rounded],
    'list-checks': [
      Icons.checklist_rounded,
      Icons.checklist_rtl_rounded,
      Icons.assignment_rounded,
      Icons.fact_check_rounded,
    ],
    'rows': [
      Icons.table_rows_rounded,
      Icons.view_list_rounded,
      Icons.list_alt,
      Icons.list_alt_rounded,
      Icons.notes_rounded,
    ],
    'checkbox': [Icons.check_box_rounded],
    'square': [
      Icons.check_box_outline_blank_rounded,
      Icons.check_box_outline_blank,
      Icons.crop_square_rounded,
    ],
    'circle': [
      Icons.radio_button_unchecked_rounded,
      Icons.circle_outlined,
      Icons.circle_rounded,
    ],
    'radio': [Icons.radio_button_checked_rounded],
    'toggle-list': [Icons.arrow_right_rounded],
    'quote': [Icons.format_quote_rounded],
    'code': [
      Icons.code_rounded,
      Icons.terminal_rounded,
      Icons.data_object_rounded,
    ],
    'divider': [Icons.horizontal_rule_rounded, Icons.remove_rounded],
    'emoji': [
      Icons.emoji_emotions_rounded,
      Icons.insert_emoticon_rounded,
      Icons.add_reaction_rounded,
      Icons.emoji_symbols_rounded,
    ],
    'columns-2': [Icons.vertical_split_rounded, Icons.view_sidebar_rounded],
    'columns-3': [Icons.view_column_rounded, Icons.view_week_rounded],
    'table': [
      Icons.grid_on_rounded,
      Icons.table_chart_rounded,
      Icons.grid_4x4_rounded,
    ],
    'squares-four': [
      Icons.grid_view_rounded,
      Icons.view_module_rounded,
      Icons.window_rounded,
    ],
    'layout': [Icons.dashboard_rounded, Icons.auto_awesome_mosaic_rounded],
    'canvas': [Icons.dashboard_customize_rounded],
    'tree': [
      Icons.account_tree_rounded,
      Icons.schema_rounded,
      Icons.account_tree_outlined,
    ],
    'sigma': [Icons.functions_rounded, Icons.calculate_rounded],
    'pen': [
      Icons.draw_rounded,
      Icons.edit_rounded,
      Icons.drive_file_rename_outline_rounded,
      Icons.gesture_rounded,
    ],
    'sticky-note': [Icons.sticky_note_2_rounded],
    'button': [Icons.smart_button_rounded, Icons.touch_app_rounded],
    'gauge': [Icons.speed_rounded],
    'plus-one': [Icons.exposure_plus_1_rounded],
    'cards': [Icons.style_rounded],
    'select': [Icons.arrow_drop_down_circle_rounded],
    'bell-ringing': [
      Icons.notifications_active_rounded,
      Icons.add_alert_rounded,
    ],
    'bell': [Icons.notifications_rounded, Icons.notifications_none_rounded],
    'folder': [Icons.folder_rounded, Icons.folder_outlined],
    'folder-open': [Icons.folder_open_rounded],
    'folder-plus': [Icons.create_new_folder_rounded],
    'folder-upload': [Icons.drive_folder_upload_rounded],
    'folder-move': [Icons.drive_file_move_rounded],
    'file-plus': [Icons.note_add_rounded],
    'file': [Icons.insert_drive_file_rounded],
    'file-pdf': [Icons.picture_as_pdf_rounded],
    'file-doc': [Icons.text_snippet_outlined, Icons.text_snippet_rounded],
    'file-xls': [Icons.table_view_rounded],
    'file-ppt': [Icons.slideshow_rounded],
    'file-zip': [Icons.folder_zip_rounded],
    'file-code': [Icons.integration_instructions_rounded],
    'image': [
      Icons.image_rounded,
      Icons.photo_rounded,
      Icons.photo_outlined,
      Icons.landscape_rounded,
    ],
    'images': [Icons.photo_library_rounded, Icons.collections_rounded],
    'film-strip': [
      Icons.movie_rounded,
      Icons.videocam_rounded,
      Icons.video_library_rounded,
    ],
    'music-note': [
      Icons.audiotrack_rounded,
      Icons.music_note_rounded,
      Icons.audio_file_rounded,
    ],
    'database': [Icons.storage_rounded],
    'book-open': [
      Icons.menu_book_rounded,
      Icons.book_rounded,
      Icons.auto_stories_rounded,
      Icons.import_contacts_rounded,
    ],
    'git-branch': [Icons.source_rounded],
    'kanban': [Icons.view_kanban_rounded],
    'calendar-blank': [
      Icons.calendar_month_rounded,
      Icons.calendar_today_rounded,
      Icons.today_rounded,
      Icons.date_range_rounded,
      Icons.event_rounded,
      Icons.event_note_rounded,
    ],
    'chat-circle': [
      Icons.chat_bubble_outline_rounded,
      Icons.chat_rounded,
      Icons.forum_rounded,
    ],
    'chart-bar': [
      Icons.bar_chart_rounded,
      Icons.insert_chart_rounded,
      Icons.analytics_rounded,
      Icons.insert_chart_outlined_rounded,
    ],
    'map-trifold': [Icons.map_rounded],
    'presentation-chart': [
      Icons.view_carousel_rounded,
      Icons.present_to_all_rounded,
      Icons.co_present_rounded,
    ],
    'graph': [Icons.timeline_rounded],
    'puzzle-piece': [
      Icons.extension_rounded,
      Icons.extension_outlined,
      Icons.widgets_rounded,
      Icons.category_rounded,
    ],
    'magnifying-glass': [Icons.search_rounded, Icons.search],
    'search-list': [Icons.manage_search_rounded, Icons.find_in_page_rounded],
    'check': [Icons.check_rounded, Icons.check, Icons.done, Icons.done_rounded],
    'check-all': [Icons.done_all_rounded],
    'x': [
      Icons.close_rounded,
      Icons.close,
      Icons.clear_rounded,
      Icons.cancel_rounded,
    ],
    'plus': [
      Icons.add_rounded,
      Icons.add,
      Icons.add_circle_outline_rounded,
      Icons.playlist_add_rounded,
    ],
    'dots-three': [
      Icons.more_horiz_rounded,
      Icons.more_horiz,
      Icons.more_vert_rounded,
    ],
    'dots-six-vertical': [Icons.drag_indicator_rounded],
    'caret-left': [
      Icons.chevron_left_rounded,
      Icons.keyboard_arrow_left_rounded,
    ],
    'caret-right': [
      Icons.chevron_right_rounded,
      Icons.keyboard_arrow_right_rounded,
    ],
    'caret-up': [
      Icons.keyboard_arrow_up_rounded,
      Icons.expand_less_rounded,
      Icons.arrow_drop_up_rounded,
    ],
    'caret-down': [
      Icons.keyboard_arrow_down_rounded,
      Icons.expand_more_rounded,
      Icons.arrow_drop_down_rounded,
      Icons.arrow_drop_down,
    ],
    'caret-up-down': [Icons.unfold_more_rounded],
    'collapse': [Icons.unfold_less_rounded],
    'sidebar-simple': [Icons.menu_open_rounded, Icons.menu_rounded],
    'arrow-left': [Icons.arrow_back_rounded, Icons.keyboard_backspace_rounded],
    'arrow-right': [Icons.arrow_forward_rounded, Icons.arrow_right_alt_rounded],
    'arrow-up': [Icons.arrow_upward_rounded, Icons.north_rounded],
    'arrow-down': [Icons.arrow_downward_rounded, Icons.south_rounded],
    'arrow-outward': [Icons.arrow_outward_rounded, Icons.north_east_rounded],
    'arrows-horizontal': [Icons.swap_horiz_rounded],
    'arrows-vertical': [Icons.swap_vert_rounded],
    'external-link': [
      Icons.open_in_new_rounded,
      Icons.launch_rounded,
      Icons.output_rounded,
    ],
    'fullscreen': [
      Icons.open_in_full_rounded,
      Icons.fullscreen_rounded,
      Icons.crop_free_rounded,
    ],
    'fullscreen-exit': [
      Icons.close_fullscreen_rounded,
      Icons.fullscreen_exit_rounded,
    ],
    'fit': [
      Icons.fit_screen_rounded,
      Icons.photo_size_select_large_rounded,
      Icons.center_focus_strong_rounded,
    ],
    'download': [
      Icons.download_rounded,
      Icons.file_download_rounded,
      Icons.save_alt_rounded,
    ],
    'upload': [
      Icons.upload_rounded,
      Icons.file_upload_rounded,
      Icons.upload_file_rounded,
    ],
    'copy': [
      Icons.copy_rounded,
      Icons.content_copy_rounded,
      Icons.copy_all_rounded,
      Icons.folder_copy_rounded,
    ],
    'duplicate': [
      Icons.control_point_duplicate_rounded,
      Icons.library_add_rounded,
    ],
    'paste': [Icons.content_paste_rounded],
    'paste-go': [Icons.content_paste_go_rounded],
    'scissors': [Icons.content_cut_rounded],
    'trash': [
      Icons.delete_outline_rounded,
      Icons.delete_rounded,
      Icons.delete_forever_rounded,
    ],
    'star': [
      Icons.star_rounded,
      Icons.star_border_rounded,
      Icons.star_outline_rounded,
    ],
    'bookmark': [Icons.bookmark_rounded, Icons.bookmark_border_rounded],
    'push-pin': [Icons.push_pin_rounded, Icons.push_pin_outlined],
    'share': [Icons.ios_share_rounded, Icons.share_rounded],
    'eye': [
      Icons.visibility_rounded,
      Icons.preview_rounded,
      Icons.chrome_reader_mode_rounded,
    ],
    'eye-off': [Icons.visibility_off_rounded],
    'info': [
      Icons.info_outline_rounded,
      Icons.info_rounded,
      Icons.help_outline_rounded,
    ],
    'warning': [
      Icons.warning_rounded,
      Icons.error_outline_rounded,
      Icons.warning_amber_rounded,
    ],
    'refresh': [
      Icons.refresh_rounded,
      Icons.sync_rounded,
      Icons.sync,
      Icons.autorenew_rounded,
      Icons.restart_alt_rounded,
    ],
    'undo': [Icons.undo_rounded],
    'redo': [Icons.redo_rounded],
    'sort': [Icons.sort_rounded, Icons.sort_by_alpha_rounded],
    'filter': [Icons.filter_alt_rounded, Icons.filter_list_rounded],
    'filter-off': [Icons.filter_alt_off_rounded, Icons.filter_list_off_rounded],
    'sliders': [Icons.tune_rounded],
    'palette': [
      Icons.palette_rounded,
      Icons.palette_outlined,
      Icons.color_lens_rounded,
      Icons.format_color_fill_rounded,
      Icons.format_color_text_rounded,
    ],
    'paint-off': [Icons.format_color_reset_rounded],
    'format-clear': [Icons.format_clear_rounded],
    'bold': [Icons.format_bold_rounded],
    'italic': [Icons.format_italic_rounded],
    'underline': [Icons.format_underline_rounded],
    'strikethrough': [
      Icons.format_strikethrough_rounded,
      Icons.strikethrough_s_rounded,
    ],
    'align-left': [Icons.format_align_left_rounded],
    'align-center': [Icons.format_align_center_rounded],
    'align-right': [Icons.format_align_right_rounded],
    'align-justify': [Icons.format_align_justify_rounded],
    'indent': [Icons.format_indent_increase_rounded],
    'outdent': [Icons.format_indent_decrease_rounded],
    'ruler': [Icons.straighten_rounded],
    'width': [Icons.width_normal_rounded, Icons.width_wide_rounded],
    'spacing': [Icons.linear_scale_rounded, Icons.space_bar_rounded],
    'aspect-ratio': [
      Icons.aspect_ratio_rounded,
      Icons.crop_16_9_rounded,
      Icons.crop_landscape_rounded,
      Icons.crop_7_5_rounded,
    ],
    'crop': [Icons.crop_rounded],
    'location': [Icons.place_rounded, Icons.location_on_rounded],
    'target': [
      Icons.my_location_rounded,
      Icons.track_changes_rounded,
      Icons.gps_fixed_rounded,
    ],
    'waveform': [Icons.graphic_eq_rounded],
    'translate': [Icons.translate_rounded],
    'hash': [Icons.tag_rounded, Icons.numbers_rounded, Icons.pin_rounded],
    'tag': [Icons.label_outline_rounded, Icons.label_rounded],
    'bolt': [Icons.bolt_rounded, Icons.flash_on_rounded],
    'play': [Icons.play_arrow_rounded, Icons.play_circle_outline_rounded],
    'pause': [Icons.pause_rounded],
    'stop': [Icons.stop_rounded],
    'layers': [Icons.layers_rounded],
    'archive': [Icons.inventory_2_rounded, Icons.archive_rounded],
    'envelope-simple': [Icons.mail_rounded, Icons.email_rounded],
    'mail-unread': [Icons.mark_email_unread_rounded],
    'mail-read': [Icons.mark_email_read_rounded, Icons.drafts_rounded],
    'mail-forward': [Icons.forward_to_inbox_rounded],
    'inbox': [Icons.inbox_rounded],
    'link-simple': [Icons.link_rounded, Icons.insert_link_rounded],
    'link-add': [Icons.add_link_rounded],
    'unlink': [Icons.link_off_rounded],
    'image-plus': [Icons.add_photo_alternate_rounded],
    'broom': [Icons.cleaning_services_rounded],
    'block': [Icons.block_rounded, Icons.do_not_disturb_alt_rounded],
    'backspace': [Icons.backspace_rounded],
    'minus-circle': [Icons.remove_circle_outline_rounded],
    'spellcheck': [Icons.spellcheck_rounded],
    'attachment': [Icons.attach_file_rounded],
    'caption': [Icons.closed_caption_off_rounded],
    'align-objects-left': [Icons.align_horizontal_left_rounded],
    'align-objects-center': [Icons.align_horizontal_center_rounded],
    'align-objects-right': [Icons.align_horizontal_right_rounded],
    'align-objects-top': [Icons.align_vertical_top_rounded],
    'align-objects-middle': [Icons.align_vertical_center_rounded],
    'align-objects-bottom': [Icons.align_vertical_bottom_rounded],
    'distribute-horizontal': [Icons.horizontal_distribute_rounded],
    'distribute-vertical': [Icons.vertical_distribute_rounded],
    'insert-above': [Icons.vertical_align_top_rounded],
    'insert-below': [Icons.vertical_align_bottom_rounded],
    'select-all': [Icons.select_all_rounded],
    'line-style': [Icons.line_style_rounded],
    'sign-out': [Icons.logout_rounded],
    'camera': [Icons.photo_camera_back_rounded, Icons.camera_alt_rounded],
    'merge': [Icons.merge_type_rounded],
    'at': [Icons.alternate_email_rounded],
    'search-off': [Icons.search_off_rounded],
    'check-circle': [
      Icons.check_circle_rounded,
      Icons.check_circle_outline_rounded,
    ],
    'bookmarks': [Icons.bookmarks_rounded],
    'chart-line': [Icons.show_chart_rounded, Icons.trending_up_rounded],
    'chart-stacked': [Icons.stacked_line_chart_rounded],
    'chart-stacked-bar': [Icons.stacked_bar_chart_rounded],
    'chart-area': [Icons.area_chart_rounded],
    'chart-scatter': [Icons.scatter_plot_rounded],
    'donut': [Icons.donut_large_rounded],
    'chart-pie': [Icons.pie_chart_rounded],
    'legend': [Icons.legend_toggle_rounded],
    'bubbles': [Icons.blur_circular_rounded, Icons.bubble_chart_rounded],
    'compass': [Icons.explore_rounded, Icons.travel_explore_rounded],
    'location-plus': [
      Icons.add_location_alt_rounded,
      Icons.edit_location_alt_rounded,
    ],
    'group': [Icons.workspaces_rounded],
    'infinity': [Icons.all_inclusive_rounded],
    'repeat': [Icons.repeat_rounded, Icons.flip_camera_android_rounded],
    'density-medium': [
      Icons.density_medium_rounded,
      Icons.view_agenda_rounded,
      Icons.view_day_rounded,
      Icons.view_stream_rounded,
    ],
    'density-small': [
      Icons.density_small_rounded,
      Icons.short_text_rounded,
    ],
    'triangle': [Icons.change_history_rounded],
    'priority': [Icons.priority_high_rounded],
    'password': [Icons.password_rounded],
    'height': [Icons.height_rounded],
    'motion-off': [Icons.motion_photos_off_rounded],
    'power': [Icons.power_settings_new_rounded],
    'layers-clear': [Icons.layers_clear_rounded],
    'skip-next': [Icons.skip_next_rounded],
    'rotate': [Icons.rotate_90_degrees_cw_rounded],
    'print': [Icons.print_rounded],
    'page-portrait': [Icons.crop_portrait_rounded],
    'fade': [Icons.gradient_rounded, Icons.blur_on_rounded],
    'swipe-up': [Icons.swipe_up_alt_rounded],
    'rocket': [Icons.rocket_launch_rounded],
    'savings': [Icons.savings_rounded],
    'school': [Icons.school_rounded],
    'flame': [Icons.local_fire_department_rounded],
    'handshake': [Icons.handshake_rounded],
    'calendar-edit': [Icons.edit_calendar_rounded],
    'insights': [Icons.insights_rounded],
    'rounded-corner': [Icons.rounded_corner_rounded],
    'brush': [Icons.brush_rounded],
    'droplet': [Icons.water_drop_outlined],
    'first-page': [Icons.first_page_rounded],
    'last-page': [Icons.last_page_rounded],
    'return': [Icons.keyboard_return_rounded],
    'rule': [Icons.rule_rounded],
    'bulb': [Icons.lightbulb_rounded],
    'bell-off': [Icons.notifications_off_rounded],
    'snooze': [Icons.snooze_rounded],
    'cloud-sync': [Icons.cloud_sync_rounded],
    'cloud-check': [Icons.cloud_done_rounded],
    'lock-clock': [Icons.lock_clock_rounded],
    'zoom-in': [Icons.zoom_in_rounded],
    'zoom-out': [Icons.zoom_out_rounded],
    'branch-arrow': [Icons.subdirectory_arrow_right_rounded],
    'toggle': [Icons.toggle_on_rounded],
    'hourglass': [Icons.hourglass_bottom_rounded],
    'sun': [Icons.wb_sunny_rounded],
    'campaign': [Icons.campaign_rounded],
    'wallet': [Icons.payments_rounded],
    'briefcase': [Icons.work_rounded, Icons.work_outline_rounded],
    'route': [Icons.route_rounded],
  };

  // Compare path stems, not FlowySvgData identity: generated and reconstructed
  // data objects must resolve identically, including after a cold start.
  static const _svgNames = <String, String>{
    'settings_page_user': 'user',
    'settings_page_users': 'users',
    'settings_page_workspace': 'workspace',
    'settings_page_database': 'database',
    'settings_page_bell': 'bell',
    'settings_page_cloud': 'cloud',
    'settings_page_keyboard': 'keyboard',
    'settings_page_ai': 'sparkles',
    'settings_page_earth': 'globe',
    'settings_page_plan': 'plan',
    'settings_page_credit_card': 'credit-card',
    'slash_menu_icon_text': 'text',
    'slash_menu_icon_h1': 'heading-1',
    'slash_menu_icon_h2': 'heading-2',
    'slash_menu_icon_h3': 'heading-3',
    'toggle_heading1': 'toggle-heading-1',
    'toggle_heading2': 'toggle-heading-2',
    'toggle_heading3': 'toggle-heading-3',
    'slash_menu_icon_bulleted_list': 'bullets',
    'slash_menu_icon_numbered_list': 'numbered-list',
    'slash_menu_icon_checkbox': 'checkbox',
    'slash_menu_icon_toggle': 'toggle-list',
    'slash_menu_icon_quote': 'quote',
    'slash_menu_icon_callout': 'info',
    'slash_menu_icon_code_block': 'code',
    'slash_menu_icon_divider': 'divider',
    'slash_menu_icon_emoji_picker': 'emoji',
    'slash_menu_icon_two_columns': 'columns-2',
    'slash_menu_icon_three_columns': 'columns-3',
    'slash_menu_icon_four_columns': 'columns-4',
    'slash_menu_icon_grid': 'table',
    'slash_menu_icon_simple_table': 'table',
    'slash_menu_icon_kanban': 'kanban',
    'slash_menu_icon_calendar': 'calendar-blank',
    'slash_menu_icon_calendar_1': 'calendar-blank',
    'slash_menu_icon_date_or_reminder': 'calendar-blank',
    'slash_menu_icon_doc': 'file-text',
    'slash_menu_icon_file': 'file',
    'slash_menu_icon_image': 'image',
    'slash_menu_image': 'image',
    'slash_menu_icon_photo_gallery': 'images',
    'slash_menu_icon_visuals': 'images',
    'slash_menu_icon_math_equation': 'sigma',
    'slash_menu_icon_ai': 'sparkles',
    'slash_menu_icon_ai_writer': 'sparkles',
    'slash_menu_icon_outline': 'rows',
    'toolbar_ai_ask_anything': 'sparkles',
    'toolbar_ai_writer': 'sparkles',
    'toolbar_ai_improve_writing': 'pen',
    'toolbar_ai_fix_spelling_grammar': 'spellcheck',
    'toolbar_ai_explain': 'info',
    'toolbar_ai_make_shorter': 'collapse',
    'toolbar_ai_make_longer': 'caret-up-down',
    'ai_writer': 'sparkles',
    'ai_writer_color': 'sparkles',
    'ai': 'sparkles',
    'page_preview': 'article',
    'insert_document': 'file-plus',
    'ai_add_to_page': 'file-plus',
    'type_page': 'file-text',
    'icon_document': 'file-text',
    'document': 'file-text',
    'icon_code_block': 'code',
    'text': 'text',
    'number': 'hash',
    'date': 'calendar-blank',
    'time': 'clock',
    'timer_start': 'clock',
    'ai_summary': 'sparkles',
    'ai_translate': 'translate',
    'media': 'attachment',
    'checkbox': 'checkbox',
    'checklist': 'list-checks',
    'select': 'select',
    'multiselect': 'list-checks',
    'url': 'link-simple',
    'link': 'link-simple',
    'relation': 'connections',
    'folder': 'folder',
    'folder_open': 'folder-open',
    'grid': 'table',
    'board': 'kanban',
    'calendar': 'calendar-blank',
    'image': 'image',
    'ft_audio': 'music-note',
    'ft_video': 'film-strip',
    'ft_image': 'image',
    'ft_document': 'file-text',
    'ft_pdf': 'file-pdf',
    'ft_file': 'file',
    'drag_element': 'dots-six-vertical',
    'three_dots': 'dots-three',
    'workspace_three_dots': 'dots-three',
    'toolbar_more': 'dots-three',
    'more': 'caret-down',
    'add': 'plus',
    'add_icon': 'emoji',
    'change_icon': 'emoji',
    'add_cover': 'image-plus',
    'add_workspace': 'folder-plus',
    'space_add': 'folder-plus',
    'space_manage': 'sliders',
    'space_lock': 'lock',
    'lock_page': 'lock',
    'collapse_all_page': 'collapse',
    'favorite_pin': 'push-pin',
    'workspace_selected': 'check',
    'published_checkmark': 'check',
    'check': 'check',
    'toolbar_check': 'check',
    'download': 'download',
    'upload': 'upload',
    'copy': 'copy',
    'duplicate': 'duplicate',
    'paste': 'paste',
    'cut': 'scissors',
    'm_table_quick_action_cut': 'scissors',
    'trash': 'trash',
    'delete': 'trash',
    'edit': 'pen',
    'view_item_rename': 'pen',
    'view_item_move_to': 'folder-move',
    'information': 'info',
    'settings': 'gear',
    'logout': 'sign-out',
    'workspace_logout': 'sign-out',
    'share_publish': 'globe',
    'turninto': 'arrows-horizontal',
    'color_format': 'palette',
    'table_align_left': 'align-left',
    'table_align_center': 'align-center',
    'table_align_right': 'align-right',
    'table_align_justify': 'align-justify',
    'table_insert_above': 'insert-above',
    'table_insert_below': 'insert-below',
    'table_insert_left': 'insert-left',
    'table_insert_right': 'insert-right',
    'table_reorder_column': 'arrows-horizontal',
    'table_reorder_row': 'arrows-vertical',
    'table_delete_column': 'minus-circle',
    'table_delete_row': 'minus-circle',
    'table_delete': 'trash',
    'table_clear': 'backspace',
    'toolbar_bold': 'bold',
    'toolbar_italic': 'italic',
    'toolbar_underline': 'underline',
    'toolbar_strikethrough': 'strikethrough',
    'toolbar_link': 'link-simple',
    'toolbar_link_unlink': 'unlink',
    'toolbar_code': 'code',
    'toolbar_undo': 'undo',
    'toolbar_redo': 'redo',
    'toolbar_extract_text': 'scan-document',
    'extract_text': 'scan-document',
    'document_scanner': 'scan-document',
    'arrow_left': 'arrow-left',
    'arrow_right': 'arrow-right',
    'arrow_up': 'arrow-up',
    'arrow_down': 'arrow-down',
    'arrow': 'arrow-up',
    'sort_ascending': 'arrow-up',
    'sort_descending': 'arrow-down',
    'search': 'magnifying-glass',
    'magnifier': 'magnifying-glass',
    'close': 'x',
    'ai_page': 'file-text',
    'chat_ai_page': 'ai-chat',
    'ai_attachment': 'attachment',
    'embed_fullscreen': 'fullscreen',
    'share': 'share',
    'share_tab_copy': 'link-simple',
    'tag': 'tag',
    'single_select': 'select',
    'm_table_quick_action_copy': 'copy',
    'm_table_quick_action_paste': 'paste',
    'm_table_quick_action_delete': 'trash',
    'm_table_duplicate': 'duplicate',
    'm_copy_link': 'link-simple',
    'm_aa_bold': 'bold',
    'm_aa_bulleted_list': 'bullets',
    'm_aa_align_left': 'align-left',
    'm_aa_align_center': 'align-center',
    'm_aa_align_right': 'align-right',
    'table_clear_content': 'backspace',
    'table_header_row': 'rows',
    'table_header_column': 'columns-2',
    'table_set_to_page_width': 'width',
    'table_distribute_columns_evenly': 'distribute-horizontal',
    'toolbar_inline_code': 'code',
    'toolbar_inline_italic': 'italic',
    'toolbar_text_format': 'text',
    'toolbar_text_color': 'palette',
    'toolbar_text_highlight': 'brush',
    'toolbar_link_edit': 'pen',
    'toolbar_link_earth': 'globe',
    'toolbar_text_align_left': 'align-left',
    'toolbar_text_align_center': 'align-center',
    'toolbar_text_align_right': 'align-right',
    'toolbar_align_left': 'align-left',
    'toolbar_align_center': 'align-center',
    'toolbar_align_right': 'align-right',
    'type_text': 'text',
    'type_font': 'text',
    'type_h1': 'heading-1',
    'type_h2': 'heading-2',
    'type_h3': 'heading-3',
    'type_bulleted_list': 'bullets',
    'type_numbered_list': 'numbered-list',
    'type_toggle_list': 'toggle-list',
    'type_toggle_h1': 'toggle-heading-1',
    'type_toggle_h2': 'toggle-heading-2',
    'type_toggle_h3': 'toggle-heading-3',
    'type_todo': 'checkbox',
    'type_callout': 'info',
    'type_quote': 'quote',
    'type_formula': 'sigma',
    'type_strikethrough': 'strikethrough',
    'icon_grid': 'table',
    'icon_board': 'kanban',
    'icon_calendar': 'calendar-blank',
    'icon_delete': 'trash',
    'icon_import': 'download',
    'icon_template': 'layout',
    'icon_math_eq': 'sigma',
    'view_item_open_in_new_tab': 'external-link',
    'database_layout': 'layout',
    'database_filter': 'filter',
    'database_sort': 'sort',
    'database_fullscreen': 'external-link',
    'database_settings_arrow_right': 'caret-right',
    'calendar_layout': 'calendar-blank',
    'properties': 'sliders',
    'group': 'group',
    'restore': 'history',
    'reload': 'refresh',
    'hide': 'eye-off',
    'show': 'eye',
    'favorite': 'star',
    'favorited': 'star',
    'unfavorite': 'star',
    'three_dots_vertical': 'dots-three',
    'ft_archive': 'file-zip',
    'ft_text': 'file-text',
    'ft_link': 'link-simple',
    'file_upload': 'upload',
    'full_view': 'fullscreen',
    'export_html': 'code',
    'export_markdown': 'file-text',
    'font_family': 'text',
    'keyboard_arrow_down': 'caret-down',
    'keyboard_arrow_up': 'caret-up',
    'keyboard_arrow_left': 'caret-left',
    'keyboard_arrow_right': 'caret-right',
  };
}
