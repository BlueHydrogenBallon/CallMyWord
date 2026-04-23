// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Renders a Google AdSense ad unit inside a Flutter web view.
/// The AdSense script must be loaded in web/index.html first.
///
/// TODO: Replace adSlot values with your real AdSense ad unit IDs.
class WebAdView extends StatefulWidget {
  final String adSlot;
  final double height;

  const WebAdView({super.key, required this.adSlot, this.height = 90});

  @override
  State<WebAdView> createState() => _WebAdViewState();
}

class _WebAdViewState extends State<WebAdView> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    // Unique ID per instance so multiple ads on the same page work correctly
    _viewId = 'adsense-${widget.adSlot}-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final container = html.DivElement()
        ..style.width = '100%'
        ..style.height = '${widget.height}px'
        ..style.overflow = 'hidden';

      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '${widget.height}px'
        ..setAttribute('data-ad-client', 'ca-pub-5595241150471151')
        ..setAttribute('data-ad-slot', widget.adSlot)
        ..setAttribute('data-ad-format', 'auto')
        ..setAttribute('data-full-width-responsive', 'true');

      container.append(ins);

      // Push after a short delay to ensure the element is in the DOM
      Future.delayed(const Duration(milliseconds: 150), () {
        try {
          js.context
              .callMethod('eval', ['(adsbygoogle = window.adsbygoogle || []).push({})']);
        } catch (e) {
          debugPrint('WebAdView: failed to push ad: $e');
        }
      });

      return container;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: HtmlElementView(viewType: _viewId),
    );
  }
}
