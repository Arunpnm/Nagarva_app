import 'fy_numbering_card.dart';
import '/nav_items.dart';
import '/app_session.dart';
import '/backend/owner_pin.dart';
import '/backend/session_logout.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/notification_bell.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
import '/main.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'business_settings_section.dart';
import 'settings_page_model.dart';
export 'settings_page_model.dart';

/// App settings and profile.
class SettingsPageWidget extends StatefulWidget {
  const SettingsPageWidget({super.key});

  static String routeName = 'SettingsPage';
  static String routePath = '/settings';

  @override
  State<SettingsPageWidget> createState() => _SettingsPageWidgetState();
}

class _SettingsPageWidgetState extends State<SettingsPageWidget> {
  late SettingsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SettingsPageModel());
    _model.notificationsEnabled = NotificationPrefs.popupsEnabled;

    // Was hardcoded placeholder data (CLAUDE.md known bug #4) — load the
    // real business profile for the signed-in org.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final orgId = AppSession.instance.currentOrgId;
      if (orgId != null) {
        final orgs = await OrganizationsTable().queryRows(
          queryFn: (q) => q.eq('id', orgId).limit(1),
        );
        _model.org = orgs.isNotEmpty ? orgs.first : null;
        safeSetState(() {});
      }
      final porterRows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'porter_enabled'),
      );
      _model.porterEnabled = porterRows.isNotEmpty &&
          (porterRows.first.value ?? '').toLowerCase() == 'true';
      safeSetState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  static const Map<String, String> _kLanguageNames = {
    'en': 'English',
    'ta': 'தமிழ்',
    'hi': 'हिन्दी',
    'kn': 'ಕನ್ನಡ',
    'te': 'తెలుగు',
    'ml': 'മലയാളം',
  };

  // ---- Hub (Claude Design handoff, "SETTINGS HUB") ----------------------
  //
  // One screen of grouped rows; each opens its own page. What used to be
  // stacked on this one page (PIN, business identity, porter switch,
  // language and theme chips) now lives behind the row that names it.
  // The read-only "Company" card is gone: Business details edits the same
  // fields.

  bool get _isOwner => AppSession.instance.currentStaffId == null;

  /// A settings sub-page: shared top bar, module header, then [children].
  void _openSub(String title, List<Widget> Function(BuildContext) children) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        backgroundColor: NgPalette.of(ctx).bg,
        appBar: const NgTopBar(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            NgModuleHeader(title),
            const SizedBox(height: 14),
            ...children(ctx),
          ],
        ),
      ),
    ));
  }

  Widget _porterCard() => StatefulBuilder(builder: (context, setLocal) {
        final c = NgPalette.of(context);
        final l = AppLocalizations.of(context);
        return NgCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.ngSetPorter,
                        style: NgFonts.geist(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(l.ngSetPorterSub,
                        style: NgFonts.geist(
                            fontSize: 12.5, height: 1.35, color: c.mute)),
                  ],
                ),
              ),
              Switch(
                value: _model.porterEnabled,
                onChanged: (v) async {
                  setLocal(() => _model.porterEnabled = v);
                  safeSetState(() {});
                  await SettingsTable().upsert(
                    {
                      'key': 'porter_enabled',
                      ...OrgScope.stamp(),
                      'value': v.toString(),
                      'updated_at': DateTime.now().toIso8601String(),
                    },
                    onConflict: 'org_id,key',
                  );
                },
              ),
            ],
          ),
        );
      });

  static const _kVariants = ['light', 'dark', 'midnight'];

  String _variantLabel(String v) {
    final l = AppLocalizations.of(context);
    return switch (v) {
      'dark' => l.ngSetThemeDark,
      'midnight' => l.ngSetThemeMidnight,
      _ => l.ngSetThemeLight,
    };
  }

  Future<void> _pickLanguage() async {
    final current = FFLocalizations.of(context).languageCode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NgPalette.of(context).sheet,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
      builder: (ctx) {
        final c = NgPalette.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(AppLocalizations.of(ctx).ngSetLanguage,
                      style: NgFonts.geist(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                ),
                for (final e in _kLanguageNames.entries)
                  ListTile(
                    title: Text(e.value,
                        style: NgFonts.geist(
                            fontSize: 14.5,
                            fontWeight: e.key == current
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: c.text)),
                    trailing: e.key == current
                        ? Icon(Icons.check_rounded, color: c.acc, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      MyApp.of(context).setLocale(e.key);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(IconData icon, String label,
      {String? sub, String? value, Widget? trailing, VoidCallback? onTap}) {
    final c = NgPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            NgIconTile(icon: icon, color: c.acc),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: NgFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.text)),
                  if ((sub ?? '').isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(sub!,
                        style: NgFonts.geist(
                            fontSize: 12, height: 1.35, color: c.mute)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              Text(value, style: NgFonts.geist(fontSize: 13, color: c.mute)),
              const SizedBox(width: 6),
            ],
            trailing ??
                Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title,
                style: NgFonts.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NgPalette.of(context).text)),
          ),
          NgCardList(children: rows),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final s = AppSession.instance;
    final logo = (s.currentOrgLogoUrl ?? '').trim();
    final variant = FlutterFlowTheme.effectiveVariant(context);
    final lang = FFLocalizations.of(context).languageCode;
    final sections = <Widget>[
      NgModuleHeader(l.settings),
      NgCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              clipBehavior: Clip.antiAlias,
              child: logo.isNotEmpty
                  ? Image.network(logo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                          'assets/images/nagarva_logo.png',
                          fit: BoxFit.cover))
                  : Image.asset('assets/images/nagarva_logo.png',
                      fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _model.org?.name ??
                          s.currentOrgName ??
                          s.currentStaffName ??
                          '',
                      style: NgFonts.geist(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                      _isOwner
                          ? l.ngRoleOwner
                          : (s.currentStaffName ?? l.ngRoleStaff),
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                ],
              ),
            ),
          ],
        ),
      ),
      _group(l.ngSetApp, [
        _row(Icons.translate_rounded, l.ngSetLanguage,
            value: _kLanguageNames[lang] ?? lang, onTap: _pickLanguage),
        _row(
          Icons.light_mode_outlined,
          l.ngSetTheme,
          value: _variantLabel(variant),
          trailing: Icon(Icons.sync_rounded, size: 20, color: c.faint),
          onTap: () {
            final i = _kVariants.indexOf(variant);
            MyApp.of(context)
                .setThemeVariant(_kVariants[(i + 1) % _kVariants.length]);
          },
        ),
        _row(
          Icons.notifications_active_outlined,
          l.ngSetNotifications,
          sub: l.ngSetNotificationsSub,
          trailing: Switch(
            value: _model.notificationsEnabled,
            onChanged: (v) {
              safeSetState(() => _model.notificationsEnabled = v);
              NotificationPrefs.setPopupsEnabled(v);
            },
          ),
        ),
      ]),
      _group(l.ngSetBusiness, [
        _row(Icons.storefront_outlined, l.ngSetBizDetails,
            sub: l.ngSetBizDetailsSub,
            onTap: () => _openSub(l.ngSetBizDetails,
                (_) => [
                      const BusinessSettingsSection(),
                      const SizedBox(height: 14),
                      _porterCard(),
                    ])),
        _row(Icons.view_in_ar_outlined, l.ngSetCft,
            sub: l.ngSetCftSub,
            onTap: () => context.pushNamed(SurveyPricingPage.routeName)),
        // Owner/admin/manager, the same people roll_over_number_series
        // accepts — offering it to staff would only end in a refusal.
        if (isOwnerOrManagerSession)
          _row(Icons.event_repeat_outlined, l.ngSetFy,
              sub: l.ngSetFySub,
              onTap: () => _openSub(l.ngSetFy, (_) => [const FyNumberingCard()])),
      ]),
      if (_isOwner)
        _group(l.ngSetSecurity, [
          _row(Icons.lock_outline_rounded, l.ngSetLogin,
              sub: l.ngSetLoginSub,
              onTap: () => _openSub(
                  l.ngSetLogin, (_) => [const _PinSettingCard()])),
        ]),
      _group(l.ngSetAccount, [
        if (_isOwner)
          _row(Icons.workspace_premium_outlined, l.ngSetPlan,
              sub: l.ngSetPlanSub,
              onTap: () => context.pushNamed(PlanPageWidget.routeName)),
        // Item 11.6: recycle bin. Owner-only, as before.
        if (_isOwner)
          _row(Icons.restore_from_trash_outlined, l.ngSetRecycle,
              sub: l.ngSetRecycleSub,
              onTap: () => context.pushNamed(RecycleBinPage.routeName)),
        // Not owner-gated: review expects the privacy policy reachable
        // from a normal staff session too (see HelpAboutPage).
        _row(Icons.support_agent_outlined, l.ngSetHelp,
            sub: l.ngSetHelpSub,
            onTap: () => context.pushNamed(HelpAboutPage.routeName)),
      ]),
      Material(
        color: c.redBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => performLogout(context),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, size: 19, color: c.red),
                const SizedBox(width: 8),
                Text(l.logout,
                    style: NgFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.red)),
              ],
            ),
          ),
        ),
      ),
      Center(
        child: Text('Nagarva $kAppVersion',
            style: NgFonts.mono(fontSize: 12, color: c.faint)),
      ),
    ];
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: const NgTopBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            sections[i],
          ],
        ],
      ),
    );
  }
}

