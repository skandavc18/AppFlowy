import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

// Literal review snapshots, deliberately NOT derived from the implementation.
// A new default needs a reviewed name AND an explicit/utility coverage decision.
const _originalDefaults = '''
magnifying-glass note-pencil house plus dots-three dots-six-vertical
caret-right caret-down caret-up-down sidebar-simple trash layout puzzle-piece
push-pin gear bell file-text folder folder-open table kanban calendar-blank
chat-circle ai-chat chart-bar map-trifold presentation-chart graph article
list-checks squares-four envelope-simple book-open images git-branch database
link-simple file file-pdf file-doc file-xls file-ppt file-zip file-code file-csv
file-markdown file-html file-json file-notebook image film-strip music-note
user users workspace cloud cloud-upload cloud-download cloud-off keyboard
sparkles globe credit-card plan history clock lock lock-open shield connections
flag scan-document text heading-1 heading-2 heading-3 toggle-heading-1
toggle-heading-2 toggle-heading-3 bullets numbered-list line-numbers
line-numbers-off table-of-contents music-list squares-nine reorder checkbox
square circle radio toggle-list quote code divider emoji columns-2 columns-3
columns-4 rows tree sigma pen sticky-note button gauge plus-one cards input
select bell-ringing canvas check check-all x caret-left caret-up collapse
arrow-left arrow-right arrow-up arrow-down arrow-outward arrows-horizontal
arrows-vertical external-link fullscreen fullscreen-exit fit download upload
folder-plus folder-upload folder-move file-plus copy duplicate paste paste-go
scissors star bookmark share eye eye-off info warning refresh undo redo sort
filter filter-off sliders palette paint-off format-clear bold italic underline
strikethrough align-left align-center align-right align-justify indent outdent
ruler width spacing aspect-ratio crop location target waveform translate hash
tag bolt play pause stop layers archive mail-unread mail-read mail-forward inbox
link-add unlink image-plus broom block backspace minus-circle book-plus
spellcheck attachment caption align-objects-left align-objects-center
align-objects-right align-objects-top align-objects-middle align-objects-bottom
distribute-horizontal distribute-vertical insert-above insert-below insert-left
insert-right select-all line-style sign-out camera merge at window search-list
search-off check-circle bookmarks chart-line chart-stacked chart-stacked-bar
chart-area chart-scatter donut chart-pie legend bubbles compass location-plus
group infinity repeat density-medium density-small triangle priority password
height motion-off power layers-clear skip-next rotate print page-portrait fade
swipe-up rocket savings school flame handshake calendar-edit insights
rounded-corner brush droplet first-page last-page return rule bulb bell-off
snooze cloud-sync cloud-check lock-clock zoom-in zoom-out branch-arrow toggle
hourglass sun campaign wallet briefcase route
''';

const _addedDefaults = '''
find-replace replace-all rotate-ccw flip-horizontal flip-vertical fit-page
actual-size help error highlight marker-number bookmark-plus location-off
puzzle-off cursor hand-pan image-broken image-off polyline commit rebase
time-progress lock-off shuffle skip-previous check-off tag-off signal user-plus
shield-info inboxes clipboard-check scales brackets fog snowflake storm
calendar-off calendar-check books key folder-off intersection replay rewind-5
forward-5 playback-speed high-definition tab-key currency-dollar percent borders
borders-none volume volume-off suitcase bank receipt cutlery science badge bug
tab moon history-search microchip computer paw food running city workspace-home
brain server unarchive alarm pin-off star-off checkbox-indeterminate
divider-vertical direction-ltr direction-rtl direction-auto key-command key-shift
key-option paragraph text-image thumb-up thumb-down send keyboard-hide
keyboard-show globe-off dots-two-vertical dock-left chevrons-left chevrons-right
''';

