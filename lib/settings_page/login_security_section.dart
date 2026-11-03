import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/app_session.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';

import '/backend/edge_function_errors.dart';
/// Settings › Login & security (Claude Design handoff, screen `sec`), the
/// parts below the owner's App PIN card: login email, change password,
/// staff PIN resets and signing out other devices.
///
/// Deliberately not built: biometric login (no biometric package in the
/// app) and the per-device list (`device_bindings` does not exist on the
/// live database — its migration was never run). A switch or a list that
/// nothing backs would be a decoy.
class LoginSecuritySections extends StatefulWidget {
  const LoginSecuritySections({super.key});

  @override
  State<LoginSecuritySections> createState() => _LoginSecuritySectionsState();
}

class _LoginSecuritySectionsState extends State<LoginSecuritySections> {
  List<StaffRow> _staff = const [];
  Set<String> _withPin = const {};
  bool _loading = true;
  bool _signingOut = false;

  /// set_staff_pin() is owner-only in the database.
  bool get _isOwner => AppSession.instance.currentStaffId == null;

  /// The owner's REAL login email. Phone-signup owners have none (Supabase
  /// returns ""), and owner PIN login gives them an internal anchor
  /// address (@owner.nagarva.in, pin-login) that is never shown or mailed.
  String? get _email {
    final e = SupaFlow.client.auth.currentUser?.email;
    if (e == null || e.isEmpty || e.endsWith('@owner.nagarva.in')) {
      return null;
    }
    return e;
  }

  String? get _phone {
    final p = SupaFlow.client.auth.currentUser?.phone;
    return (p == null || p.isEmpty) ? null : p;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final staff = await StaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
      // Which staff have a PIN, without bringing the hash to the phone.
      final withPin = await OrgScope.read(
              SupaFlow.client.from('staff').select('id'))
          .eq('active', true)
          .not('pin_hash', 'is', null);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _withPin = {for (final r in withPin) '${r['id']}'};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final email = _email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (email != null) ...[
          const SizedBox(height: 18),
          NgSectionHeader(l.lsMy),
          const SizedBox(height: 8),
          NgCardList(children: [
            NgListRow(
              icon: Icons.mail_outline_rounded,
              title: l.lsMyEmail,
              subtitle: email,
            ),
            NgListRow(
              icon: Icons.password_rounded,
              title: l.lsChangePw,
              trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
              onTap: () => _changePassword(email),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: c.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.lsForgot,
                    style: NgFonts.geist(
                        fontSize: 12.5, height: 1.4, color: c.mute)),
              ),
            ],
          ),
        ],
        // BUG-018 (3 Nov 2026): a mobile-signup owner saw a blank "Login
        // email" row and a Change password that asked for a password they
        // never had. Show the mobile they log in with, and let them add an
        // email + password as a second way in.
        if (email == null && _phone != null && _isOwner) ...[
          const SizedBox(height: 18),
          NgSectionHeader(l.lsMy),
          const SizedBox(height: 8),
          NgCardList(children: [
            NgListRow(
              icon: Icons.phone_iphone_rounded,
              title: 'Login mobile',
              subtitle: '+${_phone!.replaceAll('+', '')}',
            ),
            NgListRow(
              icon: Icons.mail_outline_rounded,
              title: 'Add login email & password',
              subtitle: 'Optional — a second way to sign in besides OTP',
              trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
              onTap: _addEmail,
            ),
          ]),
        ],
        const SizedBox(height: 18),
        NgSectionHeader(l.lsStaffPins),
        const SizedBox(height: 6),
        Text(_isOwner ? l.lsStaffPinsSub : l.lsOwnerOnly,
            style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_staff.isNotEmpty)
          NgCardList(children: [for (final s in _staff) _staffRow(c, l, s)]),
        if (email != null || _phone != null) ...[
          const SizedBox(height: 18),
          Material(
            color: c.redBg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _signingOut ? null : _signOutOthers,
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 19, color: c.red),
                    const SizedBox(width: 8),
                    Text(l.lsSignOutAll,
                        style: NgFonts.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.red)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _staffRow(NgPalette c, AppLocalizations l, StaffRow s) {
    final lockedUntil = s.getField<String>('pin_locked_until');
    final locked = lockedUntil != null &&
        (DateTime.tryParse(lockedUntil)?.isAfter(DateTime.now()) ?? false);
    final fails = s.getField<int>('failed_pin_attempts') ?? 0;
    final hasPin = _withPin.contains(s.id);
    final sub = [
      if ((s.role ?? '').isNotEmpty)
        s.role![0].toUpperCase() + s.role!.substring(1),
      if ((s.phone ?? '').isNotEmpty) s.phone!,
    ].join(' · ');
    return NgListRow(
      leading: NgAvatar(s.name),
      title: s.name,
      subtitle: [
        sub,
        locked ? l.lsLocked(fails) : (hasPin ? l.lsPinSet : l.lsNoPin),
      ].where((x) => x.isNotEmpty).join('\n'),
      trailing: _isOwner
          // Fixed width: the button's row expands, and a list row's
          // trailing slot is unbounded.
          ? SizedBox(
              width: 124,
              child: NgSecondaryButton(
                label: l.lsResetPin,
                icon: Icons.lock_reset_rounded,
                height: 38,
                onPressed: () => _resetPin(s),
              ),
            )
          : null,
    );
  }

  Future<void> _resetPin(StaffRow s) async {
    final l = AppLocalizations.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => _PinDialog(name: s.name),
    );
    if (pin == null || s.id == null) return;
    try {
      await SupaFlow.client
          .rpc('set_staff_pin', params: {'p_staff_id': s.id, 'p_new_pin': pin});
      _toast(l.lsPinSetFor(s.name));
      await _load();
    } catch (e) {
      _toast('${friendlyError(e)}');
    }
  }

