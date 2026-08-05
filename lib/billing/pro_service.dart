import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TERRAX Pro subscription: purchase, restore, and entitlement state.
///
/// No backend exists (and none is wanted), so entitlement is decided from
/// StoreKit's own purchase stream and cached locally. The cache is a
/// convenience for offline launches, never the source of truth: every launch
/// asks StoreKit again via [restore].
class ProService {
  ProService(this._prefs, {InAppPurchase? iap}) : _injectedIap = iap;

  /// Must match the subscription product created in App Store Connect.
  static const yearlyProductId = 'com.terraxtech.app.pro.yearly';

  static const _prefsKey = 'terrax_pro_active';

  final SharedPreferences _prefs;

  /// Resolved lazily: touching `InAppPurchase.instance` opens a billing
  /// connection, which must not happen just because entitlement was read
  /// (and blows up in unit tests, where no store exists).
  final InAppPurchase? _injectedIap;
  InAppPurchase? _resolvedIap;
  InAppPurchase get _iap =>
      _injectedIap ?? (_resolvedIap ??= InAppPurchase.instance);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _controller = StreamController<bool>.broadcast();

  ProductDetails? _product;

  /// The store's localized price (e.g. "₱59.00"), null until products load.
  String? get price => _product?.price;

  /// Whether Pro is currently unlocked.
  bool get isPro => _prefs.getBool(_prefsKey) ?? false;

  /// Entitlement changes. Emits the current value on listen.
  Stream<bool> get entitlement async* {
    yield isPro;
    yield* _controller.stream;
  }

  /// True when the store is reachable and the product was found. When false
  /// the paywall must say so rather than showing a dead Subscribe button.
  bool get isAvailable => _product != null;

  Future<void> init() async {
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    if (!await _iap.isAvailable()) return;
    final response = await _iap.queryProductDetails({yearlyProductId});
    if (response.productDetails.isNotEmpty) {
      _product = response.productDetails.first;
    }
    // Ask the store what this Apple ID already owns, so a reinstall or a
    // second device unlocks without the user hunting for Restore.
    await _iap.restorePurchases();
  }

  /// Starts the subscribe flow. Returns false when the product is unavailable.
  Future<bool> buy() async {
    final product = _product;
    if (product == null) return false;
    return _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product));
  }

  /// Apple requires an explicit Restore Purchases control.
  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == yearlyProductId) await _setPro(true);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          break;
      }
      // Every delivered purchase must be completed or StoreKit replays it.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _setPro(bool value) async {
    if (isPro == value) return;
    await _prefs.setBool(_prefsKey, value);
    if (!_controller.isClosed) _controller.add(value);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
