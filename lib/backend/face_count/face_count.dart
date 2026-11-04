/// Counts faces in a photo, on the phone, offline (4 Nov 2026, group-photo
/// attendance). The photo never leaves the device for this.
///
/// Android/iOS use Google ML Kit. The web build and desktop have no ML Kit,
/// so [countFaces] returns null there and the screen says the count works
/// in the phone app; the supervisor still ticks names either way.
export 'face_count_stub.dart'
    if (dart.library.io) 'face_count_mobile.dart';
