/// Checks whether any issuer has changed the terms behind the app's rates.
///
/// Run it by hand:
///
///     dart run tools/terms_watch/bin/check_terms.dart --dry-run
///
/// or let GitHub run it on the 1st and 16th of each month — see
/// `.github/workflows/check-terms.yml`.
///
/// What it does, for each document in `sources.json`:
///
///   download it -> read its text -> strip the noise -> compare with the
///   snapshot in `snapshots/` -> if it moved, write an alert
///
/// What it deliberately does not do: change `assets/rules.json`. Spotting that
/// a document's text moved is not the same as knowing the new reward rate. A
/// person has to read the document and update the dataset by hand. Automating
/// that step would put invented numbers in front of users.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';

import 'package:terms_watch/diff.dart';
import 'package:terms_watch/extract.dart';
import 'package:terms_watch/fetch.dart';
import 'package:terms_watch/normalize.dart';
import 'package:terms_watch/report.dart';

Future<int> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('dry-run',
        negatable: false,
        help: 'Fetch and compare, but do not write any files.')
    ..addOption('only',
        help: 'Check a single document by its doc_id, e.g. --only sbi-mitc.')
    ..addOption('root',
        defaultsTo: _defaultRoot(),
        help: 'Path to the repository root.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args.flag('help')) {
    stdout.writeln('Checks issuer terms documents for changes.\n');
    stdout.writeln(parser.usage);
    return 0;
  }

  final root = args.option('root')!;
  final dryRun = args.flag('dry-run');
  final only = args.option('only');

  final sourcesFile = File('$root/tools/terms_watch/sources.json');
  if (!sourcesFile.existsSync()) {
    stderr.writeln('Could not find ${sourcesFile.path}.');
    stderr.writeln('Pass --root with the path to the repository root.');
    return 2;
  }

  final documents = _readDocuments(sourcesFile);
  final selected = only == null
      ? documents
      : documents.where((d) => d.docId == only).toList();

  if (selected.isEmpty) {
    stderr.writeln(only == null
        ? 'sources.json lists no documents.'
        : 'No document with doc_id "$only" in sources.json.');
    return 2;
  }

  // Names from the dataset win; sources.json fills in the cards that are
  // monitored but not yet researched, so an alert reads "Kotak League
  // Platinum" rather than "kotak-league-platinum".
  final cardNames = {
    ..._readCardNamesFromSources(sourcesFile),
    ..._readCardNames('$root/assets/rules.json'),
  };
  final rulesVersion = _readRulesVersion('$root/assets/rules.json');

  final store = SnapshotStore('$root/snapshots');
  final index = store.readIndex();
  final now = DateTime.now().toUtc();

  stdout.writeln('Checking ${selected.length} '
      'document${selected.length == 1 ? '' : 's'}'
      '${dryRun ? ' (dry run, nothing will be written)' : ''}\n');

  if (!isPdfToolAvailable()) {
    stdout.writeln(
      'Note: pdftotext is not installed, so PDF documents will be skipped.\n'
      '      Install poppler-utils to check them. HTML documents still work.\n',
    );
  }

  final outcomes = <DocOutcome>[];
  final updatedIndex = Map<String, SnapshotRecord>.from(index);

  for (final doc in selected) {
    final previous = index[doc.docId];
    final outcome = await _check(
      doc: doc,
      previous: previous,
      store: store,
      dryRun: dryRun,
      now: now,
      updatedIndex: updatedIndex,
    );
    outcomes.add(outcome);
    stdout.writeln(_describe(outcome));
  }

  if (!dryRun) {
    store.writeIndex(updatedIndex);

    final alertsPath = '$root/alerts.json';
    final existing = _readExistingAlerts(alertsPath);
    final fresh = json.decode(buildAlertsJson(
      outcomes: outcomes,
      rulesVersion: rulesVersion,
      cardNames: cardNames,
      now: now,
    )) as Map<String, dynamic>;

    // Keep recent history so a user who has not opened the app in a month
    // still sees what changed while they were away.
    final merged = _mergeAlerts(existing, fresh, now);
    File(alertsPath)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(merged));

    stdout.writeln('\nWrote snapshots/ and alerts.json.');
  }

  return _summarise(outcomes, dryRun);
}

