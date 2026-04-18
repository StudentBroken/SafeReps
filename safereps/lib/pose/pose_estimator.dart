import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'skeleton.dart';

export 'skeleton.dart';

/// Coordinate metadata needed by [PosePainter] to map landmark pixel coords
/// onto the camera preview canvas.
class FrameMetadata {
  const FrameMetadata({
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
}

/// Backend-agnostic pose estimator interface.
/// Implementations: [MlKitPoseEstimator], and later [MediaPipePoseEstimator].
abstract class PoseEstimator {
  Future<void> initialize();

  /// Process one camera frame. Returns empty list if no person detected.
  /// [meta] is filled in from the camera controller's current orientation.
  Future<List<Skeleton>> processFrame(
    CameraImage image,
    CameraDescription camera,
    FrameMetadata meta,
  );

  Future<void> close();
}
