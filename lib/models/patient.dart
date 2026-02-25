class Patient {
  final int id;
  final String userId;
  final String name;
  final int age;
  final String bloodGroup;
  final String bp;
  final String disease;
  final String category;
  final String createdAt;

  const Patient({
    required this.id,
    required this.userId,
    required this.name,
    required this.age,
    required this.bloodGroup,
    required this.bp,
    required this.disease,
    required this.category,
    required this.createdAt,
  });

  factory Patient.fromRow(Map<String, Object?> row) {
    return Patient(
      id: row['id'] as int,
      userId: row['userId'].toString(),
      name: row['name'].toString(),
      age: row['age'] as int,
      bloodGroup: row['bloodGroup'].toString(),
      bp: row['bp'].toString(),
      disease: row['disease'].toString(),
      category: row['category'].toString(),
      createdAt: row['createdAt'].toString(),
    );
  }
}
