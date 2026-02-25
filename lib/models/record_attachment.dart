class RecordAttachment {
  final int id;
  final int recordId;
  final String filePath;
  final String createdAt;

  const RecordAttachment({
    required this.id,
    required this.recordId,
    required this.filePath,
    required this.createdAt,
  });

  factory RecordAttachment.fromRow(Map<String, Object?> row) {
    return RecordAttachment(
      id: (row['id'] as int?) ?? 0,
      recordId: (row['recordId'] as int?) ?? 0,
      filePath: (row['filePath'] as String?) ?? '',
      createdAt: (row['createdAt'] as String?) ?? '',
    );
  }
}
