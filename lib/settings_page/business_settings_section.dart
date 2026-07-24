import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Vendor self-service branding & business identity (Settings page).
///
/// Three cards, mirroring the APC reference app's Settings:
///   1. Business Details — tagline, GSTIN, PAN, address, phones, email,
///      website, bank, UPI. Saved as one JSON blob in the org-scoped
///      settings table under key 'business_profile'.
///   2. Company Logo — picked via file_picker, stored in the org-logos
///      bucket at <org_id>/logo.png, organizations.logo_url updated, and
///      the in-memory session refreshed so the sidebar updates instantly.
///   3. Authorized Signatory — draw once in a dialog, saved as a PNG to
///      <org_id>/signature.png with the public URL in settings key
///      'signature_url'.
///
/// All three feed the invoice PDF (see components/invoice_pdf.dart), which
/// is why they live together: fill this page once and every invoice comes
/// out branded.
class BusinessSettingsSection extends StatefulWidget {
  const BusinessSettingsSection({super.key});

  @override
  State<BusinessSettingsSection> createState() =>
      _BusinessSettingsSectionState();
}

class _BusinessSettingsSectionState extends State<BusinessSettingsSection> {
  static const _fields = <(String key, String label, String hint)>[
    ('tagline', 'Tagline', 'e.g. Moving You Towards Your Future'),
    ('gstin', 'GST No.', '15-char GSTIN'),
    ('pan', 'PAN No.', ''),
    ('address', 'Address', 'Registered office address'),
    ('phone1', 'Phone 1', ''),
    ('phone2', 'Phone 2', ''),
    ('email', 'Email', ''),
    ('website', 'Website', 'https://…'),
    ('bank_name', 'Bank Name', ''),
    ('account_no', 'Bank A/c No.', ''),
    ('ifsc', 'IFSC Code', ''),
    ('upi_id', 'UPI ID', 'name@bank'),
    // Multiline: one line = one numbered point on the invoice PDF.
    ('invoice_terms', 'Terms & Conditions (one per line)',
        'e.g. Claims for loss or damage must be lodged within 48 hours of delivery.'),
  ];

