import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/backend/face_count/face_count.dart';
import '/backend/private_files.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

/// Group-photo attendance (4 Nov 2026, Arun: "count faces, supervisor ticks
/// names").
///
/// The supervisor takes ONE photo of the crew. The phone counts the faces
/// (ML Kit, on the device), the supervisor ticks who is in it, and both
/// numbers are kept with the attendance so the owner can see when they
/// differ. The app never decides who is present from the photo — a face
/// count cannot tell Balaji from Murugan; the supervisor's ticks are the
/// record, the count is the cross-check, the photo is the proof.
///
/// The photo goes to the PRIVATE `org-private` bucket under
/// `<org>/attendance/<date>/…` and a `documents` row (entity_type
/// 'attendance', entity_id = the date). Each ticked person gets an
/// `attendance` row whose note names the photo.
///
/// [team] is the supervisor's branch team; [alreadyPresent] are marked
/// already today (shown ticked and locked). Returns true when saved.
Future<bool> showGroupPhotoAttendance(
  BuildContext context, {
  required List<StaffRow> team,
  required Set<String> alreadyPresent,
  required String? branch,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NgPalette.of(context).sheet,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
    builder: (_) => _GroupPhotoSheet(
        team: team, alreadyPresent: alreadyPresent, branch: branch),
  );
  return saved == true;
}

class _GroupPhotoSheet extends StatefulWidget {
  const _GroupPhotoSheet(
      {required this.team, required this.alreadyPresent, required this.branch});

  final List<StaffRow> team;
  final Set<String> alreadyPresent;
  final String? branch;

  @override
  State<_GroupPhotoSheet> createState() => _GroupPhotoSheetState();
}

class _GroupPhotoSheetState extends State<_GroupPhotoSheet> {
  Uint8List? _photo;
  String _ext = 'jpg';
  bool _counting = false;

  /// Faces found, or null when the count is not available (web/desktop, or
  /// detection failed). Never guessed.
  int? _faces;
  bool _countTried = false;
  final Set<String> _ticked = {};
  bool _saving = false;
  String? _error;

