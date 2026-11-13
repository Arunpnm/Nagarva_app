import 'package:flutter/foundation.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// What a vendor's business does, and therefore which modules the menu
/// shows (Claude Design handoff: "What does your business do?" sheet and
/// Settings › Modules).
///
/// Stored server-side, never in the phone, because the choice belongs to
/// the company and every device signed into it must agree:
/// - the type is `organizations.business_type` — the column the mobile
///   signup already writes on approval — one of [kBizPackers],
///   [kBizTransport], [kBizBoth];
/// - per-module overrides are one `app_settings` row
///   (category `modules`, key `modules_on`), a jsonb map of page name to
///   true/false. Absent means "follow the business type".
///
/// Both writes are owner-only in the database (Tier B for organizations,
/// the 16 Sept 2026 policy split for app_settings), which is the design's
/// rule too: only the owner changes what the menu shows.
///
/// Turning a module off only hides it from the menu. Its data and its
/// route are untouched, so turning it back on loses nothing.
class BusinessModules extends ChangeNotifier {
  BusinessModules._();
  static final BusinessModules instance = BusinessModules._();

  /// null until loaded, and for a company that has not chosen yet.
  String? businessType;
  Map<String, bool> overrides = {};
  bool loaded = false;
  String? _loadedFor;

  /// Billing only (Arun, 13 Nov 2026: "use this app only for billing ...
  /// just quote, invoice, LR, money receipt, packing list"). When on, the
  /// menu shows [kBillingModules] and nothing else, whatever the business
  /// type and per-module switches say. Like every switch here it only
  /// hides menu entries: routes, data and the other settings are
  /// untouched, so turning it off brings everything back as it was.
  /// One `app_settings` row (category `modules`, key `billing_only`),
  /// owner-only by the same policy as the overrides.
  bool billingOnly = false;

  /// Billing only is part of the Growth plan and above (Arun, 13 Nov
  /// 2026): the plan feature `billing_mode`. A company that turned it on
  /// and later moved to a plan without it simply gets the full menu
  /// back; its saved choice is kept for when the plan allows it again.
  static const billingFeature = 'billing_mode';
  bool get billingAllowed => AppSession.instance.hasFeature(billingFeature);
  bool get billingActive => billingOnly && billingAllowed;

  static const _category = 'modules';
  static const _key = 'modules_on';
  static const _billingKey = 'billing_only';

  /// The type the menu follows. A company that never chose sees
  /// everything, exactly as before this existed.
  String get effectiveType => businessType ?? kBizBoth;

  /// The owner has not answered yet — the one-time question shows.
  bool get needsChoice => loaded && businessType == null;

  /// Whether [pageName] belongs in the menu.
  bool isOn(String pageName) {
    if (billingActive) return kBillingModules.contains(pageName);
    final kind = moduleKind(pageName);
    if (kind == ModuleKind.core) return true;
    final o = overrides[pageName];
    if (o != null) return o;
    return switch (kind) {
      ModuleKind.packers => effectiveType != kBizTransport,
      ModuleKind.transport => effectiveType != kBizPackers,
      _ => true,
    };
  }

