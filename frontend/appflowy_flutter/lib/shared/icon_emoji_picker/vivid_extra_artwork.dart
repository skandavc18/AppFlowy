part of 'vivid_icon_artwork.dart';

// Original small illustrations. The silhouettes carry the meaning; gradients
// and inset highlights are details, never full-square colored UI backgrounds.
const _head = '<circle cx="16" cy="9" r="6" fill="url(#accent)"/>';
const _coin = '<ellipse cx="16" cy="17" rx="12" ry="13" fill="url(#main)"/>'
    '<ellipse cx="15" cy="15" rx="10" ry="11" fill="url(#accent)"/>';
const _extraIllustrations = <String, _Illustration>{
  // Chrome marks use two quiet colored strokes, not miniature solid badges.
  // Their transparent interiors and inset silhouettes stay light at 16–18px.
  'search': _Illustration(
      '#82A6B7',
      '#59899F',
      '#AAA0C3',
      '#8176A8',
      '<circle cx="13.5" cy="13.5" r="8" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="m19.5 19.5 7 7" stroke="url(#accent)" stroke-width="2.2"/>'),
  'settings': _Illustration(
      '#A49ABD',
      '#7C73A6',
      '#7BA7A1',
      '#588F92',
      '<path d="m13.5 5-.7 2.8-2.3 1.3-2.8-.8-2.5 4.4 2.1 2v2.6l-2.1 2 '
          '2.5 4.4 2.8-.8 2.3 1.3.7 2.8h5l.7-2.8 2.3-1.3 2.8.8 2.5-4.4-2.1-2v-2.6'
          'l2.1-2-2.5-4.4-2.8.8-2.3-1.3-.7-2.8Z" stroke="url(#main)" stroke-width="2"/>'
          '<circle cx="16" cy="16" r="4" stroke="url(#accent)" stroke-width="2"/>'),
  'bell': _Illustration(
      '#C8A572',
      '#A77F52',
      '#A69CBE',
      '#8378A7',
      '<path d="M9 13a7 7 0 0 1 14 0v7l3 4H6l3-4Z" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M13 27c1.4 2 4.6 2 6 0M16 4v2" stroke="url(#accent)" stroke-width="2.2"/>'),
  'trash': _Illustration(
      '#7AA8A1',
      '#548C90',
      '#A0AAC5',
      '#778BAD',
      '<path d="m8 10 1.3 16a2 2 0 0 0 2 2h9.4a2 2 0 0 0 2-2L24 10'
          'M13 14v9m6-9v9" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M6 9h20M12 9V5h8v4" stroke="url(#accent)" stroke-width="2"/>'),
  'puzzle': _Illustration(
      '#B8A0EE',
      '#8262C3',
      '#FFD292',
      '#E79A5D',
      '<path d="M4 5h8a4 4 0 1 1 8 0h8v8a4 4 0 1 0 0 8v7h-8a4 4 0 1 0-8 0H4v-8'
          'a4 4 0 1 1 0-8Z" fill="url(#main)"/>'
          '<path d="M17 7v8h8v8h-8v-8H9V7Z" fill="url(#accent)"/>'
          '<path d="M7 8v5" stroke="#E2D5FF" stroke-width="1.5"/>'),
  'plus': _Illustration(
      '#7AA5A1',
      '#588D91',
      '#92A3BE',
      '#738AAF',
      '<path d="M16 7v18" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M7 16h18" stroke="url(#accent)" stroke-width="2.2"/>'),
  'copy': _Illustration(
      '#8FA9C2',
      '#648CAC',
      '#AEA0C5',
      '#8A79AC',
      '<path d="M20 10V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h3" '
          'stroke="url(#main)" stroke-width="2"/>'
          '<rect x="11" y="11" width="16" height="16" rx="2.5" stroke="url(#accent)" stroke-width="2"/>'),
  'download': _Illustration(
      '#7BA8A0',
      '#578F91',
      '#A1A6C4',
      '#7C82AF',
      '<path d="M16 5v15m-6-6 6 6 6-6" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M6 21v5a1 1 0 0 0 1 1h18a1 1 0 0 0 1-1v-5" stroke="url(#accent)" stroke-width="2.2"/>'),
  'upload': _Illustration(
      '#91A2C3',
      '#6D87B1',
      '#C7A789',
      '#AC8567',
      '<path d="M16 21V5m-6 6 6-6 6 6" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M6 21v5a1 1 0 0 0 1 1h18a1 1 0 0 0 1-1v-5" stroke="url(#accent)" stroke-width="2.2"/>'),
  'pen': _Illustration(
      '#C6A375',
      '#A98258',
      '#AAA0C3',
      '#8477AA',
      '<path d="m7 21 13-13 5 5-13 13-7 1Z" stroke="url(#main)" stroke-width="2"/>'
          '<path d="m20 8 2-2a2 2 0 0 1 3 0l1 1a2 2 0 0 1 0 3l-2 2M7 21l5 5" '
          'stroke="url(#accent)" stroke-width="2"/>'),
  'pin': _Illustration(
      '#C6A1AF',
      '#AF7D94',
      '#91AAC0',
      '#6E90AD',
      '<path d="M11 5h10l-1 8 4 5v2H8v-2l4-5Z" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M16 20v7" stroke="url(#accent)" stroke-width="2"/>'),
  'history': _Illustration(
      '#8CA7C3',
      '#6589AD',
      '#91ADA4',
      '#67958F',
      '<path d="M6 12a11 11 0 1 1 1 11M6 5v7h7" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M17 10v7l4 3" stroke="url(#accent)" stroke-width="2.2"/>'),
  'clock': _Illustration(
      '#9DA4C6',
      '#7887B0',
      '#C5A487',
      '#AD856C',
      '<circle cx="16" cy="16" r="11" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M16 9v7l5 3" stroke="url(#accent)" stroke-width="2.2"/>'),
  'user': _Illustration(
      '#ADC8F3',
      '#6B91C7',
      '#FFD5B0',
      '#E0A380',
      '$_head<path d="M3 30v-4c0-12 26-12 26 0v4Z" fill="url(#main)"/>'
          '<path d="M9 25c1-4 4-5 7-5" stroke="#DCEBFF" stroke-width="1.6"/>'),
  'users': _Illustration(
      '#B7A4E8',
      '#8B6AC0',
      '#99D8C8',
      '#4BA79C',
      '<circle cx="23" cy="9" r="5" fill="#F0C598"/>'
          '<path d="M17 29v-7c0-8 14-8 14 0v7Z" fill="url(#accent)"/>'
          '<circle cx="11" cy="10" r="6" fill="#F7D7B5"/>'
          '<path d="M1 30v-5c0-12 23-12 23 0v5Z" fill="url(#main)"/>'),
  'workspace': _Illustration(
      '#ACCAE8',
      '#698DBB',
      '#F4CF94',
      '#DCA96A',
      '<rect x="5" y="3" width="22" height="28" rx="3" fill="url(#main)"/>'
          '<path d="M10 9h3m6 0h3M10 15h3m6 0h3" stroke="#ECF6FC" stroke-width="3"/>'
          '<path d="M12 31v-9h8v9Z" fill="url(#accent)"/>'
          '<path d="M16 23v7" stroke="#FDE9C3" stroke-width="1"/>'),
  'lock': _Illustration(
      '#C5A575',
      '#AA845A',
      '#98A4C2',
      '#7486AB',
      '<rect x="7" y="13" width="18" height="15" rx="3" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M11 13V9a5 5 0 0 1 10 0v4M16 19v4" stroke="url(#accent)" stroke-width="2"/>'),
  'shield': _Illustration(
      '#81AAA1',
      '#589491',
      '#A3A6C6',
      '#7E88B1',
      '<path d="m16 4 10 4v8c0 5-5 9-10 12-5-3-10-7-10-12V8Z" stroke="url(#main)" stroke-width="2"/>'
          '<path d="m11 16 3.5 3.5L22 12" stroke="url(#accent)" stroke-width="2.2"/>'),
  'text': _Illustration(
      '#AC9CC1',
      '#8675A9',
      '#81A7B0',
      '#5C8D9F',
      '<path d="M6 10V6h20v4" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M16 6v20m-5 0h10" stroke="url(#accent)" stroke-width="2.2"/>'),
  'number': _Illustration(
      '#80AAA1',
      '#578F90',
      '#AA9FC1',
      '#8778A8',
      '<path d="m12 5-3 22m14-22-3 22" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M6 12h21M5 21h21" stroke="url(#accent)" stroke-width="2.2"/>'),
  'checkbox': _Illustration(
      '#86AA9D',
      '#5A948B',
      '#90A8C2',
      '#6B8EAD',
      '<rect x="5" y="5" width="22" height="22" rx="4" stroke="url(#main)" stroke-width="2"/>'
          '<path d="m10 16 4 4 8-9" stroke="url(#accent)" stroke-width="2.2"/>'),
  'select': _Illustration(
      '#A89FC1',
      '#837AA9',
      '#80A8A0',
      '#5A948A',
      '<rect x="4" y="8" width="24" height="16" rx="3" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M8 16h5m6-2 3 4 3-4" stroke="url(#accent)" stroke-width="2"/>'),
  'connections': _Illustration(
      '#87A8C2',
      '#628FAF',
      '#AB9EC3',
      '#8878AB',
      '<path d="m9 9 5 5m4 0 5-5M9 23l5-5m4 0 5 5" stroke="url(#main)" stroke-width="2"/>'
          '<g stroke="url(#accent)" stroke-width="2"><circle cx="7" cy="7" r="3"/>'
          '<circle cx="25" cy="7" r="3"/><circle cx="7" cy="25" r="3"/>'
          '<circle cx="25" cy="25" r="3"/><circle cx="16" cy="16" r="3.5"/></g>'),
  'attachment': _Illustration(
      '#86A9B8',
      '#5F8EAA',
      '#AB9FC2',
      '#8779AA',
      '<path d="m11 16 8-8a4.2 4.2 0 0 1 6 6L14 25A7 7 0 0 1 4 15L16 3" '
          'stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="m11 16 8-8m-8 8a2.2 2.2 0 0 0 3 3l7-7" stroke="url(#accent)" stroke-width="2.2"/>'),
  'sigma': _Illustration(
      '#AE9DC3',
      '#8B79A9',
      '#83AAA6',
      '#5F9498',
      '<path d="M25 9V5H7l10 11L7 27h18v-4" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M7 27h18" stroke="url(#accent)" stroke-width="2.2"/>'),
  'keyboard': _Illustration(
      '#96A6C2',
      '#7187AB',
      '#8BAFA4',
      '#64988F',
      '<rect x="3" y="7" width="26" height="19" rx="3" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M8 12h1m6 0h1m6 0h1M8 17h1m6 0h1m6 0h1M10 22h12" '
          'stroke="url(#accent)" stroke-width="2"/>'),
  'filter': _Illustration(
      '#86ABB1',
      '#5E929F',
      '#B0A0C5',
      '#8C7BAA',
      '<path d="M5 6h22L19 17v8l-6 3V17Z" stroke="url(#main)" stroke-width="2"/>'
          '<path d="M9 10h14" stroke="url(#accent)" stroke-width="2"/>'),
  'sort': _Illustration(
      '#8FA9C3',
      '#6B8DB1',
      '#AE9DC2',
      '#8978A8',
      '<path d="M6 8h20M6 16h12M6 24h6" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M24 15v12m-4-4 4 4 4-4" stroke="url(#accent)" stroke-width="2.2"/>'),
  'refresh': _Illustration(
      '#7EA8A3',
      '#578F96',
      '#A79DC1',
      '#8478AA',
      '<path d="M6 13a10.5 10.5 0 0 1 18-6l2 3M26 4v6h-6" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="M26 19a10.5 10.5 0 0 1-18 6l-2-3M6 28v-6h6" stroke="url(#accent)" stroke-width="2.2"/>'),
  'link': _Illustration(
      '#88A8C2',
      '#648FAC',
      '#AAA0C4',
      '#877AAA',
      '<path d="m14 10 3-3a6 6 0 0 1 8.5 8.5L22 19" stroke="url(#main)" stroke-width="2.2"/>'
          '<path d="m18 22-3 3A6 6 0 0 1 6.5 16.5L10 13m2 7 8-8" stroke="url(#accent)" stroke-width="2.2"/>'),
  'scissors': _Illustration(
      '#C0A0B3',
      '#AC819C',
      '#95AEC2',
      '#7195B0',
      '<path d="m11 11 15 15m-15-5L26 6" stroke="url(#accent)" stroke-width="2"/>'
          '<g stroke="url(#main)" stroke-width="2"><circle cx="8" cy="8" r="4"/>'
          '<circle cx="8" cy="24" r="4"/></g>'),
  'clipboard': _Illustration(
      '#C0A589',
      '#A68C70',
      '#8FAFBC',
      '#6997AA',
      '<path d="M11 7H8a2 2 0 0 0-2 2v17a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9'
          'a2 2 0 0 0-2-2h-3M11 16h10M11 22h7" stroke="url(#main)" stroke-width="2"/>'
          '<rect x="11" y="4" width="10" height="6" rx="2" stroke="url(#accent)" stroke-width="2"/>'),
  'briefcase': _Illustration(
      '#B3BAEE',
      '#797BBC',
      '#F0C598',
      '#D39F71',
      '<path d="M11 9V3h10v6" stroke="#8C7FA7" stroke-width="3"/>'
          '<rect x="2" y="8" width="28" height="22" rx="4" fill="url(#main)"/>'
          '<path d="M2 12v5l14 6 14-6v-5" fill="url(#accent)"/>'
          '<rect x="13" y="18" width="6" height="7" rx="1.5" fill="#FDE1AF"/>'),
  'handshake': _Illustration(
      '#EFC797',
      '#D69A70',
      '#ABC8EE',
      '#648FBF',
      '<path d="m1 10 6-6 8 6-6 15-8-6Z" fill="url(#accent)"/>'
          '<path d="m9 9 7-4 14 7-8 16-5 2L6 20Z" fill="url(#main)"/>'
          '<path d="m15 7-6 7c1 4 4 3 7 0l9 8M13 20l7 6" stroke="#FFF0D9" stroke-width="2"/>'),
  'wallet': _Illustration(
      '#B6A1DD',
      '#8061AE',
      '#FFD29D',
      '#DFA166',
      '<path d="M4 10V6l21-4v8Z" fill="url(#accent)"/>'
          '<rect x="2" y="8" width="28" height="22" rx="4" fill="url(#main)"/>'
          '<rect x="19" y="15" width="12" height="9" rx="3" fill="url(#accent)"/>'
          '<circle cx="23" cy="19.5" r="1.5" fill="#93623F"/>'),
  'coins': _Illustration(
      '#E4A551',
      '#C3823D',
      '#FFE397',
      '#F2BE5D',
      '$_coin<path d="M15 8v14m4-11c-7-5-11 6-3 5s5 9-3 5" stroke="#C18B3E" stroke-width="2"/>'
          '<path d="M8 10a8 8 0 0 1 7-4" stroke="#FFF5C9" stroke-width="1.5"/>'),
  'calculator': _Illustration(
      '#ADC8EA',
      '#779AC2',
      '#B9D8B1',
      '#75AE93',
      '<rect x="5" y="2" width="22" height="29" rx="4" fill="url(#main)"/>'
          '<rect x="8" y="6" width="16" height="7" rx="2" fill="url(#accent)"/>'
          '<path d="M9 18h2m4 0h2m4 0h2M9 24h2m4 0h2m4 0h2" stroke="#EEF5FF" stroke-width="3"/>'),
  'store': _Illustration(
      '#F4B0B2',
      '#D36F8B',
      '#A4D7D1',
      '#649FAE',
      '<rect x="4" y="11" width="24" height="19" rx="2" fill="url(#accent)"/>'
          '<path d="M6 3h20l5 10H1Z" fill="url(#main)"/>'
          '<path d="m10 3-2 10m12-10 3 10" stroke="#FFF0DD" stroke-width="4"/>'
          '<rect x="7" y="17" width="8" height="7" rx="1" fill="#E8F6F7"/>'
          '<path d="M20 30V18h5v12Z" fill="#587C9D"/>'),
  'graduation': _Illustration(
      '#AFB9EA',
      '#707BBA',
      '#FFD594',
      '#DDA35F',
      '<path d="M7 14v9c6 7 12 7 18 0v-9Z" fill="url(#main)"/>'
          '<path d="m1 10 15-8 15 8-15 8Z" fill="url(#accent)"/>'
          '<path d="M29 11v15" stroke="#B17B42" stroke-width="2"/>'
          '<path d="m8 10 8-4 8 4" stroke="#FFF0C2" stroke-width="1.2"/>'),
  'science': _Illustration(
      '#A4DFD9',
      '#5BA8B5',
      '#C6ACED',
      '#956EC2',
      '<path d="M11 3h10v13l9 12c1 3-3 3-4 3H6c-2 0-5 0-4-3l9-12Z" fill="url(#main)"/>'
          '<path d="M7 22h18l5 6c1 3-3 3-4 3H6c-2 0-5 0-4-3Z" fill="url(#accent)"/>'
          '<path d="M10 3h12" stroke="#E4F9F5" stroke-width="3"/>'
          '<circle cx="15" cy="25" r="2" fill="#ECE0FC"/>'),
  'atom': _Illustration(
      '#92D6E0',
      '#509CC0',
      '#CCA7EA',
      '#9765C2',
      '<ellipse cx="16" cy="16" rx="14" ry="6" stroke="url(#main)" stroke-width="2"/>'
          '<ellipse cx="16" cy="16" rx="14" ry="6" transform="rotate(60 16 16)" stroke="url(#accent)" stroke-width="2"/>'
          '<ellipse cx="16" cy="16" rx="14" ry="6" transform="rotate(120 16 16)" stroke="#71B89E" stroke-width="2"/>'
          '<circle cx="16" cy="16" r="4" fill="#F1BC82"/>'),
  'microscope': _Illustration(
      '#A4BCEC',
      '#6E87BD',
      '#A4D9C6',
      '#65A892',
      '<path d="M20 10c12 8 6 16-5 16M10 21h12" stroke="url(#main)" stroke-width="4"/>'
          '<path d="m14 2 8 4-7 14-8-4Z" fill="url(#accent)"/>'
          '<path d="M7 30h21l-4-5H11Z" fill="url(#main)"/>'
          '<path d="m14 6 3 2" stroke="#DFF7E8" stroke-width="2"/>'),
  'backpack': _Illustration(
      '#E8B0CD',
      '#BF779F',
      '#A2CFE5',
      '#679DBE',
      '<path d="M12 7V3h8v4" stroke="#9B6D9D" stroke-width="3"/>'
          '<rect x="5" y="6" width="22" height="25" rx="7" fill="url(#main)"/>'
          '<rect x="8" y="17" width="16" height="11" rx="3" fill="url(#accent)"/>'
          '<path d="M10 20h12M12 11h8" stroke="#EAF6FF" stroke-width="1.5"/>'),
  'pencil-ruler': _Illustration(
      '#FFD69B',
      '#DDA258',
      '#A9CDE9',
      '#7299BD',
      '<path d="m3 26 21-23 6 5-22 22-7 1Z" fill="url(#main)"/>'
          '<path d="m3 7 5-5 23 24-5 5Z" fill="url(#accent)"/>'
          '<path d="m8 8-2 2m7 3-2 2m7 3-2 2m7 3-2 2" stroke="#EFF6FA" stroke-width="1.4"/>'),
  'tree': _Illustration(
      '#A6D98B',
      '#54A582',
      '#E4BA89',
      '#B58B60',
      '<path d="M13 16h6v15h-6Z" fill="url(#accent)"/>'
          '<path d="M8 21c-9-1-7-12 0-12-1-10 15-10 16 0 9 0 10 12 1 13Z" fill="url(#main)"/>'
          '<path d="M8 11c0-3 2-5 5-5" stroke="#DEF2BB" stroke-width="1.6"/>'),
  'flower': _Illustration(
      '#F8BDD3',
      '#DE7DAC',
      '#FFE19B',
      '#EFB862',
      '<path d="M16 18v13m0-4c-6 0-9-4-8-7 6-1 9 3 8 7" fill="#7BBB96" stroke="#60A785" stroke-width="1.5"/>'
          '<path d="M11 10c-7-9 10-13 10-3 11-3 13 11 3 12 4 10-12 14-13 3C0 24-2 9 11 10Z" fill="url(#main)"/>'
          '<circle cx="17" cy="14" r="5" fill="url(#accent)"/>'),
  'leaf': _Illustration(
      '#C5E69A',
      '#69B886',
      '#FFE2A9',
      '#DCAF67',
      '<path d="M4 25C0 10 14 1 30 2c0 17-11 27-26 23Z" fill="url(#main)"/>'
          '<path d="M3 29 25 7m-12 13-2-9m9 2 8 1" stroke="url(#accent)" stroke-width="2"/>'
          '<path d="M8 15c3-5 7-7 11-9" stroke="#ECF8D2" stroke-width="1.2"/>'),
  'cactus': _Illustration(
      '#9DD8AA',
      '#4B9C83',
      '#E8B6A0',
      '#CA896F',
      '<path d="M12 25V7a4 4 0 0 1 8 0v18m-5-7H8a4 4 0 0 1-4-4V9m13 5h7a4 4 0 0 0 4-4V6" stroke="url(#main)" stroke-width="5"/>'
          '<path d="m8 23 3 8h10l3-8Z" fill="url(#accent)"/>'
          '<path d="M15 7v14" stroke="#D4EDD0" stroke-width="1"/>'),
  'butterfly': _Illustration(
      '#B6ABF0',
      '#856FC7',
      '#F1C397',
      '#D89D76',
      '<path d="M15 14C8-2-2 1 2 14l6 5c-9 10 5 15 8 1Z" fill="url(#main)"/>'
          '<path d="M17 14C24-2 34 1 30 14l-6 5c9 10-5 15-8 1Z" fill="url(#accent)"/>'
          '<path d="M16 11v14m0-14-4-5m4 5 4-5" stroke="#726B9F" stroke-width="2"/>'),
  'rainbow': _Illustration(
      '#F0AFBB',
      '#D67DA9',
      '#FFD895',
      '#EABE72',
      '<path d="M3 28V17a13 13 0 0 1 26 0v11" stroke="url(#main)" stroke-width="5"/>'
          '<path d="M8 28V17a8 8 0 0 1 16 0v11" stroke="url(#accent)" stroke-width="5"/>'
          '<path d="M13 28V17a3 3 0 0 1 6 0v11" stroke="#82C1B9" stroke-width="5"/>'),
  'airplane': _Illustration(
      '#C1E5F3',
      '#7AAFCB',
      '#D4B6EB',
      '#A580C5',
      '<path d="m2 19 11-8V3c0-4 6-4 6 0v8l11 8v4l-11-4v6l4 3v3l-7-2-7 2v-3l4-3v-6L2 23Z" fill="url(#main)"/>'
          '<path d="M16 3v25l7 3v-3l-4-3v-6l11 4v-4l-11-8V3Z" fill="url(#accent)"/>'),
  'suitcase': _Illustration(
      '#DAB5E6',
      '#A37EBC',
      '#A8D8D7',
      '#69A9B1',
      '<path d="M11 6V2h10v4M8 27v4m16-4v4" stroke="#7887A5" stroke-width="3"/>'
          '<rect x="4" y="6" width="24" height="23" rx="4" fill="url(#main)"/>'
          '<path d="M10 7v20m12-20v20" stroke="url(#accent)" stroke-width="3"/>'
          '<rect x="13" y="13" width="7" height="5" rx="1" fill="#FFE0A9"/>'),
  'tent': _Illustration(
      '#F3C394',
      '#D6976A',
      '#B4C7EC',
      '#7E91C1',
      '<path d="m16 2 15 28H1Z" fill="url(#main)"/>'
          '<path d="M16 2v28h15Z" fill="url(#accent)"/>'
          '<path d="m16 13 7 17H9Z" fill="#617A91"/>'
          '<path d="m4 27 10-19" stroke="#FFE4C1" stroke-width="1.5"/>'),
  'bicycle': _Illustration(
      '#95D5D5',
      '#58A0B3',
      '#F0BBAD',
      '#D78596',
      '<g stroke="url(#main)" stroke-width="2.5"><circle cx="7" cy="24" r="6"/><circle cx="25" cy="24" r="6"/></g>'
          '<path d="m7 24 6-13 6 13H7m6-13h10l-4 13m6 0-4-18h5M9 10h6" stroke="url(#accent)" stroke-width="2.5"/>'),
  'train': _Illustration(
      '#A3C9EA',
      '#5F92BE',
      '#EDD0A1',
      '#D3A975',
      '<rect x="5" y="2" width="22" height="26" rx="6" fill="url(#main)"/>'
          '<rect x="8" y="7" width="16" height="10" rx="2" fill="#E6F7F7"/>'
          '<path d="M16 7v10m-7 9-4 5m18-5 4 5" stroke="#71819F" stroke-width="2"/>'
          '<path d="M10 22h1m10 0h1" stroke="url(#accent)" stroke-width="4"/>'),
  'beach': _Illustration(
      '#ABCFEA',
      '#719EBF',
      '#F1CDA2',
      '#D9AF76',
      '<path d="M1 24c10-6 21-6 30 0v8H1Z" fill="url(#accent)"/>'
          '<path d="M17 10 12 28" stroke="#A07E69" stroke-width="2"/>'
          '<path d="M3 13C8-4 29-1 30 19l-12-4Z" fill="url(#main)"/>'
          '<path d="M18 2c-7 3-9 8-10 12l10 1Z" fill="#EAA6BC"/>'
          '<circle cx="27" cy="4" r="3" fill="#FFDF92"/>'),
  'apple': _Illustration(
      '#F4A7A1',
      '#D66C88',
      '#A4D7A5',
      '#68A884',
      '<path d="M16 8c-13-8-20 11-9 21 4 3 7 0 9 0s5 3 9 0C36 19 29 0 16 8Z" fill="url(#main)"/>'
          '<path d="M16 8c-2-5 2-7 3-7" stroke="#96774D" stroke-width="2"/>'
          '<path d="M18 7c0-6 5-7 11-5-1 5-5 7-11 5Z" fill="url(#accent)"/>'
          '<path d="M7 13c-2 3-1 6 0 8" stroke="#FFD4C8" stroke-width="1.8"/>'),
  'pizza': _Illustration(
      '#FFE29D',
      '#EABB60',
      '#E8B185',
      '#BF825B',
      '<path d="m16 30-14-24c10-6 20-6 28 0Z" fill="url(#main)"/>'
          '<path d="M3 6c9-5 18-5 26 0" stroke="url(#accent)" stroke-width="5"/>'
          '<g fill="#DC8094"><circle cx="11" cy="12" r="3"/><circle cx="22" cy="11" r="3"/>'
          '<circle cx="16" cy="21" r="2.5"/></g><path d="m16 10 2 2m-6 5 2 1" stroke="#78AF82" stroke-width="2"/>'),
  'tea': _Illustration(
      '#B9DAB5',
      '#73A991',
      '#F1C39C',
      '#CB9B75',
      '<ellipse cx="15" cy="28" rx="14" ry="3" fill="url(#accent)"/>'
          '<path d="M24 12h3a5 5 0 0 1 0 10h-4" stroke="#8BB7AA" stroke-width="3"/>'
          '<path d="M4 11h21v10c0 10-21 10-21 0Z" fill="url(#main)"/>'
          '<ellipse cx="14.5" cy="11" rx="10.5" ry="3" fill="#F7EDCC"/>'
          '<path d="M11 7c-3-2 2-4 0-6m7 6c-3-2 2-4 0-6" stroke="#C4A981" stroke-width="1.5"/>'),
  'cake': _Illustration(
      '#EDB6CE',
      '#CF87AE',
      '#F7D29E',
      '#DCAF75',
      '<rect x="3" y="12" width="26" height="17" rx="3" fill="url(#accent)"/>'
          '<path d="M3 20h26" stroke="#FDF0D9" stroke-width="3"/>'
          '<path d="M3 15v-3c0-6 26-6 26 0v7c-5 0-4-5-7-2s-4 3-7 0-4 4-7 1-2-3-5-3Z" fill="url(#main)"/>'
          '<path d="M16 11V5" stroke="#82B7CC" stroke-width="3"/><path d="M16 1c-5 5 5 5 0 0Z" fill="#F2B661"/>'),
  'dumbbell': _Illustration(
      '#B9B4ED',
      '#827CC3',
      '#99D6D7',
      '#5FA3B9',
      '<path d="M6 16h20" stroke="url(#accent)" stroke-width="6"/>'
          '<g fill="url(#main)"><rect x="2" y="6" width="8" height="20" rx="3"/>'
          '<rect x="22" y="6" width="8" height="20" rx="3"/></g>'
          '<path d="M5 9v12m20-12v12" stroke="#E0DBFC" stroke-width="1.2"/>'),
  'first-aid': _Illustration(
      '#ECAEC0',
      '#CE799C',
      '#B1CEDF',
      '#759CB9',
      '<path d="M11 8V3h10v5" stroke="url(#accent)" stroke-width="3"/>'
          '<rect x="2" y="8" width="28" height="22" rx="4" fill="url(#main)"/>'
          '<path d="M13 12h6v5h5v6h-5v5h-6v-5H8v-6h5Z" fill="#FFF4F1"/>'),
  'meditation': _Illustration(
      '#B3A7EA',
      '#8171BF',
      '#F0C9A6',
      '#D3A582',
      '<circle cx="16" cy="7" r="5" fill="url(#accent)"/>'
          '<path d="M9 13h14l2 10-9 4-9-4Z" fill="url(#main)"/>'
          '<path d="m10 17-5 6H2m20-6 5 6h3" stroke="url(#accent)" stroke-width="3"/>'
          '<path d="m15 27-8-3c-5-2-7 6-1 6h20c6 0 4-8-1-6l-8 3" fill="#849DBD"/>'),
  'running': _Illustration(
      '#9CD6D5',
      '#58A0AF',
      '#E9B5CA',
      '#C580A3',
      '<circle cx="21" cy="5" r="4" fill="#EBC5A4"/>'
          '<path d="m19 11-5 8 7 4-2 7m-5-11-3 8H3m14-14-5-3-5 4m11 0 4 5h7" '
          'stroke="url(#main)" stroke-width="4"/>'
          '<path d="m16 11 5 3" stroke="url(#accent)" stroke-width="5"/>'),
  'laptop': _Illustration(
      '#ACBAE8',
      '#7888BD',
      '#9DD5D3',
      '#63A0B2',
      '<rect x="4" y="3" width="24" height="21" rx="3" fill="url(#main)"/>'
          '<rect x="7" y="6" width="18" height="14" rx="1" fill="url(#accent)"/>'
          '<path d="M4 24h24l4 5H0Z" fill="#ADC2D5"/>'
          '<path d="m10 16 4-6 4 5 4-2" stroke="#E5FAEE" stroke-width="1.5"/>'),
  'robot': _Illustration(
      '#AFC8E8',
      '#7396BE',
      '#D4B4E9',
      '#A67FC5',
      '<path d="M16 3v5" stroke="#89A6C3" stroke-width="2"/><circle cx="16" cy="3" r="2" fill="#E9B782"/>'
          '<rect x="4" y="8" width="24" height="22" rx="6" fill="url(#main)"/>'
          '<rect x="8" y="12" width="16" height="10" rx="3" fill="url(#accent)"/>'
          '<path d="M11 16v2m10-2v2M12 26h8" stroke="#F8EFFF" stroke-width="2"/>'),
  'gamepad': _Illustration(
      '#BCA9EA',
      '#876DC2',
      '#B0DBCD',
      '#70AC9F',
      '<path d="M10 8h12c7 0 12 18 7 21-3 2-7-4-9-4h-8c-2 0-6 6-9 4C-2 26 3 8 10 8Z" fill="url(#main)"/>'
          '<path d="M9 12v9m-4-4.5h8" stroke="#EDE4FC" stroke-width="2.5"/>'
          '<g fill="url(#accent)"><circle cx="24" cy="14" r="2.2"/><circle cx="20" cy="19" r="2.2"/></g>'),
  'headphones': _Illustration(
      '#AFCBEA',
      '#6D97C4',
      '#D2B2E6',
      '#A077BD',
      '<path d="M4 20v-5a12 12 0 0 1 24 0v5" stroke="url(#main)" stroke-width="5"/>'
          '<rect x="1" y="16" width="8" height="14" rx="4" fill="url(#accent)"/>'
          '<rect x="23" y="16" width="8" height="14" rx="4" fill="url(#accent)"/>'
          '<path d="M4 20v6m23-6v6" stroke="#EEDBF9" stroke-width="1.3"/>'),
  'selection': _Illustration(
      '#AAC9ED',
      '#698FC0',
      '#CFB2E9',
      '#9C77C0',
      '<path d="M5 11V5h6m10 0h6v6M5 21v6h6m10 0h6v-6" stroke="url(#main)" stroke-width="3"/>'
          '<path d="m12 10 14 9-7 2-3 7Z" fill="url(#accent)"/>'
          '<path d="m14 14 7 5" stroke="#F1E5FC" stroke-width="1.2"/>'),
  'relation': _Illustration(
      '#A8CDEC',
      '#7299C2',
      '#C8B4E9',
      '#967CC0',
      '<rect x="1" y="3" width="12" height="17" rx="3" fill="url(#main)"/>'
          '<rect x="19" y="12" width="12" height="17" rx="3" fill="url(#accent)"/>'
          '<path d="M9 13h7v8h7" stroke="#5EABA3" stroke-width="3"/>'
          '<path d="M4 7h6M22 16h6" stroke="#F6F7FF" stroke-width="1.5"/>'),
  'pie-chart': _Illustration(
      '#B4A3E6',
      '#8668BD',
      '#9AD6CA',
      '#5AA79E',
      '<path d="M14 2a14 14 0 1 0 16 16H14Z" fill="url(#main)"/>'
          '<path d="M18 1v13h13A14 14 0 0 0 18 1Z" fill="url(#accent)"/>'
          '<path d="M7 10c-4 8 2 15 7 15" stroke="#E3D6FB" stroke-width="1.5"/>'),
  'flag': _Illustration(
      '#F1B7BD',
      '#D37F9E',
      '#ACCDE6',
      '#739CBF',
      '<path d="M6 30V3" stroke="url(#accent)" stroke-width="3"/>'
          '<path d="M7 4c7-5 13 5 22 0v15c-9 5-15-5-22 0Z" fill="url(#main)"/>'
          '<path d="M10 7c5-2 9 3 15 1" stroke="#FFE2E4" stroke-width="1.5"/>'),
  'key': _Illustration(
      '#FFE19B',
      '#D9A963',
      '#B6C3EC',
      '#7B91C1',
      '<circle cx="10" cy="10" r="9" fill="url(#main)"/>'
          '<circle cx="9" cy="9" r="3.5" fill="#FFF1CF"/>'
          '<path d="m15 14 15 13-4 4-4-4-3 2-3-3 2-3-7-6Z" fill="url(#accent)"/>'),
  'graduation-cap': _Illustration(
      '#A3C5EA',
      '#648DBB',
      '#D6B6E9',
      '#A77CC5',
      '<path d="m3 10 13-8 13 8-13 8Z" fill="url(#main)"/>'
          '<path d="M7 15v8c6 6 12 6 18 0v-8l-9 6Z" fill="url(#accent)"/>'
          '<path d="M29 11v16m-2 0h4" stroke="#E8B876" stroke-width="2"/>'),
  'telescope': _Illustration(
      '#B5BCEB',
      '#808BC2',
      '#ACD9CE',
      '#6CAC9D',
      '<path d="m14 17 9 14m-9-14-6 14m6-14v14" stroke="#B29686" stroke-width="2.5"/>'
          '<path d="m2 13 22-11 6 12-23 9Z" fill="url(#main)"/>'
          '<path d="m21 3 4-2 6 13-5 2Z" fill="url(#accent)"/>'
          '<path d="m6 13 12-6" stroke="#DFEAFB" stroke-width="1.4"/>'),
  'ruler': _Illustration(
      '#F6D29A',
      '#D4A66B',
      '#AED5E8',
      '#7CA5C3',
      '<path d="M4 3v27h26Z" fill="url(#main)"/>'
          '<path d="M10 17v7h7Z" fill="url(#accent)"/>'
          '<path d="M7 11H4m3 6H4m3 6H4m10 4v3m6-3v3" stroke="#A4774C" stroke-width="1.4"/>'),
  'abacus': _Illustration(
      '#D5B899',
      '#AE8E6A',
      '#B5ABEA',
      '#8B7AC4',
      '<rect x="2" y="2" width="28" height="28" rx="3" stroke="url(#main)" stroke-width="3"/>'
          '<path d="M3 10h26M3 21h26" stroke="#799EA6" stroke-width="1.5"/>'
          '<g fill="url(#accent)"><rect x="7" y="6" width="5" height="8" rx="2"/><rect x="15" y="6" width="5" height="8" rx="2"/></g>'
          '<g fill="#83C5B2"><rect x="12" y="17" width="5" height="8" rx="2"/><rect x="20" y="17" width="5" height="8" rx="2"/></g>'),
  'sun': _Illustration(
      '#FFE59A',
      '#EAB665',
      '#F2B5A2',
      '#D98F86',
      '<path d="M16 1v4m0 22v4M1 16h4m22 0h4M5 5l3 3m16 16 3 3M5 27l3-3M24 8l3-3" stroke="url(#accent)" stroke-width="2.5"/>'
          '<circle cx="16" cy="16" r="9" fill="url(#main)"/>'
          '<path d="M11 13a6 6 0 0 1 5-3" stroke="#FFF5CC" stroke-width="1.7"/>'),
  'moon': _Illustration(
      '#CEC5F1',
      '#9791C8',
      '#FFE3A1',
      '#E8BE77',
      '<path d="M20 2C1-2-5 24 14 30c8 2 14-3 17-9C15 27 8 7 20 2Z" fill="url(#main)"/>'
          '<path d="m25 3 1.5 4L31 9l-4.5 1.5L25 15l-1.5-4.5L19 9l4.5-2Z" fill="url(#accent)"/>'
          '<path d="M6 17c0 5 3 8 7 10" stroke="#EEE8FF" stroke-width="1.5"/>'),
  'sailboat': _Illustration(
      '#A7D3E8',
      '#6E9CBE',
      '#F0C39E',
      '#D6A079',
      '<path d="M15 2v23" stroke="#908DAB" stroke-width="2"/>'
          '<path d="M13 4 2 21h11Z" fill="url(#main)"/>'
          '<path d="m17 6 12 15H17Z" fill="url(#accent)"/>'
          '<path d="m2 24 6 6h17l6-6Z" fill="#9380C0"/>'
          '<path d="M7 27h17" stroke="#D9D4F6" stroke-width="1.3"/>'),
  'carrot': _Illustration(
      '#FFD196',
      '#E79C61',
      '#ADDC9C',
      '#69B08B',
      '<path d="M22 11c-5-5-10-3-13 2L1 31l20-9c6-3 6-7 1-11Z" fill="url(#main)"/>'
          '<path d="m20 11 1-9m1 10 7-8m-6 10 8-1" stroke="url(#accent)" stroke-width="4"/>'
          '<path d="m11 14 4 4m-9 4 3 2" stroke="#C98858" stroke-width="1.5"/>'),
  'bread': _Illustration(
      '#F1D49F',
      '#D5AB72',
      '#E0AE7F',
      '#B8835B',
      '<path d="M3 12C-4 1 36-4 29 12v16a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3Z" fill="url(#accent)"/>'
          '<path d="M6 12c-6-8 26-11 20 0v15H6Z" fill="url(#main)"/>'
          '<path d="m9 10 4-3m4 3 4-3" stroke="#FBEACA" stroke-width="2"/>'),
  'cheese': _Illustration(
      '#FFE49A',
      '#EAB861',
      '#E4B884',
      '#C89659',
      '<path d="m3 13 24-9 4 21-28 6Z" fill="url(#main)"/>'
          '<path d="M3 13v18l28-6-1-6-6 1-1-4 6-2-2-10Z" fill="url(#accent)"/>'
          '<path d="m3 13 24-9 2 10-26 7Z" fill="url(#main)"/>'
          '<g fill="#FFF0B9"><ellipse cx="14" cy="12" rx="3" ry="1.6"/><circle cx="10" cy="24" r="2"/><circle cx="21" cy="22" r="2"/></g>'),
  'bowl': _Illustration(
      '#AED5E6',
      '#749FBF',
      '#F1D098',
      '#D8AC71',
      '<path d="M2 13h28c0 10-6 16-14 16S2 23 2 13Z" fill="url(#main)"/>'
          '<ellipse cx="16" cy="13" rx="14" ry="4" fill="url(#accent)"/>'
          '<path d="M7 12c3-4 3 4 7 0s4 4 9 0M10 5c-2-2 2-3 0-5m10 5c-2-2 2-3 0-5" stroke="#FFF0CB" stroke-width="1.5"/>'
          '<path d="M9 29h14" stroke="#6A8EA9" stroke-width="2"/>'),
  'teapot': _Illustration(
      '#AED6BD',
      '#70A991',
      '#EDC89E',
      '#CFA379',
      '<path d="M24 13c9-9 9 13 0 8" stroke="url(#accent)" stroke-width="3"/>'
          '<path d="M8 12 1 9l3 11 5 3" fill="url(#accent)"/>'
          '<ellipse cx="16" cy="20" rx="11" ry="10" fill="url(#main)"/>'
          '<path d="M8 11h16l-4-4h-8Z" fill="url(#accent)"/>'
          '<circle cx="16" cy="5" r="2" fill="#8BA888"/>'
          '<path d="M10 17c-2 4 0 7 2 8" stroke="#E3F3D9" stroke-width="1.5"/>'),
  'stethoscope': _Illustration(
      '#A5CBE7',
      '#699ABD',
      '#D6B4E4',
      '#A27FBF',
      '<path d="M4 3v11a8 8 0 0 0 16 0V3M12 22v3c0 9 16 6 14-3" stroke="url(#main)" stroke-width="3"/>'
          '<path d="M4 3h3m10 0h3" stroke="#E9C79F" stroke-width="4"/>'
          '<circle cx="26" cy="19" r="5" fill="url(#accent)"/>'
          '<circle cx="26" cy="19" r="2" fill="#EEE7FA"/>'),
  'bandage': _Illustration(
      '#F1D1A7',
      '#D5AB83',
      '#D7B4E5',
      '#AB80C4',
      '<rect x="1" y="10" width="30" height="12" rx="6" transform="rotate(-40 16 16)" fill="url(#main)"/>'
          '<rect x="11" y="10" width="10" height="12" rx="2" transform="rotate(-40 16 16)" fill="url(#accent)"/>'
          '<path d="m7 21 1-1m0 4 1-1m14-15 1-1m0 4 1-1" stroke="#FFF0DC" stroke-width="1.5"/>'),
  'pill': _Illustration(
      '#F0B1C7',
      '#CC7DA3',
      '#B6D8E9',
      '#7BA5C4',
      '<path d="m5 15 10-10a8 8 0 0 1 12 12L17 27A8 8 0 0 1 5 15Z" fill="url(#main)"/>'
          '<path d="m11 9 12 12 4-4A8 8 0 0 0 15 5Z" fill="url(#accent)"/>'
          '<path d="m17 7 2-1m-12 12 3-3" stroke="#F3F6FD" stroke-width="1.7"/>'),
  'tooth': _Illustration(
      '#EEF4F7',
      '#ABCBDC',
      '#B8B8EB',
      '#8A8CC4',
      '<path d="M16 4C2-4-2 9 5 19c3 16 7 14 8 3 1-7 5-7 6 0 1 11 5 13 8-3 7-10 3-23-11-15Z" fill="url(#main)"/>'
          '<path d="M16 4c5 3 8 2 11 0M12 20c1-7 7-7 8 0" stroke="url(#accent)" stroke-width="2"/>'
          '<path d="M7 8c-2 4 0 7 1 9" stroke="#FFFFFF" stroke-width="1.5"/>'),
  'mouse': _Illustration(
      '#C1B4E8',
      '#9080BF',
      '#A2D6D7',
      '#69A7B7',
      '<rect x="6" y="2" width="20" height="28" rx="10" fill="url(#main)"/>'
          '<path d="M16 2v13H6" stroke="#EEE4FF" stroke-width="1.2"/>'
          '<rect x="13" y="6" width="6" height="9" rx="3" fill="url(#accent)"/>'),
  'microchip': _Illustration(
      '#AACCE6',
      '#6E9BB9',
      '#B6D6B3',
      '#7BAD99',
      '<path d="M8 1v5m8-5v5m8-5v5M8 26v5m8-5v5m8-5v5M1 8h5m-5 8h5m-5 8h5M26 8h5m-5 8h5m-5 8h5" stroke="url(#accent)" stroke-width="2"/>'
          '<rect x="5" y="5" width="22" height="22" rx="3" fill="url(#main)"/>'
          '<rect x="10" y="10" width="12" height="12" rx="2" fill="url(#accent)"/>'
          '<path d="M12 12h8" stroke="#DFEFE3" stroke-width="1.4"/>'),
  'wifi': _Illustration(
      '#9BCFDC',
      '#599AB9',
      '#C8AFE9',
      '#9876C2',
      '<path d="M2 9c8-8 20-8 28 0M7 15c5-5 13-5 18 0" stroke="url(#main)" stroke-width="4"/>'
          '<path d="M12 21c2-2 6-2 8 0" stroke="url(#accent)" stroke-width="4"/>'
          '<circle cx="16" cy="28" r="3" fill="url(#accent)"/>'),
  'battery': _Illustration(
      '#ABD4BE',
      '#6AA58D',
      '#EFD198',
      '#D7B175',
      '<path d="M10 4V1h12v3" fill="url(#accent)"/>'
          '<rect x="6" y="4" width="20" height="27" rx="4" fill="url(#main)"/>'
          '<path d="m18 8-8 12h6l-1 7 8-12h-6Z" fill="url(#accent)"/>'
          '<path d="M9 9v13" stroke="#DDF1E5" stroke-width="1.2"/>'),
  'terminal': _Illustration(
      '#B0C6E4',
      '#728DAE',
      '#B8D8C1',
      '#80AF9D',
      '<rect x="2" y="4" width="28" height="25" rx="4" fill="url(#main)"/>'
          '<rect x="5" y="10" width="22" height="16" rx="2" fill="#4D6486"/>'
          '<path d="m9 14 4 4-4 4m8 0h6" stroke="url(#accent)" stroke-width="2.5"/>'
          '<path d="M6 7h1m3 0h1m3 0h1" stroke="#F6D4A4" stroke-width="1.5"/>'),
};
