import 'dart:convert';

import 'package:http/http.dart' as http;

class RxCandidate {
  final String rxcui;
  final String name;

  /// If true, this suggestion is locally generated (brand alias), not from RxNorm.
  final bool isLocal;

  /// For local candidates, already the normalized ingredients.
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

  /// Pakistan/India brand -> generic (expand over time). Keys must be lowercase.
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

  // ✅ In-memory caches
  final Map<String, List<RxCandidate>> _searchCache = {};
  final Map<String, String> _nameCache = {};
  final Map<String, List<String>> _ingredientCache = {};

  /// Fast RxNorm search with caching.
  /// - waits until term length >= 2 (you can make it 3)
  /// - caches results per term
  Future<List<RxCandidate>> search(String term, {int maxEntries = 80}) async {
    final t = term.trim();
    if (t.isEmpty) return const [];
    if (t.length < 2) return const [];

    final key = _normTerm(t);
    final cached = _searchCache[key];
    if (cached != null) return cached;

    final out = <RxCandidate>[];

    // 1) Local alias suggestion (exact match)
    final alias = _brandAlias[key];
    if (alias != null && alias.trim().isNotEmpty) {
      out.add(
        RxCandidate(
          rxcui: 'LOCAL:$key',
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
      if (res.statusCode != 200) {
        _searchCache[key] = out;
        return out;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final group = (data['approximateGroup'] as Map?)?.cast<String, dynamic>();
      final cands = (group?['candidate'] as List?) ?? const [];

      // Collect RxCUIs
      final ids = <String>[];
      for (final c in cands) {
        final m = (c as Map).cast<String, dynamic>();
        final id = (m['rxcui'] ?? '').toString();
        if (id.isNotEmpty) ids.add(id);
      }

      // Reduce calls: only take top 20, not 60
      final limited = ids.take(20).toList();

      // Fetch names with caching
      for (final id in limited) {
        final name = await _nameForCached(id);
        if (name.trim().isNotEmpty) {
          out.add(RxCandidate(rxcui: id, name: name.trim()));
        }
      }

      _searchCache[key] = out;
      return out;
    } catch (_) {
      _searchCache[key] = out;
      return out;
    }
  }

  Future<String> _nameForCached(String rxcui) async {
    final cached = _nameCache[rxcui];
    if (cached != null) return cached;

    final uri = Uri.parse('$_base/rxcui/$rxcui/properties.json');
    final res = await http.get(uri);
    if (res.statusCode != 200) return '';

    final data = json.decode(res.body) as Map<String, dynamic>;
    final props = (data['properties'] as Map?)?.cast<String, dynamic>();
    final name = (props?['name'] ?? '').toString();

    if (name.isNotEmpty) _nameCache[rxcui] = name;
    return name;
  }

  /// Ingredient list for a selected RxCUI (cached).
  Future<List<String>> ingredientsFor(String rxcui) async {
    if (rxcui.startsWith('LOCAL:')) return const [];

    final cached = _ingredientCache[rxcui];
    if (cached != null) return cached;

    final rawIN = await _fetchIngredientNamesByTty(rxcui, 'IN');
    if (rawIN.isNotEmpty) {
      final out = _normalizeMany(rawIN);
      _ingredientCache[rxcui] = out;
      return out;
    }

    final rawPIN = await _fetchIngredientNamesByTty(rxcui, 'PIN');
    if (rawPIN.isNotEmpty) {
      final out = _normalizeMany(rawPIN);
      _ingredientCache[rxcui] = out;
      return out;
    }

    final rawMIN = await _fetchIngredientNamesByTty(rxcui, 'MIN');
    if (rawMIN.isNotEmpty) {
      final out = _normalizeMany(rawMIN);
      _ingredientCache[rxcui] = out;
      return out;
    }

    _ingredientCache[rxcui] = const [];
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

  List<String> _normalizeMany(List<String> rawNames) {
    final all = <String>{};
    for (final r in rawNames) {
      all.addAll(_normalizeIngredients(r));
    }
    final out = all.toList()..sort();
    return out;
  }

  /// Normalize ingredient strings to match your local interaction rules.
  static List<String> _normalizeIngredients(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return const [];

    s = s.replaceAll('+', '/').replaceAll('&', '/');

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

    final cleaned = parts.map(clean).where((e) => e.isNotEmpty).toSet().toList()
      ..sort();
    return cleaned;
  }
}