  String get _today => DateTime.now().toIso8601String().split('T').first;

  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 75,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      final name = shot.name.toLowerCase();
      setState(() {
        _photo = bytes;
        _ext = name.endsWith('.png') ? 'png' : 'jpg';
        _faces = null;
        _countTried = false;
        _counting = !kIsWeb;
        _error = null;
      });
      if (kIsWeb) {
        setState(() => _countTried = true);
        return;
      }
      final n = await countFaces(shot.path);
      if (!mounted) return;
      setState(() {
        _faces = n;
        _countTried = true;
        _counting = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _counting = false;
          _error = 'Could not open the camera.';
        });
      }
    }
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) {
      setState(() => _error = 'Take the group photo first.');
      return;
    }
    if (_ticked.isEmpty) {
      setState(() => _error = 'Tick the people in the photo.');
      return;
    }
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final path =
        '$orgId/attendance/$_today/group-${DateTime.now().millisecondsSinceEpoch}.$_ext';
    final mime = _ext == 'png' ? 'image/png' : 'image/jpeg';
    try {
      await SupaFlow.client.storage.from(kPrivateBucket).uploadBinary(
            path,
            photo,
            fileOptions: FileOptions(contentType: mime),
          );
      String docId;
      try {
        final doc = await SupaFlow.client
            .from('documents')
            .insert({
              ...OrgScope.stamp(),
              'entity_type': 'attendance',
              'entity_id': _today,
              'doc_type': 'group_photo',
              'file_name': 'Group photo $_today.$_ext',
              'storage_path': privateRef(path),
              'mime_type': mime,
              'size_bytes': photo.length,
              'uploaded_by': SupaFlow.client.auth.currentUser?.id,
            })
            .select('id')
            .single();
        docId = '${doc['id']}';
      } catch (e) {
        // No orphan file behind a failed row.
        try {
          await SupaFlow.client.storage.from(kPrivateBucket).remove([path]);
        } catch (_) {}
        rethrow;
      }
      final note = [
        'Group photo',
        if (_faces != null) '$_faces faces',
        '${_ticked.length + widget.alreadyPresent.length} ticked',
        'doc:$docId',
      ].join(' · ');
      await SupaFlow.client.from('attendance').insert([
        for (final id in _ticked)
          {
            ...OrgScope.stamp(),
            'staff_id': id,
            'attendance_date': _today,
            'status': 'present',
            if (widget.branch != null) 'branch': widget.branch,
            'marked_by': AppSession.instance.currentStaffName ?? 'Supervisor',
            'note': note,
          },
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = extractDbErrorMessage(e,
            fallback: 'Could not save attendance. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final tickedTotal = _ticked.length +
        widget.team.where((s) => widget.alreadyPresent.contains(s.id)).length;
    String? countLine;
    Color countColor = c.mute;
    if (_photo != null) {
      if (_counting) {
        countLine = 'Counting faces…';
      } else if (_faces != null) {
        if (_faces == tickedTotal) {
          countLine = '$_faces faces in the photo · $tickedTotal ticked';
          countColor = c.green;
        } else {
          countLine =
              '$_faces faces in the photo, $tickedTotal ticked — check the names.';
          countColor = c.amber;
        }
      } else if (_countTried) {
        countLine = 'Face count works in the phone app. Tick the names.';
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 18, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Group photo attendance',
                style: NgFonts.geist(
                    fontSize: 20, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 4),
            Text('One photo of the crew, then tick who is in it.',
                style: NgFonts.geist(fontSize: 13, color: c.mute)),
            const SizedBox(height: 14),
            NgCard(
              onTap: _saving ? null : _takePhoto,
              padding: EdgeInsets.zero,
              child: _photo == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(children: [
                        Icon(Icons.photo_camera_rounded, size: 30, color: c.acc),
                        const SizedBox(height: 8),
                        Text('Take group photo',
                            style: NgFonts.geist(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                      ]),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(children: [
                        Image.memory(_photo!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Text('Retake',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12.5)),
                          ),
                        ),
                      ]),
                    ),
            ),
            if (countLine != null) ...[
              const SizedBox(height: 8),
              Text(countLine,
                  style: NgFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: countColor)),
            ],
            const SizedBox(height: 14),
            const NgFieldLabel('Who is in the photo'),
            NgCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < widget.team.length; i++)
                  _row(context, widget.team[i], first: i == 0),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)),
            ],
            const SizedBox(height: 12),
            NgPrimaryButton(
              label: _saving
                  ? 'Saving…'
                  : _ticked.isEmpty
                      ? 'Mark present'
                      : 'Mark ${_ticked.length} present',
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, StaffRow s, {required bool first}) {
    final c = NgPalette.of(context);
    final id = s.id;
    final locked = id != null && widget.alreadyPresent.contains(id);
    final ticked = locked || (id != null && _ticked.contains(id));
    return InkWell(
      onTap: id == null || locked || _saving
          ? null
          : () => setState(() =>
              _ticked.contains(id) ? _ticked.remove(id) : _ticked.add(id)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
            border: first ? null : Border(top: BorderSide(color: c.w06))),
        child: Row(children: [
          NgAvatar(s.name,
              status: ticked ? NgStatus.green : NgStatus.neutral, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.name,
                style: NgFonts.geist(fontSize: 14.5, color: c.text)),
          ),
          if (locked)
            Text('Already present',
                style: NgFonts.geist(fontSize: 12, color: c.green)),
          Checkbox(
            value: ticked,
            onChanged: id == null || locked || _saving
                ? null
                : (v) => setState(
                    () => v == true ? _ticked.add(id) : _ticked.remove(id)),
          ),
        ]),
      ),
    );
  }
}
