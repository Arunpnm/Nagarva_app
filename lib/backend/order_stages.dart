/// Customer-facing order stages for the public tracking page
/// (live-test fix brief #2, item 6).
///
/// DESIGN NOTE — deliberately a *presentation* layer, not a new set of
/// `orders.status` values.
///
/// The brief asks for a timeline of
///   Confirmed → Packing → In Transit → Arrived → Delivered → Completed
/// but this app's real `orders.status` vocabulary is
///   booked / pending / confirmed / transit / delivered / cancelled / closed
/// (OrdersPage's tabs and SupervisorJobPage both depend on exactly those).
///
/// Writing the brief's finer-grained names into `orders.status` would make
/// in-progress orders disappear from every OrdersPage tab — the same trap
/// CLAUDE.md records SupervisorJobPage hitting and deliberately avoiding.
/// So the customer timeline is derived from the existing `status` plus the
/// customer-facing `tracking_status` free-text field, and the extra
/// granularity (Packing, Arrived, Completed) comes from `tracking_status`
/// when staff set it. Nothing here changes what the office sees.
library;

const String kStageConfirmed = 'confirmed';
const String kStagePacking = 'packing';
const String kStageInTransit = 'in_transit';
const String kStageArrived = 'arrived';
const String kStageDelivered = 'delivered';
const String kStageCompleted = 'completed';

const List<String> kOrderStages = [
  kStageConfirmed,
  kStagePacking,
  kStageInTransit,
  kStageArrived,
  kStageDelivered,
  kStageCompleted,
];

String orderStageLabel(String stage) {
  switch (stage) {
    case kStagePacking:
      return 'Packing';
    case kStageInTransit:
      return 'In Transit';
    case kStageArrived:
      return 'Arrived';
    case kStageDelivered:
      return 'Delivered';
    case kStageCompleted:
      return 'Completed';
    default:
      return 'Confirmed';
  }
}

/// Normalises a stored `tracking_status` or `status` string to one of
/// [kOrderStages]. Returns null when the value means nothing on the
/// customer timeline (e.g. 'cancelled'), so callers can skip it rather
/// than mis-plotting it as a stage.
String? canonicalOrderStage(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  switch (v) {
    case 'booked':
    case 'confirmed':
    case 'pending':
      return kStageConfirmed;
    case 'packing':
    case 'packed':
    case 'loading':
      return kStagePacking;
    case 'transit':
    case 'in_transit':
    case 'shifting':
      return kStageInTransit;
    case 'arrived':
    case 'reached':
    case 'unloading':
      return kStageArrived;
    case 'delivered':
      return kStageDelivered;
    case 'completed':
    case 'closed':
    case 'approved':
      return kStageCompleted;
    default:
      return null;
  }
}

/// Index into [kOrderStages] for the timeline's current position.
///
/// [trackingStatus] wins when it maps to something, since it is the
/// customer-facing field staff update as the job progresses; [status] is
/// the fallback so an order whose tracking_status was never touched still
/// plots correctly from its real status. Returns 0 (Confirmed) rather
/// than -1 when neither maps, so the timeline always shows *something*.
int orderStageIndex(String? trackingStatus, String? status) {
  final fromTracking = canonicalOrderStage(trackingStatus);
  final fromStatus = canonicalOrderStage(status);
  final stage = fromTracking ?? fromStatus;
  if (stage == null) return 0;
  final idx = kOrderStages.indexOf(stage);
  return idx < 0 ? 0 : idx;
}
