import '/components/ng_widgets.dart';
import '/backend/detail_navigation.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'new_lead_page_model.dart';
export 'new_lead_page_model.dart';

/// Create a new CRM lead, or edit an existing one when [leadId] is passed.
class NewLeadPageWidget extends StatefulWidget {
  const NewLeadPageWidget({super.key, this.leadId});

  final String? leadId;

  static String routeName = 'NewLeadPage';
  static String routePath = '/new-lead';

  @override
  State<NewLeadPageWidget> createState() => _NewLeadPageWidgetState();
}

class _NewLeadPageWidgetState extends State<NewLeadPageWidget> {
  late NewLeadPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NewLeadPageModel());

    _model.ldCustomerFieldTextController ??= TextEditingController();
    _model.ldCustomerFieldFocusNode ??= FocusNode();

    _model.ldPhoneFieldTextController ??= TextEditingController();
    _model.ldPhoneFieldFocusNode ??= FocusNode();

    _model.ldEmailFieldTextController ??= TextEditingController();
    _model.ldEmailFieldFocusNode ??= FocusNode();

    _model.ldFromCityFieldTextController ??= TextEditingController();
    _model.ldFromCityFieldFocusNode ??= FocusNode();

    _model.ldToCityFieldTextController ??= TextEditingController();
    _model.ldToCityFieldFocusNode ??= FocusNode();

    _model.ldNotesFieldTextController ??= TextEditingController();
    _model.ldNotesFieldFocusNode ??= FocusNode();

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadBranches());
    if (widget.leadId != null) {
      _model.isLoadingExisting = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _loadExistingLead());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  /// Mirrors new_order_page_widget.dart's _loadBranches() exactly — same
  /// bug (a hardcoded Chennai/Bengaluru/Coimbatore list defaulting to
  /// 'Bengaluru'), same fix: read `branches`, org-scoped; restrict a
  /// non-owner to just their own branch instead of merely defaulting to
  /// it; owner sees every active branch with no default.
  Future<void> _loadBranches() async {
    // GUARDED. Branch is mandatory, so a failure here does not merely
    // degrade the page - it blocks the whole form, and it used to do so
    // silently: empty dropdown, and "Select a branch first" on save,
    // which blames the vendor for a query that died.
    List<String> orgBranches;
    try {
      final rows = await BranchesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
      orgBranches = rows.map((r) => r.name).toList();
      _model.branchLoadError = null;
    } catch (e) {
      if (!mounted) return;
      _model.branchLoadError = 'Could not load branches: $e';
      _model.branchesLoaded = false;
      safeSetState(() {});
      return;
    }
    _model.orgHasAnyBranches = orgBranches.isNotEmpty;
    final isOwner = AppSession.instance.currentStaffId == null;
    final ownBranch = AppSession.instance.currentStaffBranch;
    _model.availableBranches = isOwner
        ? orgBranches
        : (ownBranch != null && orgBranches.contains(ownBranch)
            ? [ownBranch]
            : const <String>[]);
    _model.branchesLoaded = true;

    // Only for a fresh lead — an existing one's branch is set by
    // _loadExistingLead() and must not be overwritten here.
    if (widget.leadId == null) {
      final picked = (!isOwner && _model.availableBranches.length == 1)
          ? _model.availableBranches.first
          : null;
      _model.ldBranch = picked;
      _model.ldBranchDropdownValue = picked;
      _model.ldBranchDropdownValueController?.value = picked;
    }

    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadExistingLead() async {
    // LEAK_AUDIT.md leak #4 (Stage 1 fix): matched only on id — a foreign
    // leadId would have silently loaded another org's lead into this form.
    final rows = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.leadId!),
    );
    if (rows.isEmpty) {
      _model.isLoadingExisting = false;
      safeSetState(() {});
      return;
    }
    final lead = rows.first;

    _model.ldCustomerFieldTextController!.text = lead.customer;
    _model.ldPhoneFieldTextController!.text = lead.phone ?? '';
    _model.ldEmailFieldTextController!.text = lead.email ?? '';
    _model.ldFromCityFieldTextController!.text = lead.fromCity ?? '';
    _model.ldToCityFieldTextController!.text = lead.toCity ?? '';
    _model.ldNotesFieldTextController!.text = lead.notes ?? '';

    _model.ldApproxDate = DateTime.tryParse(lead.approxDate ?? '');
    _model.ldApproxDatePicked = _model.ldApproxDate != null;

    // Dropdowns are backed by a lazily-created FormFieldController (see
    // form_field_controller.dart) that's already built with the field
    // defaults by the time this async load completes, so the model field
    // alone isn't enough — the controller's own value has to be updated
    // too or the dropdown keeps showing the create-mode default.
    _model.ldService = lead.service;
    _model.ldServiceDropdownValue = lead.service;
    _model.ldServiceDropdownValueController?.value = lead.service;

    _model.ldStatus = lead.status;
    _model.ldStatusDropdownValue = lead.status;
    _model.ldStatusDropdownValueController?.value = lead.status;

    _model.ldSource = lead.source;
    _model.ldSourceDropdownValue = lead.source;
    _model.ldSourceDropdownValueController?.value = lead.source;

    _packageType = lead.packageType;
    _model.ldBranch = lead.branch;
    _model.ldBranchDropdownValue = lead.branch;
    _model.ldBranchDropdownValueController?.value = lead.branch;

    _model.isLoadingExisting = false;
    safeSetState(() {});
  }

  // ---- Claude Design handoff "NEW LEAD" -------------------------------
  //
  // Phone first, route card, chip groups for service / size / when /
  // source / branch, then "Next step". The payload and the branch rules
  // are unchanged; only the form around them is new.

  static const _kServices = [
    'House Shifting',
    'Office Shifting',
    'Vehicle Transport',
    'Storage',
    'Packing Only',
    'Long Distance',
  ];
  static const _kSizes = ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4+ BHK', 'Villa'];
  static const _kSources = [
    'WhatsApp',
    'Phone Call',
    'Website',
    'Porter',
    'Referral',
    'Walk-in',
    'Google',
    'JustDial',
    'Other',
  ];

  /// leads.package_type — the home size. Display-only downstream (Lead
  /// Details' Package row); nothing prices from it.
  String? _packageType;

  /// What the office does next. Sets the starting status and where Save
  /// lands; null keeps the old behaviour (status `new`, back to Leads).
  String? _nextStep;
  bool _saving = false;
  bool _showMore = false;

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  void _setDate(DateTime d) => setState(() {
        _model.ldApproxDate = DateTime(d.year, d.month, d.day);
        _model.ldApproxDatePicked = true;
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _model.ldApproxDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) _setDate(picked);
  }

  void _swapRoute() {
    final from = _model.ldFromCityFieldTextController!.text;
    _model.ldFromCityFieldTextController!.text =
        _model.ldToCityFieldTextController!.text;
    _model.ldToCityFieldTextController!.text = from;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_model.ldCustomerFieldTextController!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.nlNameRequired)));
      return;
    }
    if (_model.ldBranch == null || _model.ldBranch!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_model.branchLoadError != null
              ? 'Branches could not be loaded, so none can be picked. Pull to retry or reopen this page.'
              : 'Select a branch first.'),
        ),
      );
      return;
    }
    final isEditing = widget.leadId != null;
    if (!isEditing) {
      _model.ldStatus =
          _nextStep == 'follow' ? 'follow_up' : (_model.ldStatus ?? 'new');
    }
    setState(() => _saving = true);
    final payload = {
      'customer': _model.ldCustomerFieldTextController!.text.trim(),
      'phone': _model.ldPhoneFieldTextController!.text.trim(),
      'email': _model.ldEmailFieldTextController!.text.trim(),
      'from_city': _model.ldFromCityFieldTextController!.text.trim(),
      'to_city': _model.ldToCityFieldTextController!.text.trim(),
      'approx_date': _model.ldApproxDate?.toString(),
      'service': _model.ldService,
      'source': _model.ldSource,
      'status': _model.ldStatus,
      'branch': _model.ldBranch,
      'notes': _model.ldNotesFieldTextController!.text,
      if (_packageType != null) 'package_type': _packageType,
    };
    try {
      if (isEditing) {
        // LEAK_AUDIT.md write-gap fix: matched only on id before — now
        // also requires the row to belong to the current org.
        await LeadsTable().update(
          data: payload,
          matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
        );
      } else {
        _model.createdLead = await LeadsTable().insert({
          ...OrgScope.stamp(),
          ...payload,
        });
      }
      _model.ldSaveSuccess = true;
    } catch (_) {
      _model.ldSaveSuccess = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (_model.ldSaveSuccess != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save lead. Please try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEditing
            ? 'Lead updated successfully!'
            : 'Lead saved successfully!')));
    if (Navigator.of(context).canPop()) context.pop();
    if (isEditing) return;
    final lead = _model.createdLead;
    switch (_nextStep) {
      case 'quote':
        context.pushNamed(
          SurveyQuotePageWidget.routeName,
          queryParameters: {
            'leadId': serializeParam(lead?.id, ParamType.String),
            'leadCustomer': serializeParam(lead?.customer, ParamType.String),
            'leadPhone': serializeParam(lead?.phone, ParamType.String),
            'leadFromCity': serializeParam(lead?.fromCity, ParamType.String),
            'leadToCity': serializeParam(lead?.toCity, ParamType.String),
          }.withoutNulls,
        );
      case 'survey' || 'confirm' || 'follow':
        // Request Survey and Confirm Order both live on Lead Details.
        if (lead != null) openLeadDetail(context, lead);
      default:
        context.pushNamed(LeadsPageWidget.routeName);
    }
  }

  Widget _chips(List<String> options, String? value, ValueChanged<String> onPick,
          {String Function(String)? label}) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            NgChip(
              label: label?.call(o) ?? o,
              selected: o == value,
              onTap: () => onPick(o),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final isEditing = widget.leadId != null;
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final date = _model.ldApproxDate;
    final customDate = date != null &&
        !_sameDay(date, now) &&
        !_sameDay(date, tomorrow);
    const gap = SizedBox(height: 22);
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        appBar: NgSimpleBar(
            title: isEditing ? 'Edit Lead' : l.newLead, close: true),
        body: _model.isLoadingExisting
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  NgFieldLabel(l.nlPhone),
                  NgInput(
                    controller: _model.ldPhoneFieldTextController!,
                    focusNode: _model.ldPhoneFieldFocusNode,
                    hint: '+91 98xxx xxxxx',
                    keyboardType: TextInputType.phone,
                    mono: true,
                  ),
                  gap,
                  NgFieldLabel(l.nlName),
                  NgInput(
                    controller: _model.ldCustomerFieldTextController!,
                    focusNode: _model.ldCustomerFieldFocusNode,
                    hint: l.nlName,
                  ),
                  gap,
                  NgFieldLabel(l.nlRoute),
                  _routeCard(context),
                  gap,
                  NgFieldLabel(l.nlService),
                  _chips(_kServices, _model.ldService, (v) => setState(() {
                        _model.ldService = v;
                        _model.ldServiceDropdownValue = v;
                      })),
                  const SizedBox(height: 10),
                  _chips(_kSizes, _packageType,
                      (v) => setState(() => _packageType = v)),
                  gap,
                  NgFieldLabel(l.nlWhen),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    NgChip(
                        label: l.nlToday,
                        selected: _sameDay(date, now),
                        onTap: () => _setDate(now)),
                    NgChip(
                        label: l.nlTomorrow,
                        selected: _sameDay(date, tomorrow),
                        onTap: () => _setDate(tomorrow)),
                    NgChip(
                        label: customDate
                            ? DateFormat('d MMM yyyy').format(date)
                            : l.nlPickDate,
                        selected: customDate,
                        onTap: _pickDate),
                  ]),
                  gap,
                  NgFieldLabel(l.nlSource),
                  _chips(_kSources, _model.ldSource, (v) => setState(() {
                        _model.ldSource = v;
                        _model.ldSourceDropdownValue = v;
                      })),
                  gap,
                  NgFieldLabel(l.nlBranch),
                  if (_model.branchLoadError != null)
                    Text(_model.branchLoadError!,
                        style: NgFonts.geist(fontSize: 13, color: c.red))
                  else if (_model.branchesLoaded &&
                      _model.availableBranches.isEmpty)
                    Text(l.nlNoBranches,
                        style: NgFonts.geist(fontSize: 13, color: c.amber))
                  else
                    _chips(_model.availableBranches, _model.ldBranch,
                        (v) => setState(() {
                              _model.ldBranch = v;
                              _model.ldBranchDropdownValue = v;
                            })),
                  if (!isEditing) ...[
                    gap,
                    NgFieldLabel(l.nlNextStep),
                    _nextStepGrid(context),
                  ],
                  gap,
                  InkWell(
                    onTap: () => setState(() => _showMore = !_showMore),
                    child: Row(children: [
                      Text(l.nlMore,
                          style: NgFonts.geist(fontSize: 14, color: c.acc)),
                      Icon(
                          _showMore
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                          color: c.acc),
                    ]),
                  ),
                  if (_showMore || isEditing) ...[
                    const SizedBox(height: 12),
                    NgInput(
                      controller: _model.ldEmailFieldTextController!,
                      focusNode: _model.ldEmailFieldFocusNode,
                      hint: l.nlEmail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    NgInput(
                      controller: _model.ldNotesFieldTextController!,
                      focusNode: _model.ldNotesFieldFocusNode,
                      hint: l.nlNotes,
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(top: BorderSide(color: c.w06)),
            ),
            child: NgPrimaryButton(
              label: isEditing ? l.nlUpdateLead : l.saveLead,
              icon: Icons.check_rounded,
              height: 54,
              onPressed: _saving ? null : _save,
            ),
          ),
        ),
      ),
    );
  }

  Widget _routeCard(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    Widget line(TextEditingController ctrl, FocusNode? node, String hint,
            Widget leading) =>
        Row(children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: node,
              style: NgFonts.geist(fontSize: 16, color: c.text),
              cursorColor: c.acc,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: NgFonts.geist(fontSize: 16, color: c.faint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ]);
    return NgCard(
      padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(children: [
              line(
                _model.ldFromCityFieldTextController!,
                _model.ldFromCityFieldFocusNode,
                l.nlMovingFrom,
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.green, width: 3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Divider(height: 1, color: c.w08),
              ),
              line(
                _model.ldToCityFieldTextController!,
                _model.ldToCityFieldFocusNode,
                l.nlMovingTo,
                Icon(Icons.location_on_outlined, size: 20, color: c.acc),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          NgHeaderButtonBox(icon: Icons.swap_vert_rounded, onTap: _swapRoute),
        ],
      ),
    );
  }

  Widget _nextStepGrid(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget card(String key, IconData icon, String title, String sub) =>
        Expanded(
          child: NgOptionCard(
            icon: icon,
            title: title,
            subtitle: sub,
            selected: _nextStep == key,
            onTap: () => setState(
                () => _nextStep = _nextStep == key ? null : key),
          ),
        );
    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          card('follow', Icons.call_outlined, l.nlStepFollow,
              l.nlStepFollowSub),
          const SizedBox(width: 10),
          card('survey', Icons.home_work_outlined, l.nlStepSurvey,
              l.nlStepSurveySub),
        ]),
      ),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          card('quote', Icons.request_quote_outlined, l.nlStepQuote,
              l.nlStepQuoteSub),
          const SizedBox(width: 10),
          card('confirm', Icons.check_circle_outline_rounded,
              l.nlStepConfirm, l.nlStepConfirmSub),
        ]),
      ),
    ]);
  }
}
