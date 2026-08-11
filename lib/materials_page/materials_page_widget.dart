import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'material_form_sheet.dart';
import 'materials_page_model.dart';
export 'materials_page_model.dart';

/// Packing material inventory management.
///
/// Was an empty shell with 8 hardcoded fake SKUs (CLAUDE.md "Empty shells" /
/// Phase 2 roadmap item). Now backed by the `materials` table, org-scoped
/// (requires supabase/phase1_add_org_id.sql to be run first).
///
/// Add/Restock: was a snackbar stub ("not built yet") — now opens
/// MaterialFormSheet (see material_form_sheet.dart) to add a new SKU or,
/// tapping an existing row, edit/restock it.
class MaterialsPageWidget extends StatefulWidget {
  const MaterialsPageWidget({super.key});

  static String routeName = 'MaterialsPage';
  static String routePath = '/materials';

  @override
  State<MaterialsPageWidget> createState() => _MaterialsPageWidgetState();
}

class _MaterialsPageWidgetState extends State<MaterialsPageWidget> {
  late MaterialsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => MaterialsPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await _reload();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  Future<void> _reload() async {
    _model.materialsOut = await MaterialsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('name'),
    );
    _model.materialsList = (_model.materialsOut ?? []).toList().cast<MaterialsRow>();
    safeSetState(() {});
  }

  Future<void> _addMaterial() async {
    final saved = await MaterialFormSheet.show(context);
    if (saved) await _reload();
  }

  Future<void> _editMaterial(MaterialsRow m) async {
    final saved = await MaterialFormSheet.show(context, existing: m);
    if (saved) await _reload();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  bool _isLow(MaterialsRow m) {
    final qty = m.quantity ?? 0;
    final min = m.minStock ?? 0;
    return min > 0 && qty < min;
  }

  Widget _statCard(BuildContext context, String label, String value,
      {bool danger = false}) {
    return Flexible(
      flex: 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: FlutterFlowTheme.of(context).labelMedium.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText,
                      letterSpacing: 0.0,
                    ),
              ),
              Text(
                value,
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.interTight(),
                      color: danger
                          ? FlutterFlowTheme.of(context).error
                          : FlutterFlowTheme.of(context).primaryText,
                      letterSpacing: 0.0,
                    ),
              ),
            ].divide(const SizedBox(height: 4.0)),
          ),
        ),
      ),
    );
  }

  Widget _materialRow(BuildContext context, MaterialsRow m) {
    final low = _isLow(m);
    final qtyLabel =
        '${(m.quantity ?? 0).toStringAsFixed(m.quantity == m.quantity?.roundToDouble() ? 0 : 1)} ${m.unit ?? ''}'
            .trim();
    return InkWell(
      onTap: () => _editMaterial(m),
      borderRadius: BorderRadius.circular(10.0),
      child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16.0, 14.0, 16.0, 14.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(),
                        color: FlutterFlowTheme.of(context).primaryText,
                        letterSpacing: 0.0,
                      ),
                ),
                Text(
                  low
                      ? 'Reorder < ${(m.minStock ?? 0).toStringAsFixed(0)}'
                      : 'OK',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: low
                            ? FlutterFlowTheme.of(context).error
                            : FlutterFlowTheme.of(context).secondaryText,
                        letterSpacing: 0.0,
                      ),
                ),
              ].divide(const SizedBox(height: 3.0)),
            ),
            Container(
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).primaryBackground,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10.0, 4.0, 10.0, 4.0),
                child: Text(
                  qtyLabel,
                  style: FlutterFlowTheme.of(context).labelMedium.override(
                        font: GoogleFonts.inter(),
                        color: low
                            ? FlutterFlowTheme.of(context).error
                            : FlutterFlowTheme.of(context).primaryText,
                        letterSpacing: 0.0,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materials = _model.materialsList;
    final lowStockCount = materials.where(_isLow).length;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              '95925ruu' /* Materials */,
            ),
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _statCard(
                            context, 'Total SKUs', '${materials.length}'),
                        _statCard(context, 'Low Stock', '$lowStockCount',
                            danger: lowStockCount > 0),
                      ].divide(const SizedBox(width: 12.0)),
                    ),
                    Text(
                      'Inventory',
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(),
                            color: FlutterFlowTheme.of(context).primaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    if (materials.isEmpty)
                      Text(
                        _model.materialsOut == null
                            ? 'Loading…'
                            : 'No materials tracked yet for this org.',
                        style: FlutterFlowTheme.of(context)
                            .bodySmall
                            .override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      )
                    else
                      ...materials.map((m) => _materialRow(context, m)),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 16.0, 0.0, 16.0),
                      child: FFButtonWidget(
                        // Was a snackbar stub ("not built yet"); now opens
                        // MaterialFormSheet to add a new SKU. Tap an
                        // existing row above to edit/restock it instead.
                        onPressed: _addMaterial,
                        text: FFLocalizations.of(context).getText(
                          'lnbmsxqs' /* Add / Restock Item */,
                        ),
                        icon: const Icon(
                          Icons.add_box,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor:
                              FlutterFlowTheme.of(context).primaryBackground,
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle: TextStyle(
                            color:
                                FlutterFlowTheme.of(context).primaryBackground,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