// Tiny navigation, typography, geometry and lower-frequency specialty marks.
// This exact allowlist prevents a missing common-action illustration from
// silently becoming "complete" just because utility-name can be generated.
const _utilityDefaults = '''
dots-three dots-six-vertical caret-right caret-down caret-up-down sidebar-simple
credit-card plan heading-1 heading-2 heading-3 toggle-heading-1 toggle-heading-2
toggle-heading-3 bullets numbered-list line-numbers line-numbers-off
table-of-contents music-list squares-nine reorder square circle radio toggle-list
quote code divider emoji columns-2 columns-3 columns-4 rows sticky-note button
gauge plus-one cards input check check-all x caret-left caret-up collapse
arrow-left arrow-right arrow-up arrow-down arrow-outward arrows-horizontal
arrows-vertical paint-off format-clear bold italic underline strikethrough
align-left align-center align-right align-justify indent outdent spacing
aspect-ratio waveform translate layers block backspace minus-circle book-plus
spellcheck caption align-objects-left align-objects-center align-objects-right
align-objects-top align-objects-middle align-objects-bottom distribute-horizontal
distribute-vertical insert-above insert-below insert-left insert-right select-all
line-style sign-out merge at window check-circle bookmarks chart-line
chart-stacked chart-stacked-bar chart-area chart-scatter donut legend bubbles
group infinity repeat density-medium density-small triangle priority password
height motion-off power layers-clear page-portrait fade swipe-up savings flame
insights rounded-corner droplet first-page last-page return rule snooze lock-clock
branch-arrow toggle hourglass campaign route brackets intersection high-definition
tab-key currency-dollar percent borders borders-none checkbox-indeterminate
divider-vertical direction-ltr direction-rtl direction-auto key-command key-shift
key-option paragraph keyboard-hide keyboard-show dots-two-vertical dock-left
chevrons-left chevrons-right
''';

const _newIllustrations = '''
find-replace replace-all fit fit-page actual-size width rotate rotate-ccw print
zoom-in zoom-out crop flip-horizontal flip-vertical fullscreen fullscreen-exit
highlight marker-number scan-document hierarchy share external-link duplicate
paste-go file-plus folder-plus folder-upload folder-move folder-off archive-box
unarchive eye eye-off search-list search-off filter-off sliders lock-open lock-off
info help warning error star bookmark-plus star-off pin-off tag tag-off link-add
unlink image-plus image-broken image-off location location-plus location-off
calendar-edit calendar-check calendar-off bell-ringing bell-off cloud-upload
cloud-download cloud-sync cloud-check cloud-off shield-info user-plus inbox
inboxes mail-read mail-unread mail-forward send alarm undo redo replay rewind-5
forward-5 play pause stop skip-next skip-previous shuffle volume volume-off
playback-speed broom brush measure commit rebase server computer brain puzzle-off
cursor hand-pan polyline time-progress signal check-off clipboard-check scales
fog snowflake storm bank receipt cutlery badge bug tab history-search paw food
city workspace-home text-image thumb-up thumb-down globe-off
''';