// ---------------------------------------------------------------------------

Future<DocOutcome> _check({
  required _Document doc,
  required SnapshotRecord? previous,
  required SnapshotStore store,
  required bool dryRun,
  required DateTime now,
  required Map<String, SnapshotRecord> updatedIndex,
}) async {
  final url = doc.url;

  if (url == null || url.isEmpty) {
    return DocOutcome(
      docId: doc.docId,
      label: doc.label,
      cardIds: doc.cardIds,
      knownBlocked: doc.knownBlocked,
      url: null,
      status: DocStatus.notConfigured,
      detail: 'no URL in sources.json yet',
    );
  }

  final fetched = await fetchDocument(url);
  if (!fetched.ok) {
    // Critical: a failed download must never look like a change. We leave the
    // snapshot exactly as it was and count the failure.
    final failures = (previous?.consecutiveFailures ?? 0) + 1;
    if (!dryRun && previous != null) {
      updatedIndex[doc.docId] = SnapshotRecord(
        sha256: previous.sha256,
        lastCheckedUtc: now.toIso8601String(),
        lastChangedUtc: previous.lastChangedUtc,
        consecutiveFailures: failures,
        lastError: fetched.error,
      );
    }
    return DocOutcome(
      docId: doc.docId,
      label: doc.label,
      cardIds: doc.cardIds,
      knownBlocked: doc.knownBlocked,
      url: url,
      status: DocStatus.fetchFailed,
      detail: fetched.error,
      consecutiveFailures: failures,
    );
  }

  final extracted = fetched.isPdf
      ? await extractPdfText(fetched.bytes)
      : extractHtmlText(fetched.bytes);

  if (!extracted.ok) {
    final failures = (previous?.consecutiveFailures ?? 0) + 1;
    if (!dryRun && previous != null) {
      updatedIndex[doc.docId] = SnapshotRecord(
        sha256: previous.sha256,
        lastCheckedUtc: now.toIso8601String(),
        lastChangedUtc: previous.lastChangedUtc,
        consecutiveFailures: failures,
        lastError: extracted.error,
      );
    }
    return DocOutcome(
      docId: doc.docId,
      label: doc.label,
      cardIds: doc.cardIds,
      knownBlocked: doc.knownBlocked,
      url: url,
      status: DocStatus.extractFailed,
      detail: extracted.error,
      consecutiveFailures: failures,
    );
  }

  final normalized = normalize(extracted.text);
  final hash = sha256.convert(utf8.encode(normalized)).toString();
  final storedText = store.readSnapshot(doc.docId);

  // First sighting: record it and say so. Reporting a change here would mean
  // every new document announced itself as a devaluation.
  if (previous == null || storedText == null) {
    if (!dryRun) {
      store.writeSnapshot(doc.docId, normalized);
      updatedIndex[doc.docId] = SnapshotRecord(
        sha256: hash,
        lastCheckedUtc: now.toIso8601String(),
      );
    }
    return DocOutcome(
      docId: doc.docId,
      label: doc.label,
      cardIds: doc.cardIds,
      knownBlocked: doc.knownBlocked,
      url: url,
      status: DocStatus.baseline,
      detail: '${toLines(normalized).length} lines recorded',
    );
  }

  // Compared against the stored text itself rather than the hash recorded in
  // index.json. The snapshot file is the thing the diff quotes from, so it has
  // to be the thing we compare against - otherwise a hand-edited snapshot and
  // a stale hash could disagree and the change would be missed. The hash stays
  // in the index as a quick way to eyeball whether a document moved.
  if (storedText == normalized) {
    if (!dryRun) {
      updatedIndex[doc.docId] = SnapshotRecord(
        sha256: hash,
        lastCheckedUtc: now.toIso8601String(),
        lastChangedUtc: previous.lastChangedUtc,
      );
    }
    return DocOutcome(
      docId: doc.docId,
      label: doc.label,
      cardIds: doc.cardIds,
      knownBlocked: doc.knownBlocked,
      url: url,
      status: DocStatus.unchanged,
    );
  }

  final result = diffLines(toLines(storedText), toLines(normalized));

  if (!dryRun) {
    store.writeSnapshot(doc.docId, normalized);
    updatedIndex[doc.docId] = SnapshotRecord(
      sha256: hash,
      lastCheckedUtc: now.toIso8601String(),
      lastChangedUtc: now.toIso8601String(),
    );
  }

  return DocOutcome(
    docId: doc.docId,
    label: doc.label,
    cardIds: doc.cardIds,
    url: url,
    status: DocStatus.changed,
    detail: result.summary,
    diff: result,
  );
}

