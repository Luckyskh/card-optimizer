/// A small pure-Dart PDF text reader, used when `pdftotext` is not available.
///
/// The monitor prefers poppler's `pdftotext`, which is far better at this — it
/// understands fonts, encodings and page layout. But poppler is an extra
/// install, and on a machine without it every PDF in the registry was being
/// skipped, which is most of them. That left the reward documents — the ones
/// that actually carry earn rates — unreadable during development.
///
/// How it works: a PDF is a set of numbered objects, and page content sits in
/// `stream` objects that are usually deflate-compressed. Dart has zlib built
/// in, so we can inflate those streams and pull the strings out of the text
/// operators (`Tj` and `TJ`) inside them.
///
/// What it deliberately does not do: fonts, encodings beyond WinAnsi-ish,
/// column layout, or ligature reconstruction. Output is good enough to diff
/// and to read a rate off, not to reproduce the document. Where the two
/// disagree, `pdftotext` is right.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Pulls readable text out of [bytes], or returns null if nothing came back.
String? extractPdfTextPure(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  final out = StringBuffer();

  for (final stream in _streams(data)) {
    final inflated = _inflate(stream);
    if (inflated == null) continue;
    final text = _textFrom(inflated);
    // Per stream, not once for the whole file: a document usually embeds
    // several subsetted fonts, each with its own glyph offset, so one global
    // shift decodes one section and scrambles the rest.
    if (text.trim().isNotEmpty) out.writeln(_deobfuscate(text));
  }

  final result = out.toString();
  if (result.trim().isEmpty) return null;

  // Refuse to return text we cannot actually read.
  //
  // Many issuer PDFs embed CID fonts — two bytes per glyph, decodable only via
  // the font's ToUnicode map, which this reader does not parse. The bytes come
  // out as stable nonsense. That would still *diff* correctly, but every alert
  // excerpt would be unreadable, and a snapshot nobody can check is worse than
  // an honest failure. Better to say "could not read" and let pdftotext, which
  // does parse those maps, handle it on the runner.
  final sample = result.length > 4000 ? result.substring(0, 4000) : result;
  final words = RegExp(r'\b(the|and|card|point|reward|bank|terms|credit)\b',
          caseSensitive: false)
      .allMatches(sample)
      .length;
  if (words < 3) return null;

  return result;
}

/// Undoes the character shift that subsetted fonts introduce.
///
/// Issuers' PDFs usually embed a subsetted font whose glyph codes bear no
/// relation to ASCII, so the raw strings come out as gibberish — HDFC's reward
/// terms begin "5 H Z D U G V", which is "Rewards" shifted by 29. Proper
/// decoding means reading the font's /ToUnicode map, which is what pdftotext
/// does and this does not.
///
/// What we can do cheaply is spot a *uniform* shift, which is the common case
/// for a single-font document: try every offset and keep whichever reads most
/// like English. If nothing scores better than the text we started with, the
/// original is returned untouched, so a document that was already readable is
/// never mangled by this.
String _deobfuscate(String text) {
  final sample = text.length > 4000 ? text.substring(0, 4000) : text;
  var bestShift = 0;
  var bestScore = _englishScore(sample);

  for (var shift = -64; shift <= 64; shift++) {
    if (shift == 0) continue;
    final score = _englishScore(_shift(sample, shift));
    if (score > bestScore) {
      bestScore = score;
      bestShift = shift;
    }
  }

  return bestShift == 0 ? text : _shift(text, bestShift);
}

String _shift(String s, int by) {
  final buf = StringBuffer();
  for (final unit in s.codeUnits) {
    // Leave whitespace alone; it is already correct and shifting it would
    // destroy the line structure the diff relies on.
    if (unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D) {
      buf.writeCharCode(unit);
      continue;
    }
    final moved = unit + by;
    buf.writeCharCode(moved >= 32 && moved < 127 ? moved : unit);
  }
  return buf.toString();
}

/// "Does this read like English" — dominated by real word matches.
///
/// Letter frequency alone is not enough to pick the right offset. Shifting
/// HDFC's reward terms by 32 rather than the correct 29 turns every glyph into
/// *some* lowercase letter and scores well on letters while reading as
/// nonsense, so words have to carry the decision.
int _englishScore(String s) {
  final lower = s.toLowerCase();
  var score = 0;

  for (final word in const [
    'the', 'and', 'for', 'card', 'point', 'reward', 'bank', 'terms',
    'will', 'shall', 'with', 'per', 'spent', 'credit', 'cash', 'fee',
    'customer', 'applicable', 'transaction', 'programme', 'program',
  ]) {
    score += RegExp('\\b$word\\b').allMatches(lower).length * 200;
  }

  // A weak tiebreak only, so it can never outvote the words above.
  for (final unit in lower.codeUnits) {
    if (unit >= 0x61 && unit <= 0x7A) score++;
  }
  return score;
}

