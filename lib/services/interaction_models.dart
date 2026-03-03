class InteractionRule {
  final String a; // ingredient A
  final String b; // ingredient B
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
}

class InteractionAlert {
  final String key; // normalized pair key
  final String title; // display title
  final String severity; // major | moderate | minor
  final String cause;
  final String effect;
  final String advice;
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