  final Map<String, TextEditingController> _ctrl = {
    for (final f in _fields) f.$1: TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _savingSignature = false;
  String? _signatureUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .inFilter('key', ['business_profile', 'signature_url']),
      );
      for (final r in rows) {
        if (r.key == 'business_profile' && (r.value ?? '').isNotEmpty) {
          final decoded = jsonDecode(r.value!);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              if (_ctrl.containsKey(k)) _ctrl[k]!.text = (v ?? '').toString();
            });
          }
        }
        if (r.key == 'signature_url') _signatureUrl = r.value;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSetting(String key, String value) =>
      SettingsTable().upsert(
        {
          'key': key,
          ...OrgScope.stamp(),
          'value': value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'org_id,key',
      );

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final profile = {
        for (final e in _ctrl.entries) e.key: e.value.text.trim(),
      };
      await _saveSetting('business_profile', jsonEncode(profile));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Business details saved. They will appear on every invoice.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _uploadToBucket(String path, Uint8List bytes) async {
    final storage = SupaFlow.client.storage.from('org-logos');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions:
          const FileOptions(contentType: 'image/png', upsert: true),
    );
    // Cache-bust so the new image shows immediately everywhere.
    return '${storage.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _pickLogo() async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final url = await _uploadToBucket('$orgId/logo.png', bytes);
      await OrganizationsTable().update(
        data: {'logo_url': url},
        matchingRows: (q) => q.eq('id', orgId),
      );
      AppSession.instance.currentOrgLogoUrl = url;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Logo updated — sidebar and invoices will use it.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Logo upload failed: $e. '
                'Has 20260717_org_logo_url.sql been run?')));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _drawSignature() async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const _SignaturePadDialog(),
    );
    if (bytes == null) return;
    setState(() => _savingSignature = true);
    try {
      final url = await _uploadToBucket('$orgId/signature.png', bytes);
      await _saveSetting('signature_url', url);
      if (mounted) {
        setState(() => _signatureUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Signature saved — it will appear on all invoices.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save signature: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingSignature = false);
    }
  }

  InputDecoration _dec(String label, String hint) {
    final theme = FlutterFlowTheme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint.isEmpty ? null : hint,
      labelStyle:
          GoogleFonts.inter(color: theme.secondaryText, fontSize: 12.5),
      hintStyle: GoogleFonts.inter(
          color: theme.secondaryText.withOpacity(0.5), fontSize: 12.5),
      filled: true,
      fillColor: theme.primaryBackground,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: theme.primary, width: 1.4),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(padding: const EdgeInsets.all(16.0), child: child),
    );
  }

  Widget _cardTitle(String title, String subtitle) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.interTight(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: theme.primaryText)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: GoogleFonts.inter(
                fontSize: 11.5, color: theme.secondaryText)),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) {
      return _card(
          child: const Center(
              child: Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator()),
      )));
    }
    final textStyle = GoogleFonts.inter(color: theme.primaryText, fontSize: 13.5);
    return Column(
      children: [
        // ---- 1. Business details ----------------------------------------
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle('Business Details',
                  'These details print on every invoice — fill once, no developer needed.'),
              LayoutBuilder(builder: (context, constraints) {
                final twoCol = constraints.maxWidth > 560;
                final children = [
                  for (final f in _fields)
                    SizedBox(
                      width: twoCol && f.$1 != 'invoice_terms' && f.$1 != 'address'
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth,
                      child: TextField(
                        controller: _ctrl[f.$1],
                        style: textStyle,
                        maxLines: f.$1 == 'invoice_terms' ? 5 : 1,
                        decoration: _dec(f.$2, f.$3),
                      ),
                    ),
                ];
                return Wrap(spacing: 12, runSpacing: 12, children: children);
              }),
              const SizedBox(height: 14),
              SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Save Business Details'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ---- 2. Logo ----------------------------------------------------
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('Company Logo',
                  'Shows in the sidebar and on every invoice PDF.'),
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.primaryBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (AppSession.instance.currentOrgLogoUrl ?? '')
                            .isEmpty
                        ? Icon(Icons.local_shipping,
                            color: theme.primary, size: 30)
                        : Image.network(
                            AppSession.instance.currentOrgLogoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image,
                                color: theme.secondaryText),
                          ),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    onPressed: _uploadingLogo ? null : _pickLogo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                    icon: _uploadingLogo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload, size: 18),
                    label: Text(
                        (AppSession.instance.currentOrgLogoUrl ?? '').isEmpty
                            ? 'Upload Logo'
                            : 'Change Logo'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ---- 3. Signature -----------------------------------------------
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('Authorized Signatory',
                  'Draw your signature once — it auto-appears on all invoices.'),
              Row(
                children: [
                  Container(
                    width: 150,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: theme.secondaryText.withOpacity(0.25)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_signatureUrl ?? '').isEmpty
                        ? Center(
                            child: Text('No signature yet',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.grey.shade500)))
                        : Image.network(_signatureUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    onPressed: _savingSignature ? null : _drawSignature,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                    icon: _savingSignature
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.draw, size: 18),
                    label: Text((_signatureUrl ?? '').isEmpty
                        ? 'Draw Signature'
                        : 'Redraw'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Simple draw-to-sign dialog. Strokes are captured with pan gestures and
/// rendered to a transparent PNG via dart:ui so the signature composites
/// cleanly onto the invoice.
class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<List<Offset>> _strokes = [];
  static const Size _padSize = Size(420, 180);

  Future<Uint8List?> _export() async {
    if (_strokes.every((s) => s.length < 2)) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = const Color(0xFF1A237E)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
    final img = await recorder
        .endRecording()
        .toImage(_padSize.width.toInt(), _padSize.height.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draw your signature'),
      content: SizedBox(
        width: _padSize.width,
        height: _padSize.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.white,
            child: GestureDetector(
              onPanStart: (d) =>
                  setState(() => _strokes.add([d.localPosition])),
              onPanUpdate: (d) =>
                  setState(() => _strokes.last.add(d.localPosition)),
              child: CustomPaint(
                size: _padSize,
                painter: _SignaturePainter(_strokes),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_strokes.clear),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final bytes = await _export();
            if (!context.mounted) return;
            if (bytes == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Draw your signature first.')));
              return;
            }
            Navigator.of(context).pop(bytes);
          },
          child: const Text('Save Signature'),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A237E)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
