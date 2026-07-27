import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService instance = AdService._internal();
  AdService._internal();

  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;

  // Official Google Mobile Ads Test Ad Unit IDs
  static String get bannerAdUnitId {
    if (kIsWeb) return 'ca-app-pub-3940256099942544/6300978111';
    if (!kIsWeb && Platform.isIOS) return 'ca-app-pub-3940256099942544/2934735716';
    return 'ca-app-pub-3940256099942544/6300978111';
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return 'ca-app-pub-3940256099942544/5224354917';
    if (!kIsWeb && Platform.isIOS) return 'ca-app-pub-3940256099942544/1712485313';
    return 'ca-app-pub-3940256099942544/5224354917';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return 'ca-app-pub-3940256099942544/1033173712';
    if (!kIsWeb && Platform.isIOS) return 'ca-app-pub-3940256099942544/4424216850';
    return 'ca-app-pub-3940256099942544/1033173712';
  }

  /// Initialize AdMob SDK
  Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      loadRewardedAd();
      loadInterstitialAd();
    } catch (e) {
      debugPrint('AdMob initialization error: $e');
    }
  }

  /// Create and load a Banner Ad instance after ensuring initialization
  Future<BannerAd?> createBannerAd({
    required Function(Ad) onAdLoaded,
    required Function(Ad, LoadAdError) onAdFailedToLoad,
  }) async {
    if (kIsWeb || bannerAdUnitId.isEmpty) return null;
    await initialize();

    final bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Banner Ad loaded successfully.');
          onAdLoaded(ad);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner Ad failed to load: $error');
          onAdFailedToLoad(ad, error);
        },
      ),
    );

    bannerAd.load();
    return bannerAd;
  }

  /// Preload Rewarded Ad for Free Hints
  void loadRewardedAd() {
    if (kIsWeb || _isRewardedAdLoading || rewardedAdUnitId.isEmpty) return;
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
          debugPrint('Rewarded Ad loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isRewardedAdLoading = false;
          debugPrint('Rewarded Ad failed to load: $error');
        },
      ),
    );
  }

  /// Show Rewarded Ad and execute reward callback upon completion
  Future<bool> showRewardedAdOrLoad({required Function(RewardItem reward) onUserEarnedReward}) async {
    if (kIsWeb) return false;

    if (_rewardedAd != null) {
      _showRewardedAdInstance(_rewardedAd!, onUserEarnedReward);
      _rewardedAd = null;
      loadRewardedAd(); // Preload next
      return true;
    }

    // Try loading on-demand if not preloaded yet
    final completer = Completer<bool>();
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _showRewardedAdInstance(ad, onUserEarnedReward);
          loadRewardedAd(); // Preload next
          completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad load failed: $error');
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  void _showRewardedAdInstance(RewardedAd ad, Function(RewardItem reward) onUserEarnedReward) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
      },
    );
    ad.show(onUserEarnedReward: (ad, reward) {
      onUserEarnedReward(reward);
    });
  }

  /// Preload Interstitial Ad
  void loadInterstitialAd() {
    if (kIsWeb || _isInterstitialAdLoading || interstitialAdUnitId.isEmpty) return;
    _isInterstitialAdLoading = true;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          debugPrint('Interstitial Ad loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isInterstitialAdLoading = false;
          debugPrint('Interstitial Ad failed to load: $error');
        },
      ),
    );
  }

  /// Custom Interstitial frequency rule evaluation:
  /// - Levels 1 - 5: No Interstitial Ad
  /// - Levels 6 - 15: Every 2 levels (Level 6, 8, 10, 12, 14)
  /// - Levels 16+: Every level (Level 16, 17, 18...)
  static bool shouldShowInterstitialOnLevelComplete(int completedLevel) {
    if (completedLevel < 6) {
      return false;
    } else if (completedLevel <= 15) {
      return completedLevel % 2 == 0;
    } else {
      return true;
    }
  }

  /// Show Interstitial Ad if available or load on-demand
  Future<bool> showInterstitialAdOrLoad({VoidCallback? onDismissed}) async {
    if (kIsWeb) {
      onDismissed?.call();
      return false;
    }

    if (_interstitialAd != null) {
      _showInterstitialAdInstance(_interstitialAd!, onDismissed);
      _interstitialAd = null;
      loadInterstitialAd(); // Preload next
      return true;
    }

    final completer = Completer<bool>();
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _showInterstitialAdInstance(ad, onDismissed);
          loadInterstitialAd();
          completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial ad load failed: $error');
          onDismissed?.call();
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  void _showInterstitialAdInstance(InterstitialAd ad, VoidCallback? onDismissed) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        onDismissed?.call();
      },
    );
    ad.show();
  }
}
