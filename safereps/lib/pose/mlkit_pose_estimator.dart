import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_estimator.dart';

class MlKitPoseEstimator implements PoseEstimator {
  late final PoseDetector _detector;

  @override
  Future<void> initialize() async {
    _detector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );
  }

  @override
  Future<List<Skeleton>> processFrame(
    CameraImage image,
    CameraDescription camera,
    FrameMetadata meta,
  ) async {
    final input = _toInputImage(image, meta);
    if (input == null) return const [];
    final poses = await _detector.processImage(input);
    return poses.map(_toSkeleton).toList();
  }

  @override
  Future<void> close() => _detector.close();

  InputImage? _toInputImage(CameraImage image, FrameMetadata meta) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: meta.imageSize,
        rotation: _toMlRotation(meta.rotation),
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  static InputImageRotation _toMlRotation(FrameRotation r) =>
      switch (r) {
        FrameRotation.deg0   => InputImageRotation.rotation0deg,
        FrameRotation.deg90  => InputImageRotation.rotation90deg,
        FrameRotation.deg180 => InputImageRotation.rotation180deg,
        FrameRotation.deg270 => InputImageRotation.rotation270deg,
      };

  static Skeleton _toSkeleton(Pose pose) {
    final joints = <SkeletonJoint, SkeletonLandmark>{};
    for (final entry in pose.landmarks.entries) {
      final joint = _jointMap[entry.key];
      if (joint == null) continue;
      joints[joint] = SkeletonLandmark(
        x: entry.value.x,
        y: entry.value.y,
        z: entry.value.z,
        visibility: entry.value.likelihood,
      );
    }
    return Skeleton(joints);
  }

  static const Map<PoseLandmarkType, SkeletonJoint> _jointMap = {
    PoseLandmarkType.nose:           SkeletonJoint.nose,
    PoseLandmarkType.leftEyeInner:   SkeletonJoint.leftEyeInner,
    PoseLandmarkType.leftEye:        SkeletonJoint.leftEye,
    PoseLandmarkType.leftEyeOuter:   SkeletonJoint.leftEyeOuter,
    PoseLandmarkType.rightEyeInner:  SkeletonJoint.rightEyeInner,
    PoseLandmarkType.rightEye:       SkeletonJoint.rightEye,
    PoseLandmarkType.rightEyeOuter:  SkeletonJoint.rightEyeOuter,
    PoseLandmarkType.leftEar:        SkeletonJoint.leftEar,
    PoseLandmarkType.rightEar:       SkeletonJoint.rightEar,
    PoseLandmarkType.leftMouth:      SkeletonJoint.mouthLeft,
    PoseLandmarkType.rightMouth:     SkeletonJoint.mouthRight,
    PoseLandmarkType.leftShoulder:   SkeletonJoint.leftShoulder,
    PoseLandmarkType.rightShoulder:  SkeletonJoint.rightShoulder,
    PoseLandmarkType.leftElbow:      SkeletonJoint.leftElbow,
    PoseLandmarkType.rightElbow:     SkeletonJoint.rightElbow,
    PoseLandmarkType.leftWrist:      SkeletonJoint.leftWrist,
    PoseLandmarkType.rightWrist:     SkeletonJoint.rightWrist,
    PoseLandmarkType.leftPinky:  SkeletonJoint.leftPinky,
    PoseLandmarkType.rightPinky: SkeletonJoint.rightPinky,
    PoseLandmarkType.leftIndex:  SkeletonJoint.leftIndex,
    PoseLandmarkType.rightIndex: SkeletonJoint.rightIndex,
    PoseLandmarkType.leftThumb:      SkeletonJoint.leftThumb,
    PoseLandmarkType.rightThumb:     SkeletonJoint.rightThumb,
    PoseLandmarkType.leftHip:        SkeletonJoint.leftHip,
    PoseLandmarkType.rightHip:       SkeletonJoint.rightHip,
    PoseLandmarkType.leftKnee:       SkeletonJoint.leftKnee,
    PoseLandmarkType.rightKnee:      SkeletonJoint.rightKnee,
    PoseLandmarkType.leftAnkle:      SkeletonJoint.leftAnkle,
    PoseLandmarkType.rightAnkle:     SkeletonJoint.rightAnkle,
    PoseLandmarkType.leftHeel:       SkeletonJoint.leftHeel,
    PoseLandmarkType.rightHeel:      SkeletonJoint.rightHeel,
    PoseLandmarkType.leftFootIndex:  SkeletonJoint.leftFootIndex,
    PoseLandmarkType.rightFootIndex: SkeletonJoint.rightFootIndex,
  };
}
