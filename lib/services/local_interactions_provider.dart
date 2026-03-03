import 'dart:convert';

import 'package:flutter/services.dart';

import 'interaction_models.dart';

class LocalInteractionsProvider {
  static final LocalInteractionsProvider instance =
      LocalInteractionsProvider._();
  LocalInteractionsProvider._();

  bool _loaded = false;
  late final Map<String, InteractionRule> _index;

  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/interactions.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final rules = (data['rules'] as List? ?? const []);

    final idx = <String, InteractionRule>{};

    for (final e in rules) {
      final r = InteractionRule.fromJson((e as Map).cast<String, dynamic>());
      final a = _norm(r.a);
      final b = _norm(r.b);
      if (a.isEmpty || b.isEmpty) continue;
      idx[_key(a, b)] = r;
    }

    _index = idx;
    _loaded = true;
  }

  List<InteractionAlert> checkByIngredients(List<String> ingredientsLower) {
    if (!_loaded) return const [];

    final ing =
        ingredientsLower.map(_norm).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();

    final out = <InteractionAlert>[];
    final seen = <String>{};

    for (var i = 0; i < ing.length; i++) {
      for (var j = i + 1; j < ing.length; j++) {
        final a = ing[i];
        final b = ing[j];

        final rule = _index[_key(a, b)];
        if (rule == null) continue;

        final ruleKey = _key(rule.a, rule.b);
        if (!seen.add(ruleKey)) continue;

        out.add(
          InteractionAlert(
            key: ruleKey,
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

    out.sort((x, y) {
      final sx = _sevRank(x.severity);
      final sy = _sevRank(y.severity);
      if (sx != sy) return sy.compareTo(sx);
      return x.title.compareTo(y.title);
    });

    return out;
  }

  static int _sevRank(String s) {
    final x = _norm(s);
    if (x == 'major') return 3;
    if (x == 'moderate') return 2;
    if (x == 'minor') return 1;
    return 0;
  }

  static String _norm(String s) {
    var x = s.trim().toLowerCase();
    if (x.isEmpty) return x;

    x = x.replaceAll('+', '/');
    x = x.replaceAll('&', '/');
    x = x.replaceAll(RegExp(r'\b(hcl|hydrochloride|sodium|potassium)\b'), '');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();

    return x;
  }

  static String _key(String a, String b) {
    final a1 = _norm(a);
    final b1 = _norm(b);
    return a1.compareTo(b1) <= 0 ? '$a1|$b1' : '$b1|$a1';
  }

  static String _cap(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t
        .split(' ')
        .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');
  }
}
