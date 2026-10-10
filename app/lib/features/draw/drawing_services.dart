import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../data/before_photo.dart';
import '../../domain/drawing_analysis_result.dart';
import '../drawing_analysis/drawing_analyzer.dart';
import '../video_export/before_photo_extractor.dart';

/// Result of the on-device analysis as the UI needs it.
class AnalysisOutcome {
  const AnalysisOutcome(this.result, {this.rejectReason, this.beforePhoto});
  final DrawingAnalysisResult result;

  /// Non-null when the child should draw more (もうすこし かいてみよう).
  final DrawingRejectReason? rejectReason;

  /// The perspective-cropped paper photo for the Before/After video,
  /// extracted in the background (never throws; null = none kept).
  final Future<BeforePhoto?>? beforePhoto;
}

/// Seam over the Vision pipeline so widget tests can use a fake.
abstract interface class DrawingAnalyzerService {
  /// Throws [UndecodableImageException] when the bytes are not an image.
  Future<AnalysisOutcome> analyze(Uint8List imageBytes);
}

class OnDeviceDrawingAnalyzer implements DrawingAnalyzerService {
  const OnDeviceDrawingAnalyzer();

  @override
  Future<AnalysisOutcome> analyze(Uint8List imageBytes) async {
    final report = await analyzeDrawingDetailed(imageBytes);
    return AnalysisOutcome(
      report.result,
      rejectReason: report.rejectReason,
      // Video export (docs/VIDEO.md): keep only the paper region. Runs
      // while the birth animation plays.
      beforePhoto: report.rejectReason == null
          ? extractBeforePhoto(imageBytes, BeforePhotoInput.fromReport(report))
          : null,
    );
  }
}

enum PhotoSource { camera, gallery }

/// Seam over image_picker.
abstract interface class DrawingImageSource {
  /// Encoded image bytes, or null when the child cancelled.
  Future<Uint8List?> pick(PhotoSource source);
}

/// image_picker, downscaled to ≤ 2048 px before analysis (SPEC §10).
class ImagePickerDrawingSource implements DrawingImageSource {
  ImagePickerDrawingSource([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  static const maxSide = 2048.0;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 92,
    );
    return file?.readAsBytes();
  }
}
