/// Removes the noise that would otherwise look like a change.
///
/// This is the most important file in the monitor, and the least obvious.
///
/// Banks regenerate these documents regularly without changing a single term.
/// The regenerated file has a new "last updated" stamp, a new version number,
/// slightly different line wrapping, and different amounts of whitespace. Hash
/// the raw text and you would tell every user their card's terms had changed,
/// roughly every fortnight, until they stopped believing the alerts.
///
/// So we normalise first, and only then compare. The rule followed throughout:
/// **strip things that carry no meaning, never strip things that might.** A
/// date inside "5% cashback from 1 April 2026" is part of the terms and stays.
/// The same date inside "Last updated on 1 April 2026" is a printing artefact
/// and gets masked.
library;

/// Lines that are page furniture rather than content.
final _pageNumber = RegExp(r'^(page\s*)?\d+(\s*(of|/)\s*\d+)?$',
    caseSensitive: false);

/// Lines that only exist to say when the document was produced. A date in one
/// of these is safe to mask; a date anywhere else is not.
final _metadataLine = RegExp(
  r'last\s+updated|last\s+revised|last\s+modified|version\s*[:\s]|'
  r'generated\s+on|printed\s+on|effective\s+date\s+of\s+this\s+document|'
  r'date\s+of\s+publication|w\.e\.f\.?\s*$',
  caseSensitive: false,
);

/// Dates in the forms these documents actually use:
/// "1 Apr 2026", "01/04/2026", "2026-04-01", "April 1, 2026", "Jul 2nd, 2026".
final _dateLike = RegExp(
  r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|'
  r'\d{4}-\d{2}-\d{2}|'
  r'\d{1,2}(st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)'
  r'[a-z]*\.?,?\s*\d{2,4}|'
  r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}'
  r'(st|nd|rd|th)?,?\s*\d{2,4}',
  caseSensitive: false,
);

/// Version stamps such as "Ver. 1.76" or "Version 1.05".
///
/// Unlike dates, these are masked wherever they appear. A document's version
/// number is always a property of the printing, never a term of the card — no
/// issuer writes "5% cashback, version 1.76".
final _versionLike =
    RegExp(r'(ver\.?|version)\s*:?\s*\d+(\.\d+)*', caseSensitive: false);

/// Turns raw extracted text into the form we store and compare.
///
/// The result is still readable, because the diff quotes it back to the user
/// in alerts. Normalising into something machine-only would make every alert
/// unintelligible.
String normalize(String raw) {
  final out = <String>[];

  for (var line in raw.split('\n')) {
    // Collapse every run of whitespace, including the wide gaps that
    // `pdftotext -layout` inserts between table columns.
    line = line.replaceAll(RegExp(r'[\t ​]+'), ' ');
    line = line.replaceAll(RegExp(r' {2,}'), ' ').trim();

    if (line.isEmpty) continue;
    if (_pageNumber.hasMatch(line)) continue;

    // Version stamps are safe to mask anywhere.
    line = line.replaceAll(_versionLike, '<version>');

    // Dates are only safe to mask on lines that exist to record when the
    // document was produced. "Cap cut to Rs 2,000 from 1 Apr 2026" is a term,
    // and masking the date there would hide a real change.
    if (_metadataLine.hasMatch(line)) {
      line = line.replaceAll(_dateLike, '<date>');
    }

    out.add(line);
  }

  return out.join('\n');
}

/// Splits normalised text back into lines, which is what the differ compares.
List<String> toLines(String normalized) =>
    normalized.split('\n').where((line) => line.isNotEmpty).toList();
