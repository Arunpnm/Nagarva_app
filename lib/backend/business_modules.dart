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

  static const _category = 'modules';
  static const _key = 'modules_on';

  /// The type the menu follows. A company that never chose sees
  /// everything, exactly as before this existed.
  String get effectiveType => businessType ?? kBizBoth;

  /// The owner has not answered yet — the one-time question shows.
  bool get needsChoice => loaded && businessType == null;

  /// Whether [pageName] belongs in the menu.
  bool isOn(String pageName) {
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
      final row = await OrgScope.read(
              SupaFlow.client.from('app_settings').select('value'))
          .eq('category', _category)
          .eq('key', _key)
          .maybeSingle();
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
    loaded = false;
    _loadedFor = null;
    notifyListeners();
  }
}

const kBizPackers = 'packers_movers';
const kBizTransport = 'transport';
const kBizBoth = 'both';
const kBizTypes = {kBizPackers, kBizTransport, kBizBoth};

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
