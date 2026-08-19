import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';
import '/components/signature_pad.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// DEAD CODE AS OF 17 AUG 2026 — NOT what a customer reaches at
/// link.nagarva.in/sign. That domain runs a separate, hand-written
/// static page calling `public_get_signature_request`/
/// `public_submit_signature` directly (anon-callable, no Edge Function
/// layer) — a different RPC pair, and a different data-exposure shape,
/// from the `sign-document` Edge Function this page goes through. See
/// CLAUDE.md's "Public web surface" section and
/// `lib/flutter_flow/nav/nav.dart`'s "WHERE CUSTOMER LINKS ACTUALLY
/// RESOLVE" comment. The `sign-document` function and the RPCs below are
/// deployed and functional — this is dead in the sense of "not reached
/// by any live traffic," not "broken." Kept in case this build is ever
/// hosted on a domain that owns `/sign` for real.
///
/// Public, unauthenticated document-signing page (live-test fix brief #2,
/// item 3). Reached via a shared link `/sign?token=...` with no login.
///
/// Unlike SurveyPageWidget — which calls its RPCs directly because
/// `get_survey_by_token`/`submit_survey` are granted to anon — everything
/// here goes through the `sign-document` Edge Function. The underlying
/// RPCs (`get_signature_request` / `submit_signature`, see
/// supabase/20260728_public_links_sign_and_track.sql) are granted to
/// service_role ONLY, so the anon key cannot reach quotations or orders
/// even indirectly. That is the posture the brief asked for.
class SignPageWidget extends StatefulWidget {
  const SignPageWidget({super.key, this.token});

  final String? token;

  static String routeName = 'SignPage';
  static String routePath = '/sign';

  @override
  State<SignPageWidget> createState() => _SignPageWidgetState();
}

class _SignPageWidgetState extends State<SignPageWidget> {
  final _nameCtrl = TextEditingController();
  final _padKey = GlobalKey<SignaturePadState>();

