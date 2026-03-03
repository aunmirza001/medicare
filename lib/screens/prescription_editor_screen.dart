import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../models/patient.dart';
import '../services/interaction_models.dart';
import '../services/local_interactions_provider.dart';
import '../services/rxnorm_service.dart';

class MedicineEntry {
  final String rxcui;
  final String name;

  List<String> ingredients;
  String strength;
  String dose;
  String frequency;
  String duration;
  String instructions;

  MedicineEntry({
    required this.rxcui,
    required this.name,
    required this.ingredients,
    this.strength = '',
    this.dose = '1-0-1',
    this.frequency = 'BD',
    this.duration = '5 days',
    this.instructions = 'After food',
  });
}

class PrescriptionEditorScreen extends StatefulWidget {
  final Patient patient;
  final String initialBp;
  final String initialCondition;

  const PrescriptionEditorScreen({
    super.key,
    required this.patient,
    required this.initialBp,
    required this.initialCondition,
  });

  @override
  State<PrescriptionEditorScreen> createState() =>
      _PrescriptionEditorScreenState();
}

class _PrescriptionEditorScreenState extends State<PrescriptionEditorScreen> {
  final _rxnorm = RxnormService();

  final _bpC = TextEditingController();
  final _condC = TextEditingController();
  final _freeTextC = TextEditingController();

  final _searchC = TextEditingController();
  Timer? _debounce;

  bool _searching = false;
  bool _interactionLoading = false;

  List<RxCandidate> _suggestions = const [];

  final List<MedicineEntry> _stagedMeds = [];
  final List<MedicineEntry> _confirmedMeds = [];

  final List<File> _pickedFiles = [];

  bool _saving = false;
  bool _rulesLoaded = false;

  bool _interactionsComputed = false;
  List<InteractionAlert> _alerts = const [];
  final Set<String> _ackMajorKeys = {};

  static const _doseOptions = <String>[
    '1-0-1',
    '1-1-1',
    '0-0-1',
    '1-0-0',
    '0-1-0',
    '1/2-0-1/2',
  ];
  static const _freqOptions = <String>['OD', 'BD', 'TDS', 'QID', 'HS', 'PRN'];
  static const _durationOptions = <String>[
    '3 days',
    '5 days',
    '7 days',
    '10 days',
    '2 weeks',
    '1 month',
  ];
  static const _instrOptions = <String>[
    'After food',
    'Before food',
    'At night',
    'Morning',
    'Empty stomach',
  ];

  @override
  void initState() {
    super.initState();
    _bpC.text = widget.initialBp;
    _condC.text = widget.initialCondition;

    _searchC.addListener(_onSearchChanged);
    _initRules();
  }

  Future<void> _initRules() async {
    await LocalInteractionsProvider.instance.load();
    if (!mounted) return;
    setState(() => _rulesLoaded = true);
  }

  @override
  void dispose() {
    _debounce?.cancel();

    _bpC.dispose();
    _condC.dispose();
    _freeTextC.dispose();

    _searchC.removeListener(_onSearchChanged);
    _searchC.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    // Rebuild for suffixIcon (clear/spinner) immediately.
    if (mounted) setState(() {});

    _debounce?.cancel();
    final q = _searchC.text.trim();

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;

      if (q.isEmpty) {
        setState(() {
          _suggestions = const [];
          _searching = false;
        });
        return;
      }

      setState(() => _searching = true);

      try {
        // Keep this high to show lots of prefix matches (RxNorm side permitting).
        final res = await _rxnorm.search(q, maxEntries: 250);
        if (!mounted) return;
        setState(() {
          _suggestions = res;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  String _nowIsoLocal() => DateTime.now().toIso8601String();

  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  Future<File> _persistPickedImage(XFile xf) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'patient_files'));
    if (!await folder.exists()) await folder.create(recursive: true);

    final ext = p.extension(xf.path).isEmpty ? '.jpg' : p.extension(xf.path);
    final fileName =
        'p${widget.patient.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final targetPath = p.join(folder.path, fileName);

    return File(xf.path).copy(targetPath);
  }

  Future<void> _pickFrom(ImageSource source) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(source: source, imageQuality: 85);
    if (xf == null) return;

    final saved = await _persistPickedImage(xf);
    if (!mounted) return;
    setState(() => _pickedFiles.add(saved));
  }

