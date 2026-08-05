import '../database.dart';

/// Record of which LR copy types have been generated (migration 009,
/// Session 3). The LR itself is issued in four versions — Driver,
/// Consignor, Consignee, Transporter — identical body, different label.
/// One row per (lr_id, copy_type); the unique index on that pair is what
/// makes "generate all four" idempotent to re-run.
class LrCopiesTable extends SupabaseTable<LrCopiesRow> {
  @override
  String get tableName => 'lr_copies';

  @override
  LrCopiesRow createRow(Map<String, dynamic> data) => LrCopiesRow(data);
}

class LrCopiesRow extends SupabaseDataRow {
  LrCopiesRow(super.data);

  @override
  SupabaseTable get table => LrCopiesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get lrId => getField<String>('lr_id');
  set lrId(String? value) => setField<String>('lr_id', value);

  /// 'driver' | 'consignor' | 'consignee' | 'transporter'
  String get copyType => getField<String>('copy_type')!;
  set copyType(String value) => setField<String>('copy_type', value);

  DateTime? get generatedAt => getField<DateTime>('generated_at');
  set generatedAt(DateTime? value) =>
      setField<DateTime>('generated_at', value);

  String? get generatedBy => getField<String>('generated_by');
  set generatedBy(String? value) => setField<String>('generated_by', value);

  String? get pdfUrl => getField<String>('pdf_url');
  set pdfUrl(String? value) => setField<String>('pdf_url', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
