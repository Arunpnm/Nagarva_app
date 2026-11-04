import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Number of faces ML Kit finds in the photo at [filePath], or null when
/// detection is not available on this device (desktop, or any failure).
Future<int?> countFaces(String filePath) async {
  FaceDetector? detector;
  try {
    detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        // A crew photo is taken from a few metres away; small faces count.
        minFaceSize: 0.05,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFilePath(filePath));
    return faces.length;
  } catch (_) {
    return null;
  } finally {
    try {
      await detector?.close();
    } catch (_) {}
  }
}