  Future<void> load({bool force = false}) async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    if (!force && loaded && _loadedFor == orgId) return;
    try {
      final org = await SupaFlow.client
          .from('organizations')
          .select('business_type')
          .eq('id', orgId)
          .maybeSingle();
      final rows = await OrgScope.read(
              SupaFlow.client.from('app_settings').select('key, value'))
          .eq('category', _category)
          .inFilter('key', [_key, _billingKey]);
      Map<String, dynamic>? row;
      var billing = false;
      for (final r in (rows as List)) {
        if (r['key'] == _key) row = Map<String, dynamic>.from(r as Map);
        if (r['key'] == _billingKey) {
          final v = r['value'];
          billing = v is Map && v['on'] == true;
        }
      }
      billingOnly = billing;
      final t = org?['business_type'] as String?;
      businessType = kBizTypes.contains(t) ? t : null;
      final v = row?['value'];
      overrides = v is Map
          ? {
              for (final e in v.entries)
                if (e.value is bool) e.key.toString(): e.value as bool
            }
          : {};
      loaded = true;
      _loadedFor = orgId;
      notifyListeners();
    } catch (e) {
      // A failed read keeps the full menu — hiding modules on a network
      // blip would look like data loss.
      debugPrint('BusinessModules.load failed: $e');
    }
  }

  /// Sets the business type and clears overrides, as the design does
  /// ("Reset to recommended for this business type" is the same move).
  Future<void> setType(String type) async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null || !kBizTypes.contains(type)) return;
    await SupaFlow.client
        .from('organizations')
        .update({'business_type': type}).eq('id', orgId);
    await _saveOverrides({});
    businessType = type;
    notifyListeners();
  }

  Future<void> setModule(String pageName, bool on) async {
    final next = {...overrides, pageName: on};
    await _saveOverrides(next);
    notifyListeners();
  }

  Future<void> setBillingOnly(bool on) async {
    await SupaFlow.client.from('app_settings').upsert({
      ...OrgScope.stamp(),
      'category': _category,
      'key': _billingKey,
      'value': {'on': on},
    }, onConflict: 'org_id,category,key');
    billingOnly = on;
    notifyListeners();
  }

  Future<void> resetModules() async {
    await _saveOverrides({});
    notifyListeners();
  }

  Future<void> _saveOverrides(Map<String, bool> next) async {
    await SupaFlow.client.from('app_settings').upsert({
      ...OrgScope.stamp(),
      'category': _category,
      'key': _key,
      'value': next,
    }, onConflict: 'org_id,category,key');
    overrides = next;
  }

  void clear() {
    businessType = null;
    overrides = {};
    billingOnly = false;
    loaded = false;
    _loadedFor = null;
    notifyListeners();
  }
}

const kBizPackers = 'packers_movers';
const kBizTransport = 'transport';
const kBizBoth = 'both';
const kBizTypes = {kBizPackers, kBizTransport, kBizBoth};

/// The whole menu in Billing only mode: make a quote, turn it into an
/// order, print its documents (tax invoice, proforma, money receipt,
/// LR / bilty, packing list ... all on the order), take the payment, and
/// the registers an accountant asks for. No leads, staff, field jobs,
/// fleet, trips, expenses or salary.
const kBillingModules = <String>{
  'HomePage',
  'SurveyQuoteHubPage', // quotes
  'OrdersPage', // every document is printed from an order
  'CustomersPage',
  'PaymentsPage',
  'LrRegisterPage',
  'EwayBillsPage',
  'GstPage',
  'CreditNotesPage',
  'SettingsPage',
};

enum ModuleKind { core, packers, transport, advanced }

/// The design's MODX groups, mapped onto this app's menu pages. Anything
/// not listed is core and always shows (Dashboard, Leads, Orders,
/// Payments, Expenses, Staff, Settings ...).
const kPackersModules = <String>[
  'SurveyQuoteHubPage',
  'ReviewsPage',
  'InsuranceClaimsPage',
  'StorageBillingPage',
  'WarehousesPage',
  'MaterialsPage',
];

const kTransportModules = <String>[
  'TripsPage',
  'LrRegisterPage',
  'PartLoadPage',
  'FuelPage',
  'DriverAppPage',
  'DieselAdvancePage',
  'VehicleDocsPage',
  'EwayBillsPage',
  'HiredTrucksPage',
];

const kAdvancedModules = <String>[
  'BusinessAccountsPage',
  'ReferralsPage',
  'LostReportPage',
  'GstPage',
  'CreditNotesPage',
  'BankMatchPage',
  'CashBookPage',
  'PLReportPage',
  'PayslipsPage',
  'IncentivesPage',
  'StaffDocumentsPage',
  'LabourContractorsPage',
  'TasksPage',
  'OperationsStandalonePage',
];

ModuleKind moduleKind(String pageName) {
  if (kPackersModules.contains(pageName)) return ModuleKind.packers;
  if (kTransportModules.contains(pageName)) return ModuleKind.transport;
  if (kAdvancedModules.contains(pageName)) return ModuleKind.advanced;
  return ModuleKind.core;
}
