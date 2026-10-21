import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/edge_function_errors.dart';
import '/backend/org_resolution.dart';
import '/backend/owner_pin.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_org_resolver.dart';
import '/components/ng_widgets.dart';
import '/components/org_switcher_sheet.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import '/l10n/gen/app_localizations.dart';

/// Vendor self-signup, approval first (Claude Design handoff, 21 Oct
/// 2026, App screen `signup`): mobile -> OTP -> business -> documents ->
/// review -> status, then the owner picks a Pro trial or Free.
///
/// It doubles as the mobile-number LOGIN for an owner who signed up this
/// way: after the OTP it routes on what the account already has — an org
/// goes straight in, an application goes to its status, nothing goes to
/// the business form. One flow, so there is no second OTP screen to keep
/// in step with this one.
///
/// Every decision is server-side (20261021_vendor_signup_approval.sql):
/// the phone on the application is the verified one on the auth user,
/// status is written only by submit/review RPCs, and the org is created
/// by `review_vendor_signup()` when the Nagarva team approves. Nothing
/// here can mark itself approved.
class VendorSignupPageWidget extends StatefulWidget {
  const VendorSignupPageWidget({super.key});

  static String routeName = 'VendorSignupPage';
  static String routePath = '/signup-mobile';

  @override
  State<VendorSignupPageWidget> createState() => _VendorSignupPageState();
}

enum _Step { loading, phone, otp, biz, docs, review, status }


class _VendorSignupPageState extends State<VendorSignupPageWidget> {
  _Step _step = _Step.loading;
  bool _busy = false;

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _city = TextEditingController();
  final _email = TextEditingController();
  final _gst = TextEditingController();
  final _ref = TextEditingController();
  String _biz = 'packers_movers';

  /// doc key -> storage path ('<uid>/<key>-<ts>.<ext>'). The visible file
  /// name is [_docNames].
  final Map<String, String> _docs = {};
  final Map<String, String> _docNames = {};
  String? _uploading;
  bool _agree = false;

