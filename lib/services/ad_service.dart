import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ─────────────────────────────────────────────
// Ad Unit IDs
// ─────────────────────────────────────────────

class AdIds {
  // kDebugMode is true with `flutter run`, false with `flutter build --release`
  static const bool _isTest = kDebugMode;

  // Google's official test IDs — safe to commit, never trigger policy violations
  static const _androidTestBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _androidTestInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _iosTestBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const _iosTestInterstitial = 'ca-app-pub-3940256099942544/4411468910';

  // TODO: Replace with real AdMob ad unit IDs before release
  static const _androidProdBanner = 'ca-app-pub-5595241150471151/9040045635';
  static const _androidProdInterstitial = 'ca-app-pub-5595241150471151/6261363699';
  static const _iosProdBanner = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const _iosProdInterstitial = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  static String get bannerId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _isTest ? _iosTestBanner : _iosProdBanner;
    }
    return _isTest ? _androidTestBanner : _androidProdBanner;
  }

  static String get interstitialId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _isTest ? _iosTestInterstitial : _iosProdInterstitial;
    }
    return _isTest ? _androidTestInterstitial : _androidProdInterstitial;
  }
}

// ─────────────────────────────────────────────
// Riverpod provider
// ─────────────────────────────────────────────

final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService();
  ref.onDispose(service.dispose);
  return service;
});

// ─────────────────────────────────────────────
// AdService
// ─────────────────────────────────────────────

class AdService {
  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  /// Call once after MobileAds.instance.initialize() to pre-load the first ad.
  void preloadInterstitial() {
    if (kIsWeb) return;
    _loadInterstitial();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdIds.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdService: interstitial failed to load: $error');
          _interstitialAd = null;
          _isInterstitialReady = false;
        },
      ),
    );
  }

  /// Shows the interstitial if ready, then calls [onComplete].
  /// [onComplete] is always called — even if the ad is unavailable or fails.
  Future<void> showInterstitialIfReady({required VoidCallback onComplete}) async {
    if (kIsWeb || !_isInterstitialReady || _interstitialAd == null) {
      onComplete();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        _loadInterstitial(); // pre-load next ad
        onComplete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdService: interstitial failed to show: $error');
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        _loadInterstitial();
        onComplete();
      },
    );

    await _interstitialAd!.show();
  }

  /// Creates a new BannerAd with [listener]. Returns null on web. Caller must dispose it.
  BannerAd? createBannerAd({BannerAdListener listener = const BannerAdListener()}) {
    if (kIsWeb) return null;
    return BannerAd(
      adUnitId: AdIds.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: listener,
    );
  }

  void dispose() {
    _interstitialAd?.dispose();
  }
}
