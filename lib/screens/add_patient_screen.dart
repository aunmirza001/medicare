import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _age = TextEditingController();
  final _bp = TextEditingController();
  final _disease = TextEditingController();

  String _bloodGroup = '';
  String _category = 'Dermatology';

  bool _loading = false;
  String? _error;

  static const _bloodGroups = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  static const _categories = <String>['Dermatology', 'OPD'];

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _bp.dispose();
    _disease.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) {
        throw Exception('Not logged in');
      }

      final db = await AppDatabase.instance.database;

      await db.insert('patients', {
        'userId': uid,
        'name': _name.text.trim(),
        'age': int.parse(_age.text.trim()),
        'bloodGroup': _bloodGroup.trim(),
        'bp': _bp.text.trim(),
        'disease': _disease.text.trim(),
        'category': _category,
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloodController = TextEditingController(text: _bloodGroup);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Patient')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Patient Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        final n = int.tryParse(s);
                        if (s.isEmpty) return 'Required';
                        if (n == null || n <= 0 || n > 150)
                          return 'Invalid age';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: _categories
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue value) {
                        final q = value.text.trim().toUpperCase();
                        if (q.isEmpty) return _bloodGroups;
                        return _bloodGroups.where((e) => e.startsWith(q));
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            controller.text = bloodController.text;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Blood Group',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                              onChanged: (v) {
                                _bloodGroup = v.trim().toUpperCase();
                              },
                            );
                          },
                      onSelected: (value) {
                        setState(() {
                          _bloodGroup = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bp,
                      keyboardType: TextInputType.number,
                      inputFormatters: [BpSlashFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'BP (e.g. 120/80)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _disease,
                      decoration: const InputDecoration(
                        labelText: 'Disease',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  if (!_bloodGroups.contains(_bloodGroup)) {
                                    setState(
                                      () =>
                                          _error = 'Select a valid blood group',
                                    );
                                    return;
                                  }
                                  _save();
                                }
                              },
                        child: _loading
                            ? const CircularProgressIndicator()
                            : const Text('Confirm Add Patient'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BpSlashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    String out;
    if (digitsOnly.length <= 3) {
      out = digitsOnly;
    } else {
      final tail = digitsOnly.substring(3, digitsOnly.length.clamp(3, 6));
      out = '${digitsOnly.substring(0, 3)}/$tail';
    }

    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}
