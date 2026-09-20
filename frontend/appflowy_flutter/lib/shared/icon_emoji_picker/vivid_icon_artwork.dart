// Original artwork authored for AppFlowy's Vivid collection; distributed under
// the repository's LICENSE. Not copied from or attributed to Fluent Emoji.

/// Rounded illustrations on a consistent 32px grid. Gradients, inset highlights
/// and contrasting faces supply depth without filters or embedded raster data.
/// The canvas is transparent: pale fills are object details, not UI surfaces.
String? vividIconSvg(String name) {
  final art = _illustrations[name];
  if (art == null) return null;
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
      '</defs>${art.body}</svg>';
}

class _Illustration {
  const _Illustration(
    this.light,
    this.shade,
    this.accentLight,
    this.accentShade,
    this.body,
  );

  final String light;
  final String shade;
  final String accentLight;
  final String accentShade;
  final String body;
}

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
};