void main() {
  test('exact default inventory and explicit/utility partition are complete',
      () {
    final expected = [
      ..._words(_originalDefaults),
      ..._words(_addedDefaults),
      'unknown',
    ];
    final utilities = _words(_utilityDefaults);
    expect(expected.toSet(), hasLength(expected.length));
    expect(utilities.toSet(), hasLength(utilities.length));
    expect(defaultIconNames, unorderedEquals(expected));
    expect(defaultIconNames, hasLength(380));
    expect(_words(_originalDefaults), hasLength(281));
    expect(_words(_addedDefaults), hasLength(98));
    expect(expected, containsAll(utilities));

    final actualUtilities = <String>[];
    for (final name in expected.where((name) => name != 'unknown')) {
      final counterpart = WorkspaceGlyphs.vividNameFor(name);
      expect(counterpart, isNotNull, reason: name);
      final artwork = vividIconSvg(counterpart!);
      expect(artwork, isNotNull, reason: '$name -> $counterpart');
      expect(artwork, isNot(defaultIconSvg(name)), reason: name);
      if (counterpart.startsWith('utility-')) {
        actualUtilities.add(name);
        expect(counterpart, 'utility-$name', reason: name);
      } else {
        expect(hasVividIllustration(counterpart), isTrue, reason: name);
      }
      _validateSvg(artwork!, name);
    }
    expect(actualUtilities, unorderedEquals(utilities));
    expect(WorkspaceGlyphs.mappedDefaultNames, isNot(contains('unknown')));
    expect(expected, containsAll(WorkspaceGlyphs.mappedDefaultNames));
    for (final icon in WorkspaceGlyphs.mappedIcons) {
      expect(
        defaultIconSvg(WorkspaceGlyphs.nameForIcon(icon)!),
        isNotNull,
        reason: '${icon.fontFamily}/${icon.codePoint}',
      );
    }
    for (final stem in WorkspaceGlyphs.mappedSvgNames) {
      final name = WorkspaceGlyphs.nameForSvg(
        FlowySvgData('assets/flowy_icons/16x/$stem.svg'),
      );
      expect(name, isNotNull, reason: stem);
      expect(defaultIconSvg(name!), isNotNull, reason: stem);
    }
  });

  test('125 new illustrations are distinct geometry, not recolored utilities',
      () {
    final additions = _words(_newIllustrations);
    expect(additions, hasLength(125));
    expect(additions.toSet(), hasLength(125));
    final saved = appFlowyVividIconGroups
        .expand((group) => group.icons)
        .map((icon) => icon.name)
        .toList();
    expect(saved, hasLength(150));
    expect(vividIllustrationNames, hasLength(275));
    expect(vividIllustrationNames.toSet(), hasLength(275));
    expect(
      vividIllustrationNames.toSet().difference(saved.toSet()),
      additions.toSet(),
    );
    expect(saved.toSet().intersection(additions.toSet()), isEmpty);
    final geometryOwners = <String, String>{};
    const defaultNames = {
      'hierarchy': 'tree',
      'archive-box': 'archive',
      'measure': 'ruler',
    };
    for (final name in additions) {
      final defaultName = defaultNames[name] ?? name;
      expect(WorkspaceGlyphs.vividNameFor(defaultName), name);
      final content = vividIconSvg(name)!;
      final root = _validateSvg(content, name);
      final geometry = jsonEncode(_geometry(root));
      expect(
        geometryOwners.containsKey(geometry),
        isFalse,
        reason: '$name must not just recolor ${geometryOwners[geometry]}',
      );
      geometryOwners[geometry] = name;
      for (final source in [
        defaultIconSvg(defaultName)!,
        vividIconSvg('utility-$defaultName')!,
      ]) {
        expect(
          geometry,
          isNot(jsonEncode(_geometry(XmlDocument.parse(source).rootElement))),
          reason: '$name is a new drawing, not the outline with another tint',
        );
      }
      final paint = root.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local != 'stop')
          .expand((element) => element.attributes)
          .map((attribute) => attribute.value)
          .toSet();
      expect(paint, containsAll(['url(#main)', 'url(#accent)']), reason: name);
    }
  });

  test('source-discovered Material actions retain their precise meanings', () {
    final cases = <IconData, String>{
      Icons.find_replace_rounded: 'find-replace',
      Icons.change_circle_rounded: 'replace-all',
      Icons.rotate_90_degrees_cw_rounded: 'rotate',
      Icons.rotate_90_degrees_ccw_rounded: 'rotate-ccw',
      Icons.flip_rounded: 'flip-horizontal',
      Icons.fit_screen_rounded: 'fit',
      Icons.width_wide_rounded: 'width',
      Icons.print_rounded: 'print',
      Icons.zoom_in_rounded: 'zoom-in',
      Icons.zoom_out_rounded: 'zoom-out',
      Icons.crop_rounded: 'crop',
      Icons.highlight_alt_rounded: 'highlight',
      Icons.filter_1_rounded: 'marker-number',
      Icons.document_scanner_rounded: 'scan-document',
      Icons.help_outline_rounded: 'help',
      Icons.info_rounded: 'info',
      Icons.account_tree_rounded: 'tree',
      Icons.dns_rounded: 'server',
      Icons.key_rounded: 'key',
      Icons.bookmark_add_rounded: 'bookmark-plus',
      Icons.image_not_supported_outlined: 'image-broken',
      Icons.hide_image_rounded: 'image-off',
      Icons.folder_off_rounded: 'folder-off',
      Icons.extension_off_rounded: 'puzzle-off',
      Icons.commit_rounded: 'commit',
      Icons.low_priority_rounded: 'rebase',
      Icons.remove_done_rounded: 'check-off',
      Icons.label_off_rounded: 'tag-off',
      Icons.event_busy_rounded: 'calendar-off',
      Icons.event_available_rounded: 'calendar-check',
      Icons.volume_up_rounded: 'volume',
      Icons.volume_off_rounded: 'volume-off',
      Icons.replay_5_rounded: 'rewind-5',
      Icons.forward_5_rounded: 'forward-5',
      Icons.skip_previous_rounded: 'skip-previous',
      Icons.skip_next_rounded: 'skip-next',
      Icons.shelves: 'books',
      Icons.home_work_rounded: 'workspace-home',
    };
    expect(cases.values.toSet(), hasLength(cases.length));
    for (final entry in cases.entries) {
      expect(WorkspaceGlyphs.nameForIcon(entry.key), entry.value);
      expect(WorkspaceGlyph(entry.key).name, entry.value);
      expect(
        WorkspaceGlyphs.vividNameFor(entry.value),
        isNot(startsWith('utility-')),
        reason: entry.value,
      );
    }
    // This glyph is intentionally ambiguous across PDF, image and canvas.
    // Supply .named('fit-page')/.named('actual-size') at those callers instead.
    expect(WorkspaceGlyphs.nameForIcon(Icons.crop_free_rounded), 'fullscreen');
    for (final group in [
      ['fit', 'fit-page', 'actual-size', 'width', 'fullscreen'],
      ['find-replace', 'replace-all', 'magnifying-glass', 'refresh'],
      ['rotate', 'rotate-ccw', 'flip-horizontal', 'flip-vertical'],
      ['info', 'help', 'warning', 'error'],
    ]) {
      final pictures = group.map(
        (name) => vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!),
      );
      expect(pictures.toSet(), hasLength(group.length), reason: '$group');
    }
    expect(defaultIconSvg('rotate'), contains('M3 10a9 9 0 0 1'));
    expect(defaultIconSvg('rotate-ccw'), contains('M21 10a9 9 0 0 0'));
    expect(vividIconSvg('rotate'), contains('M5 13A12 12 0 0 1'));
    expect(vividIconSvg('rotate-ccw'), contains('M27 13A12 12 0 0 0'));
  });

  test('legacy SVG aliases use generated paths and actual artwork meanings',
      () {
    final cases = <FlowySvgData, String>{
      FlowySvgs.icon_shuffle_s: 'shuffle',
      FlowySvgs.m_field_copy_s: 'copy',
      FlowySvgs.check_filled_s: 'checkbox',
      FlowySvgs.uncheck_s: 'square',
      FlowySvgs.unable_select_s: 'checkbox',
      FlowySvgs.clock_alarm_s: 'alarm',
      FlowySvgs.notification_unarchive_s: 'unarchive',
      FlowySvgs.notification_archive_s: 'archive',
      FlowySvgs.remove_from_recent_s: 'minus-circle',
      FlowySvgs.details_s: 'dots-two-vertical',
      FlowySvgs.details_horizontal_s: 'dots-three',
      FlowySvgs.hamburger_s_s: 'density-medium',
      FlowySvgs.pull_left_outlined_s: 'dock-left',
      FlowySvgs.arrow_tight_s: 'caret-down',
      FlowySvgs.show_menu_s: 'chevrons-right',
      FlowySvgs.open_folder_lg: 'folder-open',
      FlowySvgs.textdirection_ltr_m: 'direction-ltr',
      FlowySvgs.textdirection_rtl_m: 'direction-rtl',
      FlowySvgs.textdirection_auto_m: 'direction-auto',
      FlowySvgs.keyboard_meta_s: 'key-command',
      FlowySvgs.keyboard_option_s: 'key-option',
      FlowySvgs.ai_like_s: 'thumb-up',
      FlowySvgs.ai_dislike_s: 'thumb-down',
    };
    for (final entry in cases.entries) {
      expect(WorkspaceGlyphs.nameForSvg(entry.key), entry.value);
      expect(WorkspaceGlyph.svg(entry.key).name, entry.value);
    }
    expect(
      WorkspaceGlyphs.nameForSvg(
        const FlowySvgData(r'assets\flowy_icons\32x\OPEN-FOLDER_lg.svg'),
      ),
      'folder-open',
    );
  });

  test('same-spelled saved art is not substituted for an unrelated action', () {
    const aliases = {
      'tree': 'hierarchy',
      'archive': 'archive-box',
      'file-zip': 'archive',
      'ruler': 'measure',
      'link-simple': 'link',
      'bookmark': 'bookmark',
      'inbox': 'inbox',
      'envelope-simple': 'mail',
      'school': 'graduation-cap',
      'chart-pie': 'pie-chart',
    };
    for (final entry in aliases.entries) {
      expect(WorkspaceGlyphs.vividNameFor(entry.key), entry.value);
    }
    for (final group in appFlowyVividIconGroups) {
      for (final icon in group.icons) {
        expect(icon.content, vividIconSvg(icon.name));
        expect(icon.name, isNot(startsWith('utility-')));
      }
    }
    expect(vividIconSvg('tree'), isNot(vividIconSvg('hierarchy')));
    expect(vividIconSvg('archive'), isNot(vividIconSvg('archive-box')));
    expect(vividIconSvg('ruler'), isNot(vividIconSvg('measure')));
  });

  test('unknowns cannot become plausible but unrelated utility artwork', () {
    for (final name in [
      '',
      'unknown',
      'no-such-action',
      'find_replace',
      'utility-fit',
      'terminal', // A saved illustration, but NOT a default semantic identity.
    ]) {
      expect(WorkspaceGlyphs.vividNameFor(name), isNull, reason: name);
    }
    expect(hasVividIllustration('terminal'), isTrue);
    expect(hasVividIllustration('utility-fit'), isFalse);
    expect(vividIconSvg('utility-unknown'), isNull);
    expect(vividIconSvg('utility-no-such-action'), isNull);
    expect(vividIconSvg('no-such-action'), isNull);
    expect(
      WorkspaceGlyphs.nameForIcon(
        const IconData(0xffff, fontFamily: 'FutureAction'),
      ),
      isNull,
    );
    expect(
      WorkspaceGlyphs.nameForSvg(
        const FlowySvgData('assets/flowy_icons/16x/future_action.svg'),
      ),
      isNull,
    );
  });
}

