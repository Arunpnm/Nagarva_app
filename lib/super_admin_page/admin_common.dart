import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

/// Shared by the Nagarva Admin sections in this directory: load with a
/// spinner, say plainly when the section's migration has not run yet,
/// pull to refresh, and run a write with a toast.
///
/// Queries here are cross-tenant on purpose; see the note at the top of
/// super_admin_page_widget.dart. The database decides who may read or
/// write what (platform_has_role); the screens only avoid offering what
/// would be refused.
abstract class AdminSectionState<T extends StatefulWidget> extends State<T> {
  bool loading = true;

  /// Set when the tables behind this section do not exist yet.
  bool missing = false;
  String? error;

  SupabaseClient get db => SupaFlow.client;

  /// The migration that creates this section's tables, named in the
  /// empty state when they are missing.
  String get migrationFile => 'supabase/20261031_admin_panel.sql';

  Future<void> fetch();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      await fetch();
      missing = false;
      error = null;
    } on PostgrestException catch (e) {
      // 42P01 / PGRST205: relation missing; 42883 / PGRST202: function
      // missing. Both mean the migration has not been run.
      missing = const {'42P01', 'PGRST205', '42883', 'PGRST202'}.contains(e.code);
      error = missing ? null : e.message;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  /// Runs a write, says what happened, and reloads. Postgres raises a
  /// plain sentence (P0001) for every refusal in these sections.
  Future<bool> run(Future<void> Function() f, String done) async {
    try {
      await f();
      toast(done);
      await load();
      return true;
    } on PostgrestException catch (e) {
      toast(e.code == 'P0001' || e.code == '42501'
          ? (e.code == '42501' ? 'Your admin role cannot do this.' : e.message)
          : 'Could not save: ${e.message}');
    } catch (e) {
      toast('Could not save: $e');
    }
    return false;
  }

  /// The section body: spinner, migration note, error, or [children].
  Widget body(List<Widget> Function(NgPalette c) children) {
    final c = NgPalette.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (missing) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        NgEmptyState(
          icon: Icons.construction_rounded,
          title: 'Not set up yet',
          subtitle: 'Run $migrationFile in Supabase, then come back.',
        ),
      ]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        NgEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load',
          subtitle: error,
          action: TextButton(onPressed: load, child: const Text('Try again')),
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: children(c)),
    );
  }
}

final adminMoney =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// "25 min", "3 h", "2 d", then a date.
String adminAgo(dynamic ts) {
  final t = DateTime.tryParse('${ts ?? ''}')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  if (d.inDays < 7) return '${d.inDays} d';
  return DateFormat('d MMM').format(t);
}

String adminDate(dynamic ts, {bool time = false}) {
  final t = DateTime.tryParse('${ts ?? ''}')?.toLocal();
  if (t == null) return '';
  return DateFormat(time ? 'd MMM, h:mm a' : 'd MMM yyyy').format(t);
}

const kAdminRoles = <String, String>{
  'super': 'Super admin',
  'sales': 'Sales',
  'support': 'Support',
  'marketing': 'Marketing',
};

/// A short page title with a line under it, as the design's admin pages.
class AdminHeading extends StatelessWidget {
  const AdminHeading(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: NgFonts.geist(
                fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 2),
        Text(subtitle, style: NgFonts.geist(fontSize: 13, color: c.mute)),
      ]),
    );
  }
}
