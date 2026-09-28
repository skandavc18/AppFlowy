// Original artwork authored for AppFlowy's Vivid collection; distributed under
// the repository's LICENSE. Not copied from or attributed to Fluent Emoji.

import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';

part 'vivid_extra_artwork.dart';

/// Explicit illustrations only; generated utility variants are not a catalogue.
/// Chrome additions do not add, rename or replace persisted picker choices.
Iterable<String> get vividIllustrationNames sync* {
  yield* _illustrations.keys;
  yield* _extraIllustrations.keys;
  yield* _actionIllustrations.keys;
}

bool hasVividIllustration(String name) =>
    _illustrations.containsKey(name) ||
    _extraIllustrations.containsKey(name) ||
    _actionIllustrations.containsKey(name);

/// Rounded illustrations on a consistent 32px grid. Gradients, inset highlights
/// and contrasting faces supply depth without filters or embedded raster data.
/// The canvas is transparent: pale fills are object details, not UI surfaces.
String? vividIconSvg(String name) {
  if (name.startsWith('utility-')) {
    return _vividUtilitySvg(name.substring('utility-'.length));
  }
  final art = _illustrations[name] ??
      _extraIllustrations[name] ??
      _actionIllustrations[name];
  if (art == null) return null;
  // Do not change the serialized SVG bytes of existing saved illustrations.
  final body = art.strokeWidth == null
      ? art.body
      : '<g stroke-width="${art.strokeWidth}">${art.body}</g>';
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
      'fill="none" stroke-linecap="round" stroke-linejoin="round">'
      '<defs>'
      '<linearGradient id="main" x1="6" y1="3" x2="26" y2="29" '
      'gradientUnits="userSpaceOnUse">'
      '<stop stop-color="${art.light}"/>'
      '<stop offset="1" stop-color="${art.shade}"/>'
      '</linearGradient>'
      '<linearGradient id="accent" x1="8" y1="5" x2="24" y2="28" '
      'gradientUnits="userSpaceOnUse">'
      '<stop stop-color="${art.accentLight}"/>'
      '<stop offset="1" stop-color="${art.accentShade}"/>'
      '</linearGradient>'
      '</defs>$body</svg>';
}

/// Utility marks retain their precise geometry instead of borrowing an
/// unrelated object. A compiled gradient gives even a one-path arrow a vivid
/// palette; there is no asset IO, name hashing, badge, or theme-colored tint.
String? _vividUtilitySvg(String name) {
  final source = defaultIconSvg(name);
  if (source == null || name == 'unknown') return null;
  return _utilityCache.putIfAbsent(name, () {
    final (light, shade) = switch (name) {
      'dots-six-vertical' => ('#789DA3', '#7E8FB1'),
      'trash' || 'x' || 'minus-circle' || 'block' || 'backspace' => (
          '#EA7893',
          '#BD486D'
        ),
      'check' || 'check-all' || 'check-circle' || 'checkbox' || 'radio' => (
          '#43C7A7',
          '#3277BD'
        ),
      'text' ||
      'input' ||
      'bold' ||
      'italic' ||
      'underline' ||
      'strikethrough' ||
      'quote' ||
      'sigma' =>
        ('#AC79E0', '#527DDD'),
      'star' || 'bookmark' || 'push-pin' || 'warning' || 'priority' => (
          '#E5B44F',
          '#D16D55'
        ),
      _ => ('#489ECC', '#9365CD'),
    };
    final body = source
        .substring(source.indexOf('>') + 1, source.lastIndexOf('</svg>'))
        .replaceAll('currentColor', 'url(#utility)');
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
        '<defs><linearGradient id="utility" x1="4" y1="3" x2="20" y2="21" '
        'gradientUnits="userSpaceOnUse"><stop stop-color="$light"/>'
        '<stop offset="1" stop-color="$shade"/></linearGradient></defs>'
        '<g transform="scale(1.3333333333)" fill="none" stroke="url(#utility)" '
        'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
        '$body</g></svg>';
  });
}

final _utilityCache = <String, String>{};

class _Illustration {
  const _Illustration(
    this.light,
    this.shade,
    this.accentLight,
    this.accentShade,
    this.body,
  ) : strokeWidth = null;

  /// A compact blue/violet action palette, not a filter over default outlines.
  const _Illustration.action(
    this.body, {
    this.light = '#65BFF2',
    this.shade = '#397FC4',
    this.accentLight = '#B79AEE',
    this.accentShade = '#8251BD',
  }) : strokeWidth = 2.2;

  final String light;
  final String shade;
  final String accentLight;
  final String accentShade;
  final String body;
  final double? strokeWidth;
}

// Reusable object faces, not UI backgrounds. Every illustration remains
// transparent outside the object and uses its original palette without tint.
const _fileFace = '<path d="M8 3h11l8 8v16a3 3 0 0 1-3 3H8'
    'a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z" fill="url(#main)"/>'
    '<path d="M19 3v6a2 2 0 0 0 2 2h6Z" fill="url(#accent)"/>'
    '<path d="M8 7v17" stroke="#FFFFFF" stroke-opacity=".5" stroke-width="1.2"/>';
const _panelFace = '<rect x="3" y="5" width="26" height="24" rx="4" '
    'fill="url(#main)"/>'
    '<rect x="5" y="7" width="22" height="19" rx="2" fill="#FFF6E8"/>'
    '<path d="M7 7h18a2 2 0 0 1 2 2v3H5V9a2 2 0 0 1 2-2Z" '
    'fill="url(#accent)"/>';
const _chatFace = '<path d="M7 4h18a5 5 0 0 1 5 5v11a5 5 0 0 1-5 5H13'
    'l-8 5 1-5a5 5 0 0 1-4-5V9a5 5 0 0 1 5-5Z" fill="url(#main)"/>'
    '<path d="M7 7h17" stroke="#F5F6FF" stroke-opacity=".65" stroke-width="1.4"/>';

