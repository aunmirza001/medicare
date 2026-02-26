import 'dart:convert';

import 'package:http/http.dart' as http;

class RxCandidate {
  final String rxcui;
  final String name;

  /// If true, this suggestion is locally generated (brand alias),
  /// not from RxNorm.
  final bool isLocal;

  /// For local candidates, this is already the generic ingredient.
  /// For RxNorm candidates, this will be filled via ingredientsFor().
  final List<String> ingredientsHint;

  const RxCandidate({
    required this.rxcui,
    required this.name,
    this.isLocal = false,
    this.ingredientsHint = const [],
  });
}

class RxnormService {
  static const _base = 'https://rxnav.nlm.nih.gov/REST';

  /// Pakistan/India brand -> generic (expand this list over time)
  /// NOTE: keys must be lowercase
  static const Map<String, String> _brandAlias = {
    'tryptanol': 'amitriptyline',
    'brufen': 'ibuprofen',
    'panadol': 'paracetamol',
    'disprin': 'aspirin',
    'augmentin': 'amoxicillin/clavulanate',
    'flagyl': 'metronidazole',
    'lasix': 'furosemide',
    'glucophage': 'metformin',
    'concor': 'bisoprolol',
    'norvasc': 'amlodipine',
    'xanax': 'alprazolam',
  };

  static String _normTerm(String s) => s.trim().toLowerCase();

  /// Search RxNorm approximateTerm + also provide a local brand alias suggestion if matched.
  Future<List<RxCandidate>> search(String term, {int maxEntries = 150}) async {
    final t = term.trim();
    if (t.isEmpty) return const [];

    final out = <RxCandidate>[];

    // 1) Add local brand alias suggestion (if any)
    final alias = _brandAlias[_normTerm(t)];
    if (alias != null && alias.trim().isNotEmpty) {
      out.add(
        RxCandidate(
          rxcui: 'LOCAL:${_normTerm(t)}',
          name: '$t (Local) → $alias',
          isLocal: true,
          ingredientsHint: _normalizeIngredients(alias),
        ),
      );
    }

    // 2) RxNorm approximate term search
    final uri = Uri.parse(
      '$_base/approximateTerm.json',
    ).replace(queryParameters: {'term': t, 'maxEntries': '$maxEntries'});

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200)
        return out; // return local suggestion if exists

      final data = json.decode(res.body) as Map<String, dynamic>;
      final group = (data['approximateGroup'] as Map?)?.cast<String, dynamic>();
      final cands = (group?['candidate'] as List?) ?? const [];

      final ids = <String>[];
      for (final c in cands) {
        final m = (c as Map).cast<String, dynamic>();
        final id = (m['rxcui'] ?? '').toString();
        if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
      }

      // reduce requests
      final limited = ids.take(60).toList();
      final names = await Future.wait(limited.map(_nameFor));

      for (var i = 0; i < limited.length; i++) {
        final name = names[i].trim();
        if (name.isNotEmpty) {
          out.add(RxCandidate(rxcui: limited[i], name: name));
        }
      }
    } catch (_) {
      // ignore network failures; still show local alias suggestion if present
      return out;
    }

    return out;
  }

  Future<String> _nameFor(String rxcui) async {
    final uri = Uri.parse('$_base/rxcui/$rxcui/properties.json');
    final res = await http.get(uri);
    if (res.statusCode != 200) return '';
    final data = json.decode(res.body) as Map<String, dynamic>;
    final props = (data['properties'] as Map?)?.cast<String, dynamic>();
    return (props?['name'] ?? '').toString();
  }

  /// Returns multiple ingredient strings (normalized) for a selected RxCUI.
  /// Tries tty=IN then PIN then MIN.
  Future<List<String>> ingredientsFor(String rxcui) async {
    // local candidate
    if (rxcui.startsWith('LOCAL:')) {
      // ingredients are already embedded in suggestion, but return empty here;
      // your UI should use candidate.ingredientsHint for local results.
      return const [];
    }

    final raw = await _fetchIngredientNamesByTty(rxcui, 'IN');
    if (raw.isNotEmpty) return _normalizeMany(raw);

    final raw2 = await _fetchIngredientNamesByTty(rxcui, 'PIN');
    if (raw2.isNotEmpty) return _normalizeMany(raw2);

    final raw3 = await _fetchIngredientNamesByTty(rxcui, 'MIN');
    if (raw3.isNotEmpty) return _normalizeMany(raw3);

    return const [];
  }

  Future<List<String>> _fetchIngredientNamesByTty(
    String rxcui,
    String tty,
  ) async {
    final uri = Uri.parse(
      '$_base/rxcui/$rxcui/related.json',
    ).replace(queryParameters: {'tty': tty});
    final res = await http.get(uri);
    if (res.statusCode != 200) return const [];

    final data = json.decode(res.body) as Map<String, dynamic>;
    final group = (data['relatedGroup'] as Map?)?.cast<String, dynamic>();
    final groups = (group?['conceptGroup'] as List?) ?? const [];

    final out = <String>[];
    for (final g in groups) {
      final gm = (g as Map).cast<String, dynamic>();
      final props = (gm['conceptProperties'] as List?) ?? const [];
      for (final p in props) {
        final pm = (p as Map).cast<String, dynamic>();
        final name = (pm['name'] ?? '').toString().trim();
        if (name.isNotEmpty) out.add(name);
      }
    }
    return out;
  }

  /// Normalize list of raw ingredient names into a unique list
  List<String> _normalizeMany(List<String> rawNames) {
    final all = <String>{};
    for (final r in rawNames) {
      all.addAll(_normalizeIngredients(r));
    }
    final out = all.toList();
    out.sort();
    return out;
  }

  /// Very important: normalize ingredient strings for matching your local rules.
  /// - lowercase
  /// - remove salts (HCl/hydrochloride/etc.)
  /// - split combos: "amoxicillin / clavulanate"
  static List<String> _normalizeIngredients(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return const [];

    // unify separators for combos
    s = s.replaceAll('+', '/').replaceAll('&', '/');

    // split on common separators
    final parts = s
        .split(RegExp(r'[/,;]| and '))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String clean(String x) {
      var y = x;
      y = y.replaceAll(RegExp(r'\b(hcl|hydrochloride|sodium|potassium)\b'), '');
      y = y.replaceAll(RegExp(r'\s+'), ' ').trim();
      return y;
    }

    final cleaned = parts
        .map(clean)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    cleaned.sort();
    return cleaned;
  }
}
