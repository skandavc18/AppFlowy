import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:flutter/material.dart';

import 'web_embed_site_base.dart';

/// What shops add to an address to see where a buyer came from.
const _shopTracking = {
  '_trkparms',
  '_trksid',
  'aff_fcid',
  'aff_fsk',
  'aff_id',
  'aff_platform',
  'affextparam1',
  'affextparam2',
  'affid',
  'affiliate',
  'afsmartredirect',
  'algo_exp_id',
  'algo_pvid',
  'campid',
  'click_key',
  'cmpid',
  'customid',
  'gatewayadapt',
  'mkcid',
  'mkevt',
  'mkrid',
  'pdp_npi',
  'scm',
  'sk',
  'spm',
  'srsltid',
  'terminal_id',
  'toolid',
};

/// A product's title from the most worded part of its address, like
/// `apple-iphone-15-black-128-gb`.
String? _productTitle(Uri uri) => webEmbedArticleTitle(uri, minimumWords: 2);

/// Products, wish lists and stores from every Amazon storefront, shown as
/// Amazon's phone page.
class AmazonEmbeds extends FramedWebEmbedProvider {
  const AmazonEmbeds();

  static final _host = RegExp(
    r'^(?:www\.|smile\.|m\.)?amazon\.'
    r'(com|ca|com\.mx|com\.br|co\.uk|de|fr|it|es|nl|se|pl|com\.tr|ae|sa|eg'
    r'|in|co\.jp|cn|sg|com\.au|com\.be)$',
  );
  static final _asin = RegExp(r'^[A-Z0-9]{10}$');
  static const _shortHosts = {
    'a.co',
    'amzn.asia',
    'amzn.com',
    'amzn.eu',
    'amzn.in',
    'amzn.to',
  };

  /// The segment an ASIN follows: `/dp/<asin>`, `/gp/product/<asin>`,
  /// `/gp/aw/d/<asin>`, `/exec/obidos/ASIN/<asin>`.
  static const _asinMarkers = {'dp', 'product', 'd', 'asin'};

  @override
  String get id => 'amazon';

  @override
  String get name => 'Amazon';

  @override
  List<String> get keywords => const [
        'amazon',
        'product',
        'shopping',
        'buy',
        'store',
        'wish list',
        'prime video',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Wish list' => Icons.list_alt_rounded,
        'Search' => Icons.search_rounded,
        'Store' => Icons.sell_rounded,
        'Prime Video' => Icons.movie_rounded,
        _ => Icons.local_offer_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFF9900);

  @override
  bool ownsHost(String host) =>
      _host.hasMatch(host) || _shortHosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (_shortHosts.contains(host)) {
      return segments.isEmpty
          ? null
          : WebEmbedLink(
              provider: this,
              kind: 'Product',
              url: 'https://$host/${segments.join('/')}',
              defaultHeight: 720,
              needsResolution: true,
              parameters: const {webEmbedFullPage: 'true'},
            );
    }
    final storefront = _host.firstMatch(host)?.group(1);
    if (storefront == null) {
      return null;
    }
    final base = 'www.amazon.$storefront';
    String? asin;
    for (var i = 0; i + 1 < segments.length; i++) {
      final candidate = segments[i + 1].toUpperCase();
      if (_asinMarkers.contains(segments[i].toLowerCase()) &&
          _asin.hasMatch(candidate)) {
        asin = candidate;
        break;
      }
    }
    if (asin != null) {
      final at = segments.indexWhere(
        (segment) => segment.toUpperCase() == asin,
      );
      // `/Apple-iPhone-15-128-GB/dp/<asin>` names the product first.
      final slug = at >= 2 ? segments[at - 2] : null;
      return webEmbedPage(
        this,
        'Product',
        'https://$base/dp/$asin',
        id: asin,
        title:
            slug == null || slug == 'gp' ? null : webEmbedTitleFromSlug(slug),
        height: 720,
      );
    }
    final path = segments.join('/').toLowerCase();
    if (path.contains('wishlist')) {
      return webEmbedPage(
        this,
        'Wish list',
        Uri.https(base, segments.join('/')).toString(),
      );
    }
    if (segments.isNotEmpty &&
        (segments.first == 'stores' || segments.first == 'shop')) {
      return webEmbedPage(
        this,
        'Store',
        Uri.https(base, segments.join('/')).toString(),
      );
    }
    final query = uri.queryParameters['k'];
    if (segments.length == 1 && segments.first == 's' && query != null) {
      return webEmbedPage(
        this,
        'Search',
        Uri.https(base, '/s', {'k': query}).toString(),
        title: query,
      );
    }
    if (path.startsWith('gp/video') || path.contains('prime-video')) {
      return webEmbedPage(
        this,
        'Prime Video',
        Uri.https(base, segments.join('/')).toString(),
      );
    }
    return null;
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  /// `Amazon.in: Buy Apple iPhone 15 (128 GB) - Black Online at …` and
  /// `Apple iPhone 15 (128 GB) - Black : Amazon.in: Electronics` both read
  /// `Apple iPhone 15 (128 GB) - Black`. A bot check only says `Amazon.in`.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) {
          final tidy = title
              .replaceFirst(
                RegExp(r'^Amazon(?:\.[a-z.]+)?\s*:\s*', caseSensitive: false),
                '',
              )
              .replaceFirst(RegExp(r'^Buy\s+'), '')
              .split(RegExp(r'\s+Online at\s+|\s+:\s+Amazon\.'))
              .first
              .trim();
          return tidy.isEmpty ||
                  RegExp(r'^amazon(?:\.[a-z.]+)?$', caseSensitive: false)
                      .hasMatch(tidy)
              ? null
              : tidy;
        },
      );
}

