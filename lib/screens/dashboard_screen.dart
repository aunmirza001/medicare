import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../database/app_database.dart';
import '../models/patient.dart';
import 'add_patient_screen.dart';
import 'patient_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _auth = AuthService();

  List<Patient> _allPatients = const [];
  List<Patient> _patients = const [];
  bool _loading = true;

  final Set<int> _selectedIds = {};

  String _searchQuery = '';
  String? _filterCategory;
  int? _filterMonth;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final db = await AppDatabase.instance.database;

    final data = await db.query(
      'patients',
      where: 'userId = ?',
      whereArgs: [uid],
      orderBy: 'createdAt DESC',
    );

    if (!mounted) return;

    final list = data.map((e) => Patient.fromRow(e)).toList();

    setState(() {
      _allPatients = list;
      _applyFilters();
      _selectedIds.removeWhere((id) => !_patients.any((p) => p.id == id));
      _loading = false;
    });
  }

  void _applyFilters() {
    var list = List<Patient>.from(_allPatients);

    if (_filterCategory != null && _filterCategory!.isNotEmpty) {
      list = list.where((p) => p.category == _filterCategory).toList();
    }

    if (_filterMonth != null) {
      list = list.where((p) {
        final dt = DateTime.tryParse(p.createdAt);
        if (dt == null) return false;
        return dt.month == _filterMonth;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    _patients = list;
  }

  Future<void> _openAddPatient() async {
    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddPatientScreen()));
    if (ok == true) _load();
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_patients.map((e) => e.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final db = await AppDatabase.instance.database;

    final ids = _selectedIds.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final args = <Object?>[uid, ...ids];

    await db.delete(
      'patients',
      where: 'userId = ? AND id IN ($placeholders)',
      whereArgs: args,
    );

    _clearSelection();
    _load();
  }

  Future<void> _deleteOne(int id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final db = await AppDatabase.instance.database;

    await db.delete(
      'patients',
      where: 'userId = ? AND id = ?',
      whereArgs: [uid, id],
    );

    setState(() {
      _selectedIds.remove(id);
    });

    _load();
  }

  Future<void> _openSearch() async {
    final result = await showSearch<String?>(
      context: context,
      delegate: PatientSearchDelegate(initial: _searchQuery),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _searchQuery = result;
        _applyFilters();
      });
    }
  }

  Future<void> _openFilters() async {
    final res = await showModalBottomSheet<_FilterResult>(
      context: context,
      builder: (_) => _FilterSheet(
        selectedCategory: _filterCategory,
        selectedMonth: _filterMonth,
      ),
    );

    if (res == null) return;

    setState(() {
      _filterCategory = res.category;
      _filterMonth = res.month;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _patients.isNotEmpty && _selectedIds.length == _patients.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '${_selectedIds.length} selected' : 'Dashboard',
        ),
        leading: _selectionMode
            ? IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        actions: [
          if (!_selectionMode)
            IconButton(onPressed: _openSearch, icon: const Icon(Icons.search)),
          if (!_selectionMode)
            IconButton(
              onPressed: _openFilters,
              icon: const Icon(Icons.filter_list),
            ),
          if (_selectionMode)
            IconButton(
              onPressed: allSelected ? _clearSelection : _selectAll,
              icon: const Icon(Icons.select_all),
            ),
          if (_selectionMode)
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete),
            ),
          if (!_selectionMode)
            TextButton(
              onPressed: () async {
                await _auth.signOut();
              },
              child: const Text('Logout'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPatient,
        child: const Icon(Icons.person_add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: _patients.isEmpty
                    ? const Center(child: Text('No patients found'))
                    : ListView.separated(
                        itemCount: _patients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final p = _patients[index];
                          final selected = _selectedIds.contains(p.id);

                          return InkWell(
                            onLongPress: () => _toggleSelect(p.id),
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelect(p.id);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PatientDetailScreen(patient: p),
                                  ),
                                );
                              }
                            },
                            child: Card(
                              child: ListTile(
                                leading: _selectionMode
                                    ? Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                      )
                                    : const Icon(Icons.person),
                                title: Text(p.name),
                                subtitle: Text(
                                  'Category: ${p.category} • Age: ${p.age} • Blood: ${p.bloodGroup} • BP: ${p.bp}\nDisease: ${p.disease}',
                                ),
                                trailing: _selectionMode && selected
                                    ? IconButton(
                                        onPressed: () => _deleteOne(p.id),
                                        icon: const Icon(Icons.delete),
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

class PatientSearchDelegate extends SearchDelegate<String?> {
  final String initial;

  PatientSearchDelegate({required this.initial}) {
    query = initial;
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    close(context, query.trim());
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _FilterResult {
  final String? category;
  final int? month;

  const _FilterResult({required this.category, required this.month});
}

class _FilterSheet extends StatefulWidget {
  final String? selectedCategory;
  final int? selectedMonth;

  const _FilterSheet({
    required this.selectedCategory,
    required this.selectedMonth,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _category;
  int? _month;

  static const _categories = <String>['Dermatology', 'OPD'];

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _month = widget.selectedMonth;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Filters',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Categories'),
                ),
                ..._categories.map(
                  (e) => DropdownMenuItem(value: e, child: Text(e)),
                ),
              ],
              onChanged: (v) => setState(() => _category = v),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Category',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _month,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Months')),
                ...List.generate(12, (i) => i + 1).map(
                  (m) => DropdownMenuItem(value: m, child: Text('Month $m')),
                ),
              ],
              onChanged: (v) => setState(() => _month = v),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Month',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(const _FilterResult(category: null, month: null));
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(_FilterResult(category: _category, month: _month));
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
