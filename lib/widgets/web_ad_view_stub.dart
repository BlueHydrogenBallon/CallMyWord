import 'package:flutter/material.dart';

/// Mobile stub — never actually rendered (BannerAdWidget guards with kIsWeb).
class WebAdView extends StatelessWidget {
  final String adSlot;
  final double height;

  const WebAdView({super.key, required this.adSlot, this.height = 90});

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
