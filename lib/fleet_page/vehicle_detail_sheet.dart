import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fleet vehicle detail view + edit sheet (parity brief Part 2c).
///
/// FleetPage previously only rendered a read-only list with no way to open,
/// view in full, or edit a vehicle at all (not even a tap handler) —
/// insurance/permit expiry could be seen on the list card's badge but never
/// updated once they'd actually expired. This sheet covers both halves the
/// brief asks for: a detail view (opened by tapping a vehicle card) with an
/// Edit action, and the edit form itself (also reachable directly for
/// "Add Vehicle"). Deliberately does NOT build expiry alert notifications —
/// parked per the brief.
class VehicleDetailSheet extends StatefulWidget {
  const VehicleDetailSheet({super.key, this.existing, this.startInEdit = false});

  final VehiclesRow? existing;
  final bool startInEdit;

  bool get isEdit => existing != null;

  /// Returns true if the row was saved (caller should reload the list).
  static Future<bool> show(
    BuildContext context, {
    VehiclesRow? existing,
    bool startInEdit = false,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          VehicleDetailSheet(existing: existing, startInEdit: startInEdit),
    );
    return saved == true;
  }

  @override
  State<VehicleDetailSheet> createState() => _VehicleDetailSheetState();
}

class _VehicleDetailSheetState extends State<VehicleDetailSheet> {
  static const _statuses = ['active', 'maintenance', 'inactive'];
  static final _dateFmt = DateFormat('MMM d, yyyy');

  late bool _editing;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _regNo;
  late final TextEditingController _vehicleType;
  late final TextEditingController _driverName;
  late final TextEditingController _notes;
  String _status = 'active';
  DateTime? _insuranceExpiry;
  DateTime? _permitExpiry;
  DateTime? _lastService;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Add Vehicle (no existing row) always starts in edit mode — there's
    // nothing to "view" yet.
    _editing = widget.startInEdit || !widget.isEdit;
    final v = widget.existing;
    _regNo = TextEditingController(text: v?.regNo ?? '');
    _vehicleType = TextEditingController(text: v?.vehicleType ?? '');
    _driverName = TextEditingController(text: v?.driverName ?? '');
    _notes = TextEditingController(text: v?.notes ?? '');
    _status = _statuses.contains(v?.status) ? v!.status! : 'active';
    _insuranceExpiry = v?.insuranceExpiry;
    _permitExpiry = v?.permitExpiry;
    _lastService = v?.lastService;
  }

  @override
  void dispose() {
    _regNo.dispose();
    _vehicleType.dispose();
    _driverName.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    final theme = FlutterFlowTheme.of(context);
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2060),
      builder: (context, child) => wrapInMaterialDatePickerTheme(
        context,
        child!,
        headerBackgroundColor: theme.primary,
        headerForegroundColor: Colors.white,
        headerTextStyle: theme.headlineLarge.override(
          font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
          color: Colors.white,
        ),
        pickerBackgroundColor: theme.secondaryBackground,
        pickerForegroundColor: theme.primaryText,
        selectedDateTimeBackgroundColor: theme.primary,
        selectedDateTimeForegroundColor: Colors.white,
        actionButtonForegroundColor: theme.primary,
        iconSize: 24,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = {
        'reg_no': _regNo.text.trim(),
        'vehicle_type': _vehicleType.text.trim().isEmpty
            ? null
            : _vehicleType.text.trim(),
        'driver_name':
            _driverName.text.trim().isEmpty ? null : _driverName.text.trim(),
        'status': _status,
        'insurance_expiry': _insuranceExpiry?.toIso8601String(),
        'permit_expiry': _permitExpiry?.toIso8601String(),
        'last_service': _lastService?.toIso8601String(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      };
      if (widget.isEdit) {
        await VehiclesTable().update(
          data: data,
          matchingRows: (q) =>
              OrgScope.write(q).eq('id', widget.existing!.id!),
        );
      } else {
        await VehiclesTable().insert({...OrgScope.stamp(), ...data});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _detailRow(BuildContext context, IconData icon, String label,
      String value, {Color? valueColor}) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: theme.secondaryText)),
                const SizedBox(height: 2),
                Text(value,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: valueColor ?? theme.primaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context, String label, DateTime? value,
      ValueChanged<DateTime?> onChanged) {
    final theme = FlutterFlowTheme.of(context);
    final expired = value != null && value.isBefore(DateTime.now());
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await _pickDate(value);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        // Min 48dp tall — parity brief Part 5e tap-target audit.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border:
              Border.all(color: theme.secondaryText.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.event, size: 18, color: theme.secondaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value == null ? label : '$label: ${_dateFmt.format(value)}',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: expired ? theme.error : theme.primaryText,
                  fontWeight: expired ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (value != null)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final v = widget.existing;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.secondaryText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing
                          ? (widget.isEdit ? 'Edit Vehicle' : 'Add Vehicle')
                          : (v?.regNo ?? 'Vehicle'),
                      style: GoogleFonts.interTight(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText,
                      ),
                    ),
                  ),
                  if (!_editing)
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                    ),
                  // Min 48x48dp close target (Part 5e).
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _editing
                    ? _buildEditForm(theme)
                    : _buildDetailView(context, v!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(BuildContext context, VehiclesRow v) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(context, Icons.local_shipping, 'Type', v.vehicleType ?? '-'),
        _detailRow(context, Icons.person, 'Driver', v.driverName ?? '-'),
        _detailRow(context, Icons.info_outline, 'Status', v.status ?? '-'),
        _detailRow(
          context,
          Icons.verified_user,
          'Insurance expiry',
          v.insuranceExpiry == null
              ? 'Not set'
              : _dateFmt.format(v.insuranceExpiry!),
          valueColor: v.insuranceExpiry != null &&
                  v.insuranceExpiry!.isBefore(DateTime.now())
              ? theme.error
              : null,
        ),
        _detailRow(
          context,
          Icons.assignment_turned_in,
          'Permit expiry',
          v.permitExpiry == null ? 'Not set' : _dateFmt.format(v.permitExpiry!),
          valueColor:
              v.permitExpiry != null && v.permitExpiry!.isBefore(DateTime.now())
                  ? theme.error
                  : null,
        ),
        _detailRow(context, Icons.build, 'Last service',
            v.lastService == null ? 'Not set' : _dateFmt.format(v.lastService!)),
        if ((v.notes ?? '').isNotEmpty)
          _detailRow(context, Icons.notes, 'Notes', v.notes!),
      ],
    );
  }

  Widget _buildEditForm(FlutterFlowTheme theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: TextStyle(color: theme.error)),
            ),
          TextFormField(
            controller: _regNo,
            decoration: const InputDecoration(labelText: 'Registration No *'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _vehicleType,
            decoration:
                const InputDecoration(labelText: 'Vehicle type (e.g. Tempo)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _driverName,
            decoration: const InputDecoration(labelText: 'Driver name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in _statuses)
                DropdownMenuItem(value: s, child: Text(s))
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 14),
          _dateField(context, 'Insurance expiry', _insuranceExpiry,
              (d) => setState(() => _insuranceExpiry = d)),
          const SizedBox(height: 10),
          _dateField(context, 'Permit expiry', _permitExpiry,
              (d) => setState(() => _permitExpiry = d)),
          const SizedBox(height: 10),
          _dateField(context, 'Last service', _lastService,
              (d) => setState(() => _lastService = d)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(_saving ? 'Saving...' : 'Save Vehicle'),
            ),
          ),
        ],
      ),
    );
  }
}