/// Products, searches and categories from Flipkart, shown as its phone page.
class FlipkartEmbeds extends FramedWebEmbedProvider {
  const FlipkartEmbeds();

  static const _shortHosts = {'fkrt.it', 'fkrt.cc', 'fkrt.co'};

  @override
  String get id => 'flipkart';

  @override
  String get name => 'Flipkart';

  @override
  List<String> get keywords =>
      const ['flipkart', 'product', 'shopping', 'buy', 'india', 'store'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Search' => Icons.search_rounded,
        'Category' => Icons.sell_rounded,
        _ => Icons.local_offer_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF2874F0);

  @override
  bool ownsHost(String host) =>
      isWebEmbedHost(host, 'flipkart.com') || _shortHosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    final short = _shortHosts.contains(host) ||
        (host == 'dl.flipkart.com' &&
            segments.isNotEmpty &&
            segments.first == 's');
    if (short) {
      return segments.isEmpty
          ? null
          : WebEmbedLink(
              provider: this,
              kind: 'Product',
              url: uri.replace(scheme: 'https').toString(),
              defaultHeight: 720,
              needsResolution: true,
              parameters: const {webEmbedFullPage: 'true'},
            );
    }
    if (!isWebEmbedHost(host, 'flipkart.com')) {
      return null;
    }
    final at = segments.indexOf('p');
    if (at >= 0 &&
        at + 1 < segments.length &&
        segments[at + 1].startsWith('itm')) {
      final item = segments[at + 1];
      final slug = at > 0 && segments[at - 1] != 'dl' ? segments[at - 1] : null;
      final product = uri.queryParameters['pid'];
      return webEmbedPage(
        this,
        'Product',
        Uri.https(
          'www.flipkart.com',
          [if (slug != null) slug, 'p', item].join('/'),
          product == null ? null : {'pid': product},
        ).toString(),
        id: product ?? item,
        title: slug == null ? null : webEmbedTitleFromSlug(slug),
        height: 720,
      );
    }
    final query = uri.queryParameters['q'];
    if (segments.length == 1 && segments.first == 'search' && query != null) {
      return webEmbedPage(
        this,
        'Search',
        Uri.https('www.flipkart.com', '/search', {'q': query}).toString(),
        title: query,
      );
    }
    final category = uri.queryParameters['sid'];
    if (segments.length >= 2 && segments.last == 'pr' && category != null) {
      return webEmbedPage(
        this,
        'Category',
        Uri.https('www.flipkart.com', segments.join('/'), {'sid': category})
            .toString(),
        title: webEmbedTitleFromSlug(segments.first),
      );
    }
    return null;
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .split(
              RegExp(r'\s+[-|]\s+Buy\b|\s+Online at\b|\s+\|\s+Flipkart'),
            )
            .first
            .trim(),
      );
}

/// A site [ListingEmbeds] knows, and what its item pages look like.
class _ListingSite {
  _ListingSite(
    this.name,
    this.domains,
    String item, {
    this.kind = 'Product',
    this.accent,
    bool caseSensitive = true,
  }) : item = RegExp(item, caseSensitive: caseSensitive);

  final String name;
  final List<String> domains;

  /// Matched against the address's path; anything else on the site is one
  /// of its other pages.
  final RegExp item;

  /// What an item is called here: a product, a stay, a restaurant.
  final String kind;
  final Color? accent;
}

