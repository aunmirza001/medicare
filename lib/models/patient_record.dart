class PatientRecord {
  final int id;
  final int patientId;
  final String createdAt;
  final String bp;
  final String condition;
  final String prescription;

  const PatientRecord({
    required this.id,
    required this.patientId,
    required this.createdAt,
    required this.bp,
    required this.condition,
    required this.prescription,
  });

  factory PatientRecord.fromRow(Map<String, Object?> row) {
    return PatientRecord(
      id: (row['id'] as int?) ?? 0,
      patientId: (row['patientId'] as int?) ?? 0,
      createdAt: (row['createdAt'] as String?) ?? '',
      bp: (row['bp'] as String?) ?? '',
      condition: (row['condition'] as String?) ?? '',
      prescription: (row['prescription'] as String?) ?? '',
    );
  }
}
