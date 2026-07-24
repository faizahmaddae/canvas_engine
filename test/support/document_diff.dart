// Key-path-level structural diff for engine documents.
//
// Both engine harnesses added in roadmap 5.4 — the invert harness
// (`test/engine/command_invert_harness_test.dart`) and the codec
// fixed-point harness (`test/engine/codec_diff_harness_test.dart`) —
// compare whole documents. A plain `expect(a, b)` on two 40 KB JSON
// strings reports "strings differ" and nothing else, which is useless
// for triage: the whole point of a harness is that the failure names
// the field. This file turns two encoded documents into lines like
//
//     layers[2].transform.fx: missing vs true
//     layers[0].style.fontSize: 96 vs 72.0
//
// Pure Dart on purpose. Engine tests import it and AGENTS.md rule 6
// forbids `flutter/material.dart` anywhere under `test/engine/`; the
// only non-core dependency here is the codec itself, which is engine
// code.
import 'dart:convert';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';

/// How much of a nested value to inline before truncating. Long
/// enough to identify an effect entry or a transform, short enough
/// that a 40-line diff still fits on one screen.
const int _kValuePreviewChars = 96;

/// Structural diff of two decoded-JSON trees, as `path: left vs right`
/// lines. An empty result means the two trees are value-equal.
///
/// Numbers compare with Dart `num` semantics, so an `int 1` on one side
/// and a `double 1.0` on the other are NOT reported — that difference
/// is a *formatting* one and is surfaced separately by
/// [describeEncodedDiff], which falls back to a byte-offset report when
/// the trees agree but the strings do not.
List<String> jsonDiffPaths(Object? left, Object? right) {
  final out = <String>[];
  _diff(left, right, '', out);
  return out;
}

void _diff(Object? a, Object? b, String path, List<String> out) {
  if (a is Map && b is Map) {
    final keys = <String>{
      ...a.keys.map((k) => '$k'),
      ...b.keys.map((k) => '$k'),
    }.toList()..sort();
    for (final key in keys) {
      final child = path.isEmpty ? key : '$path.$key';
      final hasA = a.containsKey(key);
      final hasB = b.containsKey(key);
      if (!hasA) {
        out.add('$child: missing vs ${_preview(b[key])}');
      } else if (!hasB) {
        out.add('$child: ${_preview(a[key])} vs missing');
      } else {
        _diff(a[key], b[key], child, out);
      }
    }
    return;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      out.add('${_root(path)}.length: ${a.length} vs ${b.length}');
    }
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      _diff(a[i], b[i], '$path[$i]', out);
    }
    for (var i = shared; i < a.length; i++) {
      out.add('$path[$i]: ${_preview(a[i])} vs missing');
    }
    for (var i = shared; i < b.length; i++) {
      out.add('$path[$i]: missing vs ${_preview(b[i])}');
    }
    return;
  }
  // Container-vs-scalar (or container-of-different-kind): there is no
  // meaningful per-key walk, so report the whole node.
  if (a is Map || b is Map || a is List || b is List) {
    out.add('${_root(path)}: ${_preview(a)} vs ${_preview(b)}');
    return;
  }
  if (a != b) out.add('${_root(path)}: ${_preview(a)} vs ${_preview(b)}');
}

String _root(String path) => path.isEmpty ? '<document>' : path;

String _preview(Object? value) {
  final encoded = jsonEncode(value);
  if (encoded.length <= _kValuePreviewChars) return encoded;
  return '${encoded.substring(0, _kValuePreviewChars)}…';
}

/// Human-readable diff of two *encoded* documents (the strings
/// [DocumentCodec.encode] produces).
///
/// Returns an empty string when the two encodings are byte-identical.
/// Otherwise returns the key-path lines; if the trees are value-equal
/// but the bytes are not — the int-vs-double drift that a naive
/// `expect(encodeA, encodeB)` would report as an opaque string
/// mismatch — it reports the first differing offset with context
/// instead, because that IS the regression in that case.
String describeEncodedDiff(
  String expected,
  String actual, {
  int maxLines = 40,
}) {
  if (expected == actual) return '';
  final lines = jsonDiffPaths(jsonDecode(expected), jsonDecode(actual));
  if (lines.isEmpty) return _describeByteDrift(expected, actual);
  final shown = lines.length <= maxLines ? lines : lines.take(maxLines);
  final buffer = StringBuffer('${lines.length} differing key path(s):\n');
  for (final line in shown) {
    buffer.writeln('  $line');
  }
  if (lines.length > maxLines) {
    buffer.writeln('  … ${lines.length - maxLines} more');
  }
  return buffer.toString().trimRight();
}

/// Structural diff of two in-memory documents, via their encodings.
/// This is the form both harnesses call: encoding is what makes the
/// comparison reach every subclass field without each layer type
/// having to hand-implement a comparator.
String describeDocumentDiff(EditorDocument expected, EditorDocument actual) =>
    describeEncodedDiff(
      DocumentCodec.encode(expected),
      DocumentCodec.encode(actual),
    );

/// Key paths (not a rendered message) for callers that need to check a
/// diff against an allow-list of known divergences.
List<String> documentDiffPaths(EditorDocument expected, EditorDocument actual) {
  final a = DocumentCodec.toJson(expected);
  final b = DocumentCodec.toJson(actual);
  return jsonDiffPaths(a, b);
}

/// Same tree, different bytes: report where the strings part company.
/// A number that used to serialise as `1` now serialising as `1.0`
/// (or vice versa) is a real wire-format regression even though the
/// decoded values still compare equal.
String _describeByteDrift(String expected, String actual) {
  final shared = expected.length < actual.length
      ? expected.length
      : actual.length;
  var at = 0;
  while (at < shared && expected.codeUnitAt(at) == actual.codeUnitAt(at)) {
    at++;
  }
  final from = at - 40 < 0 ? 0 : at - 40;
  String window(String s) {
    final to = at + 40 > s.length ? s.length : at + 40;
    return s.substring(from, to).replaceAll('\n', '⏎');
  }

  return 'trees are value-equal but encodings differ at offset $at '
      '(number formatting drift?):\n'
      '  expected: …${window(expected)}…\n'
      '  actual:   …${window(actual)}…';
}
