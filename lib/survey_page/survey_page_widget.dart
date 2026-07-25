import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Public, unauthenticated survey form — the customer-facing half of
/// item 8's Survey -> Quotation -> Order flow (see
/// supabase/20260725_survey_quote_flow.sql for the scope assumption this
/// whole feature is built against). Reached via a shared link
/// (/survey?token=...) with no login involved; reads/writes go through
/// two public RPCs (get_survey_by_token / submit_survey) rather than
/// direct table queries, since RLS blocks anon access to `surveys`
/// entirely — the RPCs are the only door in, and each only ever
/// touches the one row matching the exact token given.
class SurveyPageWidget extends StatefulWidget {
  const SurveyPageWidget({super.key, this.token});

  final String? token;

  static String routeName = 'SurveyPage';
  static String routePath = '/survey';

  @override
  State<SurveyPageWidget> createState() => _SurveyPageWidgetState();
}

class _SurveyPageWidgetState extends State<SurveyPageWidget> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _moveDate;

  /// Rooms captured as free-text "Room name -> items" pairs — kept simple
  /// (no photo upload, no per-item structured fields) for a v1 the
  /// customer can fill from a phone in a couple of minutes.
  final List<(TextEditingController room, TextEditingController items)>
      _rooms = [];

  // null = loading, 'form' = ready, 'submitted' = already done,
  // 'invalid' = bad/unknown token, 'error' = load failed.
  String? _state;
  String _orgName = 'the moving company';
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _addRoom();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _notesCtrl.dispose();
    for (final (room, items) in _rooms) {
      room.dispose();
      items.dispose();
    }
    super.dispose();
  }

  void _addRoom() {
    _rooms.add((TextEditingController(), TextEditingController()));
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _state = 'invalid');
      return;
    }
    try {
      final res =
          await SupaFlow.client.rpc('get_survey_by_token', params: {
        'p_token': token,
      });
      final row = (res as List).isNotEmpty
          ? Map<String, dynamic>.from(res.first as Map)
          : null;
      if (row == null) {
        setState(() => _state = 'invalid');
        return;
      }
      _orgName = (row['org_name'] as String?) ?? _orgName;
      if (row['status'] == 'submitted') {
        setState(() => _state = 'submitted');
        return;
      }
      _nameCtrl.text = (row['customer_name'] as String?) ?? '';
      _phoneCtrl.text = (row['customer_phone'] as String?) ?? '';
      setState(() => _state = 'form');
    } catch (e) {
      setState(() => _state = 'error');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final rooms = _rooms
          .where((r) => r.$1.text.trim().isNotEmpty)
          .map((r) => {'room': r.$1.text.trim(), 'items': r.$2.text.trim()})
          .toList();
      final ok = await SupaFlow.client.rpc('submit_survey', params: {
        'p_token': widget.token,
        'p_customer_name': _nameCtrl.text.trim(),
        'p_customer_phone': _phoneCtrl.text.trim(),
        'p_from_address': _fromCtrl.text.trim(),
        'p_to_address': _toCtrl.text.trim(),
        'p_move_date': _moveDate?.toIso8601String().split('T').first,
        'p_rooms': rooms,
        'p_special_instructions': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      });
      if (ok == true) {
        setState(() {
          _state = 'submitted';
          _submitting = false;
        });
      } else {
        setState(() {
          _submitError = 'This link has already been used or is invalid.';
          _submitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _submitError = 'Could not submit — please try again.';
        _submitting = false;
      });
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
        title: Text('Move Survey',
            style: GoogleFonts.interTight(
                fontWeight: FontWeight.w700, color: theme.primaryText)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(context, theme),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FlutterFlowTheme theme) {
    switch (_state) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case 'invalid':
        return _message(theme, Icons.link_off,
            'This survey link is invalid or has expired.');
      case 'error':
        return _message(theme, Icons.error_outline,
            'Could not load this survey. Please check your connection and reload.');
      case 'submitted':
        return _message(theme, Icons.check_circle_outline,
            'Thanks! Your move details have been submitted to $_orgName. They\'ll follow up with a quote shortly.');
      case 'form':
      default:
        return _form(theme);
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

  InputDecoration _dec(FlutterFlowTheme theme, String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.secondaryBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  Widget _form(FlutterFlowTheme theme) {
    final textStyle = GoogleFonts.inter(color: theme.primaryText);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tell $_orgName about your move',
                style: GoogleFonts.interTight(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            const SizedBox(height: 4),
            Text(
                'Takes about 2 minutes — the more detail you give, the more accurate your quote.',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.secondaryText)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              style: textStyle,
              decoration: _dec(theme, 'Your name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              style: textStyle,
              keyboardType: TextInputType.phone,
              decoration: _dec(theme, 'Phone number'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fromCtrl,
              style: textStyle,
              maxLines: 2,
              decoration: _dec(theme, 'Moving from (full address)'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _toCtrl,
              style: textStyle,
              maxLines: 2,
              decoration: _dec(theme, 'Moving to (full address)'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _moveDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _moveDate = picked);
              },
              child: InputDecorator(
                decoration: _dec(theme, 'Preferred move date'),
                child: Text(
                  _moveDate == null
                      ? 'Tap to pick a date'
                      : DateFormat('d MMM yyyy').format(_moveDate!),
                  style: textStyle,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rooms & items',
                style: GoogleFonts.interTight(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            const SizedBox(height: 4),
            Text('e.g. "Bedroom 1" -> "Queen bed, 2 almirahs, AC unit"',
                style: GoogleFonts.inter(
                    fontSize: 11.5, color: theme.secondaryText)),
            const SizedBox(height: 10),
            for (var i = 0; i < _rooms.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _rooms[i].$1,
                        style: textStyle,
                        decoration: _dec(theme, 'Room'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _rooms[i].$2,
                        style: textStyle,
                        decoration: _dec(theme, 'Items'),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(_addRoom),
                icon: Icon(Icons.add, color: theme.primary, size: 18),
                label: Text('Add another room',
                    style: GoogleFonts.inter(color: theme.primary)),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              style: textStyle,
              maxLines: 3,
              decoration: _dec(theme, 'Anything else? (fragile items, stairs, etc.)'),
            ),
            const SizedBox(height: 20),
            if (_submitError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_submitError!,
                    style: GoogleFonts.inter(color: theme.error, fontSize: 13)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Submit',
                        style: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            color: theme.primaryBackground)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
