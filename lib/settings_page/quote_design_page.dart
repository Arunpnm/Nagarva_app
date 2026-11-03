import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/quote_design.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/logo_upload_card.dart';
import '/components/ng_widgets.dart';
import '/components/pdf_branding.dart';
import '/components/pdf_view_page.dart';
import '/components/quote_pdf.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';

import '/backend/edge_function_errors.dart';
/// Settings › Quote design (Claude Design handoff, screen `qtheme`): the
/// quotation PDF's theme and brand colour, the logo, a sample preview and
/// Save. QuotePdf reads the saved [QuoteDesign] when a quote is printed.
///
/// Owner only, like the other document settings: the `app_settings`
/// write is owner-only in the database.
class QuoteDesignPage extends StatefulWidget {
  const QuoteDesignPage({super.key});

  static const routeName = 'QuoteDesignPage';
  static const routePath = '/quote-design';

  @override
  State<QuoteDesignPage> createState() => _QuoteDesignPageState();
}

class _QuoteDesignPageState extends State<QuoteDesignPage> {
  QuoteDesign? _design;
  bool _saving = false;
  bool _previewing = false;

  bool get _isOwner => AppSession.instance.currentStaffId == null;

  @override
  void initState() {
    super.initState();
    QuoteDesign.load().then((d) {
      if (mounted) setState(() => _design = d);
    });
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final d = _design;
    if (d == null) return;
    setState(() => _saving = true);
    try {
      await d.save();
      _toast(l.qdSaved);
    } catch (e) {
      _toast(l.dwSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A quote laid out in the chosen design, with the vendor's own
  /// letterhead and logo and plainly sample customer details.
  Future<void> _preview() async {
    final d = _design;
    if (d == null) return;
    setState(() => _previewing = true);
    try {
      OrganizationsRow? orgRow;
      final orgId = OrgScope.currentOrgId;
      if (orgId != null) {
        final rows = await OrganizationsTable()
            .queryRows(queryFn: (q) => q.eq('id', orgId));
        if (rows.isNotEmpty) orgRow = rows.first;
      }
      final logo = await PdfBranding.fetchBytes(orgRow?.logoUrl);
      final bytes = await QuotePdf.generate(
        design: d,
        leadRef: 'SAMPLE',
        org: OrgProfile.resolve(orgRow),
        boilerplate: const DocumentBoilerplate(),
        customerName: 'Sample customer',
        fromCity: 'Chennai',
        toCity: 'Bengaluru',
        charges: const {'transport': 12000, 'packing': 3000},
        subtotal: 15000,
        gstPct: 18,
        gstAmount: 2700,
        total: 17700,
        interstate: true,
        logoBytes: logo,
      );
      if (!mounted) return;
      await PdfViewPage.open(context,
          title: AppLocalizations.of(context).qdTitle, bytes: bytes);
    } catch (e) {
      _toast('${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final d = _design;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgSimpleBar(title: l.qdTitle),
      body: SafeArea(
        top: false,
        child: d == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Text(l.qdSub,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                  const SizedBox(height: 16),
                  NgSectionHeader(l.qdTheme),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                    children: [
                      for (final t in kQuoteThemes) _themeCard(c, l, d, t),
                    ],
                  ),
                  const SizedBox(height: 18),
                  NgSectionHeader(l.qdColor),
                  const SizedBox(height: 8),
                  NgCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final hex in kQuoteColors)
                          _swatch(c, d, hex),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  NgSectionHeader(l.qdLogo),
                  const SizedBox(height: 8),
                  const LogoUploadCard(),
                  const SizedBox(height: 18),
                  NgSecondaryButton(
                    label: l.qdPreview,
                    icon: Icons.picture_as_pdf_outlined,
                    onPressed: _previewing ? null : _preview,
                  ),
                  const SizedBox(height: 10),
                  NgPrimaryButton(
                    label: l.qdSave,
                    onPressed: !_isOwner || _saving ? null : _save,
                  ),
                ],
              ),
      ),
    );
  }

  String _name(AppLocalizations l, String t) => switch (t) {
        '1a' => l.qdTheme1A,
        '1b' => l.qdTheme1B,
        '1c' => l.qdTheme1C,
        '1d' => l.qdTheme1D,
        '1e' => l.qdTheme1E,
        _ => l.qdTheme1F,
      };

  String _desc(AppLocalizations l, String t) => switch (t) {
        '1a' => l.qdThemeDesc1A,
        '1b' => l.qdThemeDesc1B,
        '1c' => l.qdThemeDesc1C,
        '1d' => l.qdThemeDesc1D,
        '1e' => l.qdThemeDesc1E,
        _ => l.qdThemeDesc1F,
      };

  Widget _themeCard(
      NgPalette c, AppLocalizations l, QuoteDesign d, String t) {
    final on = d.theme == t;
    final ink = Color(QuoteDesign(theme: t, color: d.color).colorValue);
    const paper = Color(0xFFFFFFFF);
    const line = Color(0xFFDDDBD6);
    Widget bar(double w, {double h = 3, Color color = line}) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        );
    // A miniature of the page, after the design's theme cards.
    final lines = Column(
      crossAxisAlignment:
          t == '1f' ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (!['1b', '1c'].contains(t)) bar(double.infinity, h: 2, color: ink),
        bar(60),
        bar(80),
        bar(80),
        bar(64),
      ],
    );
    final page = Container(
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(6),
        border: t == '1e' ? Border.all(color: ink) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t == '1c') Container(width: 26, color: ink),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t == '1b') Container(height: 28, color: ink),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: lines,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 10, 10),
                    child: bar(30, h: 4, color: ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NgRadius.card),
        side: BorderSide(color: on ? c.acc : c.w06, width: on ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(NgRadius.card),
        onTap: () => setState(() => _design = QuoteDesign(theme: t, color: d.color)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: page),
              const SizedBox(height: 10),
              Row(children: [
                Flexible(
                  child: Text(_name(l, t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                ),
                if (on) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_circle_rounded, size: 16, color: c.acc),
                ],
              ]),
              Text(_desc(l, t),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(fontSize: 12, color: c.mute)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(NgPalette c, QuoteDesign d, String hex) {
    final on = d.color.toUpperCase() == hex.toUpperCase();
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return GestureDetector(
      onTap: () => setState(() => _design = QuoteDesign(theme: d.theme, color: hex)),
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: on ? color : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