// ---------------------------------------------------------------------------

String _describe(DocOutcome outcome) {
  final marker = switch (outcome.status) {
    DocStatus.unchanged => '  ok      ',
    DocStatus.changed => '  CHANGED ',
    DocStatus.baseline => '  new     ',
    DocStatus.fetchFailed =>
      outcome.knownBlocked ? '  blocked ' : '  FAILED  ',
    DocStatus.extractFailed =>
      outcome.knownBlocked ? '  blocked ' : '  FAILED  ',
    DocStatus.notConfigured => '  skipped ',
  };

  final buffer = StringBuffer('$marker${outcome.docId.padRight(24)}');
  if (outcome.detail != null) buffer.write(outcome.detail);
  if (outcome.isStale) {
    buffer.write(
        ' (failed ${outcome.consecutiveFailures} runs in a row - needs a look)');
  }

  if (outcome.status == DocStatus.changed && outcome.diff != null) {
    for (final entry in outcome.diff!.material.take(3)) {
      if (entry.before.isNotEmpty) {
        buffer.write('\n            was: ${_short(entry.before)}');
      }
      if (entry.after.isNotEmpty) {
        buffer.write('\n            now: ${_short(entry.after)}');
      }
    }
  }

  return buffer.toString();
}

String _short(String line, {int max = 110}) =>
    line.length <= max ? line : '${line.substring(0, max)}...';

int _summarise(List<DocOutcome> outcomes, bool dryRun) {
  final changed =
      outcomes.where((o) => o.status == DocStatus.changed).toList();
  final stale = outcomes.where((o) => o.isStale).toList();
  final unconfigured =
      outcomes.where((o) => o.status == DocStatus.notConfigured).toList();

  final blocked =
      outcomes.where((o) => o.knownBlocked && o.failed).toList();
  final nowReachable =
      outcomes.where((o) => o.unexpectedlyReachable).toList();

  stdout.writeln('\n--------------------------------------------');
  stdout.writeln('${outcomes.length} checked, '
      '${changed.length} changed, '
      '${outcomes.where((o) => o.failed && !o.knownBlocked).length} failed, '
      '${blocked.length} blocked by the issuer, '
      '${unconfigured.length} not configured');

  if (changed.isNotEmpty) {
    stdout.writeln('\nChanged documents need a human to read them and update '
        'assets/rules.json:');
    for (final outcome in changed) {
      stdout.writeln('  - ${outcome.label}\n    ${outcome.url}');
    }
  }

  if (unconfigured.isNotEmpty) {
    stdout.writeln('\nStill missing a URL in sources.json:');
    for (final outcome in unconfigured) {
      stdout.writeln('  - ${outcome.docId} (${outcome.label})');
    }
  }

  if (blocked.isNotEmpty) {
    stdout.writeln('\nThe issuer refuses these to automated clients, so they '
        'are not being monitored. Changes to them have to be checked by '
        'hand:');
    for (final outcome in blocked) {
      stdout.writeln('  - ${outcome.label}\n    ${outcome.url}');
    }
  }

  if (nowReachable.isNotEmpty) {
    stdout.writeln('\nGood news - these were marked as blocked but worked '
        'this time. Remove "known_blocked" from sources.json to start '
        'monitoring them properly:');
    for (final outcome in nowReachable) {
      stdout.writeln('  - ${outcome.docId}');
    }
  }

  if (stale.isNotEmpty) {
    stdout.writeln('\nThese have failed three or more runs in a row. The app '
        'is no longer being told about changes to them:');
    for (final outcome in stale) {
      stdout.writeln('  - ${outcome.docId}: ${outcome.detail}');
    }
    // Non-zero so GitHub marks the run as failed and emails you. Silence is
    // the failure mode this whole tool exists to avoid.
    return dryRun ? 0 : 1;
  }

  return 0;
}