class _PinSettingCard extends StatefulWidget {
  const _PinSettingCard();

  @override
  State<_PinSettingCard> createState() => _PinSettingCardState();
}

class _PinSettingCardState extends State<_PinSettingCard> {
  final _pinController = TextEditingController();
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // The write, the 4-digit validation and the bound-vs-active org
    // disambiguation all moved to backend/owner_pin.dart on 28 Aug 2026,
    // when SetOwnerPinPage needed the same behaviour. Two copies of this
    // rule would drift — the org-targeting subtlety below was itself a
    // live bug once, and it is exactly the kind that survives in a
    // duplicate. One writer.
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await saveOwnerPin(context, _pinController.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.saved) _pinController.clear();
      // Null message == the user cancelled the disambiguation; say
      // nothing rather than invent an error for a deliberate choice.
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('App PIN',
              style: NgFonts.geist(
                  fontWeight: FontWeight.w700, color: theme.primaryText)),
          const SizedBox(height: 4),
          Text(
            'Set or change the 4-digit PIN used to sign in on this and '
            'other devices.',
            style:
                NgFonts.geist(fontSize: 12.5, color: theme.secondaryText),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration:
                      const InputDecoration(labelText: 'New PIN', counterText: ''),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white),
                  child: Text(_saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_message!,
                  style: NgFonts.geist(
                      fontSize: 12, color: theme.secondaryText)),
            ),
        ],
      ),
    );
  }
}
