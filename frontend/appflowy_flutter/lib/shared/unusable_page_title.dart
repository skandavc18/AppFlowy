/// Whether [title] is what a site shows in place of a page: a bot check, a
/// refusal or an error. What came with it describes the check, not the page.
bool isStandInPageTitle(String? title) {
  final value = _plain(title);
  if (value.isEmpty) {
    return false;
  }
  if (_bareStandIn.hasMatch(value)) {
    return true;
  }
  // `Reddit - Please wait for verification`, `Attention Required! | Cloudflare`.
  for (final part in value.split(_separator)) {
    final segment = _plain(part);
    if (segment.isNotEmpty && _standIn.hasMatch(segment)) {
      return true;
    }
  }
  return false;
}

/// Whether [title] cannot name the page at [url]: it is missing, it is a
/// stand-in, or it is only the site's own name on a deeper link.
bool isUnusablePageTitle(String? title, {String? url}) {
  final value = _plain(title);
  return value.isEmpty ||
      isStandInPageTitle(value) ||
      (url != null && _namesOnlyTheSite(value, url));
}

String _plain(String? text) =>
    (text ?? '').trim().toLowerCase().replaceFirst(_trailingMarks, '');

final _separator = RegExp(r'\s[-–—]\s|[|•·]|:\s');
final _trailingMarks = RegExp(r'[\s.!?…]+$');

/// Whole title segments that only a bot check, a refusal or an error page
/// uses, so `Bill blocked by Senate` or `Just a moment in time` still name
/// their pages.
final _standIn = RegExp(
  '^(?:'
  'just a moment|attention required|one more step'
  '|please wait(?: for verification| while we verify(?: you)?)?'
  r'|checking (?:your browser|if the site connection is secure)\b.*'
  r"|verif(?:y|ying)(?: that)? you(?:'re| are)(?: a)? human\b.*"
  '|(?:human|bot) verification|are you a (?:robot|human)|robot check'
  '|(?:re|h)?captcha(?: challenge)?|security check(?:point)?'
  '|ddos-guard|ddos protection by .+|pardon our interruption'
  '|access denied|access to this page has been denied'
  '|(?:sorry, )?you have been blocked'
  r'|request (?:blocked|rejected|unsuccessful)\b.*'
  '|too many requests|service (?:temporarily )?unavailable'
  '|internal server error|bad gateway|gateway timeout'
  '|(?:page|post|article|content) not found|page unavailable'
  r'|error [45]\d\d|[45]\d\d error'
  r'|[45]\d\d(?: (?:forbidden|unauthori[sz]ed|not found|bad request'
  '|internal server error|bad gateway|service unavailable|gateway timeout'
  '|too many requests))?'
  '|enable javascript(?: and cookies)?(?: to continue)?'
  '|javascript is (?:disabled|required)'
  r')$',
);

/// Words that are a stand-in only as the entire title: `Security · GitHub`
/// and `Error - Wikipedia` are real pages.
final _bareStandIn = RegExp(
  '^(?:error|blocked|forbidden|unauthori[sz]ed|not found|authenticating'
  r'|loading|redirecting)$',
);

/// `Reddit`, `Instagram` or `wsj.com` for a post, a reel or an article: what
/// a site calls every page it will not show a visitor. Its home page may
/// rightly carry the name.
bool _namesOnlyTheSite(String title, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.pathSegments.every((segment) => segment.isEmpty) &&
          uri.query.isEmpty)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final name = title.replaceAll(RegExp(r'[\s.]+'), '');
  if (name.isEmpty) {
    return false;
  }
  if (name == host.replaceAll('.', '') ||
      name == host.replaceFirst(RegExp(r'^www\d?\.'), '').replaceAll('.', '')) {
    return true;
  }
  final labels = host.split('.');
  return labels.take(labels.length - 1).contains(name);
}
