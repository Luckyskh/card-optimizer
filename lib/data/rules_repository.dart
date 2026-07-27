/// Loads `assets/rules.json` off the phone's own storage.
///
/// The file ships inside the app, so this works with no internet connection.
/// That is deliberate: the app must be fully usable offline, and the network
/// is only ever used for the optional "terms changed" alerts.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/rules.dart';

class RulesRepository {
  /// Kept after the first load so we parse the JSON once, not on every screen.
  Rules? _cached;

  Future<Rules> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/rules.json');
    final parsed = Rules.fromJson(json.decode(raw) as Map<String, dynamic>);
    _cached = parsed;
    return parsed;
  }

  /// Parses rules from a string instead of the bundled asset.
  /// Tests use this so they do not need a running Flutter app.
  static Rules parse(String rawJson) =>
      Rules.fromJson(json.decode(rawJson) as Map<String, dynamic>);
}
