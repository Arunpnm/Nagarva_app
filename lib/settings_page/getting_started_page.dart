import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/app_session.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'support_tickets_page.dart';

/// Help & support -> Getting started (13 Nov 2026).
///
/// The tester guide, inside the app (Arun: "is it possible to implement
/// this guide inside the app?"). A new company works through the main
/// jobs of a normal day, in order, and ticks each one off. Ticks are kept
/// on this phone, per company; they are a personal checklist, not data.
///
/// Each step can open the screen it is about. Reporting a problem goes
/// to the existing "Questions & replies" (support tickets), so nothing
/// here depends on a phone number being set up.
class GettingStartedPage extends StatefulWidget {
  const GettingStartedPage({super.key});

  @override
  State<GettingStartedPage> createState() => _GettingStartedPageState();
}

class _Step {
  const _Step(this.id, this.title, this.how, [this.path, this.open]);
  final String id;
  final String title;
  final String how;
  final String? path;
  final String? open;
}

const _steps = <_Step>[
  _Step('lead', 'Add a lead',
      'A customer who called about a house move. Name, phone, from and to.',
      '/leads', 'Open Leads'),
  _Step('survey', 'Do a survey for that lead',
      'List the items to move. Try the photo survey too.', '/leads',
      'Open Leads'),
  _Step('quote', 'Make a quote and send it',
      'Send the quote link to your own WhatsApp first.', '/leads',
      'Open Leads'),
  _Step('accept', 'Accept the quote like a customer',
      'Open the link on your phone and accept it.'),
  _Step('order', 'See the order and set the move date',
      'An accepted quote becomes an order.', '/orders', 'Open Orders'),
  _Step('staff', 'Add a staff member and invite them',
      'Staff, their name, Invite to app. They get a joining code.', '/users',
      'Open Staff'),
  _Step('join', 'Join as staff on a second phone',
      'On the first screen tap "I\'m staff · join my company" and enter the code.'),
  _Step('job', 'Run the move day from the staff phone',
      'Assign the staff member to the order, then follow the job steps.',
      '/orders', 'Open Orders'),
  _Step('invoice', 'Make the invoice and record a payment',
      'From the order, make the invoice. Then record what was paid.',
      '/payments', 'Open Payments'),
  _Step('expense', 'Add an expense and check the profit',
      'Add one expense for the order, then look at the order profit.',
      '/expenses', 'Open Expenses'),
  _Step('look', 'Change the language and the theme',
      'Both buttons are at the top of the Home screen.'),
  _Step('lock', 'Close the app and unlock it again',
      'Use your PIN, or fingerprint if you turned it on in Settings.',
      '/settings', 'Open Settings'),
];

class _GettingStartedPageState extends State<GettingStartedPage> {
  Set<String> _done = {};

  String get _key =>
      'ng_getting_started_${AppSession.instance.currentOrgId ?? 'none'}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getStringList(_key) ?? const [];
      if (mounted) setState(() => _done = saved.toSet());
    } catch (_) {}
  }

  Future<void> _toggle(String id) async {
    setState(() => _done.contains(id) ? _done.remove(id) : _done.add(id));
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _done.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final done = _steps.where((s) => _done.contains(s.id)).length;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          const NgModuleHeader('Getting started'),
          const SizedBox(height: 8),
          Text(
              'Work through one real job from start to finish. Tick each '
              'step when it is done.',
              style: NgFonts.geist(fontSize: 13.5, height: 1.4, color: c.soft)),
          const SizedBox(height: 14),
          // Progress
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: done / _steps.length),
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    backgroundColor: c.w08,
                    color: c.accBtn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('$done of ${_steps.length}',
                style: NgFonts.geist(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
          ]),
          const SizedBox(height: 16),
          for (var i = 0; i < _steps.length; i++) ...[
            _stepCard(c, i + 1, _steps[i]),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          _label(c, 'Found a problem?'),
          Container(
            decoration: BoxDecoration(
                color: c.s1, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Tell us what you tapped, what you expected, and your '
                    'phone model. Small things count: a wrong word, a button '
                    'that is hard to reach, a slow screen.',
                    style: NgFonts.geist(
                        fontSize: 13.5, height: 1.4, color: c.soft)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SupportTicketsPage())),
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text('Write to Nagarva support'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _label(c, 'Good to know'),
          Container(
            decoration: BoxDecoration(
                color: c.s1, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              children: [
                for (final t in const [
                  'The app needs internet. It does not work offline yet.',
                  'Android only for now. There is no iPhone app yet.',
                  'Tamil, Hindi, Kannada, Telugu and Malayalam are marked Beta. Tell us about words that read oddly.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.info_outline_rounded,
                              size: 16, color: c.mute),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t,
                              style: NgFonts.geist(
                                  fontSize: 13.5, height: 1.4, color: c.soft)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(NgPalette c, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: NgFonts.geist(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: c.mute)),
      );

  Widget _stepCard(NgPalette c, int n, _Step s) {
    final ticked = _done.contains(s.id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ticked ? c.green.withValues(alpha: 0.45) : c.w08),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggle(s.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ticked ? c.green : Colors.transparent,
                    border: Border.all(
                        color: ticked ? c.green : c.hairline(0.25), width: 2),
                  ),
                  child: ticked
                      ? const Icon(Icons.check_rounded,
                          size: 17, color: Colors.white)
                      : Text('$n',
                          style: NgFonts.geist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.mute)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                      const SizedBox(height: 3),
                      Text(s.how,
                          style: NgFonts.geist(
                              fontSize: 13, height: 1.4, color: c.soft)),
                      if (s.path != null && !ticked) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () => context.go(s.path!),
                          child: Text(s.open ?? 'Open'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