  Future<void> _openPickSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickFrom(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickFrom(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removePickedAt(int i) => setState(() => _pickedFiles.removeAt(i));

  bool _alreadyAdded(String rxcui) {
    return _stagedMeds.any((m) => m.rxcui == rxcui) ||
        _confirmedMeds.any((m) => m.rxcui == rxcui);
  }

  Future<void> _stageMedicine(RxCandidate c) async {
    if (_alreadyAdded(c.rxcui)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine already added.')),
      );
      return;
    }

    List<String> ingredients = const [];
    try {
      if (c.isLocal) {
        ingredients = c.ingredientsHint;
      } else {
        ingredients = await _rxnorm.ingredientsFor(c.rxcui);
      }
    } catch (_) {
      ingredients = const [];
    }

    if (!mounted) return;

    setState(() {
      _stagedMeds.add(
        MedicineEntry(rxcui: c.rxcui, name: c.name, ingredients: ingredients),
      );
      _searchC.clear();
      _suggestions = const [];
      _interactionsComputed = false;
      _alerts = const [];
      _ackMajorKeys.clear();
    });
  }

  void _removeStagedAt(int i) {
    setState(() {
      _stagedMeds.removeAt(i);
      _interactionsComputed = false;
      _alerts = const [];
      _ackMajorKeys.clear();
    });
  }

  void _removeConfirmedAt(int i) {
    setState(() => _confirmedMeds.removeAt(i));
    _syncConfirmedToPrescriptionText();
  }

  List<String> _duplicateIngredientWarnings(List<MedicineEntry> meds) {
    final seen = <String, int>{};
    final warnings = <String>[];

    for (final m in meds) {
      for (final ing in m.ingredients) {
        final k = ing.trim().toLowerCase();
        if (k.isEmpty) continue;
        seen[k] = (seen[k] ?? 0) + 1;
      }
    }

    for (final e in seen.entries) {
      if (e.value > 1) {
        warnings.add('Duplicate ingredient: ${e.key} (${e.value} times)');
      }
    }

    return warnings;
  }

  Future<void> _computeInteractions() async {
    if (!_rulesLoaded) return;
    if (_interactionLoading) return;

    setState(() {
      _interactionLoading = true;
      _interactionsComputed = false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final ingredients = _stagedMeds
        .expand((m) => m.ingredients)
        .map((x) => x.toLowerCase().trim())
        .where((x) => x.isNotEmpty)
        .toList();

    final alerts = LocalInteractionsProvider.instance.checkByIngredients(
      ingredients,
    );

    if (!mounted) return;

    final majorKeys = alerts
        .where((a) => a.severity.toLowerCase() == 'major')
        .map((a) => a.key)
        .toSet();
    _ackMajorKeys.removeWhere((k) => !majorKeys.contains(k));

    setState(() {
      _alerts = alerts;
      _interactionsComputed = true;
      _interactionLoading = false;
    });

    if (_stagedMeds.isNotEmpty && ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingredients not found for selected medicines. Use Local matches or improve ingredient mapping.',
          ),
        ),
      );
    }
  }

  bool get _hasUnackMajor {
    final majors = _alerts
        .where((a) => a.severity.toLowerCase() == 'major')
        .map((a) => a.key)
        .toSet();
    if (majors.isEmpty) return false;
    return majors.any((k) => !_ackMajorKeys.contains(k));
  }

