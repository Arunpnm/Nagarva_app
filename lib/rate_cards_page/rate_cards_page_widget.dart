import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'rate_card_detail_page_widget.dart';

/// Rate Cards (Session 4, Part C-2). Live schema confirmed directly
/// against the DB (rate_cards + 4 child tables — charges/rules/
/// floor_charges/multipliers). Every org has one seeded "Standard Rate
/// Card" with 16 charges, confirmed live, matching the brief.
///
/// This module is the admin CRUD for a rate card's own charge heads/
/// distance-CFT rules/floor charges/seasonal multipliers. Actually
/// turning a survey's CFT into an auto-quote (the brief's own "note" on
/// what this is for) is a separate, larger integration into the
/// survey-quote builder — not attempted here; flagged as a follow-up.
class RateCardsPageWidget extends StatefulWidget {
  const RateCardsPageWidget({super.key});

  static String routeName = 'RateCardsPage';
  static String routePath = '/rate-cards';

  @override
  State<RateCardsPageWidget> createState() => _RateCardsPageWidgetState();
}

class _RateCardsPageWidgetState extends State<RateCardsPageWidget>
    with RefreshOnPopMixin<RateCardsPageWidget> {
  bool _loading = true;
  List<RateCardsRow> _cards = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _cards = await RateCardsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load rate cards: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newCard() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Rate Card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true),
            TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Code')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(nameCtrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final inserted = await RateCardsTable().insert({
        ...OrgScope.stamp(),
        'name': name,
        if (codeCtrl.text.trim().isNotEmpty) 'code': codeCtrl.text.trim(),
      });
      await _load();
      if (mounted && inserted.id != null) {
        context.pushNamed(
          RateCardDetailPageWidget.routeName,
          queryParameters: {
            'cardId': serializeParam(inserted.id, ParamType.String),
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Rate Cards',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newCard,
        icon: const Icon(Icons.add),
        label: const Text('New Card'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  if (_cards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No rate cards yet.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final c in _cards) _cardRow(theme, c),
                ],
              ),
            ),
    );
  }

  // Item 11 sweep (17 Aug 2026): rate_cards had a live column but no
  // delete UI. Soft delete specifically — pricing changes constantly and
  // old cards are referenced by historical quotes, so a hard delete
  // would orphan them.
  Future<void> _deleteCard(RateCardsRow c) async {
    if (c.id == null) return;
    final deleted = await DeleteAction.run(
      context,
      table: 'rate_cards',
      id: c.id!,
      entityLabel: 'rate card',
      check: () async => DeleteCheck.allow,
      onDeleted: _load,
    );
    if (deleted) await _load();
  }

  Widget _cardRow(FlutterFlowTheme theme, RateCardsRow c) {
    return InkWell(
      onTap: () => context.pushNamed(
        RateCardDetailPageWidget.routeName,
        queryParameters: {'cardId': serializeParam(c.id, ParamType.String)},
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      if ((c.code ?? '').isNotEmpty) c.code,
                      c.cardType,
                      if ((c.branch ?? '').isNotEmpty) c.branch,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            if (c.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Default',
                    style: GoogleFonts.inter(fontSize: 10, color: theme.primary)),
              ),
            if (!c.active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.error.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Inactive',
                    style: GoogleFonts.inter(fontSize: 10, color: theme.error)),
              ),
            IconButton(
              tooltip: 'Delete rate card',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: theme.error),
              onPressed: () => _deleteCard(c),
            ),
          ],
        ),
      ),
    );
  }
}
