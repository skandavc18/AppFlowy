import 'package:flutter/foundation.dart';

/// Markup at least this long is parsed off the UI isolate.
///
/// Parsing a page costs the isolate that does it about a tenth of a
/// millisecond per kilobyte (a 488 KB page took 40ms in Release and 84ms in
/// Debug), so a fetched news page read on the UI isolate holds up several
/// frames while the page around it is loading or scrolling.
const backgroundMarkupLength = 16 * 1024;

/// Runs [parse] on [markup], off the UI isolate once [markup] is long enough
/// for parsing it to cost a frame.
///
/// [parse] may run in another isolate, so it must be a top-level or static
/// function, or a closure made in one that captures only values that can be
/// sent there. A closure made inside an instance method can carry `this`.
Future<R> parseMarkup<R>(String markup, R Function(String markup) parse) async {
  if (markup.length < backgroundMarkupLength) {
    return parse(markup);
  }
  return compute(parse, markup, debugLabel: 'parseMarkup');
}
