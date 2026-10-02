import 'package:flutter/material.dart';

/// A news site the news embed knows by name.
@immutable
class WebEmbedPublisher {
  const WebEmbedPublisher(this.name, this.domains, [this.accent]);

  /// The masthead, shown on the card's badge.
  final String name;

  /// The domains it publishes under. A more specific one wins, so
  /// `timesofindia.indiatimes.com` is The Times of India while
  /// `economictimes.indiatimes.com` is The Economic Times.
  final List<String> domains;

  /// The masthead's own colour, where it has a distinctive one.
  final Color? accent;
}

/// The publisher [host] belongs to, or null for a site that is not news.
WebEmbedPublisher? webEmbedPublisherFor(String host) {
  var candidate = host.toLowerCase();
  while (true) {
    final found = _byDomain[candidate];
    if (found != null) {
      return found;
    }
    final dot = candidate.indexOf('.');
    if (dot < 0) {
      return null;
    }
    candidate = candidate.substring(dot + 1);
  }
}

final Map<String, WebEmbedPublisher> _byDomain = {
  for (final publisher in webEmbedPublishers)
    for (final domain in publisher.domains) domain: publisher,
};

/// Popular news sites around the world and across India, in English and in
/// the languages India reads its news in.
const webEmbedPublishers = <WebEmbedPublisher>[
  // Global.
  WebEmbedPublisher('BBC', ['bbc.com', 'bbc.co.uk'], Color(0xFFBB1919)),
  WebEmbedPublisher('CNN', ['cnn.com'], Color(0xFFCC0000)),
  WebEmbedPublisher(
    'The New York Times',
    ['nytimes.com'],
    Color(0xFF326891),
  ),
  WebEmbedPublisher(
    'The Guardian',
    ['theguardian.com', 'guardian.co.uk'],
    Color(0xFF052962),
  ),
  WebEmbedPublisher('The Washington Post', ['washingtonpost.com']),
  WebEmbedPublisher('Reuters', ['reuters.com'], Color(0xFFFF8000)),
  WebEmbedPublisher('AP News', ['apnews.com'], Color(0xFFE4002B)),
  WebEmbedPublisher('Bloomberg', ['bloomberg.com']),
  WebEmbedPublisher('The Wall Street Journal', ['wsj.com']),
  WebEmbedPublisher('Financial Times', ['ft.com'], Color(0xFF990F3D)),
  WebEmbedPublisher('The Economist', ['economist.com'], Color(0xFFE3120B)),
  WebEmbedPublisher('Al Jazeera', ['aljazeera.com'], Color(0xFFFA9000)),
  WebEmbedPublisher('NPR', ['npr.org'], Color(0xFFD62021)),
  WebEmbedPublisher('Fox News', ['foxnews.com'], Color(0xFF003366)),
  WebEmbedPublisher('NBC News', ['nbcnews.com'], Color(0xFF0089D0)),
  WebEmbedPublisher('CBS News', ['cbsnews.com']),
  WebEmbedPublisher('ABC News', ['abcnews.go.com']),
  WebEmbedPublisher('ABC News (Australia)', ['abc.net.au']),
  WebEmbedPublisher('USA Today', ['usatoday.com'], Color(0xFF009BFF)),
  WebEmbedPublisher('Politico', ['politico.com', 'politico.eu']),
  WebEmbedPublisher('Axios', ['axios.com']),
  WebEmbedPublisher('The Atlantic', ['theatlantic.com']),
  WebEmbedPublisher('The New Yorker', ['newyorker.com']),
  WebEmbedPublisher('TIME', ['time.com'], Color(0xFFE90606)),
  WebEmbedPublisher('Newsweek', ['newsweek.com'], Color(0xFFED1C24)),
  WebEmbedPublisher('Forbes', ['forbes.com', 'forbesindia.com']),
  WebEmbedPublisher('Fortune', ['fortune.com']),
  WebEmbedPublisher(
    'Business Insider',
    ['businessinsider.com', 'insider.com', 'businessinsider.in'],
  ),
  WebEmbedPublisher('CNBC', ['cnbc.com'], Color(0xFF005594)),
  WebEmbedPublisher('MarketWatch', ['marketwatch.com']),
  WebEmbedPublisher('Yahoo News', ['news.yahoo.com']),
  WebEmbedPublisher('Yahoo Finance', ['finance.yahoo.com']),
  WebEmbedPublisher('Los Angeles Times', ['latimes.com']),
  WebEmbedPublisher('The Hill', ['thehill.com']),
  WebEmbedPublisher('Vox', ['vox.com']),
  WebEmbedPublisher('HuffPost', ['huffpost.com'], Color(0xFF0DBE98)),
  WebEmbedPublisher('Sky News', ['news.sky.com'], Color(0xFFC8102E)),
  WebEmbedPublisher('The Independent', ['independent.co.uk']),
  WebEmbedPublisher('The Telegraph', ['telegraph.co.uk']),
  WebEmbedPublisher('Daily Mail', ['dailymail.co.uk']),
  WebEmbedPublisher('The Times', ['thetimes.co.uk', 'thetimes.com']),
  WebEmbedPublisher('DW', ['dw.com'], Color(0xFF05B2FC)),
  WebEmbedPublisher('France 24', ['france24.com']),
  WebEmbedPublisher('Euronews', ['euronews.com']),
  WebEmbedPublisher('Le Monde', ['lemonde.fr']),
  WebEmbedPublisher('Der Spiegel', ['spiegel.de'], Color(0xFFE64415)),
  WebEmbedPublisher('El País', ['elpais.com']),
  WebEmbedPublisher('South China Morning Post', ['scmp.com']),
  WebEmbedPublisher('The Japan Times', ['japantimes.co.jp']),
  WebEmbedPublisher('The Straits Times', ['straitstimes.com']),
  WebEmbedPublisher('CNA', ['channelnewsasia.com']),
  WebEmbedPublisher('Gulf News', ['gulfnews.com']),
  WebEmbedPublisher('Khaleej Times', ['khaleejtimes.com']),
  WebEmbedPublisher(
    'The Sydney Morning Herald',
    ['smh.com.au'],
    Color(0xFF096DD2),
  ),
  WebEmbedPublisher('CBC News', ['cbc.ca'], Color(0xFFD80000)),
  WebEmbedPublisher('The Globe and Mail', ['theglobeandmail.com']),
  WebEmbedPublisher('The Verge', ['theverge.com'], Color(0xFF5200FF)),
  WebEmbedPublisher('WIRED', ['wired.com']),
  WebEmbedPublisher('TechCrunch', ['techcrunch.com'], Color(0xFF0A9E01)),
  WebEmbedPublisher('Ars Technica', ['arstechnica.com'], Color(0xFFFF4E00)),
  WebEmbedPublisher('Engadget', ['engadget.com']),
  WebEmbedPublisher('Mashable', ['mashable.com']),
  WebEmbedPublisher('ESPN', ['espn.com', 'espn.in'], Color(0xFFCC0000)),
  WebEmbedPublisher(
    'ESPNcricinfo',
    ['espncricinfo.com'],
    Color(0xFF03A9F4),
  ),
  WebEmbedPublisher('Cricbuzz', ['cricbuzz.com'], Color(0xFF009270)),
  // South Asia.
  WebEmbedPublisher('Dawn', ['dawn.com']),
  WebEmbedPublisher('Geo News', ['geo.tv']),
  WebEmbedPublisher('The Express Tribune', ['tribune.com.pk']),
  WebEmbedPublisher('The Daily Star', ['thedailystar.net']),
  WebEmbedPublisher('Prothom Alo', ['prothomalo.com']),
  WebEmbedPublisher('The Kathmandu Post', ['kathmandupost.com']),
  // India, in English.
  WebEmbedPublisher(
    'The Times of India',
    ['timesofindia.indiatimes.com', 'timesofindia.com'],
    Color(0xFFE21B22),
  ),
  WebEmbedPublisher(
    'The Economic Times',
    ['economictimes.indiatimes.com', 'economictimes.com'],
    Color(0xFFB71C1C),
  ),
  WebEmbedPublisher(
    'Hindustan Times',
    ['hindustantimes.com'],
    Color(0xFF00B1CD),
  ),
  WebEmbedPublisher('Mint', ['livemint.com'], Color(0xFFF99D1C)),
  WebEmbedPublisher('The Hindu', ['thehindu.com']),
  WebEmbedPublisher('Frontline', ['frontline.thehindu.com']),
  WebEmbedPublisher('Sportstar', ['sportstar.thehindu.com']),
  WebEmbedPublisher(
    'The Hindu BusinessLine',
    ['thehindubusinessline.com'],
  ),
  WebEmbedPublisher(
    'The Indian Express',
    ['indianexpress.com'],
    Color(0xFF1E5AA5),
  ),
  WebEmbedPublisher('The New Indian Express', ['newindianexpress.com']),
  WebEmbedPublisher('The Financial Express', ['financialexpress.com']),
  WebEmbedPublisher(
    'NDTV',
    ['ndtv.com', 'ndtv.in', 'ndtvprofit.com'],
    Color(0xFFE62020),
  ),
  WebEmbedPublisher('Gadgets 360', ['gadgets360.com']),
  WebEmbedPublisher('India Today', ['indiatoday.in'], Color(0xFFD71920)),
  WebEmbedPublisher('Business Today', ['businesstoday.in']),
  WebEmbedPublisher('News18', ['news18.com'], Color(0xFFE1261C)),
  WebEmbedPublisher('Moneycontrol', ['moneycontrol.com']),
  WebEmbedPublisher('Business Standard', ['business-standard.com']),
  WebEmbedPublisher('Zee Business', ['zeebiz.com']),
  WebEmbedPublisher('Deccan Herald', ['deccanherald.com']),
  WebEmbedPublisher('Deccan Chronicle', ['deccanchronicle.com']),
  WebEmbedPublisher('The Tribune', ['tribuneindia.com']),
  WebEmbedPublisher('The Telegraph India', ['telegraphindia.com']),
  WebEmbedPublisher('The Statesman', ['thestatesman.com']),
  WebEmbedPublisher('Outlook', ['outlookindia.com']),
  WebEmbedPublisher('The Wire', ['thewire.in']),
  WebEmbedPublisher('Scroll', ['scroll.in']),
  WebEmbedPublisher('ThePrint', ['theprint.in']),
  WebEmbedPublisher('The Quint', ['thequint.com']),
  WebEmbedPublisher('Swarajya', ['swarajyamag.com']),
  WebEmbedPublisher('OpIndia', ['opindia.com']),
  WebEmbedPublisher('Firstpost', ['firstpost.com']),
  WebEmbedPublisher('WION', ['wionews.com']),
  WebEmbedPublisher('DNA', ['dnaindia.com']),
  WebEmbedPublisher('Times Now', ['timesnownews.com']),
  WebEmbedPublisher('Republic', ['republicworld.com']),
  WebEmbedPublisher('Mid-day', ['mid-day.com']),
  WebEmbedPublisher('Free Press Journal', ['freepressjournal.in']),
  WebEmbedPublisher('PTI', ['ptinews.com']),
  WebEmbedPublisher('ANI', ['aninews.in']),
  WebEmbedPublisher('Inshorts', ['inshorts.com']),
  // India, in its own languages.
  WebEmbedPublisher(
    'Navbharat Times',
    ['navbharattimes.indiatimes.com'],
  ),
  WebEmbedPublisher('Maharashtra Times', ['maharashtratimes.com']),
  WebEmbedPublisher('Live Hindustan', ['livehindustan.com']),
  WebEmbedPublisher('Aaj Tak', ['aajtak.in'], Color(0xFFED1C24)),
  WebEmbedPublisher('Zee News', ['zeenews.india.com']),
  WebEmbedPublisher('India TV', ['indiatvnews.com']),
  WebEmbedPublisher('ABP Live', ['abplive.com']),
  WebEmbedPublisher('Dainik Bhaskar', ['bhaskar.com']),
  WebEmbedPublisher('Divya Bhaskar', ['divyabhaskar.co.in']),
  WebEmbedPublisher('Dainik Jagran', ['jagran.com']),
  WebEmbedPublisher('Amar Ujala', ['amarujala.com']),
  WebEmbedPublisher('Jansatta', ['jansatta.com']),
  WebEmbedPublisher('Lokmat', ['lokmat.com']),
  WebEmbedPublisher('Loksatta', ['loksatta.com']),
  WebEmbedPublisher('Sakal', ['esakal.com']),
  WebEmbedPublisher('Gujarat Samachar', ['gujaratsamachar.com']),
  WebEmbedPublisher(
    'Malayala Manorama',
    ['manoramaonline.com', 'onmanorama.com'],
  ),
  WebEmbedPublisher('Mathrubhumi', ['mathrubhumi.com']),
  WebEmbedPublisher('Eenadu', ['eenadu.net']),
  WebEmbedPublisher('Sakshi', ['sakshi.com']),
  WebEmbedPublisher('Dinamalar', ['dinamalar.com']),
  WebEmbedPublisher('Daily Thanthi', ['dailythanthi.com']),
  WebEmbedPublisher('Prajavani', ['prajavani.net']),
  WebEmbedPublisher('Vijay Karnataka', ['vijaykarnataka.com']),
  WebEmbedPublisher('Kannada Prabha', ['kannadaprabha.in']),
  WebEmbedPublisher('Anandabazar Patrika', ['anandabazar.com']),
  WebEmbedPublisher('Sangbad Pratidin', ['sangbadpratidin.in']),
];
