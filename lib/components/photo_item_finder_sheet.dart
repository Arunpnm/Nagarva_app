import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '/app_session.dart';
import '/backend/pricing_defaults.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

/// AI photo survey, staff side (10 Nov 2026).
///
/// The surveyor photographs a room; the `survey-ai` Edge Function suggests
/// items from THIS company's catalogue; the surveyor corrects the counts
/// and adds them to the quote. Nothing is added without that tap, and
/// volumes come from the catalogue on this phone — never from the AI.
///
/// The same function serves the customer's survey link
/// (public_site/survey). The AI key lives on the server only.

/// One suggested catalogue line with the count the surveyor confirmed.
typedef FoundItem = ({String cat, String item, String sub, num cft, int qty});

/// True when the server has an AI provider configured. The quote screen
/// hides the button otherwise, so there is never a button that goes
/// nowhere.
Future<bool> photoSurveyEnabled() async {
  try {
    // The server answers for THIS company: photos are a Pro plan feature
    // (`ai_survey`), and the plan is checked there, not here.
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return false;
    final res = await SupaFlow.client.functions.invoke(
      'survey-ai',
      body: {'action': 'status', 'org_id': orgId},
    );
    final data = res.data;
    return data is Map && data['ok'] == true && data['enabled'] == true;
  } catch (_) {
    return false;
  }
}

/// Opens the sheet. Returns the confirmed items and any large things seen
/// that are not in the catalogue (for the surveyor to add as custom
/// items), or null if closed without adding.
Future<({List<FoundItem> items, List<String> other})?> showPhotoItemFinder(
  BuildContext context, {
  required Map<String, List<SurveyItem>> catalogue,
}) {
  return showModalBottomSheet<({List<FoundItem> items, List<String> other})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NgPalette.of(context).sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(NgRadius.sheet)),
    ),
    builder: (_) => _FinderSheet(catalogue: catalogue),
  );
}

// Loft, cupboards, store room, terrace and garage are named on purpose:
// they are what gets missed, and the usual reason a moving-day load is
// bigger than the survey. Same list as public_site/survey/index.html.
const _kRooms = [
  'Living room',
  'Bedroom',
  'Kitchen',
  'Dining',
  'Balcony',
  'Loft',
  'Cupboards',
  'Store room',
  'Terrace',
  'Garage',
  'Other',
];
const _kMaxPhotos = 4; // must match MAX_IMAGES in survey_ai_util.ts

const _kReasons = <String, String>{
  'not_configured': 'Photo survey is not switched on yet.',
  'not_in_plan': 'Photo survey is part of the Pro plan.',
  'not_signed_in': 'Log in again to use photos.',
  'not_allowed': 'Log in again to use photos.',
  'no_catalogue': 'Add items to your item list first.',
  'month_limit':
      'Photo checks are used up for this month. Pick the items by hand.',
  'busy_today': 'Photo checks are used up for today. Pick the items by hand.',
  'bad_photo':
      'One of those photos could not be read. Remove it and try another.',
  'too_many_photos': 'Use up to $_kMaxPhotos photos per room.',
  'no_photos': 'Add at least one photo of the room.',
  'timeout': 'That took too long. Try again with fewer photos.',
  'unavailable': 'Photos are not available right now. Pick the items by hand.',
};

class _FinderSheet extends StatefulWidget {
  const _FinderSheet({required this.catalogue});
  final Map<String, List<SurveyItem>> catalogue;

  @override
  State<_FinderSheet> createState() => _FinderSheetState();
}

class _FinderSheetState extends State<_FinderSheet> {
  String _room = _kRooms.first;
  final List<Uint8List> _photos = [];
  bool _busy = false;
  String? _error;

  /// Suggestions after a check, with editable counts. Null = not checked.
  List<({String cat, String item, String sub, num cft})>? _found;
  final Map<int, int> _qty = {};

  /// Seen in the photos but not moving (stays at the old home). Not added
  /// to the quote; the count is kept so a second tap restores it.
  final Set<int> _staying = {};
  List<String> _other = const [];

