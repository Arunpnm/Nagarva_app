import 'package:url_launcher/url_launcher.dart';

import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/config/app_config.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Week 2 — Staff Management: add/edit staff form.
///
/// Opens as a modal bottom sheet. Pass [existing] to edit; null to add.
/// Inserts stamp org_id via OrgScope.stamp(); updates go through
/// OrgScope.write() per the repo's org-scoping convention.
///
/// Fields follow the live `staff` table: name, phone, role, branch, pin,
/// salary, pf_applicable, esic_applicable, active, permissions.
///
/// PIN: written to the `pin` column; the DB trigger (staff_hash_pin)
/// bcrypt-hashes it into `pin_hash`, which the staff-login Edge Function
/// verifies server-side. The client never compares PINs.
///
/// Permissions (Packers Bilty style): per-module View / Add / Edit / Del
/// checkbox matrix stored in staff.permissions (jsonb) — see
/// /permissions.dart for the payload shape, module keys, and role
/// presets. Picking a role pre-fills the matrix; every box can be
/// fine-tuned per person. Money modules are marked with ₹ and stay off
/// for every non-admin preset.
class StaffFormSheet extends StatefulWidget {
  const StaffFormSheet({super.key, this.existing});

  final StaffRow? existing;

  /// Returns true if a row was saved (caller should reload the list).
  static Future<bool> show(BuildContext context, {StaffRow? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StaffFormSheet(existing: existing),
    );
    return saved == true;
  }

