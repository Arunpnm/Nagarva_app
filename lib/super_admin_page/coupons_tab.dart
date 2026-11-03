import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Coupons. Super and marketing admins create and pause them.
/// They cannot be redeemed yet: there is no checkout until subscription
/// billing is settled (Item 31), and used_count belongs to that checkout,
/// not to this screen. Coupons are never deleted, only paused, so the
/// audit log keeps a code's whole life.
class CouponsTab extends StatefulWidget {
  const CouponsTab({super.key});
  @override
  State<CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends AdminSectionState<CouponsTab> {
  List<Map<String, dynamic>> _coupons = const [];
  List<Map<String, dynamic>> _plans = const [];
  Map<String, String> _admins = const {};

  final _code = TextEditingController();
  final _value = TextEditingController();
  final _max = TextEditingController();
  String _kind = 'pct';
  DateTime? _until;
  final Set<String> _planCodes = {};

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('platform_coupons').select().order('created_at', ascending: false),
      db.from('subscription_plans').select('code,name,price_inr').eq('active', true),
      db.from('platform_admins').select('user_id,name,email'),
    ]);
    _coupons = List<Map<String, dynamic>>.from(r[0]);
    // Only paid plans take a coupon.
    _plans = [
      for (final p in r[1])
        if ((p['price_inr'] as num? ?? 0) > 0) Map<String, dynamic>.from(p)
    ];
    _admins = {
      for (final a in r[2]) '${a['user_id']}': '${a['name'] ?? a['email'] ?? 'Admin'}'
    };
  }

  Future<void> _create() async {
    final code = _code.text.trim().toUpperCase();
    final value = num.tryParse(_value.text.trim());
    final max = int.tryParse(_max.text.trim());
    if (!RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(code)) {
      return toast('Code: 3 to 20 letters or digits, no spaces.');
    }
    if (value == null || value <= 0 || (_kind == 'pct' && value > 100)) {
      return toast(_kind == 'pct' ? 'Enter a percentage from 1 to 100.' : 'Enter the rupees off.');
    }
    if (_until == null) return toast('Pick the last day the code works.');
    if (max == null || max <= 0) return toast('Enter how many times it can be used.');
    if (_planCodes.isEmpty) return toast('Pick at least one plan.');
    final ok = await run(
        () => db.from('platform_coupons').insert({
              'code': code,
              'kind': _kind,
              'value': value,
              'plan_codes': _planCodes.toList(),
              'valid_until': DateFormat('yyyy-MM-dd').format(_until!),
              'max_uses': max,
              'created_by': db.auth.currentUser?.id,
            }),
        '$code created');
    if (ok) {
      _code.clear();
      _value.clear();
      _max.clear();
      setState(() {
        _until = null;
        _planCodes.clear();
      });
    }
  }

  String _off(Map<String, dynamic> k) => k['kind'] == 'pct'
      ? '${k['value']}% off'
      : '${adminMoney.format(k['value'])} off';

  @override
  Widget build(BuildContext context) => body((c) {
        final planName = {for (final p in _plans) '${p['code']}': '${p['name']}'};
        return [
          const AdminHeading('Coupons', 'Codes vendors use at checkout'),
          NgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New coupon',
                  style: NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                    decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. DIWALI20'),
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pct', label: Text('% off')),
                    ButtonSegment(value: 'flat', label: Text('₹ off')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: _kind == 'pct' ? 'Percent' : 'Rupees'),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(_until == null
                      ? 'Valid till'
                      : 'Till ${DateFormat('d MMM yyyy').format(_until!)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 730)),
                        initialDate: _until ?? now);
                    if (d != null) setState(() => _until = d);
                  },
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Max uses'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Plans', style: NgFonts.geist(fontSize: 13, color: c.mute)),
                for (final p in _plans)
                  NgChip(
                    label: '${p['name']}',
                    selected: _planCodes.contains(p['code']),
                    onTap: () => setState(() => _planCodes.contains(p['code'])
                        ? _planCodes.remove(p['code'])
                        : _planCodes.add('${p['code']}')),
                  ),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: NgPrimaryButton(label: 'Create coupon', compact: true, onPressed: _create),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_coupons.isEmpty)
            const NgEmptyState(icon: Icons.confirmation_number_outlined, title: 'No coupons yet')
          else
            NgCardList(children: [
              for (final k in _coupons)
                () {
                  final used = (k['used_count'] as num? ?? 0).toInt();
                  final max = (k['max_uses'] as num? ?? 1).toInt();
                  final expired = DateTime.tryParse('${k['valid_until']}')
                          ?.isBefore(DateTime.now().subtract(const Duration(days: 1))) ??
                      false;
                  final state = expired
                      ? 'expired'
                      : used >= max
                          ? 'limit reached'
                          : k['active'] == true
                              ? 'live'
                              : 'paused';
                  return Opacity(
                    opacity: state == 'live' ? 1 : 0.6,
                    child: NgListRow(
                      title: '${k['code']} · ${_off(k)}',
                      subtitle: [
                        [for (final p in (k['plan_codes'] as List? ?? const [])) planName['$p'] ?? '$p']
                            .join(', '),
                        'till ${adminDate(k['valid_until'])}',
                        state,
                        'by ${_admins['${k['created_by']}'] ?? 'admin'}',
                      ].join(' · '),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$used / $max', style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
                        Switch(
                          value: k['active'] == true,
                          onChanged: (v) => run(
                              () => db.from('platform_coupons').update({'active': v}).eq('code', k['code']),
                              v ? '${k['code']} resumed' : '${k['code']} paused'),
                        ),
                      ]),
                    ),
                  );
                }(),
            ]),
          const SizedBox(height: 10),
          Text(
              'Vendors will type the code on the Plan & billing screen once online payment is live. The discount comes off the plan price before 18% GST.',
              style: NgFonts.geist(fontSize: 12, color: c.mute, height: 1.4)),
        ];
      });
}
