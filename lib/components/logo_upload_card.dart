import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Self-contained "Company Logo" card: pick an image, upload it to the
/// `org-logos` storage bucket at `<org_id>/logo.png`, stamp
/// `organizations.logo_url`, and refresh `AppSession` so the sidebar/
/// invoices pick it up immediately. Same upload mechanism as Settings'
/// BusinessSettingsSection (kept as a separate small widget rather than a
/// shared refactor of that already-working, live-tested code — see item 10
/// in NAGARVA_STATUS.md).
class LogoUploadCard extends StatefulWidget {
  const LogoUploadCard({super.key});

  @override
  State<LogoUploadCard> createState() => _LogoUploadCardState();
}

class _LogoUploadCardState extends State<LogoUploadCard> {
  bool _uploading = false;

  Future<void> _pickLogo() async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _uploading = true);
    try {
      final storage = SupaFlow.client.storage.from('org-logos');
      final path = '$orgId/logo.png';
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
      );
      final url =
          '${storage.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await OrganizationsTable().update(
        data: {'logo_url': url},
        matchingRows: (q) => q.eq('id', orgId),
      );
      AppSession.instance.currentOrgLogoUrl = url;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Logo uploaded — it will show on invoices and the sidebar.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Logo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final logoUrl = AppSession.instance.currentOrgLogoUrl;
    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.primaryBackground,
              borderRadius: BorderRadius.circular(10),
              image: (logoUrl ?? '').isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(logoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: (logoUrl ?? '').isEmpty
                ? Icon(Icons.image_outlined, color: theme.secondaryText)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Company Logo',
                  style: GoogleFonts.interTight(
                    color: theme.primaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Shown on invoices and the app sidebar',
                  style: GoogleFonts.inter(
                      color: theme.secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _uploading ? null : _pickLogo,
            icon: _uploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.primary),
                  )
                : const Icon(Icons.upload, size: 18),
            label: Text((logoUrl ?? '').isEmpty ? 'Upload' : 'Change'),
          ),
        ],
      ),
    );
  }
}
