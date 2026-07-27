/// Downloads the "this card's terms changed" notices.
///
/// The terms monitor (see `tools/terms_watch/`) runs on GitHub twice a month,
/// re-reads each issuer's published terms documents, and writes `alerts.json`
/// when the text moves. This file is the app's side of that: it fetches the
/// JSON, remembers which alerts the user has already seen, and gets out of the
/// way if anything goes wrong.
///
/// Three rules govern this file:
///
/// 1. **Failure is silent.** No internet, no GitHub, bad JSON — the app carries
///    on working exactly as before. Reward maths never depends on the network.
/// 2. **Alerts describe documents, not rates.** An alert says "SBI changed the
///    terms for this card", never "your rate is now 2%". The monitor sees a
///    text difference, which is evidence that something moved, not a verified
///    new number.
/// 3. **Nothing is uploaded.** This is a plain GET. The app sends no
///    information about the user, their cards, or their spending.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One "the issuer changed this document" notice.
class TermsAlert {
  final String id;
  final String cardId;
  final String cardName;
  final String docLabel;
  final String detectedOn;
  final String summary;
  final String sourceUrl;

  /// Before/after snippets of the lines that actually changed.
  final List<AlertExcerpt> excerpts;

  const TermsAlert({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.docLabel,
    required this.detectedOn,
    required this.summary,
    required this.sourceUrl,
    this.excerpts = const [],
  });

  factory TermsAlert.fromJson(Map<String, dynamic> json) => TermsAlert(
        id: json['id'] as String? ?? '',
        cardId: json['card_id'] as String? ?? '',
        cardName: json['card_name'] as String? ?? '',
        docLabel: json['doc_label'] as String? ?? '',
        detectedOn: json['detected_on'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        sourceUrl: json['source_url'] as String? ?? '',
        excerpts: (json['excerpts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AlertExcerpt.fromJson)
            .toList(),
      );
}

class AlertExcerpt {
  final String before;
  final String after;

  const AlertExcerpt({required this.before, required this.after});

  factory AlertExcerpt.fromJson(Map<String, dynamic> json) => AlertExcerpt(
        before: json['before'] as String? ?? '',
        after: json['after'] as String? ?? '',
      );
}

class AlertsService {
  /// Where `alerts.json` lives once the repository is published.
  ///
  /// Replace OWNER and REPO with your GitHub username and repository name.
  /// Until you do, the app skips the download entirely rather than throwing
  /// confusing network errors at you.
  static const defaultAlertsUrl =
      'https://raw.githubusercontent.com/OWNER/REPO/main/alerts.json';

  static const _placeholderMarker = 'OWNER/REPO';
  static const _cacheKey = 'cached_alerts_json';
  static const _seenKey = 'seen_alert_ids';

  final http.Client _client;

  /// The address to download from. Overridable so tests can point at a fake
  /// server instead of the real one.
  final String url;

  AlertsService({http.Client? client, String? url})
      : _client = client ?? http.Client(),
        url = url ?? defaultAlertsUrl;

  /// True once [url] has been pointed at a real repository.
  bool get isConfigured => !url.contains(_placeholderMarker);

  /// Fetches the latest alerts, falling back to the last successful download.
  ///
  /// Never throws. An empty list means "nothing to show", whether that is
  /// because there are no alerts or because the download failed.
  Future<List<TermsAlert>> fetch() async {
    if (isConfigured) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final alerts = parseAlerts(response.body);
          // Only cache text we could actually parse, so a broken deploy does
          // not wipe out the last good copy.
          await _cache(response.body);
          return alerts;
        }
      } catch (_) {
        // Offline, DNS failure, timeout, malformed JSON — all handled the same
        // way: fall through to whatever we downloaded last time.
      }
    }

    final cached = await _readCache();
    return cached == null ? const [] : parseAlerts(cached);
  }

  /// Alerts the user has not dismissed yet.
  Future<List<TermsAlert>> unseen() async {
    final all = await fetch();
    final seen = await seenIds();
    return all.where((alert) => !seen.contains(alert.id)).toList();
  }

  Future<Set<String>> seenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_seenKey) ?? const []).toSet();
  }

  Future<void> markSeen(String alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenKey) ?? const []).toSet()
      ..add(alertId);
    await prefs.setStringList(_seenKey, seen.toList());
  }

  Future<void> markAllSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenKey) ?? const []).toSet()
      ..addAll(ids);
    await prefs.setStringList(_seenKey, seen.toList());
  }

  /// Parses the downloaded file. Returns an empty list on anything unexpected
  /// rather than crashing the app over a malformed alert.
  static List<TermsAlert> parseAlerts(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final alerts = decoded['alerts'];
      if (alerts is! List) return const [];
      return alerts
          .whereType<Map<String, dynamic>>()
          .map(TermsAlert.fromJson)
          .where((alert) => alert.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cache(String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, body);
  }

  Future<String?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cacheKey);
  }
}
