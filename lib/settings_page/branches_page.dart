import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/database/database.dart';
import '/backend/supabase/org_scope.dart';
import '/components/load_error_state.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Settings → Branches (27 Aug 2026).
///
/// Exists because a fresh tenant could not create anything at all. New
/// Order, New Lead and the staff form each require at least one ACTIVE
/// branch row, `create_org_with_owner()` seeded none, and no screen
/// anywhere in the app could create one — so a vendor could sign up, pay,
/// and be structurally unable to book a job. `branches` was read in five
/// places and written in zero.
///
/// **`name` is the whole contract.** All five consumers read `name` and
/// nothing else, filtered `.eq('active', true)`. Every other column here
/// (city, address, manager, and the GST trio) is optional metadata that
/// no screen reads yet.
///
/// **Renaming is a real operation, not a label edit.** Every
/// branch-carrying column in the database is a composite FK
/// `(org_id, branch) -> branches(org_id, name)` with ON UPDATE CASCADE,
/// across 22 tables — so a rename rewrites `orders`, `leads`, `staff`,
/// `number_series` and 18 others atomically. That part is correct and
/// safe. What is NOT handled server-side is the client cache: a staff
/// member's `AppSession.currentStaffBranch` is read once at login by
/// `StaffPermissions.loadForStaff`, so anyone already signed in keeps the
/// OLD name and their `branch_isolation` checks then match nothing —
/// they see an empty app until they log out and back in. Hence
/// [_confirmRename] states that consequence in those words.
///
/// (Refreshing it on app resume was considered and rejected:
/// `loadForStaff`'s catch nulls permissions AND branch, which is correct
/// fail-closed behaviour for permissions, so calling it on every resume
/// would turn a transient network blip into a locked-out staff member.)
///
/// **Archive, not delete — deliberately NOT the `deleted_at` pattern.**
/// This is the one table where the recycle-bin convention is the wrong
/// fit. `active` already exists AND is already honoured by all five
/// consumers, so archiving needs no migration and no new read filters.
/// Adding `deleted_at` alongside it would leave two archive flags with
/// different semantics on one table, and every consumer would have to
/// check both or silently diverge. A hard delete is also refused by the
/// database anyway: all 22 FKs are ON DELETE RESTRICT, so deleting a
/// branch that any order ever referenced fails, while an unused one
/// succeeds — behaviour an owner cannot predict from the UI.
///
/// Owner-only, mirroring `20260827_branches_management.sql`'s
/// owner-only INSERT/UPDATE/DELETE policies. This is the deliberate
/// exception in CLAUDE.md's permission convention: the gate is a
/// session-shape test because a DB policy enforces owner for exactly
/// these writes, so offering the action to a manager would only produce
/// a Postgres denial.
class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});

  static String routeName = 'BranchesPage';
  static String routePath = '/branches';

  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  bool _loading = true;
  String? _loadError;
  List<BranchesRow> _branches = const [];
  bool _busy = false;

  /// Mirrors the DB's `is_org_owner()` — see the class doc comment for
  /// why this is a session-shape test rather than a permission lookup.
  bool get _isOwner => AppSession.instance.currentStaffId == null;

  int get _activeCount => _branches.where((b) => b.active ?? true).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // Unfiltered on `active` on purpose: this is the one screen that
      // must show archived branches, so they can be restored.
      final rows = await BranchesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
      if (!mounted) return;
      setState(() {
        _branches = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load branches: $e';
        _loading = false;
      });
    }
  }

  /// Non-empty, and not a duplicate of another branch in this org.
  /// Case-insensitive, because `(org_id, name)` is the FK target — two
  /// branches differing only in case would be two distinct FK targets
  /// that read as one thing to a human, which is exactly the casing trap
  /// 20260825_branches_table.sql's own preflight guards against.
  String? _validateName(String value, {String? exceptId}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter a branch name.';
    if (trimmed.length > 60) return 'Keep it under 60 characters.';
    final clash = _branches.any((b) =>
        b.id != exceptId &&
        b.name.trim().toLowerCase() == trimmed.toLowerCase());
    if (clash) return 'A branch with that name already exists.';
    return null;
  }

  Future<void> _addBranch() async {
    final result = await _showBranchSheet();
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await BranchesTable().insert({
        ...OrgScope.stamp(),
        'name': result.name,
        if (result.city != null) 'city': result.city,
        if (result.address != null) 'address': result.address,
        'active': true,
      });
      await _load();
      _toast('Branch "${result.name}" added.');
    } catch (e) {
      _toast('Could not add branch: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editBranch(BranchesRow branch) async {
    final result = await _showBranchSheet(existing: branch);
    if (result == null) return;

    final renaming = result.name.trim() != branch.name.trim();
    if (renaming && !await _confirmRename(branch.name, result.name)) return;

    setState(() => _busy = true);
    try {
      await BranchesTable().update(
        data: {
          'name': result.name,
          'city': result.city,
          'address': result.address,
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', branch.id!),
      );
      await _load();
      _toast(renaming
          ? 'Renamed to "${result.name}". Signed-in staff must log out and back in.'
          : 'Branch updated.');
    } catch (e) {
      _toast('Could not update branch: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The rename warning. Says "log out and back in" rather than "reopen
  /// the app" because nothing re-reads `staff.branch` on resume — see the
  /// class doc comment.
  Future<bool> _confirmRename(String from, String to) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename this branch?'),
        content: Text(
          'Every order, lead, staff member and document series currently '
          'filed under "$from" will move to "$to" automatically.\n\n'
          'Staff who are signed in right now will see an empty app until '
          'they log out and back in.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rename')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _setActive(BranchesRow branch, bool active) async {
    // Refuse to archive the last active branch: that puts the org back
    // into the exact zero-branch state this screen exists to fix.
    if (!active && _activeCount <= 1) {
      _toast(
        'This is the only active branch. Add another before archiving it — '
        'with none active, no order, lead or staff member can be created.',
        isError: true,
      );
      return;
    }

    if (!active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Archive "${branch.name}"?'),
          content: const Text(
            'It stops appearing when creating orders, leads and staff. '
            'Existing records keep this branch and are not changed, and you '
            'can restore it here at any time.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Archive')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await BranchesTable().update(
        data: {'active': active},
        matchingRows: (q) => OrgScope.write(q).eq('id', branch.id!),
      );
      await _load();
      _toast(active
          ? '"${branch.name}" restored.'
          : '"${branch.name}" archived.');
    } catch (e) {
      _toast('Could not update branch: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_BranchInput?> _showBranchSheet({BranchesRow? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = FlutterFlowTheme.of(sheetContext);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'Add branch' : 'Edit branch',
                  style: theme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Branch name',
                    hintText: 'e.g. Bengaluru',
                  ),
                  validator: (v) =>
                      _validateName(v ?? '', exceptId: existing?.id),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          Navigator.of(sheetContext).pop(true);
                        }
                      },
                      child: Text(existing == null ? 'Add' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved != true) return null;
    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return _BranchInput(
      name: nameCtrl.text.trim(),
      city: orNull(cityCtrl),
      address: orNull(addressCtrl),
    );
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor:
          isError ? FlutterFlowTheme.of(context).error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primary,
        iconTheme: IconThemeData(color: theme.info),
        title: Text(
          'Branches',
          style: theme.headlineMedium.override(
            fontFamily: 'Inter',
            color: theme.info,
          ),
        ),
      ),
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addBranch,
              icon: const Icon(Icons.add),
              label: const Text('Add branch'),
            )
          : null,
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(FlutterFlowTheme theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return LoadErrorState(message: _loadError!, onRetry: _load);
    }
    if (!_isOwner) {
      return _message(
        theme,
        Icons.lock_outline,
        'Owner only',
        'Branches are managed by the account owner. Ask them to add or '
            'change a branch for you.',
      );
    }
    if (_branches.isEmpty) {
      return _message(
        theme,
        Icons.store_mall_directory_outlined,
        'No branches yet',
        'Add your first branch to start creating orders, leads and staff.',
      );
    }

    final active = _branches.where((b) => b.active ?? true).toList();
    final archived = _branches.where((b) => !(b.active ?? true)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final b in active) _branchCard(theme, b, archived: false),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Archived', style: theme.labelMedium),
            const SizedBox(height: 8),
            for (final b in archived) _branchCard(theme, b, archived: true),
          ],
        ],
      ),
    );
  }

  Widget _branchCard(FlutterFlowTheme theme, BranchesRow b,
      {required bool archived}) {
    final subtitle = [b.city, b.address]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          archived ? Icons.inventory_2_outlined : Icons.store_outlined,
          color: archived ? theme.secondaryText : theme.primary,
        ),
        title: Text(
          b.name,
          style: theme.bodyLarge.override(
            fontFamily: 'Inter',
            color: archived ? theme.secondaryText : null,
          ),
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: _busy
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _editBranch(b);
                  if (v == 'archive') _setActive(b, false);
                  if (v == 'restore') _setActive(b, true);
                },
                itemBuilder: (_) => [
                  if (!archived)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (!archived)
                    const PopupMenuItem(
                        value: 'archive', child: Text('Archive')),
                  if (archived)
                    const PopupMenuItem(
                        value: 'restore', child: Text('Restore')),
                ],
              ),
      ),
    );
  }

  Widget _message(
      FlutterFlowTheme theme, IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.secondaryText),
            const SizedBox(height: 14),
            Text(title, style: theme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.bodySmall.override(
                fontFamily: 'Inter',
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchInput {
  const _BranchInput({required this.name, this.city, this.address});
  final String name;
  final String? city;
  final String? address;
}
