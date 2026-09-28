/// Purpose-drawn defaults shared by navigation and the icon picker. A 24px
/// grid, 1.75px stroke and round caps/joins keep every symbol optically related.
/// These artwork keys retain the sidebar's original compatibility identities;
/// selected defaults use the separate namespaced catalogue in default_icons.dart.
String? defaultIconSvg(String name) => _defaultIconSvgs[name];

/// Includes chrome-only symbols as well as the selectable defaults.
Iterable<String> get defaultIconNames => _defaultIconSvgs.keys;

final _defaultIconSvgs = _bodies.map(
  (name, body) => MapEntry(
    name,
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.75" '
    'stroke-linecap="round" stroke-linejoin="round">$body</svg>',
  ),
);

// A rounded sheet and folded corner shared by all file types. Simple marks
// stay legible at navigation size, unlike tiny PDF/DOC/XLS lettering.
const _sheet = '<path d="M13.5 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12'
    'a2 2 0 0 0 2-2V9.5L13.5 3Z"/>'
    '<path d="M13.5 3v4.5a2 2 0 0 0 2 2H20"/>';

const _cloud = '<path d="M7 18a5 5 0 0 1-1-9.9 6.5 6.5 0 0 1 12.5-1.6'
    'A5.8 5.8 0 0 1 19 19"/>';
const _heading = '<path d="M4 5v14M12 5v14M4 12h8"/>';
const _one = '<path d="m16 12 2-1v8m-2 0h4"/>';
const _two = '<path d="M16 12c0-2 4-2 4 0s-4 3-4 5v2h4"/>';
const _three = '<path d="M16 11h2a2 2 0 0 1 0 4h-1m1 0a2 2 0 0 1 0 4h-2"/>';
const _toggleHeading = '<path d="m2 9 3 3-3 3M8 5v14M13 5v14M8 12h5"/>';
const _columnFrame = '<rect x="3" y="4" width="18" height="16" rx="2"/>';
const _eye = '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/>'
    '<circle cx="12" cy="12" r="3"/>';
const _filter = '<path d="M3 4h18l-7 8v7l-4 2v-9L3 4Z"/>';
const _palette = '<path d="M12 3a9 9 0 1 0 0 18c2 0 3-1 2-3s0-3 2-2'
    'c3 1 5-1 5-4a9 9 0 0 0-9-9Z"/>'
    '<circle cx="7" cy="10" r=".7"/><circle cx="11" cy="7" r=".7"/>'
    '<circle cx="16" cy="8" r=".7"/>';

