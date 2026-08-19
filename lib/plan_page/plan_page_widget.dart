import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
// flutter_flow_widgets.dart (FFButtonWidget) dropped 18 Aug 2026 with the
// dead "Upgrade Plan" button — re-add it when the WhatsApp support CTA
// is wired.
import '/app_session.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'plan_page_model.dart';
export 'plan_page_model.dart';

class PlanPageWidget extends StatefulWidget {
  const PlanPageWidget({super.key});

  static String routeName = 'PlanPage';
  static String routePath = '/plan';

  @override
  State<PlanPageWidget> createState() => _PlanPageWidgetState();
}

class _PlanPageWidgetState extends State<PlanPageWidget> {
  late PlanPageModel _model;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PlanPageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final session = context.watch<AppSession>();

    final planName = session.planName ?? 'Free Trial';
    final limits = session.planLimits;
    final features = session.planFeatures;
    final trialEnds = session.trialEndsAt;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text(
          'Your Plan',
          style: GoogleFonts.interTight(
            color: theme.primaryText,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Plan header card
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.primary, theme.primary.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          planName,
                          style: GoogleFonts.interTight(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            planName == 'Free Trial' ? 'TRIAL' : 'ACTIVE',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (trialEnds != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Trial ends ${_formatDate(trialEnds)}',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (session.currentOrgName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        session.currentOrgName!,
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Limits section
              if (limits.isNotEmpty) ...[
                _sectionTitle(theme, 'Usage Limits'),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      // Item 32 key fix (18 Aug 2026): this read
                      // `max_orders`, but the live data has always used
                      // `max_orders_per_month` — so the orders limit
                      // rendered "—" on every plan while being the limit
                      // that actually matters. `max_leads` was read here
                      // and written by the Super Admin editor, but exists
                      // on no plan and is enforced nowhere; dropped
                      // rather than left showing a permanent dash.
                      _limitRow(theme, 'Users', limits['max_users']),
                      _divider(theme),
                      _limitRow(
                          theme, 'Orders / month', limits['max_orders_per_month']),
                      _divider(theme),
                      _limitRow(theme, 'WhatsApp msgs / month',
                          limits['max_whatsapp_per_month']),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Features section
              if (features.isNotEmpty) ...[
                _sectionTitle(theme, 'Features'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: features.entries.map((e) {
                    final enabled = e.value == true;
                    return _featureChip(theme, _featureLabel(e.key), enabled);
                  }).toList(),
                ),
                const SizedBox(height: 32),
              ],

              // Activation CTA.
              //
              // 18 Aug 2026: the "Upgrade Plan" button and its "Razorpay
              // payment integration · Phase 3" subtitle were REMOVED, not
              // disabled. There is no payment rail yet (Item 31 is on
              // hold pending Arun's CA settling which entity bills), so a
              // confident-looking Upgrade button that answered with
              // "coming soon" was a dead end shown to exactly the vendor
              // least willing to tolerate one — someone whose trial just
              // ended. Plain text with no affordance is more honest than
              // a button that does nothing.
              //
              // WIRE THE WHATSAPP CTA HERE once the dedicated Nagarva
              // support line is live — Arun is setting one up on WhatsApp
              // Business, deliberately separate from APC's customer line
              // (pan-India means lapsed-trial contact at any hour). Use
              // kNagarvaSupportPhone from /config/app_config.dart and
              // buildWhatsAppLink() from the same file; see that const's
              // doc comment for every other place the number is needed.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.support_agent,
                        size: 26, color: theme.secondaryText),
                    const SizedBox(height: 10),
                    Text(
                      AppSession.instance.isTrialExpired
                          ? 'Your trial has ended. Contact Nagarva support '
                              'to activate your plan.'
                          : 'Contact Nagarva support to change your plan.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: theme.primaryText,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(FlutterFlowTheme theme, String title) => Text(
        title,
        style: GoogleFonts.interTight(
          color: theme.primaryText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _limitRow(FlutterFlowTheme theme, String label, dynamic raw) {
    final value = raw is int ? raw : (raw as num?)?.toInt() ?? 0;
    final display = value == -1 ? 'Unlimited' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: theme.primaryText,
              fontSize: 14,
            ),
          ),
          Text(
            display,
            style: GoogleFonts.interTight(
              color: value == -1 ? theme.primary : theme.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(FlutterFlowTheme theme) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: theme.alternate,
      );

  Widget _featureChip(FlutterFlowTheme theme, String label, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: enabled
            ? theme.primary.withOpacity(0.12)
            : theme.secondaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? theme.primary : theme.alternate,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel_outlined,
            size: 14,
            color: enabled ? theme.primary : theme.secondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: enabled ? theme.primary : theme.secondaryText,
              fontSize: 13,
              fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _featureLabel(String key) {
    const labels = {
      'whatsapp': 'WhatsApp Alerts',
      'reports': 'P&L Reports',
      'invoice': 'GST Invoice',
      'fleet': 'Fleet Tracking',
      'salary': 'Salary & PF',
    };
    return labels[key] ?? key;
  }

  String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}
