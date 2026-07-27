/// Reads and writes the monitor's own files: the snapshots it compares
/// against, and the `alerts.json` the app downloads.
library;

import 'dart:convert';
import 'dart:io';

import 'diff.dart';

/// What happened to one document on one run.
enum DocStatus {
  /// The text is identical to last time. The overwhelmingly common case.
  unchanged,

  /// The text moved. This is what produces an alert.
  changed,

  /// First time we have seen this document; the snapshot is now the baseline.
  baseline,

  /// Could not download it. Deliberately never produces a "changed" alert.
  fetchFailed,

  /// Downloaded but could not read the text out of it.
  extractFailed,

  /// No URL in sources.json yet.
  notConfigured,
}

/// One line of the run's results.
class DocOutcome {
  final String docId;
  final String label;
  final List<String> cardIds;
  final String? url;
  final DocStatus status;
  final String? detail;
  final DiffResult? diff;

  /// How many runs in a row this document has failed, including this one.
  final int consecutiveFailures;

  /// Set in sources.json for documents the issuer refuses to serve to any
  /// automated client. See [isStale] for why this matters.
  final bool knownBlocked;

  const DocOutcome({
    required this.docId,
    required this.label,
    required this.cardIds,
    required this.url,
    required this.status,
    this.detail,
    this.diff,
    this.consecutiveFailures = 0,
    this.knownBlocked = false,
  });

  bool get failed =>
      status == DocStatus.fetchFailed || status == DocStatus.extractFailed;

  /// A document that has failed enough times to be worth chasing. Three runs
  /// is roughly six weeks of silence, which is long enough that the rates in
  /// the app could have drifted without anyone noticing.
  ///
  /// Documents marked `known_blocked` are excluded. HDFC refuses its own PDF
  /// files to every client we have, so counting those as stale would leave the
  /// scheduled run permanently red and train you to ignore it — which would
  /// hide the failures that *are* worth reading.
  bool get isStale => consecutiveFailures >= 3 && !knownBlocked;

  /// A blocked document that unexpectedly worked. Worth knowing: the flag in
  /// sources.json can come off and the document starts being monitored again.
  bool get unexpectedlyReachable =>
      knownBlocked &&
      (status == DocStatus.unchanged ||
          status == DocStatus.changed ||
          status == DocStatus.baseline);
}

/// The record kept for each document between runs.
class SnapshotRecord {
  final String sha256;
  final String lastCheckedUtc;
  final String? lastChangedUtc;
  final int consecutiveFailures;
  final String? lastError;

  const SnapshotRecord({
    required this.sha256,
    required this.lastCheckedUtc,
    this.lastChangedUtc,
    this.consecutiveFailures = 0,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'sha256': sha256,
        'last_checked_utc': lastCheckedUtc,
        if (lastChangedUtc != null) 'last_changed_utc': lastChangedUtc,
        'consecutive_failures': consecutiveFailures,
        if (lastError != null) 'last_error': lastError,
      };

  factory SnapshotRecord.fromJson(Map<String, dynamic> json) => SnapshotRecord(
        sha256: json['sha256'] as String? ?? '',
        lastCheckedUtc: json['last_checked_utc'] as String? ?? '',
        lastChangedUtc: json['last_changed_utc'] as String?,
        consecutiveFailures:
            (json['consecutive_failures'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
      );
}

/// Reads and writes everything under `snapshots/`.
class SnapshotStore {
  final Directory directory;

  SnapshotStore(String path) : directory = Directory(path);

  File get _indexFile => File('${directory.path}/index.json');

  File snapshotFile(String docId) => File('${directory.path}/$docId.txt');

  Map<String, SnapshotRecord> readIndex() {
    if (!_indexFile.existsSync()) return {};
    try {
      final decoded =
          json.decode(_indexFile.readAsStringSync()) as Map<String, dynamic>;
      final documents = decoded['documents'] as Map<String, dynamic>? ?? {};
      return documents.map(
        (key, value) => MapEntry(
          key,
          SnapshotRecord.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      // A corrupted index means we lose the baselines and re-establish them,
      // which is safe: the next run reports "baseline" rather than "changed".
      return {};
    }
  }

  void writeIndex(Map<String, SnapshotRecord> records) {
    directory.createSync(recursive: true);
    final sorted = Map.fromEntries(
      records.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    _indexFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'documents': sorted.map((key, value) => MapEntry(key, value.toJson())),
      }),
    );
  }

  String? readSnapshot(String docId) {
    final file = snapshotFile(docId);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  void writeSnapshot(String docId, String text) {
    directory.createSync(recursive: true);
    snapshotFile(docId).writeAsStringSync(text);
  }
}

/// Builds `alerts.json`, the file the app downloads.
///
/// Deliberately conservative in what it claims. An alert says the issuer's
/// document changed and shows the lines involved. It never says what the new
/// rate is, because a text difference is evidence that something moved, not a
/// verified new number. Someone has to read the document and update
/// `assets/rules.json` by hand.
String buildAlertsJson({
  required List<DocOutcome> outcomes,
  required int rulesVersion,
  required Map<String, String> cardNames,
  required DateTime now,
}) {
  final alerts = <Map<String, dynamic>>[];
  final date = _isoDate(now);

  for (final outcome in outcomes) {
    if (outcome.status != DocStatus.changed) continue;
    final diff = outcome.diff;
    if (diff == null) continue;

    // Prefer the material lines; if a document changed only in ways we do not
    // consider material, still raise it but show the general changes.
    final excerpts =
        (diff.material.isNotEmpty ? diff.material : diff.all).take(5).toList();

    for (final cardId in outcome.cardIds) {
      alerts.add({
        'id': '$date-${outcome.docId}-$cardId',
        'card_id': cardId,
        'card_name': cardNames[cardId] ?? cardId,
        'doc_label': outcome.label,
        'detected_on': date,
        'summary': diff.summary,
        'source_url': outcome.url ?? '',
        'excerpts': [
          for (final entry in excerpts)
            {
              'before': _trim(entry.before),
              'after': _trim(entry.after),
            }
        ],
      });
    }
  }

  return const JsonEncoder.withIndent('  ').convert({
    'generated_on': now.toUtc().toIso8601String(),
    'rules_version': rulesVersion,
    'note': 'Each alert means an issuer document changed. It does not state a '
        'new reward rate - check the linked document before relying on it.',
    'alerts': alerts,
  });
}

String _isoDate(DateTime now) {
  final utc = now.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

/// Keeps excerpts short enough to read on a phone.
String _trim(String line, {int max = 220}) {
  final collapsed = line.trim();
  if (collapsed.length <= max) return collapsed;
  return '${collapsed.substring(0, max)}...';
}
