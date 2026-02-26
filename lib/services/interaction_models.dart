class InteractionRule {
  final String a; // ingredient A (generic)
  final String b; // ingredient B (generic)
  final String severity; // major | moderate | minor
  final String cause;
  final String effect;
  final String advice;

  const InteractionRule({
    required this.a,
    required this.b,
    required this.severity,
    required this.cause,
    required this.effect,
    required this.advice,
  });

  factory InteractionRule.fromJson(Map<String, dynamic> j) {
    return InteractionRule(
      a: (j['a'] ?? '').toString(),
      b: (j['b'] ?? '').toString(),
      severity: (j['severity'] ?? '').toString(),
      cause: (j['cause'] ?? '').toString(),
      effect: (j['effect'] ?? '').toString(),
      advice: (j['advice'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'a': a,
    'b': b,
    'severity': severity,
    'cause': cause,
    'effect': effect,
    'advice': advice,
  };
}

class InteractionAlert {
  final String key; // normalized unique key: a|b (sorted)
  final String title; // e.g. "Warfarin + Ibuprofen"
  final String severity;
  final String cause;
  final String effect;
  final String advice;

  /// Optional debug info (helpful when rules don't match)
  final List<String> matchedIngredients;

  const InteractionAlert({
    required this.key,
    required this.title,
    required this.severity,
    required this.cause,
    required this.effect,
    required this.advice,
    this.matchedIngredients = const [],
  });
}
