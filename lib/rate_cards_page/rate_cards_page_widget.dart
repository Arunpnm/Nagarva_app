import 'package:flutter/material.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
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
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  NgModuleHeader('Rate cards',
                      subtitle: 'Your prices. Every new quote uses them.',
                      actions: [
                        NgPrimaryButton(
                          compact: true,
                          height: 40,
                          icon: Icons.add_rounded,
                          label: 'New card',
                          onPressed: _newCard,
                        ),
                      ]),
                  const SizedBox(height: 14),
                  // "No suggested money" (CLAUDE.md): say so where the
                  // vendor sets prices, as the handoff does.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.amberBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 20, color: c.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All prices start at ₹0. Enter your own rates for '
                            'each service and add-on. New quotes use these prices.',
                            style: NgFonts.geist(
                                fontSize: 13, height: 1.4, color: c.soft),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_cards.isEmpty)
                    NgCard(
                      child: Text('No rate cards yet.',
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final rc in _cards) _cardRow(rc),
                    ]),
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

  Widget _cardRow(RateCardsRow rc) {
    final c = NgPalette.of(context);
    return NgListRow(
      onTap: () => context.pushNamed(
        RateCardDetailPageWidget.routeName,
        queryParameters: {'cardId': serializeParam(rc.id, ParamType.String)},
      ),
      icon: Icons.sell_outlined,
      title: rc.name,
      titleTrailing: rc.isDefault
          ? const NgPill('Default', status: NgStatus.accent)
          : (!rc.active
              ? const NgPill('Inactive', status: NgStatus.red)
              : null),
      subtitle: [
        if ((rc.code ?? '').isNotEmpty) rc.code!,
        rc.cardType,
        if ((rc.branch ?? '').isNotEmpty) rc.branch!,
      ].join(' · '),
      trailing: IconButton(
        tooltip: 'Delete rate card',
        icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.faint),
        onPressed: () => _deleteCard(rc),
      ),
    );
  }
}