  @override
  State<StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<StaffFormSheet> {
  static const roles = [
    'manager',
    'supervisor',
    'driver',
    'helper',
    'packer',
    'admin',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _branch;
  late final TextEditingController _pin;
  late final TextEditingController _salary;
  String _role = 'helper';
  bool _active = true;
  bool _pfApplicable = false;
  bool _esicApplicable = false;
  bool _saving = false;
  String? _error;

  /// Permission matrix state: {moduleKey: {action: bool}}.
  late Map<String, Map<String, bool>> _perms;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _branch = TextEditingController(text: s?.branch ?? '');
    // Deliberately never pre-filled with the existing PIN, even though
    // s.pin is technically readable — staff.pin is a write-only conduit
    // for the DB trigger that bcrypt-hashes it into pin_hash (see the
    // class doc comment above); showing the current secret back in a
    // plaintext field on every edit is the exact gap NAGARVA_STATUS.md's
    // "staff.pin null-out" item flags. Leaving this blank on save keeps
    // the existing PIN unchanged (see _save()'s null-if-empty payload
    // and the trigger's own "new.pin is not null and new.pin <> ''" guard).
    _pin = TextEditingController();
    _salary = TextEditingController(
        text: s?.salary == null ? '' : s!.salary!.toStringAsFixed(0));
    final r = (s?.role ?? 'helper').toLowerCase();
    _role = roles.contains(r) ? r : 'helper';
    _active = s?.active ?? true;
    _pfApplicable = s?.pfApplicable ?? false;
    _esicApplicable = s?.esicApplicable ?? false;

    // Saved matrix wins; empty/missing falls back to the role preset —
    // same rule the login/sidebar uses (StaffPermissions.effective).
    final saved = StaffPermissions.decode(s?.data['permissions']);
    _perms = StaffPermissions.isEmpty(saved)
        ? StaffPermissions.presetFor(_role)
        : saved;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _branch.dispose();
    _pin.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settingNewPin = _pin.text.trim().isNotEmpty;
      // Phase 0 credential lockdown (7 Aug 2026,
      // supabase/20260807_phase0_staff_credential_lockdown.sql):
      // pin/failed_pin_attempts/pin_locked_until are no longer in
      // `authenticated`'s UPDATE column grant on staff. PostgREST rejects
      // the whole request if any referenced column lacks grant, even ones
      // whose value isn't changing - so those three are kept out of this
      // shared map entirely. The edit path below sets a new PIN through
      // set_staff_pin() instead; the insert path (brand-new staff, no
      // prior session to protect) still writes `pin` directly further
      // down, since that migration only revoked UPDATE, not INSERT.
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'role': _role,
        'branch': _branch.text.trim().isEmpty ? null : _branch.text.trim(),
        'salary': _salary.text.trim().isEmpty
            ? null
            : double.tryParse(_salary.text.trim()),
        'pf_applicable': _pfApplicable,
        'esic_applicable': _esicApplicable,
        // Owner role: always full access regardless of whatever _perms
        // happens to hold (Step 3.2) - the matrix is disabled in the UI
        // for this case, but the write path enforces it independently
        // rather than trusting the UI state alone.
        'permissions': StaffPermissions.encode(
            StaffPermissions.isOwnerRole(_role)
                ? StaffPermissions.presetFor(_role)
                : _perms),
      };

      if (isEdit) {
        // Auth plan REVISED, item 1: deactivation must also KILL LIVE
        // SESSIONS. Staff are on their own personal phones, so a leaver
        // walks out still holding a valid JWT — and `active = false`
        // alone does nothing about that, because staff-login only checks
        // active status AT LOGIN. An already-minted token keeps working
        // until it expires.
        //
        // The app cannot revoke: that needs the admin API and the service
        // role. So the active flag is deliberately NOT in `data` above —
        // it is routed through the staff-deactivate Edge Function, which
        // flips the row and signs the user out in one call so the two
        // can't drift apart.
        final wasActive = widget.existing!.active ?? true;
        if (_active != wasActive) {
          final res = await SupaFlow.client.functions.invoke(
            'staff-deactivate',
            body: {'staff_id': widget.existing!.id, 'active': _active},
          );
          final body = res.data;
          if (body is! Map || body['ok'] != true) {
            throw Exception(
              (body is Map ? body['error'] as String? : null) ??
                  'Could not change active status.',
            );
          }
          // Surfaced, not swallowed. The row IS deactivated at this point
          // — but if the sign-out failed, that phone keeps working until
          // its token expires, and the owner needs to know that rather
          // than seeing a clean success.
          if (!_active &&
              body['had_auth_user'] == true &&
              body['sessions_revoked'] != true &&
              mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Deactivated, but their existing session could NOT be '
                  'revoked (${body['revoke_error'] ?? 'unknown error'}). '
                  'That device stays signed in until its token expires.',
                ),
                duration: const Duration(seconds: 10),
              ),
            );
          }
        }
        if (settingNewPin) {
          // set_staff_pin() (SECURITY DEFINER) replaces the old direct
          // write to pin/failed_pin_attempts/pin_locked_until now that
          // those columns aren't in `authenticated`'s UPDATE grant. It
          // still clears the lockout on a fresh PIN (Users Kickoff Step
          // 3.4: verify_staff_pin only clears these on a SUCCESSFUL login,
          // never when an owner/self sets a brand new PIN here - without
          // that, someone currently locked out would stay locked despite
          // now holding a valid PIN) and is itself owner-or-self gated, so
          // it can't be used to set a colleague's PIN from a non-owner
          // session either.
          await SupaFlow.client.rpc('set_staff_pin', params: {
            'p_staff_id': widget.existing!.id,
            'p_new_pin': _pin.text.trim(),
          });
        }
        await StaffTable().update(
          data: data,
          matchingRows: (q) =>
              OrgScope.write(q).eq('id', widget.existing!.id!),
        );
      } else {
        // New staff: no session can exist yet, so the flag - and the
        // initial PIN - go in directly. INSERT privilege on staff wasn't
        // touched by the Phase 0 column GRANT (that migration only
        // revokes UPDATE), so this still works unchanged.
        await StaffTable().insert({
          ...OrgScope.stamp(),
          ...data,
          'active': _active,
          'pin': _pin.text.trim().isEmpty ? null : _pin.text.trim(),
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // `invoke` (staff-deactivate above) throws on any non-2xx response
      // (17 Aug 2026 finding) — was showing a raw exception string here.
      //
      // Item 32: the insert above can now also be refused by the
      // plan-enforcement triggers (staff seat limit, single-branch limit,
      // expired-trial read-only). Those raise P0001 with a sentence
      // written for the vendor, so unwrap that before falling back —
      // otherwise hitting a seat limit reads as a raw PostgrestException.
      setState(() {
        _saving = false;
        _error = extractDbErrorMessage(
          e,
          fallback: extractFunctionErrorMessage(e, fallback: e.toString()),
        );
      });
    }
  }

  /// Mints a single-use device invite and shows it once.
  ///
  /// The plaintext code exists only in this dialog — the server stores
  /// only its sha256. If the owner closes it without sending, they
  /// generate a new one; there is no way to retrieve it.
  Future<void> _generateInvite() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await SupaFlow.client.functions.invoke(
        'staff-invite',
        body: {'action': 'generate', 'staff_id': widget.existing!.id},
      );
      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        throw Exception(
          (data is Map ? data['error'] as String? : null) ??
              'Could not create an invite.',
        );
      }
      if (!mounted) return;
      setState(() => _saving = false);

      final code = data['code'] as String;
      final name = (data['staff_name'] as String?) ?? 'your team member';
      final org = AppSession.instance.currentOrgName ?? 'Nagarva';
      final message = 'Hi $name, set up the $org app on your phone.\n\n'
          'Open Nagarva, tap "I have an invite code", and enter:\n\n'
          '$code\n\n'
          'This code works once and expires. Do not share it.';

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Device invite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                code,
                style: GoogleFonts.robotoMono(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Single use, and it expires. Send it to $name — they enter '
                'it on their own phone, then set their PIN.\n\n'
                'You will not be able to see this code again.',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')),
                );
              },
              child: const Text('Copy'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(buildWhatsAppLink(
                  phone: widget.existing?.phone,
                  message: message,
                ));
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('WhatsApp'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Same FunctionException-on-non-2xx bug as _save's catch above.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = extractFunctionErrorMessage(e, fallback: e.toString());
        });
      }
    }
  }

  InputDecoration _dec(BuildContext context, String label, {String? hint}) {
    final theme = FlutterFlowTheme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.inter(color: theme.secondaryText, fontSize: 13),
      hintStyle: GoogleFonts.inter(
          color: theme.secondaryText.withOpacity(0.6), fontSize: 13),
      filled: true,
      fillColor: theme.primaryBackground,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.primary, width: 1.5),
      ),
    );
  }

  // ------------------------------------------------------ permission matrix

  void _togglePerm(String moduleKey, String action, bool value) {
    setState(() {
      final actions = _perms.putIfAbsent(moduleKey, () => <String, bool>{});
      actions[action] = value;
      if (action != 'view' && value) {
        // Add/Edit/Del imply View — keep the matrix coherent.
        actions['view'] = true;
      }
      if (action == 'view' && !value) {
        // Removing View removes everything for the module.
        for (final a in kPermActions) {
          actions[a] = false;
        }
      }
    });
  }

  Widget _permissionMatrix(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    const labelColWidth = 128.0;
    const checkColWidth = 46.0;
    // Users Kickoff Step 3.2: "Owner role cannot have permissions edited
    // (always all) — render the matrix disabled with an explanatory
    // line." Checked via the alias (StaffPermissions.isOwnerRole), so
    // this also covers an existing role='admin' row without needing to
    // touch the role dropdown itself or rewrite anyone's stored role.
    final isOwner = StaffPermissions.isOwnerRole(_role);

    return Container(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.secondaryText.withOpacity(0.15)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Module Access',
                style: GoogleFonts.interTight(
                  color: theme.primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isOwner)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(
                          () => _perms = StaffPermissions.presetFor(_role)),
                  child: Text(
                    'Reset to role defaults',
                    style:
                        GoogleFonts.inter(color: theme.primary, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (isOwner) ...[
            const SizedBox(height: 4),
            Text(
              'Owner has full access to everything. This can\'t be '
              'restricted here.',
              style: GoogleFonts.inter(
                  color: theme.secondaryText,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic),
            ),
          ],
          // Horizontal scroll keeps the checkbox columns usable on phones.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: labelColWidth,
                      child: Text(
                        'PERMISSION',
                        style: GoogleFonts.inter(
                            color: theme.secondaryText,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4),
                      ),
                    ),
                    for (final a in kPermActions)
                      SizedBox(
                        width: checkColWidth,
                        child: Text(
                          kPermActionLabels[a] ?? a,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: theme.secondaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                Divider(
                    height: 10,
                    color: theme.secondaryText.withOpacity(0.15)),
                for (final m in kPermModules)
                  Row(
                    children: [
                      SizedBox(
                        width: labelColWidth,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                m.label,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    color: theme.primaryText,
                                    fontSize: 12.5),
                              ),
                            ),
                            if (m.moneyModule)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '₹',
                                  style: GoogleFonts.inter(
                                      color: theme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (final a in kPermActions)
                        SizedBox(
                          width: checkColWidth,
                          height: 32,
                          child: Checkbox(
                            value: isOwner ? true : (_perms[m.key]?[a] ?? false),
                            activeColor: theme.primary,
                            side: BorderSide(
                                color:
                                    theme.secondaryText.withOpacity(0.5)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (_saving || isOwner)
                                ? null
                                : (v) =>
                                    _togglePerm(m.key, a, v ?? false),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Applies to this staff member\'s PIN login. Picking a role fills '
            'in defaults; fine-tune any box after. ₹ = money module — off '
            'for all non-admin roles unless you enable it here.',
            style:
                GoogleFonts.inter(color: theme.secondaryText, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final textStyle =
        GoogleFonts.inter(color: theme.primaryText, fontSize: 14);

    return Padding(
      // Keep the sheet above the keyboard.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
          maxWidth: 560,
        ),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.secondaryText.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? 'Edit Staff' : 'Add Staff',
                      style: GoogleFonts.interTight(
                        color: theme.primaryText,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.secondaryText),
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _name,
                  style: textStyle,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(context, 'Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  style: textStyle,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration:
                      _dec(context, 'Phone', hint: '10-digit mobile'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // optional
                    return t.length == 10 ? null : 'Enter 10 digits';
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: _dec(context, 'Role'),
                  dropdownColor: theme.secondaryBackground,
                  style: textStyle,
                  items: [
                    for (final r in roles)
                      DropdownMenuItem(
                        value: r,
                        child: Text(r[0].toUpperCase() + r.substring(1)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _role = v ?? 'helper';
                    // Adding: role change refreshes the matrix preset.
                    // Editing: keep the saved/customised matrix — use
                    // "Reset to role defaults" to reapply explicitly.
                    if (!isEdit) {
                      _perms = StaffPermissions.presetFor(_role);
                    }
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _branch,
                        style: textStyle,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec(context, 'Branch',
                            hint: 'e.g. Chennai'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _salary,
                        style: textStyle,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _dec(context, 'Monthly Salary (₹)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pin,
                  style: textStyle,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: _dec(context, 'Login PIN',
                      hint: isEdit
                          ? 'Leave blank to keep current PIN'
                          : '4 digits — staff uses phone + PIN to log in'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // optional
                    return t.length == 4 ? null : 'PIN must be 4 digits';
                  },
                ),
                const SizedBox(height: 12),
                _permissionMatrix(context),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('PF applicable', style: textStyle),
                  value: _pfApplicable,
                  activeColor: theme.primary,
                  onChanged: (v) => setState(() => _pfApplicable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('ESIC applicable', style: textStyle),
                  value: _esicApplicable,
                  activeColor: theme.primary,
                  onChanged: (v) => setState(() => _esicApplicable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Active', style: textStyle),
                  subtitle: Text(
                    'Inactive staff cannot log in with their PIN',
                    style: GoogleFonts.inter(
                        color: theme.secondaryText, fontSize: 11.5),
                  ),
                  value: _active,
                  activeColor: theme.primary,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style:
                        GoogleFonts.inter(color: theme.error, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            isEdit ? 'Save Changes' : 'Add Staff',
                            style: GoogleFonts.interTight(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                // Auth plan REVISED item 3: remote onboarding. The owner
                // runs three branches and can't set up a supervisor's
                // phone in person — and must never hand over a credential
                // of his own. A single-use code binds that person's own
                // phone to their own staff_id.
                //
                // Only on an existing staff member: a code needs a
                // staff_id, which doesn't exist until the row is saved.
                if (isEdit) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _generateInvite,
                      icon: const Icon(Icons.qr_code_2, size: 19),
                      label: const Text('Generate device invite'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primary,
                        side: BorderSide(color: theme.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