  Future<void> _changePassword(String email) async {
    final l = AppLocalizations.of(context);
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PasswordDialog(email: email),
    );
    if (done == true) _toast(l.lsPwDone);
  }

  Future<void> _addEmail() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AddEmailDialog(),
    );
    if (ok == true) {
      _toast('Saved. Check that inbox for a confirmation link to finish '
          'setting up email login.');
      if (mounted) setState(() {});
    }
  }

  Future<void> _signOutOthers() async {
    final l = AppLocalizations.of(context);
    setState(() => _signingOut = true);
    try {
      await SupaFlow.client.auth.signOut(scope: SignOutScope.others);
      _toast(l.lsAllOut);
    } catch (e) {
      _toast('${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.name});
  final String name;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    InputDecoration dec(String label) =>
        InputDecoration(labelText: label, counterText: '');
    final fmt = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text('${l.lsResetPin} · ${widget.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _a,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            inputFormatters: fmt,
            decoration: dec(l.lsNewPin),
          ),
          TextField(
            controller: _b,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            inputFormatters: fmt,
            decoration: dec(l.lsConfPin),
          ),
          const SizedBox(height: 8),
          Text(l.lsTellStaff,
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: NgFonts.geist(fontSize: 12.5, color: c.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () {
            if (_a.text.length != 4) {
              setState(() => _err = l.lsPinBad);
            } else if (_a.text != _b.text) {
              setState(() => _err = l.lsPinMismatch);
            } else {
              Navigator.pop(context, _a.text);
            }
          },
          child: Text(l.lsSetPin),
        ),
      ],
    );
  }
}

/// Adds an email + password to a phone-signup owner (BUG-018). No current
/// password is asked for: they never had one, and they are already signed
/// in on this device.
class _AddEmailDialog extends StatefulWidget {
  const _AddEmailDialog();

  @override
  State<_AddEmailDialog> createState() => _AddEmailDialogState();
}

class _AddEmailDialogState extends State<_AddEmailDialog> {
  final _mail = TextEditingController();
  final _new = TextEditingController();
  final _conf = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _mail.dispose();
    _new.dispose();
    _conf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final mail = _mail.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      return setState(() => _err = 'Enter a valid email address.');
    }
    if (_new.text.length < 8) return setState(() => _err = l.lsPwShort);
    if (_new.text != _conf.text) return setState(() => _err = l.lsPwMismatch);
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await SupaFlow.client.auth
          .updateUser(UserAttributes(email: mail, password: _new.text));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = '${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    return AlertDialog(
      title: const Text('Add login email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _mail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _new,
            obscureText: true,
            decoration: InputDecoration(labelText: l.lsNewPw),
          ),
          TextField(
            controller: _conf,
            obscureText: true,
            decoration: InputDecoration(labelText: l.lsConfPw),
          ),
          const SizedBox(height: 8),
          Text('You can keep using mobile OTP as well.',
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: NgFonts.geist(fontSize: 12.5, color: c.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});
  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _conf = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _conf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_cur.text.isEmpty) return setState(() => _err = l.lsPwCurReq);
    if (_new.text.length < 8) return setState(() => _err = l.lsPwShort);
    if (_new.text != _conf.text) return setState(() => _err = l.lsPwMismatch);
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // Supabase does not check the old password on update, so it is
      // checked here first: a wrong one stops the change.
      await SupaFlow.client.auth
          .signInWithPassword(email: widget.email, password: _cur.text);
      await SupaFlow.client.auth
          .updateUser(UserAttributes(password: _new.text));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = '${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    Widget field(TextEditingController t, String label) => TextField(
          controller: t,
          obscureText: true,
          decoration: InputDecoration(labelText: label),
        );
    return AlertDialog(
      title: Text(l.lsChangePw),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          field(_cur, l.lsCurPw),
          field(_new, l.lsNewPw),
          field(_conf, l.lsConfPw),
          const SizedBox(height: 8),
          Text(l.lsPwSub, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: NgFonts.geist(fontSize: 12.5, color: c.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(l.lsUpdatePw),
        ),
      ],
    );
  }
}
