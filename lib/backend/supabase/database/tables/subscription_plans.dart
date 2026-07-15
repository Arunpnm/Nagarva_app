import '../database.dart';

class SubscriptionPlansTable extends SupabaseTable<SubscriptionPlansRow> {
  @override
  String get tableName => 'subscription_plans';

  @override
  SubscriptionPlansRow createRow(Map<String, dynamic> data) =>
      SubscriptionPlansRow(data);
}

class SubscriptionPlansRow extends SupabaseDataRow {
  SubscriptionPlansRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => SubscriptionPlansTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // 13 Jul 2026: reconciled against owner-confirmed live schema —
  // subscription_plans(id, code, name, price_inr, billing_period,
  // is_default_trial, limits, features, active, created_at). Previously this
  // class had `name` (short slug) + `display_name` (human label), which was
  // backwards from the live schema and meant every plan.displayName read
  // silently returned null (column doesn't exist) — that bug is why the
  // plan name always fell back to "Free Trial" everywhere. Now: `code` is
  // the short slug ('trial'/'starter'/'pro'), `name` is the human label.
  String? get code => getField<String>('code');
  set code(String? value) => setField<String>('code', value);

  String? get name => getField<String>('name');
  set name(String? value) => setField<String>('name', value);

  bool? get active => getField<bool>('active');
  set active(bool? value) => setField<bool>('active', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  double? get priceInr => getField<double>('price_inr');
  set priceInr(double? value) => setField<double>('price_inr', value);

  String? get billingPeriod => getField<String>('billing_period');
  set billingPeriod(String? value) =>
      setField<String>('billing_period', value);

  // JSONB fields — returned as Map<String, dynamic> by PostgREST
  dynamic get limits => getField<dynamic>('limits');
  set limits(dynamic value) => setField<dynamic>('limits', value);

  dynamic get features => getField<dynamic>('features');
  set features(dynamic value) => setField<dynamic>('features', value);

  bool? get isDefaultTrial => getField<bool>('is_default_trial');
  set isDefaultTrial(bool? value) =>
      setField<bool>('is_default_trial', value);
}