  Map<String, dynamic>? _app; // the caller's vendor_signups row
  Map<String, dynamic>? _proPlan;

  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in [_phone, _code, _name, _owner, _city, _email, _gst, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  AppLocalizations get _l => AppLocalizations.of(context);

  void _flash(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtPhone(String p) {
    final d = p.replaceAll(RegExp(r'\D'), '');
    final ten = d.length > 10 ? d.substring(d.length - 10) : d;
    return ten.length == 10 ? '${ten.substring(0, 5)} ${ten.substring(5)}' : p;
  }

  // ---------------------------------------------------------------- flow

  /// A phone session that survived (app restart, back to login and in
  /// again) picks up where the account is, rather than asking for an OTP
  /// it already proved.
  Future<void> _resume() async {
    final user = SupaFlow.client.auth.currentUser;
    if (user == null || (user.phone ?? '').isEmpty) {
      setState(() => _step = _Step.phone);
      return;
    }
    await _routeAfterAuth(user);
  }

  Future<void> _routeAfterAuth(User user) async {
    try {
      final members = await SupaFlow.client
          .from('org_members')
          .select('org_id')
          .eq('user_id', user.id)
          .limit(1);
      final row = await SupaFlow.client
          .from('vendor_signups')
          .select()
          .eq('auth_user_id', user.id)
          .maybeSingle();
      _app = row;
      // An org with no pending plan choice: this is a login, go in.
      if ((members as List).isNotEmpty &&
          (row == null || row['plan_choice'] != null)) {
        await _enterApp(user);
        return;
      }
      if (row != null) {
        await _loadProPlan();
        if (row['status'] == 'rejected') _fillFrom(row);
        setState(() => _step = _Step.status);
        return;
      }
      _phone.text = _fmtPhone(user.phone ?? '').replaceAll(' ', '');
      setState(() => _step = _Step.biz);
    } catch (e) {
      setState(() => _step = _Step.phone);
      _flash(extractDbErrorMessage(e, fallback: _l.suSendFailed));
    }
  }

  void _fillFrom(Map<String, dynamic> r) {
    _name.text = r['business_name'] ?? '';
    _owner.text = r['owner_name'] ?? '';
    _city.text = r['city'] ?? '';
    _email.text = r['email'] ?? '';
    _gst.text = r['gstin'] ?? '';
    _ref.text = r['referral_code'] ?? '';
    _biz = (r['business_type'] as String?) ?? _biz;
    _docs
      ..clear()
      ..addAll({
        for (final e in Map<String, dynamic>.from(r['docs'] ?? {}).entries)
          if ((e.value as String? ?? '').isNotEmpty) e.key: e.value as String,
      });
    _docNames
      ..clear()
      ..addAll(_docs.map((k, v) => MapEntry(k, v.split('/').last)));
  }

  Future<void> _loadProPlan() async {
    try {
      _proPlan = await SupaFlow.client
          .from('subscription_plans')
          .select('trial_days, limits, features')
          .eq('code', 'pro')
          .maybeSingle();
    } catch (_) {}
  }

  Future<void> _sendOtp() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return _flash(_l.suPhBad);
    setState(() => _busy = true);
    try {
      await SupaFlow.client.auth.signInWithOtp(phone: '+91$digits');
      _code.clear();
      _startResendTimer();
      setState(() => _step = _Step.otp);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      _flash(m.contains('provider') || m.contains('disabled') ||
              m.contains('not enabled') || m.contains('unsupported')
          ? _l.suOtpUnavailable
          : _l.suSendFailed);
    } catch (_) {
      _flash(_l.suSendFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendIn = 30;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verifyOtp() async {
    final code = _code.text.trim();
    if (code.length != 6) return _flash(_l.suOtpBad);
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _busy = true);
    try {
      final res = await SupaFlow.client.auth.verifyOTP(
          phone: '+91$digits', token: code, type: OtpType.sms);
      final user = res.user;
      if (user == null) throw const AuthException('no user');
      _resendTimer?.cancel();
      await _routeAfterAuth(user);
    } catch (_) {
      _flash(_l.suOtpFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueBiz() {
    if (_name.text.trim().isEmpty ||
        _owner.text.trim().isEmpty ||
        _city.text.trim().isEmpty) {
      return _flash(_l.suNeedBz);
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      return _flash(_l.suEmailBad);
    }
    final gst = _gst.text.trim();
    if (gst.isNotEmpty && gst.length != 15) return _flash(_l.suGstBad);
    if (gst.isEmpty) _docs.remove('gstc');
    setState(() => _step = _Step.docs);
  }

  Future<void> _pickDoc(String key) async {
    final uid = SupaFlow.client.auth.currentUser?.id;
    if (uid == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    final f = picked?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return;
    final ext = (f.extension ?? 'jpg').toLowerCase();
    final path = '$uid/$key-${DateTime.now().millisecondsSinceEpoch}.$ext';
    setState(() => _uploading = key);
    try {
      await SupaFlow.client.storage.from('vendor-docs').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                contentType: ext == 'pdf'
                    ? 'application/pdf'
                    : 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
          );
      final old = _docs[key];
      setState(() {
        _docs[key] = path;
        _docNames[key] = f.name;
      });
      if (old != null) _removeObject(old);
    } catch (_) {
      _flash(_l.suUploadFailed);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  void _removeObject(String path) {
    // Best-effort: an orphaned upload costs storage, not correctness —
    // submit only ever sends the paths still in [_docs].
    SupaFlow.client.storage.from('vendor-docs').remove([path]).ignore();
  }

  void _continueDocs() {
    if ((_docs['pan'] ?? '').isEmpty) return _flash(_l.suNeedPan);
    if (_gst.text.trim().isNotEmpty && (_docs['gstc'] ?? '').isEmpty) {
      return _flash(_l.suNeedGstC);
    }
    setState(() => _step = _Step.review);
  }

  Future<void> _submit() async {
    if (!_agree) return _flash(_l.suNeedAgree);
    setState(() => _busy = true);
    try {
      final row = await SupaFlow.client.rpc('submit_vendor_signup', params: {
        'p_business_name': _name.text.trim(),
        'p_owner_name': _owner.text.trim(),
        'p_city': _city.text.trim(),
        'p_business_type': _biz,
        'p_email': _email.text.trim(),
        'p_gstin': _gst.text.trim().toUpperCase(),
        'p_referral_code': _ref.text.trim(),
        'p_docs': _docs,
      });
      // Re-read the row the server wrote rather than trusting local state.
      _app = row is Map ? Map<String, dynamic>.from(row) : _app;
      await _refreshStatus(quiet: true);
      setState(() => _step = _Step.status);
      _flash(_l.suSent);
    } catch (e) {
      _flash(extractDbErrorMessage(e, fallback: _l.suUploadFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshStatus({bool quiet = false}) async {
    final uid = SupaFlow.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await SupaFlow.client
          .from('vendor_signups')
          .select()
          .eq('auth_user_id', uid)
          .maybeSingle();
      if (row != null) _app = row;
      if (_app?['status'] == 'approved') await _loadProPlan();
      if (mounted) setState(() {});
    } catch (_) {
      if (!quiet) _flash(_l.suSendFailed);
    }
  }

  Future<void> _choosePlan(bool trial) async {
    setState(() => _busy = true);
    try {
      await SupaFlow.client
          .rpc('choose_signup_plan', params: {'p_trial': trial});
      final user = SupaFlow.client.auth.currentUser;
      if (user == null) return;
      _flash(trial ? _l.suTrOn('${_trialDays()}') : _l.suFreeOn);
      await _enterApp(user);
    } catch (e) {
      _flash(extractDbErrorMessage(e, fallback: _l.suSendFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Same landing as the email login (login_page_widget.dart), so a
  /// mobile-signup owner gets the org resolution, saved-org restore and
  /// first-run PIN prompt every other owner gets.
  Future<void> _enterApp(User user) async {
    final orgs = await resolveVendorOrgs(user);
    if (!mounted) return;
    final resolved = await resolveActiveOrg(
      availableOrgs: orgs,
      showPicker: () => showOrgSwitcherSheet(context),
    );
    if (resolved == null) {
      setState(() => _step = _Step.status);
      return;
    }
    await establishVendorSession(user, resolved.orgId, orgs);
    if (!mounted) return;
    if (await ownerNeedsPin(orgId: resolved.orgId, userId: user.id)) {
      if (mounted) context.go(SetOwnerPinPageWidget.routePath);
      return;
    }
    if (mounted) context.go(HomePageWidget.routePath);
  }

  int _trialDays() => (_proPlan?['trial_days'] as int?) ?? 30;

  void _back() {
    switch (_step) {
      case _Step.otp:
        _resendTimer?.cancel();
        setState(() => _step = _Step.phone);
      case _Step.docs:
        setState(() => _step = _Step.biz);
      case _Step.review:
        setState(() => _step = _Step.docs);
      case _Step.biz:
        if (_app?['status'] == 'rejected') {
          setState(() => _step = _Step.status);
          return;
        }
        context.go(LoginPageWidget.routePath);
      default:
        context.go(LoginPageWidget.routePath);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: _step == _Step.loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _header(c),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _step == _Step.status
                            ? _refreshStatus
                            : () async {},
                        notificationPredicate: (_) => _step == _Step.status,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [_body(c)],
                        ),
                      ),
                    ),
                    _footer(c),
                  ],
                ),
        ),
      ),
    );
  }

  int get _formIndex => switch (_step) {
        _Step.phone || _Step.otp => 0,
        _Step.biz => 1,
        _Step.docs => 2,
        _Step.review => 3,
        _ => -1,
      };

  Widget _header(NgPalette c) {
    final idx = _formIndex;
    final names = [_l.suS1, _l.suS2, _l.suS3, _l.suS4];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        children: [
          Material(
            color: c.s1,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy ? null : _back,
              child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.arrow_back_rounded, size: 22)),
            ),
          ),
          const SizedBox(width: 14),
          if (idx >= 0)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_l.suStep('${idx + 1}')} · ${names[idx]}',
                      style: NgFonts.geist(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.mute)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      for (var k = 0; k < 4; k++) ...[
                        if (k > 0) const SizedBox(width: 5),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: k <= idx ? c.acc : c.w12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(NgPalette c) => switch (_step) {
        _Step.phone => _phoneStep(c),
        _Step.otp => _otpStep(c),
        _Step.biz => _bizStep(c),
        _Step.docs => _docsStep(c),
        _Step.review => _reviewStep(c),
        _Step.status => _statusStep(c),
        _Step.loading => const SizedBox.shrink(),
      };

  Widget _title(NgPalette c, String title, [String? sub, double size = 26]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: NgFonts.geist(
                fontSize: size,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: c.text)),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(sub,
              style: NgFonts.geist(fontSize: 14.5, height: 1.45, color: c.mute)),
        ],
      ],
    );
  }

  Widget _label(NgPalette c, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: NgFonts.geist(
                fontSize: 13, fontWeight: FontWeight.w500, color: c.mute)),
      );

  Widget _field(NgPalette c,
      {required String label,
      required TextEditingController ctrl,
      required IconData icon,
      String? hint,
      TextInputType? type,
      TextCapitalization caps = TextCapitalization.words,
      int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(c, label),
          TextField(
            controller: ctrl,
            keyboardType: type,
            textCapitalization: caps,
            maxLength: maxLength,
            style: NgFonts.geist(fontSize: 15.5, color: c.text),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              prefixIcon: Icon(icon, size: 20, color: c.faint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneStep(NgPalette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.asset('assets/images/nagarva_logo.png',
              width: 52, height: 52, fit: BoxFit.cover),
        ),
        const SizedBox(height: 20),
        _title(c, _l.suCreate, _l.suPhS),
        const SizedBox(height: 20),
        _label(c, _l.suPh),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          autofocus: true,
          onSubmitted: (_) => _sendOtp(),
          style: NgFonts.geist(
              fontSize: 17, letterSpacing: 0.5, color: c.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: '98400 11223',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Text('+91',
                  style: NgFonts.geist(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.soft)),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
      ],
    );
  }

  Widget _otpStep(NgPalette c) {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, _l.suOtpT),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_l.suOtpS(_fmtPhone(digits)),
                style: NgFonts.geist(fontSize: 14.5, color: c.mute)),
            GestureDetector(
              onTap: _back,
              child: Text(_l.suChange,
                  style: NgFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.acc)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          onChanged: (v) {
            if (v.length == 6) _verifyOtp();
          },
          style: NgFonts.mono(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 12,
              color: c.text),
          decoration:
              const InputDecoration(counterText: '', hintText: '••••••'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.keyboard_rounded, size: 18, color: c.mute),
            const SizedBox(width: 7),
            Expanded(
              child: Text(_l.suEnter,
                  style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            ),
            GestureDetector(
              onTap: _resendIn > 0 || _busy
                  ? null
                  : () async {
                      await _sendOtp();
                      if (_step == _Step.otp) _flash(_l.suResent);
                    },
              child: Text(
                  _resendIn > 0 ? _l.suResendIn('$_resendIn') : _l.suResend,
                  style: NgFonts.geist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _resendIn > 0 ? c.faint : c.acc)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bizStep(NgPalette c) {
    final types = [
      ('packers_movers', _l.suTPm, _l.suTPmS, Icons.home_work_outlined),
      ('transport', _l.suTTr, _l.suTTrS, Icons.local_shipping_outlined),
      ('both', _l.suTBo, _l.suTBoS, Icons.hub_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, _l.suBzT, _l.suBzS, 24),
        const SizedBox(height: 18),
        _field(c,
            label: _l.suName,
            ctrl: _name,
            icon: Icons.storefront_outlined,
            hint: _l.suNameP),
        _field(c,
            label: _l.suOwner, ctrl: _owner, icon: Icons.person_outline),
        _field(c,
            label: _l.suCity, ctrl: _city, icon: Icons.location_city_outlined),
        _field(c,
            label: _l.suEmail,
            ctrl: _email,
            icon: Icons.mail_outline,
            hint: _l.suEmailP,
            type: TextInputType.emailAddress,
            caps: TextCapitalization.none),
        _label(c, _l.suType),
        NgCardList(
          children: [
            for (final t in types)
              InkWell(
                onTap: () => setState(() => _biz = t.$1),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(t.$4,
                          size: 22, color: _biz == t.$1 ? c.acc : c.faint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.$2,
                                style: NgFonts.geist(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                            const SizedBox(height: 2),
                            Text(t.$3,
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                          ],
                        ),
                      ),
                      Icon(
                          _biz == t.$1
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 22,
                          color: _biz == t.$1 ? c.acc : c.faint),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _field(c,
            label: _l.suGst,
            ctrl: _gst,
            icon: Icons.receipt_long_outlined,
            hint: _l.suGstP,
            caps: TextCapitalization.characters,
            maxLength: 15),
        _field(c,
            label: _l.suRef,
            ctrl: _ref,
            icon: Icons.redeem_outlined,
            caps: TextCapitalization.characters),
      ],
    );
  }

  List<(String, String, String, IconData, bool)> get _docList => [
        ('pan', _l.suPan, _l.suPanS, Icons.badge_outlined, true),
        if (_gst.text.trim().isNotEmpty)
          ('gstc', _l.suGstC, _l.suGstCS, Icons.verified_outlined, true),
        ('shop', _l.suShop, _l.suShopS, Icons.add_a_photo_outlined, false),
      ];

  Widget _docsStep(NgPalette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, _l.suDcT, _l.suDcS, 24),
        const SizedBox(height: 18),
        for (final d in _docList) ...[
          _docCard(c, d),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: c.faint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_l.suPriv,
                  style: NgFonts.geist(
                      fontSize: 12.5, height: 1.45, color: c.faint)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _docCard(NgPalette c, (String, String, String, IconData, bool) d) {
    final (key, label, sub, icon, req) = d;
    final has = (_docs[key] ?? '').isNotEmpty;
    final busy = _uploading == key;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: has ? c.w06 : c.w08),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: has ? c.greenBg : c.s2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(has ? Icons.check_circle : icon,
                size: 22, color: has ? c.green : c.soft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req ? _l.suReq : _l.suOpt,
                    style: NgFonts.geist(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: req ? c.amber : c.faint)),
                Text(label,
                    style: NgFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                Text(has ? (_docNames[key] ?? '') : sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        height: 1.4,
                        color: has ? c.green : c.mute)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4))
          else if (has)
            IconButton(
              onPressed: () {
                final p = _docs.remove(key);
                _docNames.remove(key);
                if (p != null) _removeObject(p);
                setState(() {});
              },
              icon: Icon(Icons.close_rounded, color: c.mute),
            )
          else
            NgSecondaryButton(
              label: _l.suUpload,
              icon: Icons.upload_rounded,
              height: 38,
              onPressed: _uploading != null ? null : () => _pickDoc(key),
            ),
        ],
      ),
    );
  }

  String _bizLabel(String code) => switch (code) {
        'transport' => _l.suTTr,
        'both' => _l.suTBo,
        _ => _l.suTPm,
      };

  Widget _reviewStep(NgPalette c) {
    String strip(String s) => s.replaceAll(RegExp(r'\s*\(.*\)$'), '');
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final phone = digits.isEmpty
        ? (SupaFlow.client.auth.currentUser?.phone ?? '')
        : digits;
    final sections = <(String, VoidCallback?, List<(String, String)>)>[
      (_l.suS1, null, [(_l.suMob, '+91 ${_fmtPhone(phone)}')]),
      (
        _l.suS2,
        () => setState(() => _step = _Step.biz),
        [
          (_l.suName, _name.text.trim()),
          (_l.suOwner, _owner.text.trim()),
          (_l.suCity, _city.text.trim()),
          (_l.suBt, _bizLabel(_biz)),
          (strip(_l.suEmail), _email.text.trim()),
          ('GSTIN', _gst.text.trim().toUpperCase()),
          (strip(_l.suRef), _ref.text.trim()),
        ].where((r) => r.$2.isNotEmpty).toList()
      ),
      (
        _l.suS3,
        () => setState(() => _step = _Step.docs),
        [
          for (final d in _docList) (d.$2, _docNames[d.$1] ?? _l.suNone),
        ]
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, _l.suRvT, null, 24),
        const SizedBox(height: 14),
        for (final s in sections) ...[
          NgCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.$1.toUpperCase(),
                          style: NgFonts.geist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color: c.mute)),
                    ),
                    if (s.$2 != null)
                      GestureDetector(
                        onTap: s.$2,
                        child: Text(_l.suEdit,
                            style: NgFonts.geist(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: c.acc)),
                      ),
                  ],
                ),
                for (var j = 0; j < s.$3.length; j++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: j == 0
                          ? null
                          : Border(top: BorderSide(color: c.w06)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.$3[j].$1,
                            style:
                                NgFonts.geist(fontSize: 13.5, color: c.mute)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(s.$3[j].$2,
                              textAlign: TextAlign.right,
                              style: NgFonts.geist(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: c.text)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.w08),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_l.suNext,
                  style: NgFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
              for (final n in [
                (Icons.schedule_rounded, _l.suN1),
                (Icons.phone_iphone_rounded, _l.suN2b),
                (Icons.workspace_premium_outlined, _l.suN3),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(n.$1, size: 18, color: c.acc),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(n.$2,
                            style: NgFonts.geist(
                                fontSize: 13.5, height: 1.45, color: c.soft)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () => setState(() => _agree = !_agree),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_agree ? Icons.check_box : Icons.check_box_outline_blank,
                  color: _agree ? c.acc : c.faint),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(_l.suAgreeLead,
                        style: NgFonts.geist(fontSize: 13.5, color: c.soft)),
                    _link(c, _l.lgTerms, kTermsUrl),
                    Text('·',
                        style: NgFonts.geist(fontSize: 13.5, color: c.faint)),
                    _link(c, _l.lgPriv, kPrivacyPolicyUrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The real, published documents (app_config.dart) — not a copy of
  /// them typed into the app, which would drift from what is published.
  Widget _link(NgPalette c, String label, String url) => GestureDetector(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Text(label,
            style: NgFonts.geist(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.acc,
                decoration: TextDecoration.underline)),
      );

  Widget _statusStep(NgPalette c) {
    final a = _app ?? const {};
    final st = (a['status'] as String?) ?? 'pending';
    final (tone, icon, title, sub) = switch (st) {
      'approved' => (
          NgStatus.green,
          Icons.verified_rounded,
          _l.suOkT,
          _l.suOkS(a['business_name'] ?? '')
        ),
      'rejected' => (
          NgStatus.red,
          Icons.error_outline_rounded,
          _l.suNoT,
          _l.suNoS
        ),
      _ => (
          NgStatus.amber,
          Icons.hourglass_top_rounded,
          _l.suPendT,
          _l.suPendS2(_fmtPhone(a['phone'] ?? ''))
        ),
    };
    final (:fg, :bg) = c.status(tone);
    final created = DateTime.tryParse(a['created_at'] ?? '')?.toLocal();
    final tl = [
      (_l.suTl1, 'done', created == null ? '' : dateTimeFormat('d MMM, h:mm a', created)),
      (_l.suTl2, st == 'pending' ? 'now' : st == 'rejected' ? 'bad' : 'done', ''),
      (_l.suTl3, st == 'approved' ? 'done' : 'todo', ''),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, size: 34, color: fg),
        ),
        const SizedBox(height: 18),
        _title(c, title, sub),
        if (st == 'rejected' && (a['reason'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: c.redBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: c.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(a['reason'].toString(),
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.text)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        NgCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var j = 0; j < tl.length; j++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: j == 0
                        ? null
                        : Border(top: BorderSide(color: c.w06)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        switch (tl[j].$2) {
                          'done' => Icons.check_circle,
                          'now' => Icons.radio_button_checked,
                          'bad' => Icons.error,
                          _ => Icons.radio_button_unchecked,
                        },
                        size: 20,
                        color: switch (tl[j].$2) {
                          'done' => c.green,
                          'now' => c.amber,
                          'bad' => c.red,
                          _ => c.faint,
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(tl[j].$1,
                            style: NgFonts.geist(
                                fontSize: 14.5,
                                fontWeight: tl[j].$2 == 'now' ||
                                        tl[j].$2 == 'bad'
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: tl[j].$2 == 'todo' ? c.mute : c.text)),
                      ),
                      if (tl[j].$3.isNotEmpty)
                        Text(tl[j].$3,
                            style:
                                NgFonts.geist(fontSize: 12.5, color: c.mute)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (st == 'approved' && a['plan_choice'] == null) ...[
          const SizedBox(height: 16),
          _trialCard(c),
        ],
        const SizedBox(height: 14),
        Text(_l.suAppId(a['app_no'] ?? ''),
            style: NgFonts.mono(fontSize: 12.5, color: c.faint)),
      ],
    );
  }

  Widget _trialCard(NgPalette c) {
    final days = _trialDays();
    final limits = Map<String, dynamic>.from(_proPlan?['limits'] ?? {});
    final features = Map<String, dynamic>.from(_proPlan?['features'] ?? {});
    final users = limits['max_users'];
    final orders = limits['max_orders_per_month'];
    // Bullets come from the Pro plan row itself, so they cannot promise
    // something the plan does not include.
    final rows = <String>[
      if (users is num) _l.suTrUsers('${users.toInt()}'),
      if (orders is num)
        orders < 0 ? _l.suTrOrdersAll : _l.suTrOrders('${orders.toInt()}'),
      if (features['reports'] == true) _l.suTrReports,
      if (features['multi_branch'] == true) _l.suTrBranches,
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.acc.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: c.acc, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_l.suTrT('$days'),
                    style: NgFonts.geist(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
            ],
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: c.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r,
                        style: NgFonts.geist(
                            fontSize: 13.5, height: 1.4, color: c.soft)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(_l.suTrNote('$days'),
              style: NgFonts.geist(fontSize: 12.5, height: 1.45, color: c.mute)),
        ],
      ),
    );
  }

  Widget _footer(NgPalette c) {
    final buttons = <Widget>[];
    void primary(String label, IconData icon, VoidCallback? onTap) =>
        buttons.add(NgPrimaryButton(
            label: label,
            icon: icon,
            height: 54,
            onPressed: _busy ? null : onTap));
    void secondary(String label, IconData icon, VoidCallback onTap) =>
        buttons.add(NgSecondaryButton(
            label: label,
            icon: icon,
            height: 50,
            onPressed: _busy ? null : onTap));

    switch (_step) {
      case _Step.phone:
        primary(_l.suSend, Icons.sms_outlined, _sendOtp);
      case _Step.otp:
        primary(_l.suVerify, Icons.arrow_forward_rounded, _verifyOtp);
      case _Step.biz:
        primary(_l.suContinue, Icons.arrow_forward_rounded, _continueBiz);
      case _Step.docs:
        primary(_l.suContinue, Icons.arrow_forward_rounded, _continueDocs);
      case _Step.review:
        primary(_l.suSubmit, Icons.send_rounded, _agree ? _submit : null);
      case _Step.status:
        final st = _app?['status'];
        if (st == 'approved') {
          if (_app?['plan_choice'] == null) {
            primary(_l.suTrBtn('${_trialDays()}'),
                Icons.workspace_premium_outlined, () => _choosePlan(true));
            secondary(_l.suStayFree, Icons.arrow_forward_rounded,
                () => _choosePlan(false));
          } else {
            primary(_l.suStart, Icons.arrow_forward_rounded, () async {
              final u = SupaFlow.client.auth.currentUser;
              if (u != null) await _enterApp(u);
            });
          }
        } else if (st == 'rejected') {
          primary(_l.suFix, Icons.edit_outlined,
              () => setState(() => _step = _Step.biz));
        } else {
          secondary(_l.suRefresh, Icons.refresh_rounded, _refreshStatus);
        }
        // Never a contact button that goes nowhere (app_config.dart).
        if (st != 'approved' && hasNagarvaSupportPhone) {
          secondary(_l.suWa, Icons.chat_outlined, () {
            final d = kNagarvaSupportPhone.replaceAll(RegExp(r'\D'), '');
            launchUrl(Uri.parse('https://wa.me/$d'),
                mode: LaunchMode.externalApplication);
          });
        }
        if (st != 'approved') {
          secondary(_l.suToLogin, Icons.login_rounded,
              () => context.go(LoginPageWidget.routePath));
        }
      case _Step.loading:
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.w06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ],
          if (_step == _Step.phone) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${_l.suHave} ',
                    style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                GestureDetector(
                  onTap: () => context.go(LoginPageWidget.routePath),
                  child: Text(_l.suLogin,
                      style: NgFonts.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.acc)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
