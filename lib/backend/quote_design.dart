import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

/// Settings › Quote design (Claude Design handoff, screen `qtheme`): how
/// the quotation PDF looks. One `app_settings` row per company, category
/// `documents` (the area it governs, beside the other document settings),
/// key `quote_design`, value `{"theme": "1b", "color": "#D9480F"}`.
/// Writing it is owner-only in the database.
///
/// Absent means [QuoteDesign.standard]: the navy colour band every quote
/// carried before this screen existed, so no vendor's quotes change until
/// they choose to.
class QuoteDesign {
  const QuoteDesign({required this.theme, required this.color});

  /// The design's theme ids: 1a Classic, 1b Bold band, 1c Sidebar,
  /// 1d Minimal, 1e Corporate, 1f Letterhead.
  final String theme;

  /// `#RRGGBB`. Minimal ignores it and prints in black.
  final String color;

  static const standard = QuoteDesign(theme: '1b', color: '#16324F');

  int get colorValue {
    final hex = (theme == '1d' ? '#1A1A1A' : color).replaceFirst('#', '');
    return int.tryParse('FF$hex', radix: 16) ?? 0xFF16324F;
  }

  Map<String, dynamic> toJson() => {'theme': theme, 'color': color};

  static QuoteDesign fromJson(Object? v) {
    if (v is! Map) return standard;
    final t = v['theme'];
    final c = v['color'];
    return QuoteDesign(
      theme: kQuoteThemes.contains(t) ? t as String : standard.theme,
      color: c is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(c)
          ? c
          : standard.color,
    );
  }

  static const _category = 'documents';
  static const _key = 'quote_design';

  static Future<QuoteDesign> load() async {
    try {
      final row = await OrgScope.read(
              SupaFlow.client.from('app_settings').select('value'))
          .eq('category', _category)
          .eq('key', _key)
          .maybeSingle();
      return fromJson(row?['value']);
    } catch (_) {
      // A failed read prints the standard design rather than no quote.
      return standard;
    }
  }

  Future<void> save() => SupaFlow.client.from('app_settings').upsert({
        ...OrgScope.stamp(),
        'category': _category,
        'key': _key,
        'value': toJson(),
      }, onConflict: 'org_id,category,key');
}

const kQuoteThemes = ['1a', '1b', '1c', '1d', '1e', '1f'];

/// Brand colours offered in Settings. The first six are the design's
/// originals (qtColors); six more were added 13 Nov 2026 so that vendors
/// in the same town are less likely to land on the same look. All are
/// dark enough for white text on a band.
const kQuoteColors = [
  '#1F3A5F', // navy
  '#D9480F', // orange
  '#1F5C3D', // green
  '#0E6E6A', // teal
  '#7A1E2C', // maroon
  '#1A1A1A', // black
  '#3B2A7A', // indigo
  '#8A1C5B', // magenta
  '#6B4A12', // bronze
  '#0B5D8C', // ocean blue
  '#B3261E', // red
  '#3F4A56', // slate
];

/// The same list under the name the other documents use.
const kDocumentColors = kQuoteColors;