  void _confirmAndAddToPrescription() {
    if (_stagedMeds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No staged medicines to confirm.')),
      );
      return;
    }
    if (_hasUnackMajor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acknowledge major interactions first.')),
      );
      return;
    }

    setState(() {
      _confirmedMeds.addAll(_stagedMeds);
      _stagedMeds.clear();
      _alerts = const [];
      _ackMajorKeys.clear();
      _interactionsComputed = false;
    });

    _syncConfirmedToPrescriptionText();
  }

  void _syncConfirmedToPrescriptionText() {
    final buf = StringBuffer();

    if (_confirmedMeds.isNotEmpty) {
      buf.writeln('Medicines:');
      for (final m in _confirmedMeds) {
        final s = m.strength.trim().isEmpty ? '' : ' ${m.strength.trim()}';
        buf.writeln(
          '- ${m.name}$s | ${m.dose} | ${m.frequency} | ${m.duration} | ${m.instructions}',
        );
      }
      buf.writeln();
    }

    final existingNotes = _extractNotesOnly(_freeTextC.text);
    if (existingNotes.trim().isNotEmpty) buf.writeln(existingNotes.trim());

    _freeTextC.text = buf.toString().trimRight();
    _freeTextC.selection = TextSelection.fromPosition(
      TextPosition(offset: _freeTextC.text.length),
    );
  }

  String _extractNotesOnly(String full) {
    final t = full.trim();
    if (!t.toLowerCase().startsWith('medicines:')) return t;

    final lines = t.split('\n');
    var i = 0;
    if (i < lines.length) i++; // skip "Medicines:"
    while (i < lines.length) {
      final ln = lines[i].trimLeft();
      if (ln.startsWith('- ')) {
        i++;
        continue;
      }
      break;
    }
    while (i < lines.length && lines[i].trim().isEmpty) i++;
    return lines.sublist(i).join('\n');
  }

  Future<void> _saveRecord() async {
    if (_saving) return;

    if (_stagedMeds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm staged medicines before saving.')),
      );
      return;
    }

    final bp = _bpC.text.trim();
    final condition = _condC.text.trim();
    final prescription = _freeTextC.text.trim();

    if (bp.isEmpty &&
        condition.isEmpty &&
        prescription.isEmpty &&
        _pickedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add BP, condition, prescription or attachments.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = await AppDatabase.instance.database;

      final recordId = await db.insert('patient_records', {
        'patientId': widget.patient.id,
        'createdAt': _nowIsoLocal(),
        'bp': bp,
        'condition': condition,
        'prescription': prescription,
      });

      for (final f in _pickedFiles) {
        await db.insert('record_attachments', {
          'recordId': recordId,
          'filePath': f.path,
          'createdAt': _nowIsoLocal(),
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save prescription record.')),
      );
    }
  }

  Color _sevColor(String sev) {
    final s = sev.toLowerCase();
    if (s == 'major') return Colors.red;
    if (s == 'moderate') return Colors.orange;
    return Colors.blueGrey;
  }

  String _sevLabel(String sev) {
    final s = sev.toLowerCase();
    if (s == 'major') return 'Major';
    if (s == 'moderate') return 'Moderate';
    return 'Minor';
  }

  Widget _doseGrid({
    required MedicineEntry m,
    required double maxWidth,
  }) {
    // FIX for overflow: use 2-column responsive grid (instead of 4 fixed 170px).
    const gap = 10.0;
    final colWidth = (maxWidth - gap) / 2;

    Widget field(Widget child) => SizedBox(width: colWidth, child: child);

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        field(
          DropdownButtonFormField<String>(
            value: m.dose,
            isExpanded: true,
            items: _doseOptions
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => m.dose = v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Dose',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        field(
          DropdownButtonFormField<String>(
            value: m.frequency,
            isExpanded: true,
            items: _freqOptions
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => m.frequency = v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Frequency',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        field(
          DropdownButtonFormField<String>(
            value: m.duration,
            isExpanded: true,
            items: _durationOptions
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => m.duration = v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Duration',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        field(
          DropdownButtonFormField<String>(
            value: m.instructions,
            isExpanded: true,
            items: _instrOptions
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => m.instructions = v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Instructions',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p0 = widget.patient;
    final stagedDupWarnings = _duplicateIngredientWarnings(_stagedMeds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveRecord,
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _chip('Name: ${p0.name}', Icons.person_outline),
                    _chip('Age: ${p0.age}', Icons.cake_outlined),
                    _chip('Blood: ${p0.bloodGroup}', Icons.bloodtype_outlined),
                    _chip('Category: ${p0.category}',
                        Icons.local_hospital_outlined),
                    _chip(
                      'BP: ${_bpC.text.trim().isEmpty ? '-' : _bpC.text.trim()}',
                      Icons.monitor_heart_outlined,
                    ),
                    _chip(
                      'Condition: ${_condC.text.trim().isEmpty ? '-' : _condC.text.trim()}',
                      Icons.medical_information_outlined,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _bpC,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'BP',
                        prefixIcon: Icon(Icons.monitor_heart_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _condC,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Condition',
                        prefixIcon: Icon(Icons.medical_information_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Medicine Search (RxNorm)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _searchC,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        labelText: 'Search medicine (e.g., panadol, tryptanol)',
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (_searchC.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchC.clear();
                                      setState(() => _suggestions = const []);
                                    },
                                    icon: const Icon(Icons.clear),
                                  )),
                      ),
                    ),

                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                          itemBuilder: (_, i) {
                            final s = _suggestions[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                s.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('RxCUI: ${s.rxcui}'),
                              onTap: () => _stageMedicine(s),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Staged Medicines',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_stagedMeds.isEmpty || !_rulesLoaded)
                              ? null
                              : _computeInteractions,
                          icon: _interactionLoading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.rule),
                          label: Text(
                            _interactionLoading
                                ? 'Checking...'
                                : 'Show interactions',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    if (_stagedMeds.isEmpty)
                      Text(
                        'No staged medicines yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ..._stagedMeds.asMap().entries.map((e) {
                        final i = e.key;
                        final m = e.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _removeStagedAt(i),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Ingredients: ${m.ingredients.isEmpty ? '(unknown)' : m.ingredients.join(', ')}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                TextFormField(
                                  key: ValueKey('strength_${m.rxcui}'),
                                  initialValue: m.strength,
                                  onChanged: (v) => m.strength = v,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Strength (optional)',
                                  ),
                                ),

                                const SizedBox(height: 10),

                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return _doseGrid(
                                      m: m,
                                      maxWidth: constraints.maxWidth,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                    if (_interactionsComputed) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Interactions / Safety',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),

                            if (stagedDupWarnings.isNotEmpty)
                              ...stagedDupWarnings.map((w) => Text('• $w')),

                            if (stagedDupWarnings.isNotEmpty &&
                                _alerts.isNotEmpty)
                              const SizedBox(height: 10),

                            if (_alerts.isEmpty)
                              Text(
                                'No interactions found in local JSON rules for these ingredients.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              )
                            else
                              ..._alerts.map((a) {
                                final sev = a.severity.toLowerCase();
                                final isMajor = sev == 'major';
                                final acknowledged =
                                    _ackMajorKeys.contains(a.key);

                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                a.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _sevColor(a.severity)
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: _sevColor(a.severity),
                                                ),
                                              ),
                                              child: Text(
                                                _sevLabel(a.severity),
                                                style: TextStyle(
                                                  color: _sevColor(a.severity),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text('Cause: ${a.cause}'),
                                        const SizedBox(height: 6),
                                        Text('Effect: ${a.effect}'),
                                        const SizedBox(height: 6),
                                        Text('Advice: ${a.advice}'),
                                        if (isMajor) ...[
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            onPressed: acknowledged
                                                ? null
                                                : () => setState(() =>
                                                    _ackMajorKeys.add(a.key)),
                                            child: Text(
                                              acknowledged
                                                  ? 'Acknowledged'
                                                  : 'Acknowledge & continue',
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed:
                          _stagedMeds.isEmpty ? null : _confirmAndAddToPrescription,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirm & add to prescription'),
                    ),

                    if (_confirmedMeds.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Confirmed Medicines',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      ..._confirmedMeds.asMap().entries.map((e) {
                        final i = e.key;
                        final m = e.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeConfirmedAt(i),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Prescription Writing Area',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _freeTextC,
                      minLines: 8,
                      maxLines: 16,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Write clinical notes and prescription here...',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openPickSheet,
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              _pickedFiles.isEmpty
                                  ? 'Attach photo/report'
                                  : 'Attachments (${_pickedFiles.length})',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _syncConfirmedToPrescriptionText,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Rebuild text'),
                        ),
                      ],
                    ),
                    if (_pickedFiles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pickedFiles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final f = _pickedFiles[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    f,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: InkWell(
                                    onTap: () => _removePickedAt(i),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }
}