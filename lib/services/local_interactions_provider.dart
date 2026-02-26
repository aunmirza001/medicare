import 'dart:convert';

import 'package:flutter/services.dart';

import 'interaction_models.dart';

class LocalInteractionsProvider {
  static final LocalInteractionsProvider instance =
      LocalInteractionsProvider._();
  LocalInteractionsProvider._();

  bool _loaded = false;

  /// Fast index: "a|b" -> rule (a and b normalized and sorted)
  final Map<String, InteractionRule> _index = {};

  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/interactions.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final rules = (data['rules'] as List? ?? const []);

    for (final e in rules) {
      final rule = InteractionRule.fromJson((e as Map).cast<String, dynamic>());
      if (rule.a.trim().isEmpty || rule.b.trim().isEmpty) continue;
      _index[_key(rule.a, rule.b)] = rule;
    }

    _loaded = true;
  }

  // -------------------------
  // Normalization (important)
  // -------------------------

  static String _norm(String s) {
    var x = s.trim().toLowerCase();
    if (x.isEmpty) return x;

    // strip common salts/words that break matching
    x = x.replaceAll(RegExp(r'\b(hcl|hydrochloride|sodium|potassium)\b'), '');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  static String _key(String a, String b) {
    final a1 = _norm(a);
    final b1 = _norm(b);
    if (a1.compareTo(b1) <= 0) return '$a1|$b1';
    return '$b1|$a1';
  }

  static String _cap(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1);
        })
        .join(' ');
  }

  // -------------------------
  // Public API
  // -------------------------

  /// ingredientsLower: can be mixed-case, salted, etc.
  /// This function normalizes internally.
  List<InteractionAlert> checkByIngredients(List<String> ingredientsLower) {
    if (!_loaded) return const [];

    final ing = ingredientsLower
        .map(_norm)
        .where((x) => x.isNotEmpty)
        .toSet() // dedupe
        .toList();

    final out = <InteractionAlert>[];

    for (var i = 0; i < ing.length; i++) {
      for (var j = i + 1; j < ing.length; j++) {
        final a = ing[i];
        final b = ing[j];
        final key = _key(a, b);

        final rule = _index[key];
        if (rule == null) continue;

        out.add(
          InteractionAlert(
            key: key,
            title: '${_cap(rule.a)} + ${_cap(rule.b)}',
            severity: _norm(rule.severity),
            cause: rule.cause,
            effect: rule.effect,
            advice: rule.advice,
            matchedIngredients: [a, b],
          ),
        );
      }
    }

    return out;
  }
}
