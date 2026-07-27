/// Works out what actually changed between two versions of a document, and
/// decides whether it is worth telling anyone.
///
/// "The document changed" is close to useless on its own — these files run to
/// tens of pages and a change could be a reworded address. What the app's
/// users need is "the line about the 5% cap changed, and here is the before
/// and after".
///
/// Two steps get us there:
///
/// 1. Find the added and removed lines, and pair up the ones that look like
///    edits of each other so we can show before/after rather than two
///    unrelated lists.
/// 2. Keep only the pairs that mention money, a percentage, or a reward word.
///    A change to a customer service phone number is real, but it is not a
///    devaluation and does not deserve a notification.
library;

/// One thing that changed.
class DiffEntry {
  /// The line as it read before. Empty when the line is newly added.
  final String before;

  /// The line as it reads now. Empty when the line was removed.
  final String after;

  const DiffEntry({this.before = '', this.after = ''});

  bool get isEdit => before.isNotEmpty && after.isNotEmpty;
}

class DiffResult {
  /// Every difference found, material or not.
  final List<DiffEntry> all;

  /// The subset worth alerting on.
  final List<DiffEntry> material;

  const DiffResult({required this.all, required this.material});

  bool get hasChanges => all.isNotEmpty;

  /// A one-line description for the alert.
  String get summary {
    if (material.isEmpty) {
      return '${all.length} changed ${_lines(all.length)}, none of which '
          'mention rates, caps or fees';
    }
    return '${material.length} changed ${_lines(material.length)} '
        'mentioning rates, caps or fees';
  }

  static String _lines(int count) => count == 1 ? 'line' : 'lines';
}

/// Words that make a changed line worth someone's attention.
const _rewardWords = [
  'cashback',
  'cash back',
  'reward',
  'point',
  'neucoin',
  'mile',
  'cap',
  'capped',
  'ceiling',
  'milestone',
  'waiver',
  'surcharge',
  'markup',
  'mark-up',
  'lounge',
  'exclu', // catches exclusion, excluded, excluding
  'fee',
  'charge',
  'interest',
  'annual',
  'accelerated',
  'minimum',
  'threshold',
  'voucher',
  'discount',
];

/// Compares two versions of a document.
///
/// This is a set comparison rather than a true line-by-line diff. Reflowed
/// paragraphs would defeat a positional diff anyway, and what we need is "which
/// statements appeared or disappeared", which set comparison answers directly
/// and cheaply even on documents of several thousand lines.
DiffResult diffLines(List<String> before, List<String> after) {
  final beforeCounts = _counts(before);
  final afterCounts = _counts(after);

  final removed = <String>[];
  beforeCounts.forEach((line, count) {
    final remaining = count - (afterCounts[line] ?? 0);
    for (var i = 0; i < remaining; i++) {
      removed.add(line);
    }
  });

  final added = <String>[];
  afterCounts.forEach((line, count) {
    final remaining = count - (beforeCounts[line] ?? 0);
    for (var i = 0; i < remaining; i++) {
      added.add(line);
    }
  });

  final entries = _pair(removed, added);
  final material = entries.where(_isMaterial).toList();

  return DiffResult(all: entries, material: material);
}

Map<String, int> _counts(List<String> lines) {
  final counts = <String, int>{};
  for (final line in lines) {
    counts[line] = (counts[line] ?? 0) + 1;
  }
  return counts;
}

/// Matches removed lines with the added lines that replaced them.
///
/// A cap being cut from Rs 5,000 to Rs 2,000 shows up as one removal and one
/// addition that are ninety per cent identical. Pairing them turns two
/// confusing entries into one clear "was / now".
List<DiffEntry> _pair(List<String> removed, List<String> added) {
  final entries = <DiffEntry>[];
  final unusedAdded = List<String>.from(added);

  for (final oldLine in removed) {
    var bestIndex = -1;
    var bestScore = 0.0;

    for (var i = 0; i < unusedAdded.length; i++) {
      final score = _similarity(oldLine, unusedAdded[i]);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    // 0.5 keeps genuine rewrites paired while stopping two unrelated
    // sentences from being presented as an edit of one another.
    if (bestIndex >= 0 && bestScore >= _pairThreshold) {
      entries.add(DiffEntry(before: oldLine, after: unusedAdded[bestIndex]));
      unusedAdded.removeAt(bestIndex);
    } else {
      entries.add(DiffEntry(before: oldLine));
    }
  }

  for (final newLine in unusedAdded) {
    entries.add(DiffEntry(after: newLine));
  }

  return entries;
}

const _pairThreshold = 0.5;

/// How alike two lines are, from 0 to 1, by shared words.
///
/// Mostly this is the proportion of words the two lines have in common. But
/// the commonest devaluation is a clause being *added* to an existing line —
/// "5% cashback on online spends" becoming "5% cashback on online spends,
/// capped at Rs 500 per month". That pair shares every word of the shorter
/// line and still scores only 0.45 on the plain measure, because the added
/// words count against it, and it would be reported as one deletion plus one
/// unrelated addition.
///
/// So when one line is wholly contained in the other, we treat them as a
/// match. The four-word floor stops short boilerplate ("Terms apply") from
/// being paired with every longer line that happens to contain those words.
double _similarity(String a, String b) {
  final wordsA = _words(a);
  final wordsB = _words(b);
  if (wordsA.isEmpty || wordsB.isEmpty) return 0;

  final shared = wordsA.intersection(wordsB).length;
  final total = wordsA.union(wordsB).length;
  final jaccard = total == 0 ? 0.0 : shared / total;

  final shorter = wordsA.length < wordsB.length ? wordsA.length : wordsB.length;
  if (shorter >= 4) {
    final containment = shared / shorter;
    if (containment >= 0.8) return jaccard > _pairThreshold ? jaccard : 0.8;
  }

  return jaccard;
}

Set<String> _words(String line) => line
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9%₹.]+'))
    .where((word) => word.isNotEmpty)
    .toSet();

/// True when a change is about money or rewards rather than housekeeping.
bool _isMaterial(DiffEntry entry) {
  final text = '${entry.before} ${entry.after}'.toLowerCase();

  // A figure of some kind: a percentage, a rupee amount, or a bare number.
  if (RegExp(r'\d').hasMatch(text) &&
      RegExp(r'%|₹|rs\.?\s*\d|inr').hasMatch(text)) {
    return true;
  }

  return _rewardWords.any(text.contains);
}
