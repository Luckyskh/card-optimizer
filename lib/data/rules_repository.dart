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

    // Deliberately load() + decode rather than loadString().
    //
    // rootBundle.loadString hands UTF-8 decoding to a background isolate once
    // an asset passes 50 KB. rules.json crossed that when the card list grew,
    // and isolates do not run under the widget-test fake clock — so every
    // screen sat on its loading spinner forever and six tests began timing
    // out. Decoding here keeps it on the main isolate. The file is well under
    // a megabyte, so there is nothing to gain from offloading it anyway.
    final data = await rootBundle.load('assets/rules.json');
    final raw = utf8.decode(data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ));
    final parsed = Rules.fromJson(json.decode(raw) as Map<String, dynamic>);
    _cached = parsed;
    return parsed;
  }

  /// Parses rules from a string instead of the bundled asset.
  /// Tests use this so they do not need a running Flutter app.
  static Rules parse(String rawJson) =>
      Rules.fromJson(json.decode(rawJson) as Map<String, dynamic>);
}