final _stores = [
  _ListingSite(
    'Myntra',
    ['myntra.com'],
    r'/\d{5,}/buy/?$',
    accent: const Color(0xFFFF3F6C),
  ),
  _ListingSite(
    'Meesho',
    ['meesho.com'],
    r'/p/[a-z0-9]+/?$',
    caseSensitive: false,
    accent: const Color(0xFF9F2089),
  ),
  _ListingSite(
    'AJIO',
    ['ajio.com'],
    r'/p/[a-z0-9_]+/?$',
    caseSensitive: false,
    accent: const Color(0xFF2C4152),
  ),
  _ListingSite(
    'Nykaa',
    ['nykaa.com', 'nykaafashion.com'],
    r'/p/\d+/?$',
    accent: const Color(0xFFFC2779),
  ),
  _ListingSite('Snapdeal', ['snapdeal.com'], '^/product/'),
  _ListingSite(
    'JioMart',
    ['jiomart.com'],
    '^/p/',
    accent: const Color(0xFF0078AD),
  ),
  _ListingSite(
    'BigBasket',
    ['bigbasket.com'],
    r'^/pd/\d+',
    accent: const Color(0xFF84C225),
  ),
  _ListingSite(
    'Blinkit',
    ['blinkit.com'],
    r'/prid/\d+',
    accent: const Color(0xFFF8CB46),
  ),
  _ListingSite('Zepto', ['zeptonow.com', 'zepto.com'], '/pvid/'),
  _ListingSite(
    'Tata CLiQ',
    ['tatacliq.com'],
    r'/p-mp\d+',
    caseSensitive: false,
  ),
  _ListingSite(
    'Croma',
    ['croma.com'],
    r'/p/\d+/?$',
    accent: const Color(0xFF00E9BF),
  ),
  _ListingSite(
    'Reliance Digital',
    ['reliancedigital.in'],
    r'/p/\d+/?$',
    accent: const Color(0xFFE42529),
  ),
  _ListingSite('Lenskart', ['lenskart.com'], r'\.html$'),
  _ListingSite('Decathlon', ['decathlon.in'], '^/p/'),
  _ListingSite(
    'eBay',
    [
      'ebay.com',
      'ebay.co.uk',
      'ebay.de',
      'ebay.fr',
      'ebay.it',
      'ebay.es',
      'ebay.ca',
      'ebay.com.au',
    ],
    '^/itm/',
    accent: const Color(0xFFE53238),
  ),
  _ListingSite(
    'Etsy',
    ['etsy.com'],
    r'/listing/\d+',
    accent: const Color(0xFFF1641E),
  ),
  _ListingSite(
    'Walmart',
    ['walmart.com', 'walmart.ca'],
    '^/ip/',
    accent: const Color(0xFF0071DC),
  ),
  _ListingSite(
    'Target',
    ['target.com'],
    r'/-/A-\d+',
    accent: const Color(0xFFCC0000),
  ),
  _ListingSite(
    'Best Buy',
    ['bestbuy.com'],
    r'\.p$',
    accent: const Color(0xFF0046BE),
  ),
  _ListingSite(
    'AliExpress',
    ['aliexpress.com', 'aliexpress.us'],
    r'^/item/\d+\.html$',
    accent: const Color(0xFFE62E04),
  ),
  _ListingSite(
    'IKEA',
    ['ikea.com'],
    r'/p/[^/]+-[0-9a-z]+/?$',
    caseSensitive: false,
    accent: const Color(0xFF0058A3),
  ),
  _ListingSite('SHEIN', ['shein.com', 'shein.in'], r'-p-\d+\.html$'),
  _ListingSite(
    'Temu',
    ['temu.com'],
    r'-g-\d+\.html$',
    accent: const Color(0xFFFB7701),
  ),
];

