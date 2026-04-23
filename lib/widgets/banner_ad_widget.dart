import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import 'web_ad_view.dart';

/// A self-contained banner ad widget.
/// On web: renders a Google AdSense banner via HtmlElementView.
/// On mobile: renders a Google AdMob banner.
class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // Delay banner load until after the first frame so Flutter layout is
    // settled before the native PlatformView is created. Loading during
    // initState can cause the native AdView to briefly render at full-screen
    // size and intercept all touch events.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBanner();
    });
  }

  void _loadBanner() {
    final adService = ref.read(adServiceProvider);
    _bannerAd = adService.createBannerAd(
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAdWidget: failed to load: $error');
          ad.dispose();
          if (mounted) setState(() => _isAdLoaded = false);
        },
      ),
    );
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const WebAdView(adSlot: '4768743652', height: 90);
    }

    if (!_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final adWidth = _bannerAd!.size.width.toDouble();
    final adHeight = _bannerAd!.size.height.toDouble();
    return ClipRect(
      child: SizedBox(
        width: adWidth,
        height: adHeight,
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
