import 'package:flutter/material.dart';

import '../booking.dart';
import '../theme.dart';

/// Gives every flow screen the same Booking.
class BookingScope extends InheritedNotifier<Booking> {
  const BookingScope({super.key, required Booking booking, required super.child})
      : super(notifier: booking);

  static Booking of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookingScope>()!.notifier!;

  /// Without subscribing: for initState and callbacks.
  static Booking read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BookingScope>()!.notifier!;
}

/// Flow screen frame: back, title, step dots, body, bottom action.
class FlowFrame extends StatelessWidget {
  const FlowFrame({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.content,
    required this.action,
  });

  final int step; // 0..5
  final String title;
  final String? subtitle;
  final List<Widget> content;
  final Widget action;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Row(children: [
            for (var i = 0; i < 6; i++) ...[
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? C.orange : C.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < 5) const SizedBox(width: 4),
            ],
          ]),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(title,
                      style: geist(22, weight: FontWeight.w600, height: 1.2)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: geist(13.5, color: C.secondary)),
                  ],
                  const SizedBox(height: 16),
                  ...content,
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(top: BorderSide(color: C.hairline)),
              ),
              child: action,
            ),
          ]),
        ),
      );
}

class QtyStepper extends StatelessWidget {
  const QtyStepper(
      {super.key,
      required this.value,
      required this.onChanged,
      this.min = 0,
      this.max = 50});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center, style: mono(15))),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);
}

String money(num v) {
  final s = v.round().toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}
