import 'package:flutter/material.dart';

import '/flutter_flow/ng_tokens.dart';

/// The vendor's own logo, or their initials when they have not uploaded
/// one yet. Never the platform's logo: inside the app the vendor is the
/// brand (Arun, 12 Nov 2026 — a new company "Ponci PNM" saw the Nagarva
/// mark beside its own name on the dashboard). Login, sign-up and Help &
/// About keep the platform's logo; this widget is for the vendor's own
/// screens.
class VendorLogo extends StatelessWidget {
  const VendorLogo({
    super.key,
    required this.url,
    required this.name,
    this.size = 30,
    this.radius = 9,
  });

  final String? url;
  final String name;
  final double size;
  final double radius;

  static String initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return '';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final u = (url ?? '').trim();
    final fallback = Container(
      color: c.acc.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: initials(name).isEmpty
          ? Icon(Icons.local_shipping_rounded, size: size * 0.55, color: c.acc)
          : Text(
              initials(name),
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
                color: c.acc,
              ),
            ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: u.isEmpty ? null : Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: u.isEmpty
          ? fallback
          : Image.network(u,
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}
