import 'dart:async';

import 'package:flutter/material.dart';

import 'web_ad_view.dart';

/// Full-screen interstitial overlay for web.
/// Shows an AdSense display ad with a countdown close button.
class WebInterstitialOverlay extends StatefulWidget {
  final VoidCallback onClose;

  // TODO: Replace with your real AdSense interstitial/display ad unit ID
  static const String adSlot = '2550103998';

  const WebInterstitialOverlay({super.key, required this.onClose});

  @override
  State<WebInterstitialOverlay> createState() => _WebInterstitialOverlayState();
}

class _WebInterstitialOverlayState extends State<WebInterstitialOverlay> {
  static const int _countdownSeconds = 5;
  int _secondsLeft = _countdownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: label + close/countdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Advertisement',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  _secondsLeft > 0
                      ? Text(
                          'Close in $_secondsLeft...',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        )
                      : TextButton.icon(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, color: Colors.white, size: 16),
                          label: const Text('Close', style: TextStyle(color: Colors.white)),
                        ),
                ],
              ),
            ),

            // Ad content
            const Expanded(
              child: Center(
                child: WebAdView(
                  adSlot: WebInterstitialOverlay.adSlot,
                  height: 250,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
