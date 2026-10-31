import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Admin team: who can use this panel and in which role. Only a
/// super admin can change it, and only through platform_admin_add /
/// platform_admin_update, which also keep one active super admin at all
/// times. The person must already have an account (they sign up, then are
/// added here), so this screen never creates logins or passwords.
class TeamTab extends StatefulWidget {
  const TeamTab({super.key, required this.myRole});
  final String? myRole;
  @override
  State<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends AdminSectionState<TeamTab> {
  List<Map<String, dynamic>> _team = const [];
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _role = 'sales';

  bool get _isSuper => widget.myRole == 'super';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    // role and active only exist once the admin panel migration has run.
    final rows = await db
        .from('platform_admins')
        .select('user_id,name,email,role,active,created_at')
        .order('created_at');
    _team = List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      return toast('Enter the person\'s name and work email.');
    }
    final ok = await run(
        () => db.rpc('platform_admin_add',
            params: {'p_email': email, 'p_name': name, 'p_role': _role}),
        '$name added as ${kAdminRoles[_role]}');
    if (ok) {
      _name.clear();
      _email.clear();
    }
  }

  Future<void> _edit(Map<String, dynamic> a) async {
    var role = '${a['role']}';
    var active = a['active'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${a['name'] ?? a['email']}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: role,
              onChanged: (v) => set(() => role = v ?? role),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in kAdminRoles.entries)
                  RadioListTile<String>(value: e.key, title: Text(e.value)),
              ]),
            ),
            SwitchListTile(
              value: active,
              title: const Text('Can sign in'),
              onChanged: (v) => set(() => active = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await run(
        () => db.rpc('platform_admin_update',
            params: {'p_user': a['user_id'], 'p_role': role, 'p_active': active}),
        'Saved');
  }

  @override
  Widget build(BuildContext context) => body((c) => [
        const AdminHeading('Admin team', 'People, roles and permissions'),
        NgCardList(children: [
          for (final a in _team)
            NgListRow(
              leading: NgAvatar('${a['name'] ?? a['email'] ?? '?'}'),
              title: '${a['name'] ?? a['email'] ?? 'Admin'}',
              subtitle: '${kAdminRoles['${a['role']}'] ?? a['role']} · ${a['email'] ?? ''}',
              trailing: Text(a['active'] == true ? 'Active' : 'Off',
                  style: NgFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: a['active'] == true ? c.green : c.faint)),
              onTap: _isSuper ? () => _edit(a) : null,
            ),
        ]),
        const SizedBox(height: 14),
        if (_isSuper)
          NgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Add someone',
                  style: NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 4),
              Text('They sign up with this email first; adding them here gives that account access to the admin panel.',
                  style: NgFonts.geist(fontSize: 12.5, color: c.mute, height: 1.4)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                    width: 200,
                    child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                SizedBox(
                    width: 240,
                    child: TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Work email'))),
                for (final e in kAdminRoles.entries)
                  NgChip(label: e.value, selected: _role == e.key, onTap: () => setState(() => _role = e.key)),
                NgPrimaryButton(label: 'Add', icon: Icons.person_add_alt_rounded, compact: true, onPressed: _add),
              ]),
            ]),
          )
        else
          Text('Only a super admin can change the team.',
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        const SizedBox(height: 14),
        Text(
            'Sales: vendors, signups, plans, coupons (view). Support: vendors and tickets. Marketing: coupons and broadcasts. Super admin: everything, including this team.',
            style: NgFonts.geist(fontSize: 12, color: c.mute, height: 1.4)),
      ]);
}
