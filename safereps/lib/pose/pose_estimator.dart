import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';

import 'skeleton.dart';

export 'skeleton.dart';

/// Coordinate metadata passed from the camera controller to the estimator
/// and forwarded to [PosePainter].
class FrameMetadata {
  const FrameMetadata({
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Size imageSize;
  final FrameRotation rotation;
  final CameraLensDirection lensDirection;
}

/// Backend-agnostic pose estimator interface.
/// Implementations: [MlKitPoseEstimator].
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
