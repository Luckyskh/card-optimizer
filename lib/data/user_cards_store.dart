/// Remembers which cards the user owns, on the phone itself.
///
/// `shared_preferences` is a small key-value store built into the phone. There
/// is no server and no account, so this data never leaves the device.
///
/// Worth repeating: we store card *names* only. No card numbers, no expiry
/// dates, no CVVs, nothing that could identify a real account.
library;

import 'package:shared_preferences/shared_preferences.dart';

class UserCardsStore {
  static const _cardIdsKey = 'owned_card_ids';
  static const _primeKey = 'amazon_prime_member';
  static const _cycleSpendPrefix = 'cycle_spend_';

  /// The ids of the cards the user has added, e.g. `{"axis-ace"}`.
  Future<Set<String>> ownedCardIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_cardIdsKey) ?? const []).toSet();
  }

  Future<void> setOwnedCardIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cardIdsKey, ids.toList()..sort());
  }

  Future<void> addCard(String id) async {
    final current = await ownedCardIds();
    current.add(id);
    await setOwnedCardIds(current);
  }

  Future<void> removeCard(String id) async {
    final current = await ownedCardIds();
    current.remove(id);
    await setOwnedCardIds(current);
    await setCycleSpend(id, 0);
  }

  /// Amazon Pay ICICI pays a different rate to Prime members, so the app has
  /// to ask. This is the only personal detail the reward maths needs.
  Future<bool> isAmazonPrimeMember() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_primeKey) ?? false;
  }

  Future<void> setAmazonPrimeMember(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_primeKey, value);
  }

  /// How much the user has already spent on a card this statement cycle.
  ///
  /// Optional, and zero by default. It only changes the answer for cards whose
  /// rate improves with cycle spend — IDFC FIRST Select today — but for those
  /// it changes it a lot, so the app offers a field for it.
  Future<double> cycleSpend(String cardId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_cycleSpendPrefix$cardId') ?? 0;
  }

  Future<void> setCycleSpend(String cardId, double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_cycleSpendPrefix$cardId', amount);
  }

  Future<Map<String, double>> allCycleSpends(Set<String> cardIds) async {
    final result = <String, double>{};
    for (final id in cardIds) {
      result[id] = await cycleSpend(id);
    }
    return result;
  }
}
