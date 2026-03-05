class InteractionRule {
  final String a;
  final String b;
  final String severity;
  final String mechanism; // ✅ NEW
  final String cause;
  final String effect;
  final String advice;

  const InteractionRule({
    required this.a,
    required this.b,
    required this.severity,
    required this.mechanism,
    required this.cause,
    required this.effect,
    required this.advice,
  });

  factory InteractionRule.fromJson(Map<String, dynamic> j) {
    return InteractionRule(
      a: (j['a'] ?? '').toString(),
      b: (j['b'] ?? '').toString(),
      severity: (j['severity'] ?? '').toString(),
      mechanism: (j['mechanism'] ?? '').toString(), // ✅
      cause: (j['cause'] ?? '').toString(),
      effect: (j['effect'] ?? '').toString(),
      advice: (j['advice'] ?? '').toString(),
    );
  }
}

class InteractionAlert {
  final String key;
  final String title;
  final String severity;
  final String mechanism; // ✅ NEW
  final String cause;
  final String effect;
  final String advice;
  final List<String> matchedIngredients;

  const InteractionAlert({
    required this.key,
    required this.title,
    required this.severity,
    required this.mechanism,
    required this.cause,
    required this.effect,
    required this.advice,
    this.matchedIngredients = const [],
  });
}
