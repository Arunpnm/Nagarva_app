import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../booking.dart';
import '../theme.dart';
import 'common.dart';

/// Sign-in, booking and "My moves" (14 Nov 2026, list item 27).
///
/// The customer signs in with their mobile number (OTP), types their name
/// and the two full addresses, and pays the advance on Razorpay's own
/// page. The server (mkt-book) prices the move again; the app never sends
/// a price. Once Razorpay says it is paid, the move appears in My moves as
/// booked and goes out to vendors.

/// The network calls, as fields so tests can stand in for them.
class Account {
  static SupabaseClient get _db => Supabase.instance.client;

  static bool Function() signedIn = () => _db.auth.currentSession != null;
  static Future<void> Function(String phone10) sendOtp = (p) =>
      _db.auth.signInWithOtp(phone: '+91$p');
  static Future<void> Function(String phone10, String code) verifyOtp =
      (p, c) async {
    await _db.auth.verifyOTP(phone: '+91$p', token: c, type: OtpType.sms);
  };
  static Future<void> Function() signOut = () => _db.auth.signOut();

  /// {booking_id, pay_url} or {error}.
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> body) book =
      (body) async {
    try {
      final r = await _db.functions.invoke('mkt-book', body: body);
      return Map<String, dynamic>.from(r.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) return {'error': '${d['error']}'};
      return {'error': 'Could not book right now. Please try again.'};
    }
  };

  static Future<List<Map<String, dynamic>>> Function() myMoves = () async {
    final r = await _db.rpc('mkt_my_moves');
    return [for (final m in (r as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
  };

  static Future<bool> Function(String url) openUrl = (url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

InputDecoration _field(String label, {String? hint, String? prefix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      filled: true,
      fillColor: C.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

// ---- Sign in ---------------------------------------------------------------

/// Mobile number, then the 6-digit code. Pops with true once signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  String get _p => _phone.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _send() async {
    if (_p.length != 10) {
      setState(() => _error = 'Enter your 10-digit mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Account.sendOtp(_p);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final c = _code.text.trim();
    if (c.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Account.verifyOtp(_p, c);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'That code did not work. Check it and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Sign in', style: geist(22, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('We send a code to your mobile. Your moves stay under this number.',
                style: geist(13.5, color: C.secondary)),
            const SizedBox(height: 18),
            TextField(
              key: const Key('phone'),
              controller: _phone,
              enabled: !_sent,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: _field('Mobile number', prefix: '+91 '),
            ),
            if (_sent) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('code'),
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: _field('Code from SMS'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _sent = false;
                          _code.clear();
                        }),
                child: const Text('Change number'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: geist(13.5, color: C.red)),
              ),
            const SizedBox(height: 16),
            CButton(
              label: _busy ? 'Please wait…' : (_sent ? 'Sign in' : 'Send code'),
              onPressed: _busy ? null : (_sent ? _verify : _send),
            ),
          ]),
        ),
      );
}

/// Signs in first when needed. True when the customer is signed in.
Future<bool> ensureSignedIn(BuildContext context) async {
  if (Account.signedIn()) return true;
  final ok = await Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
  return ok == true;
}

// ---- Details and pay -------------------------------------------------------

/// Name and the two full addresses, then pay the advance.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.booking, required this.advance});
  final Booking booking;
  final num advance;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _name = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _pay() async {
    final b = widget.booking;
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (_from.text.trim().length < 8 || _to.text.trim().length < 8) {
      setState(() => _error = 'Please enter both full addresses.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await Account.book({
      'input': b.quoteInput(),
      'name': _name.text.trim(),
      'pickup_address': _from.text.trim(),
      'drop_address': _to.text.trim(),
      'move_date': DateFormat('yyyy-MM-dd').format(b.date!),
      'slot': b.slot,
    });
    if (!mounted) return;
    if (r['pay_url'] == null) {
      setState(() {
        _busy = false;
        _error = '${r['error'] ?? 'Could not book right now. Please try again.'}';
      });
      return;
    }
    await Account.openUrl('${r['pay_url']}');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MyMovesScreen(justBooked: true)),
        (route) => route.isFirst);
  }

  @override
  void dispose() {
    _name.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final to = b.scope == 'inter' ? b.toCity : b.fromCity;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Your details', style: geist(22, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('The mover uses these to reach you on the day.',
                  style: geist(13.5, color: C.secondary)),
              const SizedBox(height: 16),
              TextField(
                key: const Key('name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _field('Your name'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('from'),
                controller: _from,
                maxLines: 3,
                minLines: 2,
                decoration: _field('Pickup address in ${b.fromCity}',
                    hint: 'House no, street, area, landmark, pincode'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('to'),
                controller: _to,
                maxLines: 3,
                minLines: 2,
                decoration: _field('Drop address in $to',
                    hint: 'House no, street, area, landmark, pincode'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: geist(13.5, color: C.red)),
                ),
              const SizedBox(height: 14),
              Text(
                  'You pay the advance on a secure payment page. After paying, come back to this app: your move shows under My moves.',
                  style: geist(12.5, height: 1.4, color: C.secondary)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: C.card,
              border: Border(top: BorderSide(color: C.hairline)),
            ),
            child: CButton(
              label: _busy ? 'Please wait…' : 'Pay ${money(widget.advance)}',
              onPressed: _busy ? null : _pay,
            ),
          ),
        ]),
      ),
    );
  }
}