  // null = loading, 'form' = ready, 'signed' = already done,
  // 'invalid' = bad token, 'error' = load failed.
  String? _state;
  String _orgName = 'the moving company';
  String _docType = 'quote';
  Map<String, dynamic>? _doc;
  DateTime? _signedAt;
  String? _signedBy;
  bool _hasSignature = false;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _state = 'invalid');
      return;
    }
    try {
      final res = await SupaFlow.client.functions.invoke(
        'sign-document',
        body: {'action': 'get', 'token': token},
      );
      final data = res.data;
      if (data is! Map || data['documentType'] == null) {
        setState(() => _state = 'invalid');
        return;
      }
      _orgName = (data['orgName'] as String?) ?? _orgName;
      _docType = (data['documentType'] as String?) ?? 'quote';
      _doc = data['document'] is Map
          ? Map<String, dynamic>.from(data['document'] as Map)
          : null;
      _signedBy = data['customerName'] as String?;
      final signedAtRaw = data['signedAt'] as String?;
      _signedAt = signedAtRaw == null ? null : DateTime.tryParse(signedAtRaw);
      _nameCtrl.text = _signedBy ?? '';
      setState(() => _state = data['status'] == 'signed' ? 'signed' : 'form');
    } catch (e) {
      // Same fix as track_page_widget.dart's _load (17 Aug 2026) —
      // sign-document returns 404 for an invalid/expired token, which
      // used to land here as a generic 'error' instead of 'invalid'.
      final status = e is FunctionException ? e.status : null;
      setState(() => _state = status == 404 ? 'invalid' : 'error');
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _submitError = 'Please enter your name.');
      return;
    }
    final png = await _padKey.currentState?.toPngBase64();
    if (png == null) {
      setState(() => _submitError = 'Please sign in the box above.');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final res = await SupaFlow.client.functions.invoke(
        'sign-document',
        body: {
          'action': 'sign',
          'token': widget.token,
          'signature': png,
          'name': name,
        },
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        setState(() {
          _state = 'signed';
          _signedBy = name;
          _signedAt = DateTime.now();
        });
      } else {
        setState(() => _submitError =
            (data is Map ? data['error'] as String? : null) ??
                'Could not record your signature. Please try again.');
      }
    } catch (e) {
      // `invoke` throws on the 400 sign-document returns for a failed
      // submit (17 Aug 2026 finding) — was showing a raw exception string.
      setState(() => _submitError = extractFunctionErrorMessage(e,
          fallback: 'Could not record your signature. Please try again.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _docLabel => _docType == 'invoice' ? 'Invoice' : 'Quotation';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Customers open this on a phone, but it must not stretch
            // absurdly wide if opened on a desktop browser.
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_state) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case 'invalid':
        return _message(
          Icons.link_off,
          'This link is not valid',
          'It may have expired, or been replaced by a newer one. Please ask '
              '$_orgName to send you a fresh link.',
        );
      case 'error':
        return _message(
          Icons.wifi_off,
          'Could not load the document',
          'Please check your connection and try again.',
          onRetry: () {
            setState(() => _state = null);
            _load();
          },
        );
      case 'signed':
        return _message(
          Icons.check_circle,
          'Thank you — signed',
          _signedAt == null
              ? 'Your acceptance has been recorded.'
              : 'Accepted by ${_signedBy ?? 'you'} on '
                  '${DateFormat('d MMM yyyy, h:mm a').format(_signedAt!.toLocal())}.',
        );
      default:
        return _form(context);
    }
  }

  Widget _message(IconData icon, String title, String body,
      {VoidCallback? onRetry}) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: theme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.interTight(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 14, height: 1.45, color: theme.secondaryText),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _orgName,
            style: GoogleFonts.interTight(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review & accept your $_docLabel',
            style: GoogleFonts.interTight(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.primaryText,
            ),
          ),
          const SizedBox(height: 18),
          _documentCard(context),
          const SizedBox(height: 22),
          Text(
            'Your signature',
            style: GoogleFonts.interTight(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.alternate),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: SignaturePad(
              key: _padKey,
              onChanged: (has) => setState(() => _hasSignature = has),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _padKey.currentState?.clear();
                setState(() => _hasSignature = false);
              },
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Clear'),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your full name',
              border: OutlineInputBorder(),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(
              _submitError!,
              style: GoogleFonts.inter(fontSize: 13, color: theme.error),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  (_submitting || !_hasSignature) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Sign & Accept',
                      style: GoogleFonts.interTight(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'By signing you confirm you have read and accept the '
            '${_docLabel.toLowerCase()} above.',
            style: GoogleFonts.inter(
                fontSize: 11.5, height: 1.4, color: theme.secondaryText),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Read-only rendering of whatever the RPC returned. The payload is the
  /// row as jsonb (minus org_id, and minus job_otp for orders), so this
  /// picks out the fields worth showing rather than assuming a fixed
  /// shape — an added column must never break the customer's page.
  Widget _documentCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final d = _doc;
    if (d == null) {
      return Text(
        'The $_docLabel could not be loaded, but you can still sign below '
        'if $_orgName has shown it to you.',
        style: GoogleFonts.inter(fontSize: 13.5, color: theme.secondaryText),
      );
    }

    num? asNum(String k) => d[k] is num ? d[k] as num : null;
    String? asStr(String k) =>
        (d[k] is String && (d[k] as String).trim().isNotEmpty)
            ? d[k] as String
            : null;

    final items = d['items'] is List ? d['items'] as List : const [];
    final total = asNum('total') ?? asNum('amount');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asStr('id') != null)
            _line(context, 'Reference', asStr('id')!),
          if (asStr('customer') != null)
            _line(context, 'Customer', asStr('customer')!),
          // Parens matter: `??` binds looser than `!=`, so without them
          // this parsed as `asStr(a) ?? (asStr(b) != null)` — a String?/bool
          // mix that the analyzer rejected as a non-bool condition.
          if ((asStr('from_address') ?? asStr('from_city')) != null)
            _line(context, 'From',
                asStr('from_address') ?? asStr('from_city') ?? '—'),
          if ((asStr('to_address') ?? asStr('to_city')) != null)
            _line(context, 'To',
                asStr('to_address') ?? asStr('to_city') ?? '—'),
          if (items.isNotEmpty)
            _line(context, 'Items', '${items.length} line(s)'),
          if (asNum('subtotal') != null)
            _line(context, 'Subtotal',
                '₹${asNum('subtotal')!.toStringAsFixed(0)}'),
          if (asNum('gst_amount') != null)
            _line(
              context,
              'GST${asNum('gst_pct') != null ? ' (${asNum('gst_pct')!.toStringAsFixed(0)}%)' : ''}',
              '₹${asNum('gst_amount')!.toStringAsFixed(0)}',
            ),
          if (total != null) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.primaryText)),
                Text('₹${total.toStringAsFixed(0)}',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: theme.primary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13, color: theme.secondaryText)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: theme.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}
