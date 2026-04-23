library;

// Conditional export: uses HtmlElementView + AdSense on web,
// returns a sized placeholder on mobile (never rendered there).
export 'web_ad_view_stub.dart' if (dart.library.html) 'web_ad_view_web.dart';