final _places = [
  _ListingSite(
    'Airbnb',
    [
      'airbnb.com',
      'airbnb.co.in',
      'airbnb.co.uk',
      'airbnb.ca',
      'airbnb.com.au',
      'airbnb.de',
      'airbnb.fr',
      'airbnb.es',
      'airbnb.it',
    ],
    r'^/rooms/(?:plus/)?\d+',
    kind: 'Stay',
    accent: const Color(0xFFFF5A5F),
  ),
  _ListingSite(
    'Booking.com',
    ['booking.com'],
    '^/hotel/',
    kind: 'Hotel',
    accent: const Color(0xFF003580),
  ),
  _ListingSite(
    'Tripadvisor',
    ['tripadvisor.com', 'tripadvisor.in', 'tripadvisor.co.uk'],
    '(?:Hotel|Restaurant|Attraction|Vacation)_Review-',
    kind: 'Place',
    accent: const Color(0xFF34E0A1),
  ),
  _ListingSite(
    'Expedia',
    ['expedia.com', 'expedia.co.in', 'expedia.co.uk'],
    r'\.Hotel-Information',
    kind: 'Hotel',
  ),
  _ListingSite('Agoda', ['agoda.com'], '/hotel/', kind: 'Hotel'),
  _ListingSite(
    'MakeMyTrip',
    ['makemytrip.com'],
    'hotel-details',
    kind: 'Hotel',
    accent: const Color(0xFF008CFF),
  ),
  _ListingSite(
    'Goibibo',
    ['goibibo.com'],
    r'^/hotels/.+-\d+/?$',
    kind: 'Hotel',
  ),
  _ListingSite(
    'Zomato',
    ['zomato.com'],
    r'^/[^/]+/[^/]+/(?:info|order|menu|reviews|photos)/?$',
    kind: 'Restaurant',
    accent: const Color(0xFFE23744),
  ),
  _ListingSite(
    'Swiggy',
    ['swiggy.com'],
    r'^/(?:restaurants/|city/.+-rest\d+)',
    kind: 'Restaurant',
    accent: const Color(0xFFFC8019),
  ),
  _ListingSite(
    'BookMyShow',
    ['bookmyshow.com'],
    r'/ET\d+',
    kind: 'Event',
    caseSensitive: false,
    accent: const Color(0xFFF84464),
  ),
  _ListingSite(
    'Yelp',
    ['yelp.com', 'yelp.ca', 'yelp.co.uk'],
    '^/biz/',
    kind: 'Place',
    accent: const Color(0xFFD32323),
  ),
];

/// Stores, or places to stay, eat and go, from sites that have no embed:
/// their item pages and the rest of their pages shown as the site's phone
/// page, with the site's own name and colour on the card.
class ListingEmbeds extends FramedWebEmbedProvider {
  const ListingEmbeds.stores() : id = 'stores';

  const ListingEmbeds.places() : id = 'places';

  @override
  final String id;

  bool get _isStores => id == 'stores';

  List<_ListingSite> get _sites => _isStores ? _stores : _places;

  @override
  String get name => _isStores ? 'Shops' : 'Travel & dining';

  @override
  List<String> get keywords => _isStores
      ? const [
          'shopping',
          'product',
          'store',
          'buy',
          'myntra',
          'meesho',
          'ajio',
          'nykaa',
          'ebay',
          'etsy',
          'walmart',
        ]
      : const [
          'travel',
          'hotel',
          'stay',
          'restaurant',
          'food',
          'tickets',
          'airbnb',
          'booking',
          'tripadvisor',
          'zomato',
          'swiggy',
          'bookmyshow',
        ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Product' => Icons.local_offer_rounded,
        'Stay' || 'Hotel' => Icons.home_rounded,
        'Restaurant' => Icons.restaurant_rounded,
        'Place' => Icons.place_rounded,
        'Event' => Icons.event_rounded,
        'Store page' => Icons.sell_rounded,
        _ => Icons.travel_explore_rounded,
      };

  @override
  Color colorFor(String kind) =>
      _isStores ? const Color(0xFFE8590C) : const Color(0xFF0B7285);

  @override
  bool ownsHost(String host) => _siteFor(host) != null;

  _ListingSite? _siteFor(String host) {
    for (final site in _sites) {
      if (isWebEmbedHostOf(host, site.domains)) {
        return site;
      }
    }
    return null;
  }

  @override
  WebEmbedLink? recognize(Uri uri) {
    final site = _siteFor(uri.host.toLowerCase());
    final segments = webEmbedSegments(uri);
    // A site's home page is better left as a plain link, and a manual or a
    // menu it hosts as a PDF reads better in a file viewer.
    if (site == null || segments.isEmpty || isWebEmbedDocument(uri)) {
      return null;
    }
    final page = withoutWebEmbedTracking(
      uri.replace(scheme: 'https'),
      _shopTracking,
    ).removeFragment();
    final item = site.item.hasMatch('/${segments.join('/')}');
    return webEmbedPage(
      this,
      item ? site.kind : (_isStores ? 'Store page' : 'Page'),
      page.toString(),
      siteName: site.name,
      title: item ? _productTitle(page) : null,
      height: 720,
      accent: site.accent,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .split(RegExp(r'\s+[|]\s+'))
            .first
            .replaceFirst(
              RegExp(r'\s+[-–]\s+(?:Buy|Shop|Order)\b.*$'),
              '',
            )
            .trim(),
      );
}