const _illustrations = <String, _Illustration>{
  'home': _Illustration(
    '#FF9565',
    '#E93966',
    '#FFECA0',
    '#FFB544',
    '<rect x="22" y="5" width="5" height="10" rx="1.5" fill="#CE3F61"/>'
        '<path d="M5 13 16 5l11 8v13a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3Z" '
        'fill="url(#accent)"/>'
        '<path d="M23 13h4v13a3 3 0 0 1-3 3h-1Z" fill="#F5A23B"/>'
        '<path d="m2.8 12.4 11-9a3.5 3.5 0 0 1 4.4 0l11 9a1.8 1.8 0 0 1-2.3 2.8'
        'L16 6.3 5.1 15.2a1.8 1.8 0 0 1-2.3-2.8Z" fill="url(#main)"/>'
        '<rect x="8" y="16" width="6" height="6" rx="1.6" fill="#39BDE5"/>'
        '<path d="M9 17h4v1.8H9Z" fill="#B1F3FF"/>'
        '<path d="M18 29v-8a3 3 0 0 1 6 0v8Z" fill="#3976C6"/>'
        '<circle cx="22" cy="24" r=".8" fill="#FFF3C3"/>'
        '<path d="m5 12 10-8" stroke="#FFD2AD" stroke-width="1.4"/>',
  ),
  'book': _Illustration(
    '#A38BFF',
    '#593BC8',
    '#FFD97A',
    '#FF9246',
    '<rect x="5" y="4" width="22" height="26" rx="3.5" fill="#49349A"/>'
        '<path d="M9 22h17v6H9a3 3 0 0 1 0-6Z" fill="#FFF3D8"/>'
        '<path d="M10 25h15M10 27h15" stroke="#DDBEAC" stroke-width=".8"/>'
        '<path d="M9 3h15a3 3 0 0 1 3 3v17H9a4 4 0 0 0-4 3V7a4 4 0 0 1 4-4Z" '
        'fill="url(#main)"/>'
        '<path d="M9 3v20a4 4 0 0 0-4 3V7a4 4 0 0 1 4-4Z" fill="#6850CC"/>'
        '<path d="M20 3h4v13l-2-1.6-2 1.6Z" fill="url(#accent)"/>'
        '<path d="M12 9h5M12 12h7" stroke="#E8DFFF" stroke-width="1.6"/>'
        '<path d="M11 5h7" stroke="#D6C8FF" stroke-width="1.2"/>',
  ),
  'bolt': _Illustration(
    '#FFF185',
    '#FF9D23',
    '#80ECFF',
    '#328FEE',
    '<path d="M18.8 3 7 18.5a1.5 1.5 0 0 0 1.2 2.4h6.7l-1.4 7.9'
        'a.9.9 0 0 0 1.6.7L27 14a1.5 1.5 0 0 0-1.2-2.4h-7.2l1.8-7.8'
        'a.9.9 0 0 0-1.6-.8Z" fill="#E77A23"/>'
        '<path d="M17.2 2.4 5.4 17.2a1.4 1.4 0 0 0 1.1 2.3H14l-1.8 9.1'
        'L25.7 13a1 1 0 0 0-.8-1.6h-8L18.8 3a.9.9 0 0 0-1.6-.6Z" '
        'fill="url(#main)"/>'
        '<path d="m16 6-8 10h6" stroke="#FFF8C6" stroke-width="1.5"/>'
        '<path d="m5 4 .9 2.6L8.5 7l-2.6.9L5 10.5l-.9-2.6L1.5 7l2.6-.4Z'
        'M21 21l1.3 3.7L26 26l-3.7 1.3L21 31l-1.3-3.7L16 26l3.7-1.3Z" '
        'fill="url(#accent)"/>',
  ),
  'coffee': _Illustration(
    '#FF94AE',
    '#E83E6D',
    '#FFDF8D',
    '#EE9D3E',
    '<ellipse cx="16" cy="27.5" rx="13" ry="3" fill="url(#accent)"/>'
        '<path d="M23 12h2a5 5 0 0 1 0 10h-3" stroke="#C53865" stroke-width="4"/>'
        '<path d="M23 12h2a4 4 0 0 1 0 8" stroke="#FFADBB" stroke-width="2"/>'
        '<path d="M5 12h19v8.5a7.5 7.5 0 0 1-7.5 7.5H13a8 8 0 0 1-8-8Z" '
        'fill="url(#main)"/>'
        '<ellipse cx="14.5" cy="12" rx="9.5" ry="3" fill="#FFE7D4"/>'
        '<ellipse cx="14.5" cy="12.4" rx="7.4" ry="1.8" fill="#754335"/>'
        '<path d="M9 17v3.5a4 4 0 0 0 2 3.5" stroke="#FFD0D9" stroke-width="1.8"/>'
        '<path d="M11 7c-3-2 2-3 0-5M17 7c-3-2 2-3 0-5" '
        'stroke="#E7AD84" stroke-width="1.5"/>'
        '<path d="m17 18 1 1.4 1.7.5-1.2 1.3.1 1.8-1.6-.8-1.6.8.1-1.8-1.2-1.3'
        ' 1.7-.5Z" fill="#FFE59C"/>',
  ),
  'target': _Illustration(
    '#FF9A8B',
    '#EF3D67',
    '#AD9BFF',
    '#6448CD',
    '<path d="m10 24-3 5m13-5 3 5" stroke="#527BB5" stroke-width="3"/>'
        '<circle cx="14" cy="16" r="12" fill="#C62F62"/>'
        '<circle cx="14" cy="15" r="11" fill="url(#main)"/>'
        '<circle cx="14" cy="15" r="8" fill="#FFF2DF"/>'
        '<circle cx="14" cy="15" r="5.2" fill="url(#main)"/>'
        '<circle cx="14" cy="15" r="2.2" fill="#FFF2DF"/>'
        '<path d="m14 15 12-12" stroke="#533A9E" stroke-width="2"/>'
        '<path d="m21 4 5-2v4l4 .2-2 4-6-1Z" fill="url(#accent)"/>'
        '<path d="m5.5 11 1-1.7 1.5-1.5" stroke="#FFC9B9" stroke-width="1.3"/>',
  ),
  'rocket': _Illustration(
    '#B6F4FF',
    '#419BE9',
    '#FFE78E',
    '#FF863E',
    '<path d="M10 20C4 20 3 24 3 29c5 0 9-1 9-7Z" fill="url(#accent)"/>'
        '<path d="M10 23c-2 0-3 2-3 3 2 0 3-1 4-3Z" fill="#FFF5C2"/>'
        '<path d="M12 11H8l-5 8 7 1m11-1 1 7 7-7v-5Z" fill="#D9538D"/>'
        '<path d="M9 20C9 11 18 3 27 3h2v2c0 10-8 18-17 18Z" '
        'fill="url(#main)"/>'
        '<path d="M22 4c2-.7 4-1 7-1 0 3-.3 5-1 7Z" fill="#FF697F"/>'
        '<path d="m9 20 3 3 4-1-6-6Z" fill="#496CBC"/>'
        '<circle cx="20" cy="12" r="4.5" fill="#F3FCFF"/>'
        '<circle cx="20" cy="12" r="3" fill="#4661BB"/>'
        '<path d="M18 12a2 2 0 0 1 2-2" stroke="#8CD9FF" stroke-width="1.2"/>'
        '<path d="m12 15 3-4" stroke="#EDFDFF" stroke-width="1.4"/>',
  ),
  'seedling': _Illustration(
    '#A6ED6B',
    '#20A766',
    '#FFB77B',
    '#E36E50',
    '<path d="m9 22 2 7h10l2-7Z" fill="url(#accent)"/>'
        '<rect x="8" y="20" width="16" height="4" rx="2" fill="#FFBE88"/>'
        '<ellipse cx="16" cy="20.5" rx="7" ry="1.5" fill="#795546"/>'
        '<path d="M16 21V11" stroke="#258A5C" stroke-width="2.5"/>'
        '<path d="M16 17C7 18 3 12 4 7c8-1 13 3 12 10Z" fill="url(#main)"/>'
        '<path d="M16 12C15 5 21 1 28 3c0 7-5 12-12 9Z" fill="url(#main)"/>'
        '<path d="m8 10 8 7m2-7 6-4" stroke="#D4F8A1" stroke-width="1.3"/>'
        '<path d="m12 25 .7 2.5" stroke="#FFE1B4" stroke-width="1.5"/>',
  ),
  'bulb': _Illustration(
    '#FFF29C',
    '#FFB326',
    '#8BE4F5',
    '#4078C5',
    '<path d="M7 13a9 9 0 1 1 15.4 6.4C20.8 21 20 22 20 24h-8'
        'c0-2-1-3.2-2.5-4.8A9 9 0 0 1 7 13Z" fill="url(#main)"/>'
        '<path d="M12 24h8v3a4 4 0 0 1-8 0Z" fill="url(#accent)"/>'
        '<path d="M12 25h8m-7 2h6" stroke="#D4F3FF" stroke-width="1.2"/>'
        '<path d="M14 23v-6l-3-3m7 9v-6l3-3m-7 3h4" '
        'stroke="#E58E22" stroke-width="1.6"/>'
        '<path d="M10.5 12a5.5 5.5 0 0 1 4-5" stroke="#FFFBDD" stroke-width="2"/>'
        '<path d="M16 1v1M4 5l2 2M1 13h2m24 0h3M26 5l-2 2" '
        'stroke="#EAB449" stroke-width="1.8"/>',
  ),
  'sparkles': _Illustration(
    '#FFF5A0',
    '#FFB232',
    '#C0A0FF',
    '#8450D8',
    '<path d="M12 5c1.4 7.4 3.5 9.5 11 11-7.5 1.5-9.6 3.6-11 11'
        'C10.5 19.6 8.4 17.5 1 16c7.4-1.5 9.5-3.6 11-11Z" '
        'fill="url(#main)"/>'
        '<path d="M24 1c.8 4.8 2.2 6.2 7 7-4.8.8-6.2 2.2-7 7'
        '-.8-4.8-2.2-6.2-7-7 4.8-.8 6.2-2.2 7-7Z" fill="url(#accent)"/>'
        '<path d="M25 21c.6 3.4 1.6 4.4 5 5-3.4.6-4.4 1.6-5 5'
        '-.6-3.4-1.6-4.4-5-5 3.4-.6 4.4-1.6 5-5Z" fill="#46C5BB"/>'
        '<path d="m12 11-1.8 3.2L7 16" stroke="#FFFAD1" stroke-width="1.5"/>'
        '<circle cx="5" cy="26" r="1.4" fill="#BDA0F2"/>',
  ),
  'planet': _Illustration(
    '#EA9DF6',
    '#8551DB',
    '#FFD988',
    '#F29C55',
    '<ellipse cx="16" cy="16" rx="15" ry="5" transform="rotate(-25 16 16)" '
        'stroke="url(#accent)" stroke-width="2.5"/>'
        '<circle cx="16" cy="16" r="10.5" fill="url(#main)"/>'
        '<path d="M8 10c5 0 9 5 17 4m-19 1c7 0 11 7 17 6" '
        'stroke="#C17AE9" stroke-width="2"/>'
        '<path d="M11 8.5 14 7" stroke="#F7C5FF" stroke-width="1.8"/>'
        '<path d="M2.4 20.8C1 25 10 25 20.3 20.1 27 17 31 13.6 29.6 11.2" '
        'stroke="url(#accent)" stroke-width="3"/>'
        '<path d="M5 23c3.4.3 7.5-.7 11-2" stroke="#FFE9B7" stroke-width=".9"/>'
        '<circle cx="27" cy="4" r="1.3" fill="#FFDA81"/>'
        '<circle cx="5" cy="5" r=".9" fill="#88DDEC"/>',
  ),
  'books': _Illustration(
    '#AA91FF',
    '#674BCC',
    '#8EEAE1',
    '#20A6A3',
    '<path d="M5 21h22v8H5a4 4 0 0 1 0-8Z" fill="url(#main)"/>'
        '<path d="M7 23h20v4H7a2 2 0 0 1 0-4Z" fill="#FFF0D3"/>'
        '<path d="M8 25h17" stroke="#D7BBA4" stroke-width=".8"/>'
        '<path d="M8 12h18a4 4 0 0 1 0 8H8Z" fill="#E75583"/>'
        '<path d="M9 14h15a2 2 0 0 1 0 4H9Z" fill="#FFF1D9"/>'
        '<path d="M10 16h13" stroke="#D7BBA4" stroke-width=".8"/>'
        '<path d="M6 3h20v8H6a4 4 0 0 1 0-8Z" fill="url(#accent)"/>'
        '<path d="M8 5h18v4H8a2 2 0 0 1 0-4Z" fill="#FFF7E8"/>'
        '<path d="M9 7h15" stroke="#D7BBA4" stroke-width=".8"/>'
        '<path d="M18 5h4v9l-2-1.5-2 1.5Z" fill="#FFC558"/>',
  ),
  'camera': _Illustration(
    '#AD9DFF',
    '#6750CF',
    '#9BF6F3',
    '#259ECE',
    '<path d="m9 9 2-4h10l2 4" fill="#7562CB"/>'
        '<rect x="3" y="8" width="26" height="21" rx="5" fill="#493D94"/>'
        '<rect x="3" y="8" width="26" height="18" rx="5" fill="url(#main)"/>'
        '<rect x="6" y="11" width="5" height="3" rx="1" fill="#FFE49D"/>'
        '<circle cx="18" cy="17" r="7" fill="#4C3B94"/>'
        '<circle cx="18" cy="17" r="5.5" fill="url(#accent)"/>'
        '<circle cx="18" cy="17" r="3.4" fill="#30749E"/>'
        '<path d="M14 16a4 4 0 0 1 4-3" stroke="#DDFDF7" stroke-width="1.5"/>'
        '<circle cx="20" cy="19" r="1" fill="#8ADCE4"/>'
        '<path d="M6 23h3" stroke="#C5B7FF" stroke-width="1.2"/>',
  ),
  'music': _Illustration(
    '#D89CFF',
    '#8D42D2',
    '#FFCB89',
    '#F58173',
    '<path d="M11 8 27 3v19h-3V11l-10 3v12h-3Z" fill="#703EB2"/>'
        '<path d="M10 6 26 2v19h-3V9l-10 3v12h-3Z" fill="url(#main)"/>'
        '<path d="M13 7v2l10-3V4Z" fill="#EFC6FF"/>'
        '<ellipse cx="8" cy="25" rx="6" ry="4.5" transform="rotate(-20 8 25)" '
        'fill="url(#main)"/>'
        '<ellipse cx="21" cy="22" rx="5.5" ry="4" transform="rotate(-20 21 22)" '
        'fill="url(#accent)"/>'
        '<path d="m5 24 3-1m10-2 3-1" stroke="#F9CEFA" stroke-width="1.4"/>'
        '<path d="m4 8 .8 2.2L7 11l-2.2.8L4 14l-.8-2.2L1 11l2.2-.8Z" '
        'fill="url(#accent)"/>',
  ),
  'calendar': _Illustration(
    '#FF9C93',
    '#EC5279',
    '#8ADBFF',
    '#467CD1',
    '<rect x="4" y="6" width="25" height="24" rx="4" fill="url(#accent)"/>'
        '<rect x="3" y="5" width="25" height="23" rx="4" fill="#FFF1DA"/>'
        '<path d="M7 5h17a4 4 0 0 1 4 4v5H3V9a4 4 0 0 1 4-4Z" '
        'fill="url(#main)"/>'
        '<path d="M10 3v5M21 3v5" stroke="#4569A2" stroke-width="3"/>'
        '<path d="M9.5 3v3M20.5 3v3" stroke="#B6E7FF" stroke-width="1"/>'
        '<rect x="7" y="17" width="4" height="4" rx="1" fill="#8BCCDE"/>'
        '<rect x="14" y="17" width="4" height="4" rx="1" fill="#FFB96C"/>'
        '<path d="m20 21 2 2 4-5" stroke="#43B896" stroke-width="2"/>'
        '<path d="M8 24h8" stroke="#D9B9A4" stroke-width="1.3"/>',
  ),
  'folder': _Illustration(
    '#FFE790',
    '#F6AC35',
    '#87E7F6',
    '#2A9BCD',
    '<path d="M3 9a3 3 0 0 1 3-3h6l3 4h11a3 3 0 0 1 3 3v12'
        'a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3Z" fill="#E99132"/>'
        '<rect x="7" y="11" width="18" height="13" rx="2" fill="#FFF5DE"/>'
        '<path d="M10 14h12M10 17h9" stroke="#C6CED2" stroke-width="1.2"/>'
        '<path d="M5 15h23a2 2 0 0 1 2 2.3l-1.5 9a3 3 0 0 1-3 2.7H7'
        'a3 3 0 0 1-3-2.6L2.5 18a2.5 2.5 0 0 1 2.5-3Z" fill="url(#main)"/>'
        '<path d="M6 17h19" stroke="#FFF0B5" stroke-width="1.5"/>'
        '<rect x="11" y="21" width="10" height="4" rx="2" fill="url(#accent)"/>',
  ),
  'chart': _Illustration(
    '#C5A2FF',
    '#8751D8',
    '#97F1DC',
    '#23B5AD',
    '<path d="M4 6v22h25" stroke="#577EA8" stroke-width="2"/>'
        '<rect x="7" y="18" width="5" height="8" rx="1.5" fill="url(#accent)"/>'
        '<rect x="15" y="13" width="5" height="13" rx="1.5" fill="url(#main)"/>'
        '<rect x="23" y="8" width="5" height="18" rx="1.5" fill="#FF9279"/>'
        '<path d="M8.5 20v3M16.5 15v4M24.5 10v5" stroke="#FFFFFF" '
        'stroke-opacity=".5" stroke-width="1"/>'
        '<path d="m7 12 7-5 5 2 8-6m-5 0h5v5" stroke="#EBA83E" '
        'stroke-width="2.2"/>',
  ),
  'globe': _Illustration(
    '#86E6FF',
    '#327ECF',
    '#B9F39A',
    '#3BB486',
    '<path d="M19 24v4m-8 1h14" stroke="#536EB0" stroke-width="3"/>'
        '<path d="M25 5a14 14 0 0 1-17 21" stroke="#F3B45F" stroke-width="2.5"/>'
        '<circle cx="15" cy="14" r="11" fill="url(#main)"/>'
        '<path d="m7 7 5-3 4 1 1 4-4 1-1 4-4-1-2-3Z'
        'M8 14 11 14 14 17 13 22 11 21 10 17Z'
        'M21 9 24 11 25 15 22 18 20 17 18 13Z" fill="url(#accent)"/>'
        '<path d="M5 17c6 3 13 3 19-1M16 4c-4 5-5 13-1 20" '
        'stroke="#CEF8FF" stroke-opacity=".5" stroke-width=".8"/>'
        '<path d="M8 6.5 11 5" stroke="#E0FBFF" stroke-width="1.4"/>',
  ),
  'palette': _Illustration(
    '#FFE5B0',
    '#F4B558',
    '#86DFF1',
    '#3A8BD1',
    '<path fill-rule="evenodd" d="M16 2C8 2 2 7 2 15c0 8 6 14 14 14'
        ' 3 0 4-2 3-4-1.5-3 0-5 3-4 5 1 8-2 8-6C30 7 24 2 16 2Z'
        'M9 18a2.2 2.2 0 1 0 0 4.4A2.2 2.2 0 0 0 9 18Z" fill="url(#main)"/>'
        '<circle cx="8" cy="12" r="2.5" fill="#F27184"/>'
        '<circle cx="14" cy="7" r="2.5" fill="#A277DF"/>'
        '<circle cx="21" cy="8" r="2.5" fill="#56A9E3"/>'
        '<circle cx="25" cy="14" r="2.5" fill="#52C7AF"/>'
        '<path d="m18 25 9-14a1.5 1.5 0 0 1 2.5 1.7l-9 14Z" fill="url(#accent)"/>'
        '<path d="m18 24 3 2c-1 4-4 4-7 4 2-1 1-4 4-6Z" fill="#AF68CA"/>'
        '<path d="M6 8 8 6" stroke="#FFF4DA" stroke-width="1.5"/>',
  ),
  'gem': _Illustration(
    '#F6A7EA',
    '#C54DBF',
    '#B0F1FF',
    '#5799E5',
    '<path d="M8 5h16l7 9-13.5 15a2 2 0 0 1-3 0L1 14Z" fill="#8755B9"/>'
        '<path d="M8 4h16l7 9-15 16L1 13Z" fill="url(#main)"/>'
        '<path d="m8 4 8 9-8 0-7 0Zm16 0-8 9h15Z" fill="url(#accent)"/>'
        '<path d="m8 4 8 9 8-9Z" fill="#FFD9F3"/>'
        '<path d="m8 13 8 16 8-16Z" fill="url(#accent)"/>'
        '<path d="m1 13 15 16-8-16Z" fill="#B473D6"/>'
        '<path d="M4 12 8 7m3 7 3 7" stroke="#FDF2FF" stroke-width="1.2"/>',
  ),
  'trophy': _Illustration(
    '#FFEE96',
    '#F4AE2B',
    '#FFA674',
    '#E7763E',
    '<path d="M9 7H4v5a6 6 0 0 0 7 6m12-11h5v5a6 6 0 0 1-7 6" '
        'stroke="url(#accent)" stroke-width="3"/>'
        '<path d="M14 20h4v7h-4Z" fill="url(#accent)"/>'
        '<path d="M8 4h16v8a8 8 0 0 1-16 0Z" fill="url(#main)"/>'
        '<rect x="8" y="3" width="16" height="3" rx="1.5" fill="#FFE6A1"/>'
        '<rect x="9" y="26" width="14" height="4" rx="1.5" fill="#5F80C6"/>'
        '<rect x="13" y="27" width="6" height="2" rx=".6" fill="#FFD773"/>'
        '<path d="m16 8 1.3 2.7 3 .5-2.1 2.1.5 3-2.7-1.4-2.7 1.4.5-3'
        '-2.1-2.1 3-.5Z" fill="#FFF8D1"/>'
        '<path d="M10 8v3" stroke="#FFF8CD" stroke-width="1.5"/>',
  ),
  'heart': _Illustration(
    '#FF9CB8',
    '#E23E79',
    '#FFDC91',
    '#F8AC48',
    '<path d="M16 8C11 1 2 5 2 12c0 7 8 13 14 17 6-4 14-10 14-17'
        ' 0-7-9-11-14-4Z" fill="url(#main)"/>'
        '<path d="M16 29c6-4 14-10 14-17 0-1.5-.4-3-1-4'
        ' 1 9-7 16-13 21Z" fill="#C9326B"/>'
        '<path d="M6 12c0-3 2-4.5 4-4.5" stroke="#FFD7E3" stroke-width="2"/>'
        '<path d="m26 1 1 2.7L30 5l-3 1.3L26 9l-1-2.7L22 5l3-1.3Z" '
        'fill="url(#accent)"/>',
  ),
  'cloud': _Illustration(
    '#CBF5FF',
    '#609EED',
    '#FFE69A',
    '#FFB54B',
    '<circle cx="23" cy="10" r="7" fill="url(#accent)"/>'
        '<path d="M23 1v1m8 8h-1M29 4l-1 1" stroke="#F1BA59" stroke-width="1.4"/>'
        '<path d="M9 28a7 7 0 0 1-1-13.9A9 9 0 0 1 25 13'
        'a7.5 7.5 0 0 1-1 15Z" fill="#4C83CC"/>'
        '<path d="M8 26a6.5 6.5 0 0 1 0-13 8.5 8.5 0 0 1 16.8-1'
        'A7 7 0 0 1 24 26Z" fill="url(#main)"/>'
        '<path d="M11 12a5 5 0 0 1 7-3M5 19c0-2 1-3 3-3" '
        'stroke="#F2FDFF" stroke-width="1.8"/>',
  ),
  'mountain': _Illustration(
    '#B7A2F8',
    '#7953B8',
    '#91E8D3',
    '#2BA7A0',
    '<circle cx="6" cy="7" r="3.5" fill="#FFC96F"/>'
        '<path d="M16 5a2 2 0 0 1 3.5 0L31 27H4Z" fill="url(#main)"/>'
        '<path d="m18 5 13 22H18Z" fill="#67469E"/>'
        '<path d="m13 11 3-6a2 2 0 0 1 3.5 0l3 6-3-.8-2 2-2-2Z" '
        'fill="#EAE8FF"/>'
        '<path d="m1 28 8-15a1.7 1.7 0 0 1 3 0l9 15Z" fill="url(#accent)"/>'
        '<path d="m7 17 2-4a1.7 1.7 0 0 1 3 0l2 4-3-1-1 2Z" fill="#E5FFF3"/>'
        '<path d="M3 29h26" stroke="#427996" stroke-width="1.5"/>',
  ),
  'compass': _Illustration(
    '#FFA89C',
    '#E65D7D',
    '#A5EAF9',
    '#438BCA',
    '<circle cx="16" cy="17" r="14" fill="#BF5375"/>'
        '<circle cx="16" cy="15" r="13" fill="url(#main)"/>'
        '<circle cx="16" cy="15" r="10.5" fill="url(#accent)"/>'
        '<circle cx="16" cy="15" r="8.5" fill="#FFF2DE"/>'
        '<path d="M16 8v1m0 12v1M9 15h1m12 0h1" stroke="#9BAABD" '
        'stroke-width="1.4"/>'
        '<path d="m22 9-3.5 8.5L10 21l3.5-8.5Z" fill="#4C8EBE"/>'
        '<path d="m22 9-3.5 8.5-5-5Z" fill="url(#main)"/>'
        '<circle cx="16" cy="15" r="1.5" fill="#FFF7E7"/>'
        '<path d="M7 8a11 11 0 0 1 7-4" stroke="#FFD8C9" stroke-width="1.3"/>',
  ),
  'page': _Illustration(
    '#E5F5FF',
    '#99C8EA',
    '#9FDCD6',
    '#4CAAA6',
    '$_fileFace<path d="M11 14h10M11 18h10M11 22h7" '
        'stroke="#507BA7" stroke-width="1.7"/>',
  ),
  'file': _Illustration(
    '#E5EAF8',
    '#AFBDD9',
    '#ADCFEF',
    '#6A92C7',
    '$_fileFace<rect x="11" y="16" width="10" height="7" rx="2" '
        'fill="#F8F7FF"/>',
  ),
  'pdf': _Illustration(
    '#FFF0E7',
    '#F4CABC',
    '#FF9C94',
    '#D65370',
    '$_fileFace<path d="M12 12h9M12 16h9M12 20h7" '
        'stroke="#C96A73" stroke-width="1.5"/>'
        '<rect x="2" y="20" width="12" height="8" rx="2" fill="url(#accent)"/>'
        '<path d="M6 25v-3h3a1.5 1.5 0 0 1 0 3H6" '
        'stroke="#FFF3E9" stroke-width="1.3"/>',
  ),
  'document': _Illustration(
    '#E1F1FF',
    '#99BFE8',
    '#81B5FA',
    '#4074BD',
    '$_fileFace<path d="M12 14h10M12 18h10M12 22h6" '
        'stroke="#4F7CAB" stroke-width="1.5"/>'
        '<rect x="2" y="16" width="13" height="12" rx="3" fill="url(#accent)"/>'
        '<path d="m5 20 1.5 5 2-3 2 3 1.5-5" stroke="#F5FBFF" '
        'stroke-width="1.5"/>',
  ),
  'spreadsheet': _Illustration(
    '#E4F8EC',
    '#9AD5B3',
    '#80D6AF',
    '#279775',
    '$_fileFace<rect x="11" y="13" width="12" height="11" rx="1.5" '
        'stroke="#418E73" stroke-width="1.3"/>'
        '<path d="M11 17h12M11 21h12M17 13v11" stroke="#418E73" stroke-width="1.2"/>'
        '<rect x="2" y="17" width="12" height="11" rx="2.5" fill="url(#accent)"/>'
        '<path d="m6 20 4 5m-4 0 4-5" stroke="#EDFFF7" stroke-width="1.6"/>',
  ),
  'presentation': _Illustration(
    '#FFF0DA',
    '#F1CAA4',
    '#FFA576',
    '#DC7354',
    '$_fileFace<rect x="11" y="13" width="12" height="9" rx="1.5" '
        'stroke="#B87B58" stroke-width="1.3"/>'
        '<path d="M17 22v4m-3 0h6" stroke="#B87B58" stroke-width="1.3"/>'
        '<rect x="2" y="17" width="12" height="11" rx="2.5" fill="url(#accent)"/>'
        '<path d="M6 25v-5h3a1.5 1.5 0 0 1 0 3H6" stroke="#FFF5E8" '
        'stroke-width="1.5"/>',
  ),
  'archive': _Illustration(
    '#FFE6AA',
    '#ECAF59',
    '#AE9BE8',
    '#7960B5',
    '$_fileFace<path d="M13 3v3h3v3h-3v3h3v3h-3v3" '
        'stroke="#96714C" stroke-width="2"/>'
        '<rect x="11" y="18" width="7" height="8" rx="2" fill="url(#accent)"/>'
        '<rect x="13" y="21" width="3" height="3" rx="1" fill="#FFF3D3"/>',
  ),
  'code-file': _Illustration(
    '#E1EEF9',
    '#AAC7E2',
    '#AFA0F1',
    '#7552BD',
    '$_fileFace<rect x="9" y="13" width="20" height="13" rx="3" '
        'fill="url(#accent)"/>'
        '<path d="m15 17-3 3 3 3m8-6 3 3-3 3m-3-7-2 8" '
        'stroke="#F5EDFF" stroke-width="1.5"/>',
  ),
  'markdown': _Illustration(
    '#EDF3F8',
    '#B1C7D8',
    '#8FBCCB',
    '#568799',
    '$_fileFace<rect x="8" y="14" width="21" height="12" rx="2.5" '
        'fill="url(#accent)"/>'
        '<path d="M11 23v-6l3 3 3-3v6m7-6v6m-2-2 2 2 2-2" '
        'stroke="#F7FCFF" stroke-width="1.5"/>',
  ),
  'html-file': _Illustration(
    '#FFF0DB',
    '#EDCAA4',
    '#FFB878',
    '#D98257',
    '$_fileFace<rect x="9" y="14" width="20" height="12" rx="3" '
        'fill="url(#accent)"/>'
        '<path d="m15 17-3 3 3 3m8-6 3 3-3 3m-3-7-2 8" '
        'stroke="#FFF6E8" stroke-width="1.5"/>',
  ),
  'json-file': _Illustration(
    '#FFF5CE',
    '#E9D69C',
    '#B3C982',
    '#7F9954',
    '$_fileFace<rect x="9" y="14" width="20" height="12" rx="3" '
        'fill="url(#accent)"/>'
        '<path d="M16 17h-2v2l-1 1 1 1v2h2m6-6h2v2l1 1-1 1v2h-2" '
        'stroke="#FCFFE7" stroke-width="1.4"/>',
  ),
  'notebook': _Illustration(
    '#FFD8A5',
    '#E9A361',
    '#AE9BEA',
    '#7353B5',
    '<rect x="6" y="3" width="23" height="27" rx="3" fill="url(#main)"/>'
        '<path d="M10 3v27" stroke="#C58653" stroke-width="1.5"/>'
        '<path d="M4 8h4M4 15h4M4 22h4" stroke="#FFF0D3" stroke-width="3"/>'
        '<rect x="13" y="10" width="13" height="13" rx="2" fill="url(#accent)"/>'
        '<path d="m16 14 3 3-3 3m5 0h2" stroke="#FAEFFF" stroke-width="1.5"/>',
  ),
  'csv': _Illustration(
    '#E5F5EB',
    '#ADD2B8',
    '#A4D8CF',
    '#5EAA9D',
    '$_fileFace<rect x="10" y="13" width="13" height="12" rx="1.5" '
        'fill="#F6FFF8"/>'
        '<path d="M10 17h13M10 21h13M15 13v12M19 13v12" '
        'stroke="#659F88" stroke-width="1.3"/>',
  ),
  'image': _Illustration(
    '#A8DBF2',
    '#5E94CC',
    '#ACD891',
    '#4EAA87',
    '<rect x="3" y="4" width="26" height="25" rx="4" fill="url(#main)"/>'
        '<rect x="6" y="7" width="20" height="18" rx="2" fill="#E8F8FE"/>'
        '<circle cx="21" cy="11" r="2.5" fill="#FFD48B"/>'
        '<path d="m6 22 6-9 7 8 4-5 3 4v5H6Z" fill="url(#accent)"/>',
  ),
  'video': _Illustration(
    '#A8C3F4',
    '#667BCC',
    '#FBC992',
    '#E4966E',
    '<rect x="3" y="4" width="26" height="25" rx="4" fill="url(#main)"/>'
        '<rect x="8" y="7" width="16" height="19" rx="2" fill="#E8EBFA"/>'
        '<path d="m13 11 8 5.5-8 5.5Z" fill="url(#accent)"/>'
        '<path d="M5 9h1m-1 7h1m-1 7h1M26 9h1m-1 7h1m-1 7h1" '
        'stroke="#DEE8FF" stroke-width="2"/>',
  ),
  'album': _Illustration(
    '#E5B8EC',
    '#AD79C0',
    '#A8DCE8',
    '#659EC7',
    '<rect x="3" y="7" width="23" height="23" rx="4" fill="url(#main)"/>'
        '<rect x="7" y="2" width="23" height="23" rx="4" fill="url(#accent)"/>'
        '<rect x="10" y="5" width="17" height="16" rx="2" fill="#EFF9FF"/>'
        '<circle cx="23" cy="9" r="2" fill="#FFD090"/>'
        '<path d="m10 19 5-8 6 7 3-3 3 4v2H10Z" fill="#78BAA6"/>',
  ),
  'repository': _Illustration(
    '#A2D6EB',
    '#619DBE',
    '#B6ACEE',
    '#8370BE',
    '<path d="M3 9V7a3 3 0 0 1 3-3h6l4 5h10a3 3 0 0 1 3 3v14'
        'a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3Z" fill="url(#main)"/>'
        '<rect x="7" y="12" width="18" height="13" rx="3" fill="url(#accent)"/>'
        '<path d="m12 16-3 3 3 3m8-6 3 3-3 3m-3-7-2 8" '
        'stroke="#F1F4FF" stroke-width="1.6"/>',
  ),
  'database': _Illustration(
    '#A8DFEA',
    '#538FAE',
    '#BEB3F2',
    '#8772C1',
    '<path d="M4 8h24v17c0 7-24 7-24 0Z" fill="url(#main)"/>'
        '<ellipse cx="16" cy="8" rx="12" ry="5" fill="url(#accent)"/>'
        '<path d="M4 15c0 7 24 7 24 0M4 22c0 7 24 7 24 0" '
        'stroke="#E4F8FC" stroke-width="1.3"/>'
        '<path d="M8 8c4-2 12-2 16 0" stroke="#EDE8FF" stroke-width="1.2"/>',
  ),
  'bookmark': _Illustration(
    '#ADCDF2',
    '#6A96CB',
    '#FFD79B',
    '#E9A768',
    '$_panelFace<path d="M11 10h10v14l-5-3-5 3Z" fill="url(#accent)"/>'
        '<path d="M14 13h4" stroke="#FFF5D9" stroke-width="1.3"/>',
  ),
  'mail': _Illustration(
    '#C2E4EF',
    '#71A7C9',
    '#F3CCEA',
    '#C48DBB',
    '<rect x="2" y="6" width="28" height="23" rx="4" fill="url(#main)"/>'
        '<path d="m3 8 11 9a3 3 0 0 0 4 0l11-9-9 1H9Z" fill="url(#accent)"/>'
        '<path d="m4 26 8-8m16 8-8-8M6 9l9 7a1.5 1.5 0 0 0 2 0l9-7" '
        'stroke="#EEF7FF" stroke-width="1.3"/>',
  ),
  'table': _Illustration(
    '#A8D8CE',
    '#569F97',
    '#A8C7F4',
    '#779ACE',
    '$_panelFace<path d="M5 17h22M5 22h22M12 12v14M20 12v14" '
        'stroke="#91B7B4" stroke-width="1.2"/>',
  ),
  'board': _Illustration(
    '#B3C4F3',
    '#7C8BC5',
    '#CBB6F0',
    '#AA87CE',
    '$_panelFace<rect x="7" y="14" width="5" height="9" rx="1.3" fill="#98C9BE"/>'
        '<rect x="14" y="14" width="5" height="5" rx="1.3" fill="#F4C48C"/>'
        '<rect x="21" y="14" width="4" height="11" rx="1.3" fill="#AFA0D7"/>',
  ),
  'chat': _Illustration(
    '#A6DCE9',
    '#5B9DC0',
    '#FFE2AA',
    '#F0BA7C',
    '$_chatFace<g fill="url(#accent)"><circle cx="9" cy="15" r="2"/>'
        '<circle cx="16" cy="15" r="2"/><circle cx="23" cy="15" r="2"/></g>',
  ),
  'ai-chat': _Illustration(
    '#C4B3F5',
    '#8770C9',
    '#FFE6AC',
    '#F0BB78',
    '$_chatFace<path d="m16 8 2.2 5.8L24 16l-5.8 2.2L16 24l-2.2-5.8'
        'L8 16l5.8-2.2Z" fill="url(#accent)"/>'
        '<path d="m25 2 1 3 3 1-3 1-1 3-1-3-3-1 3-1Z" fill="#A6ECE2"/>',
  ),
  'map': _Illustration(
    '#A5D5EB',
    '#5893BB',
    '#B2DEAC',
    '#6CAD8C',
    '<path d="m2 8 9-4 10 4 9-4v23l-9 4-10-4-9 4Z" fill="url(#main)"/>'
        '<path d="m11 4 10 4v23l-10-4Z" fill="url(#accent)"/>'
        '<path d="m3 18 8-3 10 5 8-4M11 5v21M21 9v21" '
        'stroke="#EFF8DB" stroke-width="1.4"/>'
        '<path d="M25 7c0 4-5 8-5 8s-5-4-5-8a5 5 0 0 1 10 0Z" fill="#E9838C"/>'
        '<circle cx="20" cy="7" r="2" fill="#FFEDE2"/>',
  ),
  'slides': _Illustration(
    '#B6C5EE',
    '#7F90C4',
    '#F3C79D',
    '#D99A78',
    '<rect x="2" y="9" width="6" height="17" rx="2" fill="url(#accent)"/>'
        '<rect x="24" y="9" width="6" height="17" rx="2" fill="url(#accent)"/>'
        '<rect x="6" y="4" width="20" height="25" rx="3" fill="url(#main)"/>'
        '<rect x="9" y="7" width="14" height="11" rx="2" fill="#F7EFD9"/>'
        '<path d="m10 16 4-6 3 4 3-2 2 4Z" fill="#99C5B1"/>'
        '<path d="M10 22h12M10 25h8" stroke="#EEF3FF" stroke-width="1.4"/>',
  ),
  'timeline': _Illustration(
    '#AED4EB',
    '#6A9CBC',
    '#C4B0EA',
    '#9672C3',
    '$_panelFace<path d="M10 14v10M21 14v10" stroke="#C2CCD3" stroke-width="1"/>'
        '<rect x="7" y="15" width="12" height="3" rx="1.5" fill="url(#main)"/>'
        '<rect x="13" y="21" width="12" height="3" rx="1.5" fill="url(#accent)"/>',
  ),
  'feed': _Illustration(
    '#D4C1EE',
    '#AC90CC',
    '#A2D1D9',
    '#719FAB',
    '$_panelFace<rect x="7" y="14" width="5" height="5" rx="1" fill="#F2C395"/>'
        '<path d="M15 15h9M15 18h7M7 22h17" stroke="#9A8DB0" stroke-width="1.3"/>',
  ),
  'form': _Illustration(
    '#B9DDCB',
    '#7FAE97',
    '#DFC4EC',
    '#B38BC4',
    '$_panelFace<path d="m7 16 1 1 2-3m-3 9 1 1 2-3M14 16h10M14 23h10" '
        'stroke="#74998C" stroke-width="1.5"/>',
  ),
  'gallery': _Illustration(
    '#E9C2D8',
    '#C58DAE',
    '#ADC8EF',
    '#7B9BC7',
    '$_panelFace<rect x="7" y="14" width="7" height="10" rx="1.5" fill="#B8DBCB"/>'
        '<rect x="17" y="14" width="7" height="10" rx="1.5" fill="#EDD09D"/>'
        '<path d="m8 20 2-3 3 4m5-1 2-3 3 4" stroke="#FCFFF3" stroke-width="1.2"/>',
  ),
  'dashboard': _Illustration(
    '#ADCFEF',
    '#729BC7',
    '#CDB5EA',
    '#A283C4',
    '$_panelFace<rect x="7" y="14" width="7" height="10" rx="1.5" fill="#9CCDBD"/>'
        '<rect x="17" y="14" width="7" height="4" rx="1.3" fill="#EDC995"/>'
        '<rect x="17" y="20" width="7" height="4" rx="1.3" fill="#C6AFDD"/>',
  ),
  'canvas': _Illustration(
    '#E2D3B8',
    '#B9A489',
    '#B9C8F1',
    '#889BCC',
    '<rect x="3" y="3" width="26" height="26" rx="4" fill="url(#main)"/>'
        '<rect x="5" y="5" width="22" height="22" rx="2" fill="#FFF5DE"/>'
        '<path d="M11 12v9h10" stroke="#9CABB7" stroke-width="1.5"/>'
        '<rect x="7" y="7" width="10" height="9" rx="2" fill="url(#accent)"/>'
        '<rect x="18" y="18" width="7" height="7" rx="2" fill="#E7AF91"/>',
  ),
};