  Future<void> _add(ImageSource source) async {
    if (_photos.length >= _kMaxPhotos) return;
    try {
      // Shrunk on the phone: full-size photos are 3-12 MB each.
      final shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 72,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photos.add(bytes);
        _error = null;
        _found = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  Future<void> _check() async {
    final orgId = OrgScope.currentOrgId;
    if (orgId == null || _photos.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final res = await SupaFlow.client.functions.invoke(
        'survey-ai',
        body: {
          'org_id': orgId,
          'room': _room,
          'images': [for (final p in _photos) base64Encode(p)],
          'catalogue': {
            for (final e in widget.catalogue.entries)
              e.key: [
                for (final it in e.value)
                  {
                    'name': it.name,
                    'subs': [
                      for (final s in it.subs) {'label': s.label, 'cft': s.cft},
                    ],
                  },
              ],
          },
        },
      );
      final data = res.data;
      if (!mounted) return;
      if (data is! Map || data['ok'] != true) {
        setState(() {
          _busy = false;
          _error =
              _kReasons[data is Map ? '${data['reason']}' : ''] ??
              'Could not read those photos. Try again, or pick the items by hand.';
        });
        return;
      }
      // Resolve every suggestion against the catalogue on THIS phone. A
      // line the catalogue does not have is dropped, and the cft is ours.
      final found = <({String cat, String item, String sub, num cft})>[];
      final qty = <int, int>{};
      for (final raw in (data['items'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final cat = '${raw['cat']}',
            item = '${raw['item']}',
            sub = '${raw['sub']}';
        num? cft;
        for (final it in widget.catalogue[cat] ?? const <SurveyItem>[]) {
          if (it.name != item) continue;
          for (final s in it.subs) {
            if (s.label == sub) cft = s.cft;
          }
        }
        final n = (raw['qty'] as num?)?.toInt() ?? 0;
        if (cft == null || n <= 0) continue;
        qty[found.length] = n.clamp(1, 99);
        found.add((cat: cat, item: item, sub: sub, cft: cft));
      }
      setState(() {
        _busy = false;
        _found = found;
        _qty
          ..clear()
          ..addAll(qty);
        _staying.clear();
        _other = [
          for (final o in (data['other'] as List? ?? const []))
            if ('$o'.trim().isNotEmpty) '$o'.trim(),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Photos did not send. Check your connection and try again.';
      });
    }
  }

  void _done() {
    final found = _found ?? const [];
    Navigator.of(context).pop((
      items: <FoundItem>[
        for (var i = 0; i < found.length; i++)
          if ((_qty[i] ?? 0) > 0 && !_staying.contains(i))
            (
              cat: found[i].cat,
              item: found[i].item,
              sub: found[i].sub,
              cft: found[i].cft,
              qty: _qty[i]!,
            ),
      ],
      other: _other,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final found = _found;
    var total = 0;
    _qty.forEach((i, n) {
      if (!_staying.contains(i)) total += n;
    });
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Items from photos',
              style: NgFonts.geist(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Up to $_kMaxPhotos photos of one room. These are suggestions: '
              'check the counts before adding. Remember the loft, cupboards, '
              'balcony and terrace.',
              style: NgFonts.geist(fontSize: 13, color: c.mute),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _kRooms)
                  NgChip(
                    label: r,
                    selected: _room == r,
                    onTap: () {
                      if (_busy || _room == r) return;
                      setState(() {
                        _room = r;
                        _photos.clear();
                        _found = null;
                        _error = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _photos[i],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => setState(() {
                                      _photos.removeAt(i);
                                      _found = null;
                                    }),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: NgSecondaryButton(
                    label: 'Camera',
                    icon: Icons.photo_camera_rounded,
                    onPressed: _busy || _photos.length >= _kMaxPhotos
                        ? null
                        : () => _add(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NgSecondaryButton(
                    label: 'Gallery',
                    icon: Icons.photo_library_outlined,
                    onPressed: _busy || _photos.length >= _kMaxPhotos
                        ? null
                        : () => _add(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)),
            ],
            if (found != null) ...[
              const SizedBox(height: 14),
              if (found.isEmpty)
                Text(
                  'No items spotted in those photos. Try a wider photo, or pick the items by hand.',
                  style: NgFonts.geist(fontSize: 13, color: c.amber),
                )
              else
                NgCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < found.length; i++)
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                          decoration: BoxDecoration(
                            border: i == 0
                                ? null
                                : Border(top: BorderSide(color: c.w06)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      found[i].item,
                                      style:
                                          NgFonts.geist(
                                            fontSize: 14,
                                            color: _staying.contains(i)
                                                ? c.mute
                                                : c.text,
                                          ).copyWith(
                                            decoration: _staying.contains(i)
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                    ),
                                    Text(
                                      '${found[i].sub} · ${found[i].cft} CFT',
                                      style: NgFonts.geist(
                                        fontSize: 12,
                                        color: c.mute,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              NgChip(
                                label: _staying.contains(i)
                                    ? 'Staying'
                                    : 'Moving',
                                selected: !_staying.contains(i),
                                onTap: () => setState(() {
                                  if (!_staying.remove(i)) _staying.add(i);
                                }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed:
                                    (_qty[i] ?? 0) <= 0 || _staying.contains(i)
                                    ? null
                                    : () => setState(
                                        () => _qty[i] = (_qty[i] ?? 0) - 1,
                                      ),
                              ),
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '${_qty[i] ?? 0}',
                                  textAlign: TextAlign.center,
                                  style: NgFonts.mono(
                                    fontSize: 14,
                                    color: c.text,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed:
                                    (_qty[i] ?? 0) >= 99 || _staying.contains(i)
                                    ? null
                                    : () => setState(
                                        () => _qty[i] = (_qty[i] ?? 0) + 1,
                                      ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (_other.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Also seen, not in your item list: ${_other.join(', ')}.',
                  style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (found == null || found.isEmpty)
              NgPrimaryButton(
                label: _busy ? 'Looking at the photos…' : 'Find items',
                icon: Icons.auto_awesome_rounded,
                onPressed: _busy || _photos.isEmpty ? null : _check,
              )
            else
              NgPrimaryButton(
                label: total == 0
                    ? 'Nothing to add'
                    : 'Add $total ${total == 1 ? 'item' : 'items'} to quote',
                icon: Icons.check_rounded,
                onPressed: total == 0 ? null : _done,
              ),
          ],
        ),
      ),
    );
  }
}
