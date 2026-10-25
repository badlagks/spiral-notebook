import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one-time purchase that unlocks more notebooks and covers. Every
/// feature works in the first notebook without it.
abstract class Purchases {
  /// Whether Pro is unlocked on this device.
  ValueListenable<bool> get isPro;

  Future<void> init();

  /// The price in the store's own words, such as "€4.99", or null when the
  /// store can't be reached.
  Future<String?> price();

  /// Opens the store's payment sheet. The result arrives through [isPro].
  /// Returns false if the store couldn't be reached.
  Future<bool> buy();

  /// Asks the store for a purchase made before, on this or another device.
  Future<bool> restore();
}

/// The product set up in Google Play Console and App Store Connect.
const proProductId = 'pro_unlock';

class _StorePurchases implements Purchases {
  static const _key = 'pro.unlocked';
  final _isPro = ValueNotifier(false);
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  @override
  ValueListenable<bool> get isPro => _isPro;

  // The web preview has no store, so everything is open there.
  bool get _hasStore => !kIsWeb;

  @override
  Future<void> init() async {
    if (!_hasStore) {
      _isPro.value = true;
      return;
    }
    try {
      // Remembered, so Pro works with no connection.
      final prefs = await SharedPreferences.getInstance();
      _isPro.value = prefs.getBool(_key) ?? false;
      _sub ??= InAppPurchase.instance.purchaseStream.listen(_onPurchases, onError: (Object e) {
        debugPrint('Store error: $e');
      });
    } catch (e) {
      debugPrint('Could not start purchases: $e');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != proProductId) continue;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        _isPro.value = true;
        try {
          await (await SharedPreferences.getInstance()).setBool(_key, true);
        } catch (_) {}
      }
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
    }
  }

  Future<ProductDetails?> _load() async {
    if (_product != null || !_hasStore) return _product;
    try {
      if (!await InAppPurchase.instance.isAvailable().timeout(const Duration(seconds: 5))) return null;
      final r = await InAppPurchase.instance.queryProductDetails({proProductId}).timeout(const Duration(seconds: 8));
      return _product = r.productDetails.firstOrNull;
    } catch (e) {
      debugPrint('Could not reach the store: $e');
      return null;
    }
  }

  @override
  Future<String?> price() async => (await _load())?.price;

  @override
  Future<bool> buy() async {
    final product = await _load();
    if (product == null) return false;
    return InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  @override
  Future<bool> restore() async {
    if (!_hasStore) return true;
    try {
      if (!await InAppPurchase.instance.isAvailable().timeout(const Duration(seconds: 5))) return false;
      await InAppPurchase.instance.restorePurchases();
      return true;
    } catch (e) {
      debugPrint('Could not restore: $e');
      return false;
    }
  }
}

/// Stands in for the store in tests.
class FakePurchases implements Purchases {
  FakePurchases({bool pro = false}) : _isPro = ValueNotifier(pro);
  final ValueNotifier<bool> _isPro;
  bool storeReachable = true;
  int bought = 0;

  @override
  ValueListenable<bool> get isPro => _isPro;

  @override
  Future<void> init() async {}

  @override
  Future<String?> price() async => storeReachable ? '€4.99' : null;

  @override
  Future<bool> buy() async {
    if (!storeReachable) return false;
    bought++;
    _isPro.value = true;
    return true;
  }

  @override
  Future<bool> restore() async => storeReachable;
}

Purchases purchases = _StorePurchases();
