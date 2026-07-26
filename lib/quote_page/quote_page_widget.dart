import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Public, unauthenticated quote view/accept page — the second
/// customer-facing half of item 8's Survey -> Quotation -> Order flow
/// (see supabase/20260725_survey_quote_flow.sql). Reached via a shared
/// link (/quote?token=...); reads via get_quotation_by_token, "e-signs"
/// via accept_quotation (typed full name + timestamp — no signature-pad
/// dependency for v1). Both RPCs only ever touch the one row matching
/// the exact token given.
class QuotePageWidget extends StatefulWidget {
  const QuotePageWidget({super.key, this.token});

  final String? token;

  static String routeName = 'QuotePage';
  static String routePath = '/quote';

  @override
  State<QuotePageWidget> createState() => _QuotePageWidgetState();
}

class _QuotePageWidgetState extends State<QuotePageWidget> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  // null = loading, 'ready' = loaded, 'invalid' = bad token, 'error' = load failed.
  String? _state;
  Map<String, dynamic>? _quote;
  final _signCtrl = TextEditingController();
  bool _accepting = false;
  String? _acceptError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _signCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _state = 'invalid');
      return;
    }
    try {
      final res = await SupaFlow.client
          .rpc('get_quotation_by_token', params: {'p_token': token});
      final row = (res as List).isNotEmpty
          ? Map<String, dynamic>.from(res.first as Map)
          : null;
      if (row == null) {
        setState(() => _state = 'invalid');
        return;
      }
      setState(() {
        _quote = row;
        _state = 'ready';
      });
    } catch (e) {
      setState(() => _state = 'error');
    }
  }

  Future<void> _accept() async {
    if (_signCtrl.text.trim().isEmpty) {
      setState(() => _acceptError = 'Type your full name to accept.');
      return;
    }
    setState(() {
      _accepting = true;
      _acceptError = null;
    });
    try {
      final ok = await SupaFlow.client.rpc('accept_quotation', params: {
        'p_token': widget.token,
        'p_signature_name': _signCtrl.text.trim(),
      });
      if (ok == true) {
        await _load();
      } else {
        setState(() => _acceptError = 'Could not accept — please reload and try again.');
      }
    } catch (e) {
      setState(() => _acceptError = 'Could not accept — please try again.');
    } finally {
      setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        title: Text('Your Quote',
            style: GoogleFonts.interTight(
                fontWeight: FontWeight.w700, color: theme.primaryText)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(theme),
          ),
        ),
      ),
    );
  }

  Widget _body(FlutterFlowTheme theme) {
    switch (_state) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case 'invalid':
        return _message(theme, Icons.link_off,
            'This quote link is invalid or has expired.');
      case 'error':
        return _message(theme, Icons.error_outline,
            'Could not load this quote. Please check your connection and reload.');
      case 'ready':
      default:
        return _quoteView(theme);
    }
  }

  Widget _message(FlutterFlowTheme theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.secondaryText),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 15, color: theme.primaryText)),
        ],
      ),
    );
  }

  Widget _row(FlutterFlowTheme theme, String label, String value,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, color: theme.secondaryText)),
          Text(value,
              style: GoogleFonts.interTight(
                  fontSize: bold ? 16 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: theme.primaryText)),
        ],
      ),
    );
  }

  Widget _quoteView(FlutterFlowTheme theme) {
    final q = _quote!;
    final status = q['status'] as String? ?? 'draft';
    // items/charges are jsonb — the app's own quote-creation path always
    // writes a real [] array, but pre-existing rows from other insert
    // paths (e.g. the ad-hoc quotation_page_widget.dart form, which
    // doesn't set these fields at all) can leave them as a JSON object or
    // null instead, which crashed this page's build with a TypeError
    // before this guard (found live-testing item 8 against real seed
    // data, not something the new flow itself produces).
    final itemsRaw = q['items'];
    final chargesRaw = q['charges'];
    final items = itemsRaw is List ? itemsRaw : const [];
    final charges = chargesRaw is List ? chargesRaw : const [];
    final accepted = status == 'accepted';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quote from ${q['org_name'] ?? 'your mover'}',
              style: GoogleFonts.interTight(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(theme, 'Customer', (q['customer'] as String?) ?? '-'),
                _row(theme, 'From', (q['from_address'] as String?) ?? '-'),
                _row(theme, 'To', (q['to_address'] as String?) ?? '-'),
                if (items.isNotEmpty) ...[
                  const Divider(height: 20),
                  Text('Items',
                      style: GoogleFonts.interTight(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                  for (final it in items)
                    _row(
                        theme,
                        (it is Map ? it['name']?.toString() : it.toString()) ??
                            '',
                        it is Map && it['amount'] != null
                            ? _currency.format(it['amount'])
                            : ''),
                ],
                if (charges.isNotEmpty) ...[
                  const Divider(height: 20),
                  for (final c in charges)
                    _row(
                        theme,
                        (c is Map ? c['name']?.toString() : c.toString()) ??
                            '',
                        c is Map && c['amount'] != null
                            ? _currency.format(c['amount'])
                            : ''),
                ],
                const Divider(height: 20),
                if (q['subtotal'] != null)
                  _row(theme, 'Subtotal', _currency.format(q['subtotal'])),
                if (q['gst_amount'] != null)
                  _row(theme, 'GST${q['gst_pct'] != null ? ' (${q['gst_pct']}%)' : ''}',
                      _currency.format(q['gst_amount'])),
                const SizedBox(height: 4),
                _row(theme, 'Total', _currency.format(q['total'] ?? 0),
                    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (accepted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Accepted by ${q['accepted_by_name'] ?? 'you'}. Thanks — the team will be in touch to confirm your move.',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: theme.primaryText)),
                  ),
                ],
              ),
            )
          else ...[
            Text('Type your full name to accept this quote',
                style: GoogleFonts.interTight(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            const SizedBox(height: 8),
            TextField(
              controller: _signCtrl,
              style: GoogleFonts.inter(color: theme.primaryText),
              decoration: InputDecoration(
                labelText: 'Full name',
                filled: true,
                fillColor: theme.secondaryBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_acceptError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_acceptError!,
                    style: GoogleFonts.inter(color: theme.error, fontSize: 13)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _accepting ? null : _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _accepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Accept Quote',
                        style: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            color: theme.primaryBackground)),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
