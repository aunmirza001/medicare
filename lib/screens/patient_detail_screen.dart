import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../models/patient.dart';
import '../models/patient_record.dart';
import '../models/record_attachment.dart';
import 'prescription_editor_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  bool _loading = true;

  List<PatientRecord> _allRecords = const [];
  List<PatientRecord> _records = const [];
  Map<int, List<RecordAttachment>> _attachmentsByRecordId = {};

  final _bpController = TextEditingController();
  final _conditionController = TextEditingController();
  final _rxController = TextEditingController();

  final List<File> _pickedFiles = [];
  bool _saving = false;

  String _recordSearchQuery = '';
  DateTimeRange? _recordDateRange;

  @override
  void initState() {
    super.initState();
    _bpController.text = widget.patient.bp;
    _conditionController.text = widget.patient.disease;
    _load();
  }

  @override
  void dispose() {
    _bpController.dispose();
    _conditionController.dispose();
    _rxController.dispose();
    super.dispose();
  }

  DateTime? _parseCreatedAt(String v) {
    final dt = DateTime.tryParse(v);
    if (dt == null) return null;
    return dt.isUtc ? dt.toLocal() : dt;
  }

  String _fmtDateTime(String iso) {
    final dt = _parseCreatedAt(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    return '$y-$m-$d  $hh:$mm';
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _nowIsoLocal() => DateTime.now().toIso8601String();

  PatientRecord? get _latestRecord =>
      _allRecords.isEmpty ? null : _allRecords.first;

  Future<void> _load() async {
    setState(() => _loading = true);

    final db = await AppDatabase.instance.database;

    final recRows = await db.query(
      'patient_records',
      where: 'patientId = ?',
      whereArgs: [widget.patient.id],
      orderBy: 'createdAt DESC',
    );

    final records = recRows.map((e) => PatientRecord.fromRow(e)).toList();

    final attRows = await db.query(
      'record_attachments',
      where: records.isEmpty
          ? '1 = 0'
          : 'recordId IN (${List.filled(records.length, '?').join(',')})',
      whereArgs: records.isEmpty ? [] : records.map((r) => r.id).toList(),
      orderBy: 'createdAt DESC',
    );

    final attachments = attRows
        .map((e) => RecordAttachment.fromRow(e))
        .toList();

    final map = <int, List<RecordAttachment>>{};
    for (final a in attachments) {
      map.putIfAbsent(a.recordId, () => []);
      map[a.recordId]!.add(a);
    }

    if (!mounted) return;

    setState(() {
      _allRecords = records;
      _attachmentsByRecordId = map;

      final latest = _latestRecord;
      if (latest != null) {
        if (_bpController.text.trim().isEmpty) _bpController.text = latest.bp;
        if (_conditionController.text.trim().isEmpty) {
          _conditionController.text = latest.condition;
        }
      }

      _applyRecordFilters();
      _loading = false;
    });
  }

  void _applyRecordFilters() {
    var list = List<PatientRecord>.from(_allRecords);

    if (_recordDateRange != null) {
      final start = DateTime(
        _recordDateRange!.start.year,
        _recordDateRange!.start.month,
        _recordDateRange!.start.day,
      );
      final endExclusive = DateTime(
        _recordDateRange!.end.year,
        _recordDateRange!.end.month,
        _recordDateRange!.end.day,
      ).add(const Duration(days: 1));

      list = list.where((r) {
        final dt = _parseCreatedAt(r.createdAt);
        if (dt == null) return false;
        return !dt.isBefore(start) && dt.isBefore(endExclusive);
      }).toList();
    }

    if (_recordSearchQuery.trim().isNotEmpty) {
      final q = _recordSearchQuery.trim().toLowerCase();
      list = list.where((r) {
        final idStr = r.id.toString();
        final cond = r.condition.toLowerCase();
        final rx = r.prescription.toLowerCase();
        final dateStr = r.createdAt.toLowerCase();
        return idStr.contains(q) ||
            cond.contains(q) ||
            rx.contains(q) ||
            dateStr.contains(q);
      }).toList();
    }

    _records = list;
  }

  Future<File> _persistPickedImage(XFile xf) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'patient_files'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final ext = p.extension(xf.path).isEmpty ? '.jpg' : p.extension(xf.path);
    final fileName =
        'p${widget.patient.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final targetPath = p.join(folder.path, fileName);

    final src = File(xf.path);
    return src.copy(targetPath);
  }

  Future<void> _pickFrom(ImageSource source) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(source: source, imageQuality: 85);
    if (xf == null) return;

    final saved = await _persistPickedImage(xf);

    if (!mounted) return;
    setState(() {
      _pickedFiles.add(saved);
    });
  }

  Future<void> _openPickSheetForNewRecord() async {
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

  Future<void> _removePickedAt(int index) async {
    setState(() {
      _pickedFiles.removeAt(index);
    });
  }

  Future<void> _saveNewRecord() async {
    final bp = _bpController.text.trim();
    final condition = _conditionController.text.trim();
    final rx = _rxController.text.trim();

    if (bp.isEmpty && condition.isEmpty && rx.isEmpty && _pickedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add BP, condition, prescription, or an attachment.'),
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
        'prescription': rx,
      });

      for (final f in _pickedFiles) {
        await db.insert('record_attachments', {
          'recordId': recordId,
          'filePath': f.path,
          'createdAt': _nowIsoLocal(),
        });
      }

      if (!mounted) return;

      setState(() {
        _rxController.clear();
        _pickedFiles.clear();
        _saving = false;
      });

      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save record.')));
    }
  }

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

  Widget _headerCard() {
    final p0 = widget.patient;
    final latest = _latestRecord;

    final lastBp = (latest?.bp.trim().isNotEmpty ?? false) ? latest!.bp : p0.bp;
    final lastCondition = (latest?.condition.trim().isNotEmpty ?? false)
        ? latest!.condition
        : p0.disease;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p0.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _chip('Age: ${p0.age}', Icons.cake_outlined),
                _chip('Blood: ${p0.bloodGroup}', Icons.bloodtype_outlined),
                _chip(
                  'Category: ${p0.category}',
                  Icons.local_hospital_outlined,
                ),
                _chip('Last BP: $lastBp', Icons.monitor_heart_outlined),
                _chip(
                  'Last Condition: $lastCondition',
                  Icons.medical_information_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPrescriptionEditor() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PrescriptionEditorScreen(
          patient: widget.patient,
          initialBp: _bpController.text.trim(),
          initialCondition: _conditionController.text.trim(),
        ),
      ),
    );

    if (ok == true) {
      await _load();
    }
  }

  Widget _newRecordComposer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Visit Record',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bpController,
              decoration: const InputDecoration(
                labelText: 'BP',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.monitor_heart_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _conditionController,
              decoration: const InputDecoration(
                labelText: 'Condition',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.medical_information_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rxController,
              readOnly: true,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Prescription / Notes (Tap to open editor)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
              onTap: _openPrescriptionEditor,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _openPickSheetForNewRecord,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _pickedFiles.isEmpty
                          ? 'Attach photo/report'
                          : 'Attachments (${_pickedFiles.length})',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: _saving ? null : _saveNewRecord,
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
            if (_pickedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pickedFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                            onTap: _saving ? null : () => _removePickedAt(i),
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
    );
  }

  Future<void> _openRecordSearch() async {
    final controller = TextEditingController(text: _recordSearchQuery);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Search Records',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Record #, condition, prescription, date...',
                  ),
                  onChanged: (v) {
                    setState(() {
                      _recordSearchQuery = v;
                      _applyRecordFilters();
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          controller.clear();
                          setState(() {
                            _recordSearchQuery = '';
                            _applyRecordFilters();
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickRecordDateRange() async {
    final now = DateTime.now();
    final initial =
        _recordDateRange ??
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
      _recordDateRange = picked;
      _applyRecordFilters();
    });
  }

  String _recordRangeLabel() {
    final r = _recordDateRange;
    if (r == null) return 'Any date';
    return '${_fmtDate(r.start)} → ${_fmtDate(r.end)}';
  }

  Future<void> _editRecord(PatientRecord r) async {
    final db = await AppDatabase.instance.database;

    final bpC = TextEditingController(text: r.bp);
    final condC = TextEditingController(text: r.condition);
    final rxC = TextEditingController(text: r.prescription);

    final picked = <File>[];
    final currentAtt = List<RecordAttachment>.from(
      _attachmentsByRecordId[r.id] ?? const [],
    );

    Future<File> persist(XFile xf) async {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'patient_files'));
      if (!await folder.exists()) await folder.create(recursive: true);
      final ext = p.extension(xf.path).isEmpty ? '.jpg' : p.extension(xf.path);
      final fileName = 'r${r.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final targetPath = p.join(folder.path, fileName);
      return File(xf.path).copy(targetPath);
    }

    Future<void> pickFrom(
      ImageSource source,
      void Function(void Function()) ss,
    ) async {
      final picker = ImagePicker();
      final xf = await picker.pickImage(source: source, imageQuality: 85);
      if (xf == null) return;
      final saved = await persist(xf);
      ss(() => picked.add(saved));
    }

    Future<void> openPickSheet(void Function(void Function()) ss) async {
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
                      await pickFrom(ImageSource.camera, ss);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Gallery'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await pickFrom(ImageSource.gallery, ss);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, ss) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Edit Record #${r.id}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bpC,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'BP',
                        prefixIcon: Icon(Icons.monitor_heart_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: condC,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Condition',
                        prefixIcon: Icon(Icons.medical_information_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rxC,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Prescription / Notes',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: saving ? null : () => openPickSheet(ss),
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              picked.isEmpty
                                  ? 'Add attachment'
                                  : 'Added (${picked.length})',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (currentAtt.isNotEmpty || picked.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: currentAtt.length + picked.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            if (i < currentAtt.length) {
                              final a = currentAtt[i];
                              final f = File(a.filePath);
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: f.existsSync()
                                        ? Image.file(
                                            f,
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 90,
                                            height: 90,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Theme.of(
                                                  ctx,
                                                ).dividerColor,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: InkWell(
                                      onTap: saving
                                          ? null
                                          : () async {
                                              ss(() => saving = true);
                                              final ff = File(a.filePath);
                                              if (await ff.exists()) {
                                                await ff.delete().catchError(
                                                  (_) {},
                                                );
                                              }
                                              await db.delete(
                                                'record_attachments',
                                                where: 'id = ?',
                                                whereArgs: [a.id],
                                              );
                                              ss(() {
                                                currentAtt.removeAt(i);
                                                saving = false;
                                              });
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.delete,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              final f = picked[i - currentAtt.length];
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
                                      onTap: saving
                                          ? null
                                          : () => ss(
                                              () => picked.removeAt(
                                                i - currentAtt.length,
                                              ),
                                            ),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
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
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    ss(() => saving = true);

                                    await db.update(
                                      'patient_records',
                                      {
                                        'bp': bpC.text.trim(),
                                        'condition': condC.text.trim(),
                                        'prescription': rxC.text.trim(),
                                      },
                                      where: 'id = ?',
                                      whereArgs: [r.id],
                                    );

                                    for (final f in picked) {
                                      await db.insert('record_attachments', {
                                        'recordId': r.id,
                                        'filePath': f.path,
                                        'createdAt': _nowIsoLocal(),
                                      });
                                    }

                                    if (mounted) Navigator.of(ctx).pop();
                                  },
                            child: saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await _load();
  }

  Widget _recordCard(PatientRecord r, int displayNumber) {
    final atts = _attachmentsByRecordId[r.id] ?? const [];

    return InkWell(
      onTap: () => _editRecord(r),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Record $displayNumber • ${_fmtDateTime(r.createdAt)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chip(
                    'BP: ${r.bp.trim().isEmpty ? '-' : r.bp}',
                    Icons.monitor_heart_outlined,
                  ),
                  _chip(
                    'Condition: ${r.condition.trim().isEmpty ? '-' : r.condition}',
                    Icons.medical_information_outlined,
                  ),
                  if (atts.isNotEmpty)
                    _chip('${atts.length} attachment(s)', Icons.image_outlined),
                ],
              ),
              const SizedBox(height: 12),
              if (r.prescription.trim().isNotEmpty) ...[
                Text(
                  'Prescription / Notes',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(r.prescription),
              ],
              if (atts.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: atts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final a = atts[i];
                      final f = File(a.filePath);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: f.existsSync()
                            ? Image.file(
                                f,
                                width: 110,
                                height: 100,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 110,
                                height: 100,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordToolsRow() {
    final anySearch = _recordSearchQuery.trim().isNotEmpty;
    final anyDate = _recordDateRange != null;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openRecordSearch,
            icon: const Icon(Icons.search),
            label: Text(
              anySearch ? 'Search: "$_recordSearchQuery"' : 'Search records',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickRecordDateRange,
            icon: const Icon(Icons.calendar_today),
            label: Text(_recordRangeLabel()),
          ),
        ),
        if (anySearch || anyDate) ...[
          const SizedBox(width: 12),
          IconButton(
            onPressed: () {
              setState(() {
                _recordSearchQuery = '';
                _recordDateRange = null;
                _applyRecordFilters();
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.patient.name)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _headerCard(),
                    const SizedBox(height: 12),
                    _newRecordComposer(),
                    const SizedBox(height: 12),
                    _recordToolsRow(),
                    const SizedBox(height: 12),
                    Text(
                      'Records (${_records.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_records.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No matching records. Adjust search/filter or add a new one.',
                          ),
                        ),
                      )
                    else
                      ..._records.asMap().entries.map((e) {
                        final displayNumber =
                            _allRecords.length -
                            _allRecords.indexWhere((x) => x.id == e.value.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _recordCard(e.value, displayNumber),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}
