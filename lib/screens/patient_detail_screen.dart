import 'package:flutter/material.dart';

import '../models/patient.dart';

class PatientDetailScreen extends StatelessWidget {
  final Patient patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(patient.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Name: ${patient.name}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Age: ${patient.age}'),
                  Text('Blood Group: ${patient.bloodGroup}'),
                  Text('BP: ${patient.bp}'),
                  Text('Disease: ${patient.disease}'),
                  Text('Category: ${patient.category}'),
                  const SizedBox(height: 8),
                  Text('Created At: ${patient.createdAt}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