const _bodies = <String, String>{
  'magnifying-glass': '<circle cx="10.5" cy="10.5" r="6.5"/>'
      '<path d="m15.5 15.5 5 5"/>',
  'note-pencil': '<path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12'
      'a2 2 0 0 0 2-2v-6M15.5 4.5l4 4M9 16l1-5 8-8a2.8 2.8 0 0 1 4 4'
      'l-8 8-5 1Z"/>',
  'house': '<path d="m3 10 7.8-6.4a2 2 0 0 1 2.4 0L21 10'
      'M5 9v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9'
      'M9 21v-7a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v7"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'dots-three': '<g fill="currentColor" stroke="none">'
      '<circle cx="5" cy="12" r="1.35"/>'
      '<circle cx="12" cy="12" r="1.35"/>'
      '<circle cx="19" cy="12" r="1.35"/></g>',
  'dots-six-vertical': '<g fill="currentColor" stroke="none">'
      '<circle cx="9" cy="6" r="1.5"/><circle cx="15" cy="6" r="1.5"/>'
      '<circle cx="9" cy="12" r="1.5"/><circle cx="15" cy="12" r="1.5"/>'
      '<circle cx="9" cy="18" r="1.5"/><circle cx="15" cy="18" r="1.5"/></g>',
  'dots-two-vertical': '<g fill="currentColor" stroke="none">'
      '<circle cx="12" cy="8" r="1.5"/><circle cx="12" cy="16" r="1.5"/></g>',
  'dock-left': '<path d="M3 3v18M21 12H8m5-5-5 5 5 5"/>',
  'chevrons-left': '<path d="m11 5-7 7 7 7m9-14-7 7 7 7"/>',
  'chevrons-right': '<path d="m4 5 7 7-7 7m9-14 7 7-7 7"/>',
  'caret-right': '<path d="m9 5 7 7-7 7"/>',
  'caret-down': '<path d="m5 9 7 7 7-7"/>',
  'caret-up-down': '<path d="m8 8 4-4 4 4m-8 8 4 4 4-4"/>',
  'sidebar-simple': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M9 4v16"/>',
  'trash': '<path d="M4 7h16M9 7V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v3'
      'M6 7l.8 12.1A2 2 0 0 0 8.8 21h6.4a2 2 0 0 0 2-1.9L18 7'
      'M10 11v6M14 11v6"/>',
  'layout': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M3 9h18M9 9v11"/>',
  'puzzle-piece': '<path d="M9 4H5a1 1 0 0 0-1 1v4a3 3 0 1 0 0 6v4'
      'a1 1 0 0 0 1 1h4a3 3 0 1 1 6 0h4a1 1 0 0 0 1-1v-4'
      'a3 3 0 1 0 0-6V5a1 1 0 0 0-1-1h-4a3 3 0 1 0-6 0Z"/>',
  'push-pin': '<path d="M8 3h8l-1 6 3 4v2H6v-2l3-4-1-6ZM12 15v6"/>',
  'gear': '<path d="m10 3-.5 2.2-2 .9-2-.7-2 3.4L5 10.5v3'
      'l-1.5 1.7 2 3.4 2-.7 2 .9.5 2.2h4l.5-2.2 2-.9 2 .7 2-3.4'
      '-1.5-1.7v-3l1.5-1.7-2-3.4-2 .7-2-.9L14 3h-4Z"/>'
      '<circle cx="12" cy="12" r="3"/>',
  'bell': '<path d="M18 8a6 6 0 0 0-12 0v5l-2 4h16l-2-4V8'
      'M9.5 20a2.8 2.8 0 0 0 5 0"/>',
  'file-text': '$_sheet<path d="M8 12h3M8 16h8"/>',
  'folder': '<path d="M3 8V6a2 2 0 0 1 2-2h4.2a2 2 0 0 1 1.5.7L12.8 7H19'
      'a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Z"/>',
  'folder-open': '<path d="M3 17V6a2 2 0 0 1 2-2h4l3 3h6a2 2 0 0 1 2 2v2'
      'M5 20h13a2 2 0 0 0 1.9-1.4l2-6A1.2 1.2 0 0 0 20.8 11H8'
      'a2 2 0 0 0-1.9 1.4l-2 6A1.2 1.2 0 0 0 5 20Z"/>',
  'table': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M3 9h18M3 14h18M9 9v11"/>',
  'kanban': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M8 8v7M12 8v4M16 8v9"/>',
  'calendar-blank': '<rect x="3" y="5" width="18" height="16" rx="2.5"/>'
      '<path d="M7 3v4M17 3v4M3 10h18M8 14h2M14 14h2M8 17h2"/>',
  'chat-circle': '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5'
      ' 9 9 0 0 1-4-.9L3 21l1.9-5.5a9 9 0 0 1-.9-4A8.5 8.5 0 0 1 21 11.5Z"/>',
  'ai-chat': '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5'
      ' 9 9 0 0 1-4-.9L3 21l1.9-5.5a9 9 0 0 1-.9-4A8.5 8.5 0 0 1 21 11.5Z"/>'
      '<path d="m12.5 7 1.3 3.2 3.2 1.3-3.2 1.3-1.3 3.2-1.3-3.2'
      '-3.2-1.3 3.2-1.3 1.3-3.2Z"/>',
  'chart-bar': '<path d="M4 3v16a1 1 0 0 0 1 1h16M9 15v-5M14 15V5'
      'M19 15V8"/>',
  'map-trifold': '<path d="m9 4-6 3v13l6-3 6 3 6-3V4l-6 3-6-3Z'
      'M9 4v13M15 7v13"/>',
  'presentation-chart': '<rect x="3" y="4" width="18" height="13" rx="2"/>'
      '<path d="M12 17v4M8 22l4-2 4 2M7 12l3-3 3 3 4-5"/>',
  'graph': '<path d="M4 5h8M10 12h10M4 19h10M7 3v4M16 10v4M9 17v4"/>',
  'article': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M7 8h10M7 12h10M7 16h6"/>',
  'list-checks': '<path d="m3 6 1.5 1.5L7 4M11 6h10'
      'm-18 6 1.5 1.5L7 10M11 12h10m-18 6 1.5 1.5L7 16M11 18h7"/>',
  'squares-four': '<rect x="3" y="3" width="7" height="7" rx="2"/>'
      '<rect x="14" y="3" width="7" height="7" rx="2"/>'
      '<rect x="3" y="14" width="7" height="7" rx="2"/>'
      '<rect x="14" y="14" width="7" height="7" rx="2"/>',
  'envelope-simple': '<rect x="3" y="5" width="18" height="14" rx="2.5"/>'
      '<path d="m4 7 6.8 5.1a2 2 0 0 0 2.4 0L20 7"/>',
  // Closed cover, bound spine and the curved page edge along the bottom.
  'book-open': '<path d="M7.5 3H18a1.5 1.5 0 0 1 1.5 1.5V21h-12'
      'A2.5 2.5 0 0 1 5 18.5v-13A2.5 2.5 0 0 1 7.5 3Z"/>'
      '<path d="M5 18.5A2.5 2.5 0 0 1 7.5 16h12M9 3v13"/>',
  'images': '<rect x="6" y="3" width="15" height="15" rx="2.5"/>'
      '<path d="M17 18v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9'
      'a2 2 0 0 1 2-2h1m0 7 4-4 4 4 3-3 4 4"/>'
      '<circle cx="16.5" cy="7.5" r="1" fill="currentColor" stroke="none"/>',
  // A repository is a collection of code, not an isolated branch diagram.
  'git-branch': '<path d="M3 8V6a2 2 0 0 1 2-2h4.2a2 2 0 0 1 1.5.7L12.8 7H19'
      'a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Z"/>'
      '<path d="m9.5 11.5-2.5 2.5 2.5 2.5m5-5 2.5 2.5-2.5 2.5"/>',
  'database': '<ellipse cx="12" cy="5.5" rx="8" ry="3"/>'
      '<path d="M4 5.5v13c0 4 16 4 16 0v-13M4 12c0 4 16 4 16 0"/>',
  'link-simple': '<path d="m10 8 3-3a4.3 4.3 0 0 1 6 6l-3 3'
      'M14 16l-3 3a4.3 4.3 0 0 1-6-6l3-3M8.5 15.5l7-7"/>',
  'file': _sheet,
  'file-pdf': '$_sheet<path d="M8 13h8M8 17h5"/>',
  'file-doc': '$_sheet<path d="M8 12h3M8 15.5h8M8 19h6"/>',
  'file-xls': '$_sheet<rect x="7.5" y="12" width="9" height="6.5" rx="1"/>'
      '<path d="M7.5 15.3h9M12 12v6.5"/>',
  'file-ppt': '$_sheet<rect x="7.5" y="12" width="9" height="5" rx="1"/>'
      '<path d="M12 17v2.5M10 19.5h4"/>',
  'file-zip': '$_sheet<path d="M9 3v3h2v3H9v3h2v3"/>'
      '<rect x="8.5" y="15" width="3" height="4" rx="1"/>',
  'file-code': '$_sheet<path d="m10 12.5-2.5 3 2.5 3m4-6 2.5 3-2.5 3"/>',
  'file-csv': '$_sheet<path d="M8 12h8M8 15.5h8M8 19h8M11 12v7"/>',
  'file-markdown': '$_sheet<path d="M7 18v-6l3 3 3-3v6m3-6v6m-2-2 2 2 2-2"/>',
  'file-html': '$_sheet<path d="m10 12-3 3 3 3m5-6 3 3-3 3M13 11l-2 8"/>',
  'file-json':
      '$_sheet<path d="M10 12H9v2l-1 1 1 1v2h1m4-6h1v2l1 1-1 1v2h-1"/>',
  'file-notebook': '<rect x="5" y="3" width="15" height="18" rx="2"/>'
      '<path d="M3 7h4M3 12h4M3 17h4M10 8h6m-6 4 2 2-2 2m4 0h3"/>',
  'image': '<rect x="3" y="3" width="18" height="18" rx="3"/>'
      '<path d="m3 16 5-5 5 5 3-3 5 5"/>'
      '<circle cx="15.5" cy="7.5" r="1" fill="currentColor" stroke="none"/>',
  'film-strip': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
  'music-note': '<path d="M9 18V6l11-3v12M9 10l11-3"/>'
      '<ellipse cx="6" cy="18" rx="3" ry="2.5"/>'
      '<ellipse cx="17" cy="15" rx="3" ry="2.5"/>',
  // Original chrome artwork. Never turn a filled font silhouette into an
  // outline by recolouring it: each mark shares the grid/stroke above.
  'user': '<circle cx="12" cy="8" r="4"/>'
      '<path d="M4 21v-2a8 6 0 0 1 16 0v2"/>',
  'users': '<circle cx="9" cy="8" r="3.5"/>'
      '<path d="M2 21v-2a7 6 0 0 1 14 0v2M16 4a3.5 3.5 0 0 1 0 7'
      'M18 14a6 5 0 0 1 4 5v2"/>',
  'workspace': '<rect x="4" y="4" width="16" height="17" rx="2"/>'
      '<path d="M8 8h1m6 0h1M8 12h1m6 0h1M10 21v-5h4v5"/>',
  'cloud': '<path d="M7 19a5 5 0 0 1-1-9.9 6.5 6.5 0 0 1 12.5-1.6'
      'A5.8 5.8 0 0 1 19 19H7Z"/>',
  'cloud-upload': '$_cloud<path d="M12 22V12m-3 3 3-3 3 3"/>',
  'cloud-download': '$_cloud<path d="M12 12v10m-3-3 3 3 3-3"/>',
  'cloud-off': '<path d="M5.5 9.2A5 5 0 0 0 7 19h11M9 4.8'
      'a6.5 6.5 0 0 1 9.5 2.7 5.8 5.8 0 0 1 3 8M3 3l18 18"/>',
  'keyboard': '<rect x="2" y="5" width="20" height="14" rx="2.5"/>'
      '<path d="M6 9h.5m4 0h.5m4 0h.5M6 12h.5m4 0h.5m4 0h.5m3-3h.5'
      'M8 16h8"/>',
  'sparkles': '<path d="m10 3 2.5 6.5L19 12l-6.5 2.5L10 21l-2.5-6.5'
      'L1 12l6.5-2.5L10 3Zm9-2 1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3Z"/>',
  'globe': '<circle cx="12" cy="12" r="9"/>'
      '<ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  'credit-card': '<rect x="2" y="5" width="20" height="14" rx="2.5"/>'
      '<path d="M2 10h20M6 15h4"/>',
  'plan': '<path d="m3 6 5 4 4-7 4 7 5-4-2 13H5L3 6ZM5 15h14"/>',
  'history': '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6M12 7v5l4 2"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
  'lock': '<rect x="5" y="10" width="14" height="11" rx="2"/>'
      '<path d="M8 10V7a4 4 0 0 1 8 0v3M12 15v2"/>',
  'lock-open': '<rect x="5" y="10" width="14" height="11" rx="2"/>'
      '<path d="M8 10V7a4 4 0 0 1 7.5-2M12 15v2"/>',
  'shield': '<path d="m12 2 8 3v6c0 5-3 8-8 11-5-3-8-6-8-11V5l8-3Z"/>',
  'connections': '<circle cx="12" cy="12" r="3"/>'
      '<circle cx="5" cy="4" r="2"/><circle cx="20" cy="6" r="2"/>'
      '<circle cx="4" cy="20" r="2"/><circle cx="20" cy="20" r="2"/>'
      '<path d="m6.5 5.5 3.5 4m4.5.5 4-3m-9 7-4 4m9-3.5 4 4"/>',
  'flag': '<path d="M5 22V3m0 1c5-4 9 4 15 0v10c-6 4-10-4-15 0"/>',
  'scan-document': '<path d="M7 3H4a1 1 0 0 0-1 1v3m14-4h3a1 1 0 0 1 1 1v3'
      'M3 17v3a1 1 0 0 0 1 1h3m10 0h3a1 1 0 0 0 1-1v-3"/>'
      '<rect x="7" y="5" width="10" height="14" rx="1.5"/>'
      '<path d="M10 9h4M10 12h4M10 15h2"/>',
  'text': '<path d="M4 6V4h16v2M12 4v16M8 20h8"/>',
  'heading-1': '$_heading$_one',
  'heading-2': '$_heading$_two',
  'heading-3': '$_heading$_three',
  'toggle-heading-1': '$_toggleHeading$_one',
  'toggle-heading-2': '$_toggleHeading$_two',
  'toggle-heading-3': '$_toggleHeading$_three',
  'bullets': '<path d="M9 6h12M9 12h12M9 18h12"/>'
      '<circle cx="4" cy="6" r=".75"/><circle cx="4" cy="12" r=".75"/>'
      '<circle cx="4" cy="18" r=".75"/>',
  'numbered-list': '<path d="m2 4 2-1v6M2 9h4M2 15c0-3 4-3 4 0'
      ' 0 2-4 3-4 6h4M10 6h11M10 12h11M10 18h11"/>',
  // A code gutter and its hidden state, not density or list-formatting icons.
  'line-numbers': '<path d="m2 4 1-1v5M2 8h2M2 12c0-2 2-2 2 0'
      'l-2 3h2M2 18h2l-1 2 1 1H2M7 3v18M10 5h11M10 12h8M10 19h11"/>',
  'line-numbers-off': '<path d="M4 5h17M4 12h12M4 19h17"/>',
  'table-of-contents': '<path d="M3 6h12M3 12h12M3 18h12"/>'
      '<circle cx="20" cy="6" r=".75"/><circle cx="20" cy="12" r=".75"/>'
      '<circle cx="20" cy="18" r=".75"/>',
  'music-list': '<path d="M3 5h10M3 10h10M3 15h6M18 17V7l4 2"/>'
      '<ellipse cx="15" cy="18" rx="3" ry="2.5"/>',
  'squares-nine': '<rect x="3" y="3" width="4" height="4" rx="1"/>'
      '<rect x="10" y="3" width="4" height="4" rx="1"/>'
      '<rect x="17" y="3" width="4" height="4" rx="1"/>'
      '<rect x="3" y="10" width="4" height="4" rx="1"/>'
      '<rect x="10" y="10" width="4" height="4" rx="1"/>'
      '<rect x="17" y="10" width="4" height="4" rx="1"/>'
      '<rect x="3" y="17" width="4" height="4" rx="1"/>'
      '<rect x="10" y="17" width="4" height="4" rx="1"/>'
      '<rect x="17" y="17" width="4" height="4" rx="1"/>',
  'reorder': '<path d="M3 5h18M3 10h18M3 15h18M3 20h18"/>',
  'checkbox': '<rect x="3" y="3" width="18" height="18" rx="3"/>'
      '<path d="m7 12 3.5 3.5L17 8"/>',
  'square': '<rect x="3" y="3" width="18" height="18" rx="3"/>',
  'circle': '<circle cx="12" cy="12" r="9"/>',
  'radio': '<circle cx="12" cy="12" r="9"/>'
      '<circle cx="12" cy="12" r="4"/>',
  'toggle-list': '<path d="m3 4 5 4-5 4V4ZM12 8h9M12 14h9M12 20h6"/>',
  'quote': '<path d="M4 6h6v7H5v2a3 3 0 0 0 3 3M14 6h6v7h-5v2'
      'a3 3 0 0 0 3 3"/>',
  'code': '<path d="m8 6-6 6 6 6m8-12 6 6-6 6M14 4l-4 16"/>',
  'divider': '<path d="M3 12h18"/>',
  'emoji': '<circle cx="12" cy="12" r="9"/>'
      '<path d="M8 9h.1m7.9 0h.1M7 14a5.5 5.5 0 0 0 10 0"/>',
  'columns-2': '$_columnFrame<path d="M12 4v16"/>',
  'columns-3': '$_columnFrame<path d="M9 4v16M15 4v16"/>',
  'columns-4': '$_columnFrame<path d="M7.5 4v16M12 4v16M16.5 4v16"/>',
  'rows': '$_columnFrame<path d="M3 9h18M3 15h18"/>',
  'tree': '<rect x="9" y="2" width="6" height="5" rx="1"/>'
      '<rect x="2" y="17" width="6" height="5" rx="1"/>'
      '<rect x="16" y="17" width="6" height="5" rx="1"/>'
      '<path d="M12 7v5M5 17v-5h14v5"/>',
  'sigma': '<path d="M20 4H5l8 8-8 8h15M20 4v3M20 17v3"/>',
  'pen': '<path d="m5 15 11-11a2.8 2.8 0 0 1 4 4L9 19l-6 2 2-6Z'
      'M14 6l4 4M5 15l4 4"/>',
  'sticky-note': '<path d="M20 14V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14'
      'a2 2 0 0 0 2 2h8l7-7Zm-7 7v-5a2 2 0 0 1 2-2h5M7 8h9M7 12h5"/>',
  'button': '<rect x="3" y="7" width="18" height="10" rx="4"/>'
      '<path d="M8 12h8"/>',
  'gauge': '<path d="M4.5 19a9 9 0 1 1 15 0H4.5ZM12 13l4-5'
      'M5 12h1M8 6.5l.5 1M18 12h1"/><circle cx="12" cy="14" r="1.5"/>',
  'plus-one': '<path d="M6 6v12M1 12h10m4-5 3-2v14m-3 0h6"/>',
  'cards': '<rect x="7" y="3" width="14" height="16" rx="2"/>'
      '<path d="M4 7H3v13a2 2 0 0 0 2 2h12M11 8h6M11 12h4"/>',
  'input': '<rect x="2" y="6" width="20" height="12" rx="2"/>'
      '<path d="M6 9v6M10 12h7"/>',
  'select': '<rect x="2" y="6" width="20" height="12" rx="2"/>'
      '<path d="M6 12h4m4-1 3 3 3-3"/>',
  'bell-ringing': '<path d="M18 9a6 6 0 0 0-12 0v4l-2 4h16l-2-4V9'
      'M10 21h4M2 8a11 11 0 0 1 2-5m18 5a11 11 0 0 0-2-5"/>',
  'canvas': '<rect x="4" y="4" width="16" height="16" rx="2"/>'
      '<path d="M1 4h3M4 1v3m16-3v3m3 0h-3M1 20h3m0 3v-3m16 3v-3'
      'm3 0h-3M8 8h4v4H8Zm6 6h3v3h-3Z"/>',
  'check': '<path d="m4 12 5 5L20 6"/>',
  'check-all': '<path d="m2 12 5 5L18 6m-5 11 9-9"/>',
  'x': '<path d="m6 6 12 12M6 18 18 6"/>',
  'caret-left': '<path d="m15 5-7 7 7 7"/>',
  'caret-up': '<path d="m5 15 7-7 7 7"/>',
  'collapse': '<path d="m8 4 4 4 4-4m-8 16 4-4 4 4"/>',
  'arrow-left': '<path d="M21 12H3m7-7-7 7 7 7"/>',
  'arrow-right': '<path d="M3 12h18m-7-7 7 7-7 7"/>',
  'arrow-up': '<path d="M12 21V3m-7 7 7-7 7 7"/>',
  'arrow-down': '<path d="M12 3v18m-7-7 7 7 7-7"/>',
  'arrow-outward': '<path d="m5 19 14-14M6 5h13v13"/>',
  'arrows-horizontal': '<path d="M3 7h18m-4-4 4 4-4 4M21 17H3m4-4-4 4 4 4"/>',
  'arrows-vertical': '<path d="M7 21V3m-4 4 4-4 4 4M17 3v18m-4-4 4 4 4-4"/>',
  'external-link': '<path d="M13 3h8v8m0-8L10 14M10 4H5a2 2 0 0 0-2 2v13'
      'a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-5"/>',
  'fullscreen': '<path d="M9 3H3v6m12-6h6v6M3 15v6h6m6 0h6v-6"/>',
  'fullscreen-exit': '<path d="M3 9h6V3m6 0v6h6M3 15h6v6m6 0v-6h6"/>',
  'fit': '<path d="M7 3H3v4m14-4h4v4M3 17v4h4m10 0h4v-4"/>'
      '<rect x="6" y="8" width="12" height="8" rx="1"/>',
  'download': '<path d="M12 3v12m-5-5 5 5 5-5M3 16v4a1 1 0 0 0 1 1h16'
      'a1 1 0 0 0 1-1v-4"/>',
  'upload': '<path d="M12 16V3m-5 5 5-5 5 5M3 16v4a1 1 0 0 0 1 1h16'
      'a1 1 0 0 0 1-1v-4"/>',
  'folder-plus': '<path d="M3 8V6a2 2 0 0 1 2-2h4l3 3h7a2 2 0 0 1 2 2v9'
      'a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8ZM12 10v7m-3-3.5h6"/>',
  'folder-upload': '<path d="M3 8V6a2 2 0 0 1 2-2h4l3 3h7a2 2 0 0 1 2 2v9'
      'a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8ZM12 18v-7m-3 3 3-3 3 3"/>',
  'folder-move': '<path d="M3 8V6a2 2 0 0 1 2-2h4l3 3h7a2 2 0 0 1 2 2v9'
      'a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8ZM8 14h8m-3-3 3 3-3 3"/>',
  'file-plus': '$_sheet<path d="M8 15h8M12 11v8"/>',
  'copy': '<rect x="8" y="8" width="13" height="13" rx="2"/>'
      '<path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9'
      'a2 2 0 0 0 2 2h3"/>',
  'duplicate': '<rect x="7" y="7" width="14" height="14" rx="2"/>'
      '<path d="M16 3H5a2 2 0 0 0-2 2v11M10 14h8m-4-4v8"/>',
  'paste': '<rect x="8" y="2" width="8" height="5" rx="1.5"/>'
      '<path d="M8 4H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14'
      'a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-3M7 12h10M7 16h7"/>',
  'paste-go': '<rect x="7" y="2" width="8" height="5" rx="1.5"/>'
      '<path d="M7 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8M15 4h3'
      'a2 2 0 0 1 2 2v3M12 16h10m-4-4 4 4-4 4"/>',
  'scissors': '<circle cx="5" cy="6" r="3"/><circle cx="5" cy="18" r="3"/>'
      '<path d="m7.5 7.5 14 13m-14-4 14-13"/>',
  'star': '<path d="m12 2 3 6.2 6.8 1-4.9 4.8 1.2 6.8-6.1-3.2-6.1 3.2'
      'L7.1 14 2.2 9.2l6.8-1L12 2Z"/>',
  'bookmark': '<path d="M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1Z"/>',
  'share': '<path d="M12 16V2m-4 4 4-4 4 4M7 9H4v12h16V9h-3"/>',
  'eye': _eye,
  'eye-off': '<path d="M3 3l18 18M9 5.5a10 10 0 0 1 3-.5'
      'c6.5 0 10 7 10 7a17 17 0 0 1-3 4M5 7a20 20 0 0 0-3 5'
      's3.5 7 10 7a11 11 0 0 0 5-1.3M10 10a3 3 0 0 0 4 4"/>',
  'info': '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
  'warning': '<path d="m12 3 10 18H2L12 3ZM12 9v5M12 17h.01"/>',
  'refresh': '<path d="M3 10a9 9 0 0 1 15-6l3 3M21 2v5h-5'
      'M21 14a9 9 0 0 1-15 6l-3-3M3 22v-5h5"/>',
  'undo': '<path d="M3 9h11a7 7 0 0 1 0 14M8 4 3 9l5 5"/>',
  'redo': '<path d="M21 9H10a7 7 0 0 0 0 14m6-19 5 5-5 5"/>',
  'sort': '<path d="M3 6h18M3 12h12M3 18h6"/>',
  'filter': _filter,
  'filter-off': '$_filter<path d="m2 2 20 20"/>',
  'sliders': '<path d="M3 6h3m4 0h11M3 12h11m4 0h3M3 18h5m4 0h9"/>'
      '<circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/>'
      '<circle cx="10" cy="18" r="2"/>',
  'palette': _palette,
  'paint-off': '$_palette<path d="m2 2 20 20"/>',
  'format-clear': '<path d="M5 4h14M12 4 8 20m-4 0h8m4-5 6 6m-6 0 6-6"/>',
  'bold': '<path d="M6 3h7a4.5 4.5 0 0 1 0 9H6V3Zm0 9h8'
      'a4.5 4.5 0 0 1 0 9H6v-9Z"/>',
  'italic': '<path d="M10 3h10M4 21h10M15 3 9 21"/>',
  'underline': '<path d="M6 3v8a6 6 0 0 0 12 0V3M4 21h16"/>',
  'strikethrough': '<path d="M18 6c-2-4-11-4-11 1 0 3 3 3 6 4'
      'm3 3c5 6-6 9-10 4M3 12h18"/>',
  'align-left': '<path d="M3 5h18M3 10h12M3 15h18M3 20h12"/>',
  'align-center': '<path d="M3 5h18M6 10h12M3 15h18M6 20h12"/>',
  'align-right': '<path d="M3 5h18M9 10h12M3 15h18M9 20h12"/>',
  'align-justify': '<path d="M3 5h18M3 10h18M3 15h18M3 20h18"/>',
  'indent': '<path d="M3 4h18M11 9h10M11 15h10M3 20h18m0-12 4 4-4 4"/>',
  'outdent': '<path d="M3 4h18M11 9h10M11 15h10M3 20h18M7 8l-4 4 4 4"/>',
  'ruler': '<path d="m3 16 13-13 5 5L8 21l-5-5Zm6-6 2 2m2-6 2 2M5 14l2 2"/>',
  'width': '<path d="M3 4v16M21 4v16M6 12h12m-3-3 3 3-3 3M9 9l-3 3 3 3"/>',
  'spacing': '<path d="M4 12h16"/><circle cx="4" cy="12" r="2"/>'
      '<circle cx="20" cy="12" r="2"/>',
  'aspect-ratio': '<rect x="2" y="5" width="20" height="14" rx="2"/>'
      '<path d="M6 12V9h4m4 6h4v-3"/>',
  'crop': '<path d="M7 2v15h15M2 7h15v15M7 7h10"/>',
  'location': '<path d="M19 9c0 5-7 13-7 13S5 14 5 9a7 7 0 0 1 14 0Z"/>'
      '<circle cx="12" cy="9" r="2.5"/>',
  'target': '<circle cx="12" cy="12" r="7"/>'
      '<circle cx="12" cy="12" r="2"/><path d="M12 1v4m0 14v4M1 12h4m14 0h4"/>',
  'waveform': '<path d="M3 10v4M7 6v12M12 3v18M17 7v10M21 10v4"/>',
  'translate': '<path d="M2 5h12M8 2v3m3 0c0 6-4 10-8 12M4 8l8 8'
      'm1 6 5-12 5 12m-8-4h6"/>',
  'hash': '<path d="m9 3-2 18M17 3l-2 18M3 8h18M3 16h18"/>',
  'tag': '<path d="M3 3h8l10 10-8 8L3 11V3Z"/>'
      '<circle cx="7" cy="7" r="1"/>',
  'bolt': '<path d="m14 2-11 12h8l-1 8 11-12h-8l1-8Z"/>',
  'play': '<path d="m7 3 14 9-14 9V3Z"/>',
  'pause': '<rect x="5" y="3" width="4" height="18" rx="1"/>'
      '<rect x="15" y="3" width="4" height="18" rx="1"/>',
  'stop': '<rect x="5" y="5" width="14" height="14" rx="2"/>',
  'layers':
      '<path d="m12 2 10 5-10 5L2 7l10-5ZM2 12l10 5 10-5M2 17l10 5 10-5"/>',
  'archive': '<rect x="3" y="3" width="18" height="5" rx="1"/>'
      '<path d="M5 8v12h14V8M9 12h6"/>',
  'mail-unread': '<path d="M14 5H5a2 2 0 0 0-2 2v12h18V12M3 7l9 7 5-4"/>'
      '<circle cx="19" cy="5" r="3"/>',
  'mail-read': '<path d="m3 9 9-7 9 7v12H3V9Zm0 0 9 7 9-7M3 21l6-7m6 0 6 7"/>',
  'mail-forward':
      '<path d="M12 19H3V5h18v7M3 5l9 8 9-8M14 18h8m-4-4 4 4-4 4"/>',
  'inbox': '<path d="M3 14 6 4h12l3 10v7H3v-7Zm0 0h5l2 3h4l2-3h5"/>',
  'link-add': '<path d="m10 8 3-3a4.3 4.3 0 0 1 6 6M10 19'
      'a4.3 4.3 0 0 1-5-6l3-3M8.5 15.5l7-7M17 15v7m-3.5-3.5h7"/>',
  'unlink': '<path d="m14 4 1-1a4.3 4.3 0 0 1 6 6l-3 3M10 20'
      'l-1 1a4.3 4.3 0 0 1-6-6l3-3M9 15l6-6M7 3v4H3m14 14v-4h4"/>',
  'image-plus': '<path d="M21 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5'
      'a2 2 0 0 1 2-2h8M3 16l5-5 6 6 3-3 4 4M18 2v8m-4-4h8"/>',
  'broom': '<path d="m15 3-4 8M8 10l8 4-4 8-9-4 5-8Zm-2 9 3-6m0 8 3-6"/>',
  'block': '<circle cx="12" cy="12" r="9"/><path d="m6 6 12 12"/>',
  'backspace': '<path d="M9 5h13v14H9l-7-7 7-7Zm3 4 6 6m-6 0 6-6"/>',
  'minus-circle': '<circle cx="12" cy="12" r="9"/><path d="M7 12h10"/>',
  'book-plus': '<path d="M5 20V5a2 2 0 0 1 2-2h13v18H7a2 2 0 0 1 0-4h13'
      'M9 10h7m-3.5-3.5v7"/>',
  'spellcheck': '<path d="m2 16 5-13 5 13M4 11h6m3 7 3 3 6-7"/>',
  'attachment': '<path d="m8 12 7-7a4 4 0 0 1 6 6l-9 9a6 6 0 0 1-8-8l9-9'
      'M8 12a2 2 0 0 0 3 3l7-7"/>',
  'caption': '<rect x="2" y="5" width="20" height="14" rx="2"/>'
      '<path d="M10 9H6v6h4m8-6h-4v6h4"/>',
  'align-objects-left': '<path d="M3 2v20"/>'
      '<rect x="7" y="5" width="14" height="5" rx="1"/>'
      '<rect x="7" y="15" width="9" height="5" rx="1"/>',
  'align-objects-center': '<path d="M12 2v20"/>'
      '<rect x="3" y="5" width="18" height="5" rx="1"/>'
      '<rect x="7" y="15" width="10" height="5" rx="1"/>',
  'align-objects-right': '<path d="M21 2v20"/>'
      '<rect x="3" y="5" width="14" height="5" rx="1"/>'
      '<rect x="8" y="15" width="9" height="5" rx="1"/>',
  'align-objects-top': '<path d="M2 3h20"/>'
      '<rect x="4" y="7" width="5" height="14" rx="1"/>'
      '<rect x="15" y="7" width="5" height="9" rx="1"/>',
  'align-objects-middle': '<path d="M2 12h20"/>'
      '<rect x="4" y="3" width="5" height="18" rx="1"/>'
      '<rect x="15" y="7" width="5" height="10" rx="1"/>',
  'align-objects-bottom': '<path d="M2 21h20"/>'
      '<rect x="4" y="3" width="5" height="14" rx="1"/>'
      '<rect x="15" y="8" width="5" height="9" rx="1"/>',
  'distribute-horizontal': '<path d="M2 3v18M22 3v18M5 12h3m8 0h3"/>'
      '<rect x="8" y="5" width="8" height="14" rx="1"/>',
  'distribute-vertical': '<path d="M3 2h18M3 22h18M12 5v3m0 8v3"/>'
      '<rect x="5" y="8" width="14" height="8" rx="1"/>',
  'insert-above': '<path d="M3 3h18M12 7v7m-3-3.5h6"/>'
      '<rect x="3" y="17" width="18" height="4" rx="1"/>',
  'insert-below': '<rect x="3" y="3" width="18" height="4" rx="1"/>'
      '<path d="M12 10v7m-3-3.5h6M3 21h18"/>',
  'insert-left': '<path d="M3 3v18M7 12h7m-3.5-3v6"/>'
      '<rect x="17" y="3" width="4" height="18" rx="1"/>',
  'insert-right': '<rect x="3" y="3" width="4" height="18" rx="1"/>'
      '<path d="M10 12h7m-3.5-3v6M21 3v18"/>',
  'select-all': '<path d="M3 6V3h3m3 0h6m3 0h3v3m0 3v6m0 3v3h-3'
      'm-3 0H9m-3 0H3v-3m0-3V9"/><rect x="7" y="7" width="10" height="10" rx="1"/>',
  'line-style': '<path d="M3 5h18M3 12h4m3 0h4m3 0h4M3 19h.1m4 0h.1m4 0h.1'
      'm4 0h.1m4 0h.1"/>',
  'sign-out': '<path d="M9 3H3v18h6M9 12h13m-5-5 5 5-5 5"/>',
  'camera': '<path d="M8 5 10 2h4l2 3h4a2 2 0 0 1 2 2v12'
      'a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h4Z"/>'
      '<circle cx="12" cy="13" r="5"/>',
  'merge': '<path d="M5 21V11l7-7 7 7v10M12 4v17M8 4h8"/>',
  'at': '<circle cx="11" cy="12" r="4"/><path d="M15 8v6a3 3 0 0 0 6 0v-2'
      'a9 9 0 1 0-3.5 7"/>',
  'window': '<rect x="3" y="3" width="18" height="18" rx="2"/>'
      '<path d="M3 12h18M12 3v18"/>',
  'search-list': '<path d="M3 4h18M3 8h8M3 12h5M3 16h5"/>'
      '<circle cx="15" cy="14" r="4"/><path d="m18 17 4 4"/>',
  'search-off': '<circle cx="11" cy="11" r="7"/>'
      '<path d="m16 16 6 6M8 8l6 6m-6 0 6-6"/>',
  'check-circle': '<circle cx="12" cy="12" r="9"/>'
      '<path d="m7 12 3.5 3.5L17 8"/>',
  'bookmarks': '<path d="M4 6h12v16l-6-4-6 4V6Zm5-4h11v15"/>',
  'chart-line': '<path d="M3 3v18h18M6 16l5-6 4 3 6-8M17 5h4v4"/>',
  'chart-stacked': '<path d="M3 3v18h18M6 15l5-5 5 2 5-6'
      'M6 18l5-4 5 2 5-5"/>',
  'chart-stacked-bar': '<path d="M3 3v18h18"/>'
      '<rect x="7" y="10" width="4" height="8" rx="1"/>'
      '<rect x="15" y="3" width="4" height="15" rx="1"/>'
      '<path d="M7 14h4M15 9h4M15 14h4"/>',
  'chart-area': '<path d="M3 3v18h18M6 18v-5l4-6 5 4 6-8v15H6Z"/>',
  'chart-scatter': '<path d="M3 3v18h18"/>'
      '<circle cx="7" cy="14" r="1"/><circle cx="11" cy="8" r="1"/>'
      '<circle cx="15" cy="12" r="1"/><circle cx="20" cy="5" r="1"/>',
  'donut': '<circle cx="12" cy="12" r="9"/>'
      '<circle cx="12" cy="12" r="5"/><path d="M12 3v4M17 12h4"/>',
  'chart-pie': '<path d="M10 3a9 9 0 1 0 11 11H10V3Zm4-1v8h8a9 9 0 0 0-8-8Z"/>',
  'legend': '<circle cx="5" cy="6" r="2"/><path d="M11 6h10"/>'
      '<rect x="3" y="15" width="4" height="4" rx="1"/><path d="M11 17h10"/>',
  'bubbles': '<circle cx="8" cy="8" r="5"/><circle cx="17" cy="17" r="4"/>'
      '<circle cx="6" cy="19" r="2"/>',
  'compass': '<circle cx="12" cy="12" r="9"/>'
      '<path d="m16 8-2 6-6 2 2-6 6-2Z"/>',
  'location-plus': '<path d="M19 9c0 5-7 13-7 13S5 14 5 9a7 7 0 0 1 14 0Z'
      'M12 5v8M8 9h8"/>',
  'group': '<circle cx="12" cy="6" r="3.5"/><circle cx="5" cy="17" r="3.5"/>'
      '<circle cx="19" cy="17" r="3.5"/>',
  'infinity': '<path d="M12 12c-3-6-9-6-9 0s6 6 9 0 9-6 9 0-6 6-9 0Z"/>',
  'repeat': '<path d="M3 10V6h18m-4-4 4 4-4 4M21 14v4H3m4-4-4 4 4 4"/>',
  'density-medium': '<path d="M3 5h18M3 12h18M3 19h18"/>',
  'density-small': '<path d="M3 4h18M3 8h18M3 12h18M3 16h18M3 20h18"/>',
  'triangle': '<path d="m12 3 10 18H2L12 3Z"/>',
  'priority': '<path d="M12 3v12M12 20h.01"/>',
  'password': '<rect x="2" y="6" width="20" height="12" rx="2"/>'
      '<path d="M6 10v4m-2-2h4M12 10v4m-2-2h4M18 10v4m-2-2h4"/>',
  'height': '<path d="M4 3h16M4 21h16M12 6v12m-3-3 3 3 3-3M9 9l3-3 3 3"/>',
  'motion-off': '<circle cx="12" cy="12" r="5"/>'
      '<path d="M12 2a10 10 0 0 1 10 10M12 22A10 10 0 0 1 2 12M3 3l18 18"/>',
  'power': '<path d="M12 2v10M6 5a9 9 0 1 0 12 0"/>',
  'layers-clear': '<path d="m12 2 10 5-10 5L2 7l10-5ZM2 12l10 5 10-5'
      'M2 17l10 5 10-5M3 3l18 18"/>',
  'skip-next': '<path d="m4 4 12 8-12 8V4ZM20 4v16"/>',
  'rotate': '<path d="M3 10a9 9 0 0 1 15-6l3 3m0-5v5h-5"/>'
      '<rect x="7" y="11" width="11" height="11" rx="1.5"/>',
  'print': '<path d="M6 8V2h12v6M6 17H2V8h20v9h-4M6 13h12v9H6V13ZM18 11h.01"/>',
  'page-portrait': '<rect x="5" y="2" width="14" height="20" rx="2"/>',
  'fade': '<path d="M3 3v18M7 3v18M11 3v3m0 3v3m0 3v3m0 3h.01'
      'M16 4v1m0 5v1m0 5v1M21 4h.01m0 6h.01m0 6h.01"/>',
  'swipe-up': '<path d="M8 21V10a2 2 0 0 1 4 0v5l3-2 6 3-3 6'
      'M4 8V2m-3 3 3-3 3 3"/>',
  'rocket': '<path d="M9 15c0-8 5-12 13-13 0 8-5 13-13 13Z'
      'M9 9H5l-3 7 7-1m6-6v10l-7 3 1-7M5 18l-3 4 4-2"/>'
      '<circle cx="16" cy="8" r="2"/>',
  'savings': '<path d="M5 7 4 3l6 3h5a6 6 0 0 1 6 5h2v5h-3l-2 5h-3v-3H9v3H6'
      'l-2-6a6 6 0 0 1 1-8ZM10 9h5M18 11h.01"/>',
  'school': '<path d="m2 8 10-5 10 5-10 5L2 8Zm4 2v7l6 4 6-4v-7M22 8v9"/>',
  'flame': '<path d="M13 2c0 6-7 7-7 12a6 6 0 0 0 12 0c0-2-1-5-3-7'
      ' 0 3-2 4-2 4 2-5 2-7 0-9Z"/>',
  'handshake': '<path d="m2 8 4-4 5 3m2-1 5-2 4 4-4 10-5 4-7-5-4-9Z'
      'M6 17l3-4 7 6M18 9l-5-3-5 4c0 3 3 3 5 1l7 6"/>',
  'calendar-edit': '<path d="M12 21H3V5h18v7M7 3v4M17 3v4M3 10h18'
      'm-8 10 6-6 3 3-6 6h-3v-3Z"/>',
  'insights': '<path d="M3 20 9 13l5 3 7-11M17 5h4v4'
      'M7 2v5M4.5 4.5h5M18 18v4m-2-2h4"/>',
  'rounded-corner': '<path d="M3 21V11a8 8 0 0 1 8-8h10M3 3h.01M21 21h.01"/>',
  'brush': '<path d="m10 15 9-12a2 2 0 0 1 3 3L12 17M10 15'
      'c-5-3-4 6-8 5 5 4 11 0 8-5Z"/>',
  'droplet': '<path d="M12 2C10 7 5 10 5 15a7 7 0 0 0 14 0c0-5-5-8-7-13Z"/>',
  'first-page': '<path d="M4 4v16m14-15-7 7 7 7"/>',
  'last-page': '<path d="M20 4v16M6 5l7 7-7 7"/>',
  'return': '<path d="M21 4v10H3m5-5-5 5 5 5"/>',
  'rule': '<path d="m2 5 2 2 3-4M11 5h10M2 15l5 5m-5 0 5-5M11 17h10"/>',
  'bulb': '<path d="M8 17C1 10 6 3 12 3s11 7 4 14v4H8v-4ZM8 17h8M10 23h4"/>',
  'bell-off': '<path d="M10 21h4M18 12V9a6 6 0 0 0-10-5M6 8v5l-2 4h13'
      'M3 3l18 18"/>',
  'snooze': '<path d="M19 10a8 8 0 1 1-8-7M3 3l3 3M3 21l3-3m12 0 3 3'
      'M14 2h7l-7 5h7M12 8v5l3 2"/>',
  'cloud-sync': '$_cloud<path d="M8 15a4 4 0 0 1 7-1l1 1m0-3v3h-4'
      'M16 18a4 4 0 0 1-7 2l-1-1m0 3v-3h4"/>',
  'cloud-check': '$_cloud<path d="m9 18 3 3 6-6"/>',
  'lock-clock': '<path d="M11 21H4V10h16v1M7 10V6a4 4 0 0 1 8 0v4"/>'
      '<circle cx="18" cy="18" r="5"/><path d="M18 15v3l2 1"/>',
  'zoom-in': '<circle cx="10" cy="10" r="7"/>'
      '<path d="m15 15 7 7M6 10h8M10 6v8"/>',
  'zoom-out': '<circle cx="10" cy="10" r="7"/>'
      '<path d="m15 15 7 7M6 10h8"/>',
  'branch-arrow': '<path d="M4 3v11h17m-5-5 5 5-5 5"/>',
  'toggle': '<rect x="2" y="6" width="20" height="12" rx="6"/>'
      '<circle cx="16" cy="12" r="3"/>',
  'hourglass':
      '<path d="M6 2h12v4l-6 6 6 6v4H6v-4l6-6-6-6V2ZM6 6h12M6 18h12"/>',
  'sun': '<circle cx="12" cy="12" r="4"/>'
      '<path d="M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
  'campaign': '<path d="M4 9h4l12-6v18L8 15H4V9Zm4 6 2 6H6l-2-6M8 9v6"/>',
  'wallet': '<rect x="3" y="5" width="18" height="15" rx="2"/>'
      '<path d="M4 5 17 2v3M21 10h-7v5h7M17 12.5h.01"/>',
  'briefcase': '<rect x="2" y="7" width="20" height="14" rx="2"/>'
      '<path d="M8 7V3h8v4M2 12l10 4 10-4M10 13h4"/>',
  'route': '<circle cx="5" cy="4" r="2"/><circle cx="19" cy="20" r="2"/>'
      '<path d="M8 4h8a4 4 0 0 1 0 8H8a4 4 0 0 0 0 8h8"/>',
  // Source-audited chrome identities. These are not saved picker choices.
  // Keep opposite directions, absent states and actions distinguishable.
  'find-replace': '<circle cx="8" cy="8" r="5"/>'
      '<path d="m12 12 3 3M3 18h17m-4-4 4 4-4 4"/>',
  'replace-all': '<path d="M3 8a9 9 0 0 1 16-3l2 3m0-5v5h-5'
      'M21 16a9 9 0 0 1-16 3l-2-3m0 5v-5h5M8 10h6m-4 4h6"/>',
  'rotate-ccw': '<path d="M21 10a9 9 0 0 0-15-6L3 7m0-5v5h5"/>'
      '<rect x="6" y="11" width="11" height="11" rx="1.5"/>',
  'flip-horizontal': '<path d="M12 2v3m0 4v6m0 4v3M3 6l6 6-6 6V6Z'
      'm18 0-6 6 6 6V6Z"/>',
  'flip-vertical': '<path d="M2 12h3m4 0h6m4 0h3M6 3l6 6 6-6H6Z'
      'm0 18 6-6 6 6H6Z"/>',
  'fit-page': '<path d="M6 2H2v4m16-4h4v4M2 18v4h4m12 0h4v-4"/>'
      '<rect x="7" y="5" width="10" height="14" rx="1"/>',
  'actual-size': '<path d="M7 3H3v4m14-4h4v4M3 17v4h4m10 0h4v-4'
      'M6 10l2-1v6m8-5 2-1v6M12 10h.01M12 14h.01"/>',
  'help': '<circle cx="12" cy="12" r="9"/>'
      '<path d="M9 8a3 3 0 1 1 4 3c-1 .4-1 1-1 2M12 17h.01"/>',
  'error': '<path d="M8 2h8l6 6v8l-6 6H8l-6-6V8l6-6Z'
      'M12 7v6M12 17h.01"/>',
  'highlight': '<path d="m8 15 10-12 4 4-11 11-3-3Zm0 0-3 5h7'
      'M2 22h20M14 7l4 4"/>',
  'marker-number': '<rect x="4" y="3" width="16" height="18" rx="3"/>'
      '<path d="m9 9 3-2v10m-3 0h6"/>',
  'bookmark-plus': '<path d="M13 3H5v18l7-4 7 4v-9M18 2v7m-3.5-3.5h7"/>',
  'location-off': '<path d="M7 4a7 7 0 0 1 12 5c0 2-1 4-2 6'
      'M5 9c0 5 7 13 7 13l3-4M3 3l18 18"/>',
  'puzzle-off': '<path d="M9 4h3a3 3 0 0 1 6 0h3v5a3 3 0 0 0 0 6'
      'M4 9v3a3 3 0 0 0 0 6v3h5a3 3 0 0 1 6 0h6M2 2l20 20"/>',
  'cursor': '<path d="m4 2 16 11-8 1-4 8L4 2Zm8 12 6 8"/>',
  'hand-pan': '<path d="M8 12V3a2 2 0 0 1 4 0v8-5a2 2 0 0 1 4 0v5-3'
      'a2 2 0 0 1 4 0v8l-3 6H9l-6-8a2 2 0 0 1 3-2l2 2"/>',
  'image-broken': '<rect x="3" y="3" width="18" height="18" rx="2"/>'
      '<path d="m3 15 5-4 4 4 4-4 5 4M13 3l-3 6 4 2-4 6 3 4"/>',
  'image-off': '<path d="M9 3h10a2 2 0 0 1 2 2v10M3 7v12a2 2 0 0 0 2 2h12'
      'M3 16l5-5 7 7M3 3l18 18"/>',
  'polyline': '<path d="m5 5 14 3-6 11-8-14Z"/>'
      '<rect x="3" y="3" width="4" height="4" rx="1"/>'
      '<rect x="17" y="6" width="4" height="4" rx="1"/>'
      '<rect x="11" y="17" width="4" height="4" rx="1"/>',
  'commit': '<circle cx="12" cy="12" r="5"/><path d="M2 12h5m10 0h5"/>',
  'rebase': '<circle cx="5" cy="4" r="2"/><circle cx="5" cy="20" r="2"/>'
      '<path d="M5 6v12M10 17h9V5m-4 4 4-4 4 4"/>',
  'time-progress': '<circle cx="12" cy="12" r="9"/>'
      '<path d="M12 3v9l6 6M12 7v5l-4 2"/>',
  'lock-off': '<path d="M8 6a4 4 0 0 1 8 1v3h3v6M5 10v11h14'
      'M3 3l18 18M12 15v2"/>',
  'shuffle': '<path d="M3 5h3l12 14h3m-4-4 4 4-4 4M3 19h3l12-14h3'
      'm-4-4 4 4-4 4"/>',
  'skip-previous': '<path d="m20 4-12 8 12 8V4ZM4 4v16"/>',
  'check-off': '<path d="m3 12 4 4 3-3m3-3 7-7M3 3l18 18"/>',
  'tag-off': '<path d="M9 3h4l9 9-5 5M3 7v6l9 9 2-2M2 2l20 20"/>',
  'signal': '<circle cx="12" cy="12" r="2"/>'
      '<path d="M8 7a6 6 0 0 0 0 10m8-10a6 6 0 0 1 0 10'
      'M5 3a11 11 0 0 0 0 18M19 3a11 11 0 0 1 0 18"/>',
  'user-plus': '<circle cx="9" cy="7" r="4"/>'
      '<path d="M2 21v-3a7 6 0 0 1 13-3M19 11v8m-4-4h8"/>',
  'shield-info': '<path d="m12 2 8 3v6c0 5-3 8-8 11-5-3-8-6-8-11V5l8-3Z'
      'M12 11v6M12 7h.01"/>',
  'inboxes': '<path d="M5 3h14v4M2 12l3-4h14l3 4v9H2v-9Zm0 0h6'
      'l2 3h4l2-3h6"/>',
  'clipboard-check': '<rect x="8" y="2" width="8" height="5" rx="1"/>'
      '<path d="M8 4H4v18h16V4h-4M7 14l3 3 7-7"/>',
  'scales': '<path d="M12 2v19M7 22h10M3 6h18M5 6l-4 9h8L5 6Z'
      'm14 0-4 9h8l-4-9Z"/>',
  'brackets': '<path d="M8 3H4v18h4M16 3h4v18h-4"/>',
  'fog': '<path d="M7 12a4 4 0 1 1 1-8 5 5 0 0 1 9 2 3 3 0 1 1 0 6'
      'M2 16h20M5 20h14"/>',
  'snowflake': '<path d="M12 2v20M3.3 7l17.4 10M3.3 17 20.7 7'
      'M9 3l3 3 3-3M9 21l3-3 3 3M3 10l4-1-1-4m12 14-1-4 4-1'
      'M3 14l4 1-1 4M18 5l-1 4 4 1"/>',
  'storm': '<path d="M6 14a4 4 0 0 1 0-8 6 6 0 0 1 11-1'
      ' 4.5 4.5 0 0 1 2 9M12 10l-5 7h5l-1 5 6-8h-5l1-4Z"/>',
  'calendar-off': '<rect x="3" y="5" width="18" height="16" rx="2"/>'
      '<path d="M7 3v4M17 3v4M3 10h18m-12 3 6 6m-6 0 6-6"/>',
  'calendar-check': '<rect x="3" y="5" width="18" height="16" rx="2"/>'
      '<path d="M7 3v4M17 3v4M3 10h18m-14 5 3 3 7-6"/>',
  'books': '<path d="M4 3h5v18H4V3Zm5 2h5v16H9V5Zm7-2 5-1 3 18-5 1-3-18Z'
      'M4 17h10"/>',
  'key': '<circle cx="7" cy="7" r="5"/>'
      '<path d="m11 11 10 10m-4-4 3-3m-6 0 3-3M5 5h.01"/>',
  'folder-off': '<path d="M9 4h2l3 3h5a2 2 0 0 1 2 2v6M3 7v12h14'
      'M2 2l20 20"/>',
  'intersection': '<circle cx="8" cy="12" r="7"/>'
      '<circle cx="16" cy="12" r="7"/><path d="M12 7v10"/>',
  'replay': '<path d="M6 5a9 9 0 1 1-3 10M6 1v5h5"/>',
  'rewind-5': '<path d="M6 5a9 9 0 1 1-3 10M6 1v5h5'
      'M15 9h-5v4h3a2.5 2.5 0 0 1 0 5h-3"/>',
  'forward-5': '<path d="M18 5a9 9 0 1 0 3 10M18 1v5h-5'
      'M15 9h-5v4h3a2.5 2.5 0 0 1 0 5h-3"/>',
  'playback-speed': '<path d="M12 3a9 9 0 1 1-9 9M3 8h.01M5 5h.01M8 3h.01'
      'm2 5 7 4-7 4V8Z"/>',
  'high-definition': '<rect x="2" y="5" width="20" height="14" rx="2"/>'
      '<path d="M6 9v6M10 9v6M6 12h4M14 9h2a3 3 0 0 1 0 6h-2V9Z"/>',
  'tab-key': '<path d="M3 12h14m-5-5 5 5-5 5M21 5v14"/>',
  'currency-dollar': '<path d="M12 2v20M18 6c-8-8-18 5-6 6s2 14-6 6"/>',
  'percent': '<circle cx="6" cy="6" r="3"/>'
      '<circle cx="18" cy="18" r="3"/><path d="M3 21 21 3"/>',
  'borders': '<rect x="3" y="3" width="18" height="18" rx="1"/>'
      '<path d="M3 12h18M12 3v18"/>',
  'borders-none': '<path d="M3 6V3h3m3 0h6m3 0h3v3m0 3v6m0 3v3h-3'
      'm-3 0H9m-3 0H3v-3m0-3V9M12 11v2M11 12h2"/>',
  'volume': '<path d="M3 9h4l5-5v16l-5-5H3V9Zm13 0a5 5 0 0 1 0 6'
      'm3-10a9 9 0 0 1 0 14"/>',
  'volume-off': '<path d="M3 9h4l5-5v16l-5-5H3V9Zm13 0 6 6m-6 0 6-6"/>',
  'suitcase': '<rect x="4" y="6" width="16" height="15" rx="2"/>'
      '<path d="M9 6V2h6v4M8 10v7m8-7v7M7 21v2m10-2v2"/>',
  'bank': '<path d="m2 8 10-6 10 6H2ZM4 21h16M6 11v7m6-7v7m6-7v7"/>',
  'receipt': '<path d="m5 2 3 2 4-2 4 2 3-2v20l-3-2-4 2-4-2-3 2V2Z'
      'M8 8h8M8 12h8M8 16h5"/>',
  'cutlery': '<path d="M3 2v6a3 3 0 0 0 6 0V2M6 2v20'
      'M19 2c-4 2-5 7-5 12h5V2Zm0 12v8"/>',
  'science': '<path d="M8 2h8M9 2v8l-7 11h20l-7-11V2M6 16h12"/>'
      '<circle cx="10" cy="18" r=".6"/>',
  'badge': '<rect x="2" y="5" width="20" height="16" rx="2"/>'
      '<path d="M9 2v5h6V2M14 12h5m-5 4h5M4 18c0-4 8-4 8 0"/>'
      '<circle cx="8" cy="12" r="2"/>',
  'bug': '<rect x="7" y="6" width="10" height="15" rx="5"/>'
      '<path d="m8 3 2 3m6-3-2 3M3 9h4m10 0h4M3 14h4m10 0h4M3 20l4-2'
      'm10 0 4 2M12 10v11"/>',
  'tab': '<path d="M3 7h9V3h9v18H3V7Zm0 0V3h9M12 7h9"/>',
  'moon': '<path d="M15 2A10 10 0 1 0 22 16 10 10 0 0 1 15 2Z"/>',
  'history-search': '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>'
      '<circle cx="13" cy="11" r="3"/><path d="m15 13 3 3"/>',
  'microchip': '<rect x="5" y="5" width="14" height="14" rx="2"/>'
      '<rect x="9" y="9" width="6" height="6" rx="1"/>'
      '<path d="M8 2v3m8-3v3M8 19v3m8-3v3M2 8h3m14 0h3M2 16h3m14 0h3"/>',
  'computer': '<rect x="2" y="3" width="20" height="14" rx="2"/>'
      '<path d="M9 17v4m6-4v4M6 22h12M2 13h20"/>',
  'paw': '<path d="M12 11c-3 0-3 3-6 4-5 4-1 8 3 6 2-1 4-1 6 0'
      ' 4 2 8-2 3-6-3-1-3-4-6-4Z"/>'
      '<ellipse cx="4" cy="9" rx="2" ry="3"/>'
      '<ellipse cx="9" cy="5" rx="2" ry="3"/>'
      '<ellipse cx="15" cy="5" rx="2" ry="3"/>'
      '<ellipse cx="20" cy="9" rx="2" ry="3"/>',
  'food': '<path d="M2 14a6 6 0 0 1 12 0H2Zm0 3h12M2 20h12'
      'M16 6h6l-1 15h-4L16 6Zm2 0V2h4"/>',
  'running': '<circle cx="16" cy="4" r="2"/>'
      '<path d="m14 8-4 6 6 3-1 5m-5-8-3 6H2m10-11-3-3-5 4'
      'm10-2 3 5h5"/>',
  'city': '<path d="M3 21V8h7v13M10 21V3h11v18M1 21h22'
      'M6 11v1m0 4v1M14 7h3m-3 4h3m-3 4h3"/>',
  'workspace-home': '<path d="M3 13V3h10v5M6 6h3M6 10h3M2 15l9-7 11 7'
      'M5 13v8h14v-8M10 21v-6h4v6"/>',
  'brain': '<path d="M12 4c-3-4-9 0-7 4-5 2-4 8 0 9-1 5 5 7 7 3'
      ' 2 4 8 2 7-3 4-1 5-7 0-9 2-4-4-8-7-4Zm0 0v16'
      'M5 8l3 2m-3 7 3-3m11-6-3 2m3 7-3-3"/>',
  'server': '<rect x="3" y="3" width="18" height="7" rx="2"/>'
      '<rect x="3" y="14" width="18" height="7" rx="2"/>'
      '<path d="M7 6.5h.01M7 17.5h.01M12 6.5h5M12 17.5h5"/>',
  'unarchive': '<rect x="3" y="3" width="18" height="5" rx="1"/>'
      '<path d="M5 8v13h14V8M12 18v-7m-3 3 3-3 3 3"/>',
  'alarm': '<circle cx="12" cy="13" r="8"/>'
      '<path d="m3 4 3-2m12 0 3 2M12 8v5l4 2M6 20l-2 2m14-2 2 2"/>',
  'pin-off': '<path d="M11 3h6l-1 6 3 4v2h-4M7 7l1 3-3 5h6v6M3 3l18 18"/>',
  'star-off': '<path d="m9 7 3-5 3 6 7 1-5 5 1 3M6 8l-4 1 5 5-1 7 6-3'
      ' 6 3M2 2l20 20"/>',
  'checkbox-indeterminate': '<rect x="3" y="3" width="18" height="18" rx="3"/>'
      '<path d="M7 12h10"/>',
  'divider-vertical': '<path d="M12 3v18"/>',
  'direction-ltr': '<path d="M13 3v11M17 3v11M17 3h-7a4 4 0 0 0 0 8h3'
      'M3 19h18m-4-3 4 3-4 3"/>',
  'direction-rtl': '<path d="M13 3v11M17 3v11M17 3h-7a4 4 0 0 0 0 8h3'
      'M21 19H3m4-3-4 3 4 3"/>',
  'direction-auto': '<path d="M13 3v10M17 3v10M17 3h-7a3 3 0 0 0 0 6h3'
      'M3 17h18m-3-2 3 2-3 2M21 21H3m3-2-3 2 3 2"/>',
  'key-command': '<path d="M8 8H5a3 3 0 1 1 3-3v14a3 3 0 1 1-3-3h14'
      'a3 3 0 1 1-3 3V5a3 3 0 1 1 3 3H8Z"/>',
  'key-shift': '<path d="m12 3 10 10h-6v8H8v-8H2L12 3Z"/>',
  'key-option': '<path d="M3 5h5l8 14h5M14 5h7"/>',
  'paragraph': '<path d="M14 3v18M19 3v18M19 3h-9a5 5 0 0 0 0 10h4"/>',
  'text-image': '<rect x="2" y="3" width="20" height="18" rx="2"/>'
      '<path d="M6 7h12M6 11h7m-8 7 4-4 4 4 4-3 4 3"/>',
  'thumb-up': '<path d="M8 10l5-8 3 1-1 6h6l-2 12H8V10Z'
      'M3 10h5v11H3V10Z"/>',
  'thumb-down': '<path d="m8 14 5 8 3-1-1-6h6L19 3H8v11Z'
      'M3 3h5v11H3V3Z"/>',
  'send': '<path d="m2 3 20 9-20 9 4-9-4-9Zm4 9h16"/>',
  'keyboard-hide': '<rect x="2" y="3" width="20" height="12" rx="2"/>'
      '<path d="M6 7h.1m4 0h.1m4 0h.1m4 0h.1M8 11h8m-8 8 4 3 4-3"/>',
  'keyboard-show': '<rect x="2" y="9" width="20" height="12" rx="2"/>'
      '<path d="M6 13h.1m4 0h.1m4 0h.1m4 0h.1M8 17h8M8 5l4-3 4 3"/>',
  'globe-off': '<path d="M9 3.5A9 9 0 0 1 21 15M3 8a9 9 0 0 0 13 12'
      'M12 3c3 3 4 7 3 10M8 8c-1 4 0 9 4 13M3 12h9m5 0h4M3 3l18 18"/>',
  'unknown': '<rect x="3" y="3" width="18" height="18" rx="4"/>'
      '<path d="M9 9a3 3 0 1 1 4 2.8c-1 .4-1 1.2-1 2.2M12 18h.01"/>',
};
