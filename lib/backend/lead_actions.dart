import 'lead_status.dart';

/// What a person may DO to a lead right now — derived from the lead's
/// state and evidence, never from a hard-coded button list per screen.
///
/// Arun, 15 Sept 2026 (pending UX list items 2, 4 and 6): "Once a lead is
/// converted to an order it should read Converted. Today it still offers
/// Build Quote from Survey, Convert Quote to Order, Confirm Order, Edit
/// Lead and Delete Lead." And: build this as ONE resolver every screen
/// reads, not a per-page fix — six separate "show the right buttons"
/// implementations would be another two-sources-one-value problem.
///
/// Every screen that offers lead actions (Lead Details, the order journey,
/// the Survey & Quote hub, list cards) asks this, so they cannot disagree.
class LeadActions {
  const LeadActions._({
    required this.converted,
    required this.lost,
    required this.hasQuote,
    this.orderId,
  });

  /// [hasOrder]: a live (not cancelled / deleted) order exists for this
  /// lead — by `orders.lead_id` or through one of its quotes. That record,
  /// not the status label, is what "converted" means.
  factory LeadActions.resolve({
    required String? status,
    required bool hasOrder,
    required bool hasQuote,
    String? orderId,
  }) {
    final s = canonicalLeadStatus(status);
    return LeadActions._(
      converted: hasOrder,
      lost: !hasOrder && s == kLeadStatusLost,
      hasQuote: hasQuote,
      orderId: orderId,
    );
  }

  /// An order exists. The lead is history: read-only, with a way to the
  /// order.
  final bool converted;

  /// Marked lost and never converted.
  final bool lost;

  final bool hasQuote;

  /// The order this lead became, when known.
  final String? orderId;

  bool get isOpen => !converted && !lost;

  // ---- what the screens may offer ---------------------------------------

  bool get canEdit => !converted;
  bool get canChangeStatus => !converted;
  bool get canRequestSurvey => isOpen;
  bool get canBuildQuote => isOpen;
  bool get canReviseQuote => isOpen && hasQuote;
  bool get canSendForSignature => isOpen && hasQuote;
  bool get canConvertQuote => isOpen && hasQuote;

  /// Lost leads may still be confirmed — the confirm flow asks to reopen
  /// first (BUG-056).
  bool get canConfirmOrder => !converted;

  /// A converted lead is referenced by its order; "Lost" is the honest end
  /// state for one that did not work out.
  bool get canDelete => !converted;
  bool get canMarkLost => isOpen;
  bool get canReopen => lost;

  /// One word for the lead's place in life, for headers and list cards.
  String get stateLabel => converted
      ? 'Converted'
      : lost
          ? 'Lost'
          : 'Open';
}