// ---- My moves --------------------------------------------------------------

class MyMovesScreen extends StatefulWidget {
  const MyMovesScreen({super.key, this.justBooked = false});
  final bool justBooked;
  @override
  State<MyMovesScreen> createState() => _MyMovesScreenState();
}

class _MyMovesScreenState extends State<MyMovesScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _moves;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the payment page: show the new status.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final m = await Account.myMoves();
      if (mounted) {
        setState(() {
          _moves = m;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your moves. Pull down to try again.');
    }
  }

  static const _jobWords = {
    'broadcast': 'Finding your mover',
    'accepted': 'Mover assigned',
    'on_the_way': 'Mover on the way',
    'arrived': 'Mover has arrived',
    'loading': 'Packing and loading',
    'in_transit': 'On the way to your new home',
    'delivered': 'Delivered',
    'cancelled': 'Cancelled',
  };

  ({String text, Color color}) _status(Map<String, dynamic> m) => switch (m['status']) {
        'awaiting_payment' => (text: 'Waiting for payment', color: C.orange),
        'cancelled' => (text: 'Not booked', color: C.secondary),
        'expired' => (text: 'Payment not done', color: C.secondary),
        _ => (
            text: _jobWords[m['job_status']] ?? 'Booked',
            color: m['job_status'] == 'cancelled' ? C.red : C.green
          ),
      };

  Widget _card(Map<String, dynamic> m) {
    final st = _status(m);
    final date = DateTime.tryParse('${m['move_date']}');
    final total = (m['total'] as num?) ?? 0;
    final adv = (m['advance'] as num?) ?? 0;
    final paid = m['status'] == 'paid';
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(k, style: geist(12.5, color: C.secondary))),
            Expanded(child: Text(v, style: geist(13))),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  m['from_city'] == m['to_city']
                      ? '${m['from_city']}'
                      : '${m['from_city']} → ${m['to_city']}',
                  style: geist(16, weight: FontWeight.w600)),
            ),
            Text(st.text, style: geist(12.5, weight: FontWeight.w600, color: st.color)),
          ]),
          if (date != null)
            Text(
                [DateFormat('EEE d MMM yyyy').format(date), m['slot']]
                    .whereType<String>()
                    .join(' · '),
                style: geist(13, color: C.secondary)),
          if (m['job_no'] != null) line('Booking no', '${m['job_no']}'),
          line('From', '${m['pickup_address'] ?? ''}'),
          line('To', '${m['drop_address'] ?? ''}'),
          line('Total', money(total)),
          line(paid ? 'Paid now' : 'Pay now', money(adv)),
          line('Pay mover', '${money(total - adv)} after delivery'),
          if (m['vendor_name'] != null) line('Mover', '${m['vendor_name']}'),
          if (m['vendor_phone'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Account.openUrl('tel:${m['vendor_phone']}'),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Call mover'),
              ),
            ),
          if (m['delivery_code'] != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: C.page, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Text('Delivery code. Give it to the mover only when everything has arrived safely.',
                      style: geist(12.5, height: 1.35, color: C.secondary)),
                ),
                const SizedBox(width: 10),
                Text('${m['delivery_code']}',
                    style: mono(22, color: C.blueText, weight: FontWeight.w600)),
              ]),
            ),
          if (m['pay_url'] != null) ...[
            const SizedBox(height: 10),
            CButton(
              label: 'Pay ${money(adv)}',
              onPressed: () => Account.openUrl('${m['pay_url']}'),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moves = _moves;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My moves'),
        actions: [
          IconButton(
              tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (_) async {
              await Account.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.justBooked)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  'After you pay, your move changes to "Finding your mover" here. It can take a minute.',
                  style: geist(13, height: 1.4, color: C.secondary)),
            ),
          if (_error != null) Text(_error!, style: geist(13.5, color: C.red)),
          if (moves == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (moves != null && moves.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text('No moves yet.',
                  textAlign: TextAlign.center, style: geist(14, color: C.secondary)),
            ),
          for (final m in moves ?? const <Map<String, dynamic>>[]) _card(m),
        ]),
      ),
    );
  }
}

/// From the first screen: sign in if needed, then My moves.
Future<void> openMyMoves(BuildContext context) async {
  if (!await ensureSignedIn(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const MyMovesScreen()));
}
