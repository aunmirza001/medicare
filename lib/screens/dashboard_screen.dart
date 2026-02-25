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

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searching = false;
  String _searchQuery = '';

  String? _filterCategory;
  DateTimeRange? _dateRange;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  static const _categories = <String>['OPD', 'Dermatology'];

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      final v = _searchController.text;
      if (v == _searchQuery) return;
      setState(() {
        _searchQuery = v;
        _applyFilters();
        _selectedIds.removeWhere((id) => !_patients.any((p) => p.id == id));
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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

  DateTime? _parseCreatedAt(String v) {
    final dt = DateTime.tryParse(v);
    if (dt == null) return null;
    return dt.isUtc ? dt.toLocal() : dt;
  }

  void _applyFilters() {
    var list = List<Patient>.from(_allPatients);

    if (_filterCategory != null && _filterCategory!.isNotEmpty) {
      list = list.where((p) => p.category == _filterCategory).toList();
    }

    if (_dateRange != null) {
      final start = DateTime(
        _dateRange!.start.year,
        _dateRange!.start.month,
        _dateRange!.start.day,
      );
      final endExclusive = DateTime(
        _dateRange!.end.year,
        _dateRange!.end.month,
        _dateRange!.end.day,
      ).add(const Duration(days: 1));

      list = list.where((p) {
        final dt = _parseCreatedAt(p.createdAt);
        if (dt == null) return false;
        return !dt.isBefore(start) && dt.isBefore(endExclusive);
      }).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((p) {
        final name = p.name.toLowerCase();
        return name.startsWith(q) || name.contains(q);
      }).toList();
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

  void _startSearch() {
    if (_selectionMode) return;
    setState(() {
      _searching = true;
    });
    _searchFocus.requestFocus();
  }

  void _stopSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _searchQuery = '';
      _applyFilters();
      _selectedIds.removeWhere((id) => !_patients.any((p) => p.id == id));
    });
    _searchFocus.unfocus();
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _dateRangeLabel() {
    final r = _dateRange;
    if (r == null) return 'Any date';
    return '${_fmtDate(r.start)} → ${_fmtDate(r.end)}';
  }

  Future<void> _pickDateRange() async {
    if (_selectionMode) return;

    final now = DateTime.now();
    final initial =
        _dateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _dateRange = picked;
      _applyFilters();
      _selectedIds.removeWhere((id) => !_patients.any((p) => p.id == id));
    });
  }

  Future<void> _openFilters() async {
    if (_selectionMode) return;

    final res = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        selectedCategory: _filterCategory,
        selectedRange: _dateRange,
      ),
    );

    if (res == null) return;

    setState(() {
      _filterCategory = res.category;
      _dateRange = res.range;
      _applyFilters();
      _selectedIds.removeWhere((id) => !_patients.any((p) => p.id == id));
    });
  }

  Widget _buildTopChips() {
    final cat = _filterCategory;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: cat == null || cat.isEmpty,
            onSelected: (_) {
              setState(() {
                _filterCategory = null;
                _applyFilters();
                _selectedIds.removeWhere(
                  (id) => !_patients.any((p) => p.id == id),
                );
              });
            },
          ),
          const SizedBox(width: 8),
          ..._categories.map((c) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c),
                selected: cat == c,
                onSelected: (_) {
                  setState(() {
                    _filterCategory = c;
                    _applyFilters();
                    _selectedIds.removeWhere(
                      (id) => !_patients.any((p) => p.id == id),
                    );
                  });
                },
              ),
            );
          }),
          const SizedBox(width: 4),
          ActionChip(
            label: Text(_dateRangeLabel()),
            avatar: const Icon(Icons.calendar_today, size: 18),
            onPressed: _pickDateRange,
          ),
          const SizedBox(width: 8),
          if (_filterCategory != null ||
              _dateRange != null ||
              _searchQuery.trim().isNotEmpty)
            ActionChip(
              label: const Text('Clear'),
              avatar: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() {
                  _filterCategory = null;
                  _dateRange = null;
                  _searchController.clear();
                  _searchQuery = '';
                  _applyFilters();
                  _selectedIds.removeWhere(
                    (id) => !_patients.any((p) => p.id == id),
                  );
                });
              },
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final allSelected =
        _patients.isNotEmpty && _selectedIds.length == _patients.length;

    return AppBar(
      leading: _selectionMode
          ? IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close),
            )
          : (_searching
                ? IconButton(
                    onPressed: _stopSearch,
                    icon: const Icon(Icons.arrow_back),
                  )
                : null),
      title: _selectionMode
          ? Text('${_selectedIds.length} selected')
          : (_searching
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search patients...',
                      border: InputBorder.none,
                    ),
                  )
                : const Text('Dashboard')),
      actions: [
        if (!_selectionMode && !_searching)
          IconButton(onPressed: _startSearch, icon: const Icon(Icons.search)),
        if (!_selectionMode && !_searching)
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
        if (!_selectionMode && !_searching)
          TextButton(
            onPressed: () async {
              await _auth.signOut();
            },
            child: const Text('Logout'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPatient,
        child: const Icon(Icons.person_add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTopChips(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _patients.isEmpty
                          ? const Center(child: Text('No patients found'))
                          : ListView.separated(
                              itemCount: _patients.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
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
                                                  : Icons
                                                        .radio_button_unchecked,
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
                  ],
                ),
              ),
      ),
    );
  }
}

class _FilterResult {
  final String? category;
  final DateTimeRange? range;

  const _FilterResult({required this.category, required this.range});
}

class _FilterSheet extends StatefulWidget {
  final String? selectedCategory;
  final DateTimeRange? selectedRange;

  const _FilterSheet({
    required this.selectedCategory,
    required this.selectedRange,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _category;
  DateTimeRange? _range;

  static const _categories = <String>['OPD', 'Dermatology'];

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _range = widget.selectedRange;
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _rangeLabel() {
    final r = _range;
    if (r == null) return 'Any date';
    return '${_fmtDate(r.start)} → ${_fmtDate(r.end)}';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial =
        _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _range = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
            InkWell(
              onTap: _pickRange,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Date range',
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_rangeLabel())),
                    const Icon(Icons.calendar_today, size: 18),
                  ],
                ),
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
                      ).pop(const _FilterResult(category: null, range: null));
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
                      ).pop(_FilterResult(category: _category, range: _range));
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