// ---------------------------------------------------------------------------

class _Document {
  final String docId;
  final String label;
  final List<String> cardIds;
  final String? url;
  final bool knownBlocked;

  const _Document({
    required this.docId,
    required this.label,
    required this.cardIds,
    required this.url,
    this.knownBlocked = false,
  });
}

List<_Document> _readDocuments(File file) {
  final decoded = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  final documents = decoded['documents'] as List<dynamic>? ?? [];

  return documents.whereType<Map<String, dynamic>>().map((entry) {
    return _Document(
      docId: entry['doc_id'] as String,
      label: entry['label'] as String? ?? entry['doc_id'] as String,
      cardIds: (entry['card_ids'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      url: entry['url'] as String?,
      knownBlocked: entry['known_blocked'] as bool? ?? false,
    );
  }).toList();
}

/// Display names for cards that are monitored but not yet in rules.json.
Map<String, String> _readCardNamesFromSources(File file) {
  try {
    final decoded =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final names = decoded['card_names'] as Map<String, dynamic>? ?? {};
    return names.map((key, value) => MapEntry(key, value.toString()));
  } catch (_) {
    return {};
  }
}

/// Card id to display name, so alerts can say "Cashback SBI Card" rather than
/// "sbi-cashback".
Map<String, String> _readCardNames(String rulesPath) {
  final file = File(rulesPath);
  if (!file.existsSync()) return {};
  try {
    final decoded =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final cards = decoded['cards'] as List<dynamic>? ?? [];
    return {
      for (final card in cards.whereType<Map<String, dynamic>>())
        card['id'] as String:
            '${card['bank'] ?? ''} ${card['name'] ?? ''}'.trim(),
    };
  } catch (_) {
    return {};
  }
}

int _readRulesVersion(String rulesPath) {
  final file = File(rulesPath);
  if (!file.existsSync()) return 0;
  try {
    final decoded =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    return (decoded['version'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

Map<String, dynamic> _readExistingAlerts(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  try {
    return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

/// Adds this run's alerts to the existing file, dropping anything older than
/// 90 days so the file does not grow forever.
Map<String, dynamic> _mergeAlerts(
  Map<String, dynamic> existing,
  Map<String, dynamic> fresh,
  DateTime now,
) {
  final cutoff = now.subtract(const Duration(days: 90));
  final byId = <String, Map<String, dynamic>>{};

  for (final alert in (existing['alerts'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()) {
    final detected = DateTime.tryParse(alert['detected_on'] as String? ?? '');
    if (detected != null && detected.isBefore(cutoff)) continue;
    byId[alert['id'] as String] = alert;
  }

  for (final alert in (fresh['alerts'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()) {
    byId[alert['id'] as String] = alert;
  }

  final sorted = byId.values.toList()
    ..sort((a, b) => (b['detected_on'] as String)
        .compareTo(a['detected_on'] as String));

  return {...fresh, 'alerts': sorted};
}

/// Assumes the script sits at `<root>/tools/terms_watch/bin/`.
String _defaultRoot() {
  final script = File.fromUri(Platform.script).absolute.parent; // bin/
  return script.parent.parent.parent.path; // -> repository root
}
