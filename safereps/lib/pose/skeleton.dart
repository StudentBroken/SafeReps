import 'package:flutter/foundation.dart';

enum SkeletonJoint {
  nose,
  leftEyeInner, leftEye, leftEyeOuter,
  rightEyeInner, rightEye, rightEyeOuter,
  leftEar, rightEar,
  mouthLeft, mouthRight,
  leftShoulder, rightShoulder,
  leftElbow, rightElbow,
  leftWrist, rightWrist,
  leftPinky, rightPinky,
  leftIndex, rightIndex,
  leftThumb, rightThumb,
  leftHip, rightHip,
  leftKnee, rightKnee,
  leftAnkle, rightAnkle,
  leftHeel, rightHeel,
  leftFootIndex, rightFootIndex,
}

@immutable
class SkeletonLandmark {
  const SkeletonLandmark({
    required this.x,
    required this.y,
    this.z = 0,
    this.visibility = 1,
  });

  /// Normalized image-space x (0–imageWidth in pixels, post-rotation).
  final double x;

  /// Normalized image-space y (0–imageHeight in pixels, post-rotation).
  final double y;

  /// World-space depth (metres). May be 0 when unavailable (ML Kit).
  final double z;

  /// Confidence/visibility [0, 1].
  final double visibility;
}

@immutable
class Skeleton {
  const Skeleton(this.joints);

  final Map<SkeletonJoint, SkeletonLandmark> joints;

  SkeletonLandmark? operator [](SkeletonJoint j) => joints[j];
}

// Bones to draw, with a flag indicating whether they are on the left side.
// Left = true → orangeAccent, Right = false → lightBlueAccent, null → greenAccent.
const List<(SkeletonJoint, SkeletonJoint, bool?)> skeletonBones = [
  // Torso
  (SkeletonJoint.leftShoulder,  SkeletonJoint.rightShoulder, null),
  (SkeletonJoint.leftHip,       SkeletonJoint.rightHip,      null),
  (SkeletonJoint.leftShoulder,  SkeletonJoint.leftHip,       null),
  (SkeletonJoint.rightShoulder, SkeletonJoint.rightHip,      null),
  // Left arm
  (SkeletonJoint.leftShoulder,  SkeletonJoint.leftElbow,  true),
  (SkeletonJoint.leftElbow,     SkeletonJoint.leftWrist,  true),
  // Right arm
  (SkeletonJoint.rightShoulder, SkeletonJoint.rightElbow, false),
  (SkeletonJoint.rightElbow,    SkeletonJoint.rightWrist, false),
  // Left leg
  (SkeletonJoint.leftHip,   SkeletonJoint.leftKnee,  true),
  (SkeletonJoint.leftKnee,  SkeletonJoint.leftAnkle, true),
  // Right leg
  (SkeletonJoint.rightHip,  SkeletonJoint.rightKnee,  false),
  (SkeletonJoint.rightKnee, SkeletonJoint.rightAnkle, false),
];