/// Every `stream ... endstream` payload in the file.
Iterable<Uint8List> _streams(Uint8List data) sync* {
  const streamTag = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6D]; // "stream"
  const endTag = [0x65, 0x6E, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D];

  var i = 0;
  while (i < data.length - streamTag.length) {
    if (!_matches(data, i, streamTag)) {
      i++;
      continue;
    }
    var start = i + streamTag.length;
    // The keyword is followed by CRLF or LF before the payload begins.
    if (start < data.length && data[start] == 0x0D) start++;
    if (start < data.length && data[start] == 0x0A) start++;

    final end = _indexOf(data, endTag, start);
    if (end < 0) return;
    yield Uint8List.sublistView(data, start, end);
    i = end + endTag.length;
  }
}

bool _matches(Uint8List data, int at, List<int> pattern) {
  if (at + pattern.length > data.length) return false;
  for (var j = 0; j < pattern.length; j++) {
    if (data[at + j] != pattern[j]) return false;
  }
  return true;
}

int _indexOf(Uint8List data, List<int> pattern, int from) {
  for (var i = from; i <= data.length - pattern.length; i++) {
    if (_matches(data, i, pattern)) return i;
  }
  return -1;
}

/// Inflates a deflate-compressed stream. Streams that are not compressed, or
/// use a filter we do not handle, simply come back null and are skipped.
Uint8List? _inflate(Uint8List stream) {
  if (stream.isEmpty) return null;
  try {
    return Uint8List.fromList(ZLibDecoder().convert(stream));
  } catch (_) {
    try {
      // Some producers omit the zlib header and emit a raw deflate stream.
      return Uint8List.fromList(
          ZLibDecoder(raw: true).convert(stream));
    } catch (_) {
      return null;
    }
  }
}

/// Pulls the string literals out of a content stream's text operators.
///
/// Content streams look like `BT /F1 12 Tf (Hello) Tj ET`. We take what is
/// inside the parentheses, plus the pieces of `[(a) -20 (b)] TJ` arrays, and
/// use the text-positioning operators as a hint for where lines break.
String _textFrom(Uint8List content) {
  final s = latin1.decode(content, allowInvalid: true);
  final out = StringBuffer();
  var i = 0;
  var pendingBreak = false;

  while (i < s.length) {
    final c = s[i];

    if (c == '(') {
      final literal = _readLiteral(s, i);
      if (literal == null) break;
      if (pendingBreak) {
        out.write('\n');
        pendingBreak = false;
      }
      out.write(literal.text);
      i = literal.end;
      continue;
    }

    // T*, TD, Td and ' all move to a new line.
    if (c == 'T' && i + 1 < s.length) {
      final next = s[i + 1];
      if (next == '*' || next == 'D' || next == 'd') pendingBreak = true;
    } else if (c == 'E' && i + 1 < s.length && s[i + 1] == 'T') {
      pendingBreak = true;
    }

    i++;
  }

  return out.toString();
}

class _Literal {
  final String text;
  final int end;
  const _Literal(this.text, this.end);
}

/// Reads a `( ... )` string, honouring escapes and nested parentheses.
_Literal? _readLiteral(String s, int start) {
  final buf = StringBuffer();
  var depth = 0;
  var i = start;

  while (i < s.length) {
    final c = s[i];

    if (c == r'\' && i + 1 < s.length) {
      final next = s[i + 1];
      switch (next) {
        case 'n':
          buf.write('\n');
        case 'r':
          buf.write('\n');
        case 't':
          buf.write('\t');
        case 'b':
        case 'f':
          break;
        default:
          // \( \) \\ and octal escapes; take the character as written.
          if (!RegExp(r'[0-7]').hasMatch(next)) buf.write(next);
      }
      i += 2;
      continue;
    }

    if (c == '(') {
      depth++;
      if (depth > 1) buf.write(c);
      i++;
      continue;
    }

    if (c == ')') {
      depth--;
      if (depth == 0) return _Literal(buf.toString(), i + 1);
      buf.write(c);
      i++;
      continue;
    }

    buf.write(c);
    i++;
  }

  return null;
}