List<String> _words(String source) => source.trim().split(RegExp(r'\s+'));

XmlElement _validateSvg(String source, String reason) {
  final root = XmlDocument.parse(source).rootElement;
  expect(root.name.local, 'svg', reason: reason);
  expect(root.getAttribute('viewBox'), '0 0 32 32', reason: reason);
  expect(source.toLowerCase(), isNot(contains('currentcolor')), reason: reason);
  expect(source.toUpperCase(), isNot(contains('<!DOCTYPE')), reason: reason);
  final elements = [root, ...root.descendants.whereType<XmlElement>()];
  const forbidden = {
    'image',
    'use',
    'filter',
    'script',
    'style',
    'foreignObject'
  };
  expect(
    elements.where((element) => forbidden.contains(element.name.local)),
    isEmpty,
    reason: reason,
  );
  for (final attribute in elements.expand((element) => element.attributes)) {
    expect(attribute.name.local.toLowerCase(), isNot('href'), reason: reason);
    expect(attribute.name.local, isNot(startsWith('on')), reason: reason);
  }
  final ids = elements
      .map((element) => element.getAttribute('id'))
      .whereType<String>()
      .toList();
  expect(ids.toSet(), hasLength(ids.length), reason: reason);
  final usedIds = <String>{};
  for (final match in RegExp(r'url\(([^)]*)\)').allMatches(source)) {
    final id = match.group(1)!;
    expect(id, startsWith('#'), reason: reason);
    expect(ids, contains(id.substring(1)), reason: reason);
    usedIds.add(id.substring(1));
  }
  final gradients = root.findAllElements('linearGradient').toList();
  expect(gradients, isNotEmpty, reason: reason);
  for (final gradient in gradients) {
    expect(usedIds, contains(gradient.getAttribute('id')), reason: reason);
    expect(gradient.getAttribute('gradientUnits'), 'userSpaceOnUse');
    final colors = gradient
        .findElements('stop')
        .map((stop) => stop.getAttribute('stop-color'))
        .toSet();
    expect(colors.length, greaterThanOrEqualTo(2), reason: reason);
    expect(colors, isNot(contains(null)), reason: reason);
  }
  expect(_geometry(root), isNotEmpty, reason: reason);
  return root;
}

// Ignore paint and metadata. Preserve only drawing geometry and transforms so
// palette changes cannot disguise duplicates or manufacture coverage numbers.
List<Object> _geometry(XmlElement root) => [
      for (final element in root.descendants.whereType<XmlElement>())
        if (const {
              'path',
              'rect',
              'circle',
              'ellipse',
              'line',
              'polygon',
              'polyline',
            }.contains(element.name.local) ||
            (element.name.local == 'g' &&
                element.getAttribute('transform') != null))
          [
            element.name.local,
            for (final name in const [
              'd',
              'points',
              'x',
              'y',
              'x1',
              'x2',
              'y1',
              'y2',
              'cx',
              'cy',
              'r',
              'rx',
              'ry',
              'width',
              'height',
              'transform',
            ])
              if (element.getAttribute(name) != null)
                [name, element.getAttribute(name)],
          ],
    ];
