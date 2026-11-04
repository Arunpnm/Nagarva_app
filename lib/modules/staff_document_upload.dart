import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '/backend/edge_function_errors.dart';
import '/backend/private_files.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/components/pdf_view_page.dart';
import '/flutter_flow/ng_tokens.dart';

/// Staff documents: upload and view (4 Nov 2026, BUG-026).
///
/// The Staff documents screen listed `documents` rows but nothing in the
/// app could create one. Files go to the PRIVATE `org-private` bucket
/// under `<org>/staff/<staff id>/…` — the bucket's policies only let the
/// org's own sessions read or write that folder — and the row stores the
/// `org-private:` reference, never a public URL. An Aadhaar or licence
/// scan must not be reachable by anyone holding a link.

const _kDocTypes = <(String, String)>[
  ('aadhaar', 'Aadhaar'),
  ('pan', 'PAN'),
  ('driving_licence', 'Driving licence'),
  ('bank_passbook', 'Bank passbook'),
  ('joining_letter', 'Joining letter'),
  ('photo', 'Photo'),
  ('other', 'Other'),
];

/// ID papers are sensitive by default; the owner can switch it off.
const _kSensitiveByDefault = {'aadhaar', 'pan', 'bank_passbook'};

Future<bool> showStaffDocumentUpload(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NgPalette.of(context).sheet,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
    builder: (_) => const _UploadSheet(),
  );
  return saved == true;
}

/// Opens a stored document: a PDF in the viewer, an image full screen.
Future<void> openStaffDocument(
    BuildContext context, Map<String, dynamic> row) async {
  final messenger = ScaffoldMessenger.of(context);
  final path = '${row['storage_path'] ?? ''}';
  final bytes = await fetchFileBytes(path);
  if (!context.mounted) return;
  if (bytes == null) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this document.')));
    return;
  }
  final name = '${row['file_name'] ?? 'document'}';
  final isPdf = '${row['mime_type'] ?? ''}'.contains('pdf') ||
      name.toLowerCase().endsWith('.pdf');
  if (isPdf) {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewPage(title: name, bytes: bytes, filename: name)));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InteractiveViewer(
              child: Image.memory(bytes,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('This file cannot be shown here.'),
                      )),
            ),
          ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    ),
  );
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet();

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  List<Map<String, dynamic>> _staff = const [];
  bool _loadingStaff = true;
  String? _staffId;
  String? _docType;
  bool _sensitive = false;
  PlatformFile? _file;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final rows = await OrgScope.read(
              SupaFlow.client.from('staff').select('id, name, role, active'))
          .order('name', ascending: true);
      _staff = [
        for (final r in rows as List)
          if (r['active'] != false) Map<String, dynamic>.from(r as Map)
      ];
    } catch (_) {
      _staff = const [];
    }
    if (mounted) setState(() => _loadingStaff = false);
  }

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    final f = picked?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 10 * 1024 * 1024) {
      setState(() => _error = 'Choose a file smaller than 10 MB.');
      return;
    }
    setState(() {
      _file = f;
      _error = null;
    });
  }

  Future<void> _save() async {
    final staffId = _staffId, type = _docType, file = _file;
    String? missing;
    if (staffId == null) {
      missing = 'Choose the staff member.';
    } else if (type == null) {
      missing = 'Choose what document this is.';
    } else if (file == null || file.bytes == null) {
      missing = 'Choose the file to upload.';
    }
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }
    final f = file!, sid = staffId!, docType = type!;
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final ext = (f.extension ?? 'jpg').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    final path =
        '$orgId/staff/$sid/$docType-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await SupaFlow.client.storage.from(kPrivateBucket).uploadBinary(
            path,
            f.bytes!,
            fileOptions: FileOptions(contentType: mime),
          );
      try {
        await SupaFlow.client.from('documents').insert({
          ...OrgScope.stamp(),
          'entity_type': 'staff',
          'entity_id': sid,
          'doc_type': docType,
          'file_name': f.name,
          'storage_path': privateRef(path),
          'mime_type': mime,
          'size_bytes': f.size,
          'uploaded_by': SupaFlow.client.auth.currentUser?.id,
          'is_sensitive': _sensitive,
        });
      } catch (e) {
        // Don't leave an orphan file behind a failed row.
        try {
          await SupaFlow.client.storage.from(kPrivateBucket).remove([path]);
        } catch (_) {}
        rethrow;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = extractDbErrorMessage(e,
            fallback: 'Could not upload the document. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 18, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload staff document',
                style: NgFonts.geist(
                    fontSize: 20, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 16),
            const NgFieldLabel('Staff member *'),
            if (_loadingStaff)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (_staff.isEmpty)
              Text('Add staff first, in Staff.',
                  style: NgFonts.geist(fontSize: 13, color: c.amber))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in _staff)
                  NgChip(
                    label: '${s['name'] ?? ''}',
                    selected: _staffId == '${s['id']}',
                    onTap: () => setState(() => _staffId = '${s['id']}'),
                  ),
              ]),
            const SizedBox(height: 14),
            const NgFieldLabel('Document *'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, label) in _kDocTypes)
                NgChip(
                  label: label,
                  selected: _docType == key,
                  onTap: () => setState(() {
                    _docType = key;
                    _sensitive = _kSensitiveByDefault.contains(key);
                  }),
                ),
            ]),
            const SizedBox(height: 14),
            NgCard(
              onTap: _saving ? null : _pick,
              child: Row(children: [
                Icon(_file == null
                        ? Icons.upload_file_rounded
                        : Icons.check_circle_rounded,
                    size: 22, color: _file == null ? c.acc : c.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _file == null
                        ? 'Choose file (photo or PDF, up to 10 MB)'
                        : _file!.name,
                    style: NgFonts.geist(fontSize: 14, color: c.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('Sensitive (ID or bank details)',
                    style: NgFonts.geist(fontSize: 14.5, color: c.text)),
              ),
              Switch(
                value: _sensitive,
                onChanged: (v) => setState(() => _sensitive = v),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)),
            ],
            const SizedBox(height: 12),
            NgPrimaryButton(
              label: _saving ? 'Uploading…' : 'Upload',
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
