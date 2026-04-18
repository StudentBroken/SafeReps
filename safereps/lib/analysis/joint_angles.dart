import 'dart:math' as math;

import '../pose/skeleton.dart';

/// 2D image-space joint angles in degrees.
/// Accurate enough for Phase 1 rep counting; swap for world-space
/// coords (SkeletonLandmark.z) when 3-D accuracy is needed.
class JointAngles {
  const JointAngles({
    this.leftKnee,
    this.rightKnee,
    this.leftHip,
    this.rightHip,
    this.leftElbow,
    this.rightElbow,
    this.leftShoulder,
    this.rightShoulder,
  });

  final double? leftKnee;
  final double? rightKnee;
  final double? leftHip;
  final double? rightHip;
  final double? leftElbow;
  final double? rightElbow;
  final double? leftShoulder;
  final double? rightShoulder;

  double? get avgKnee => _avg(leftKnee, rightKnee);
  double? get avgHip => _avg(leftHip, rightHip);
  double? get avgElbow => _avg(leftElbow, rightElbow);
  double? get avgShoulder => _avg(leftShoulder, rightShoulder);

  static double? _avg(double? a, double? b) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return (a + b) / 2;
  }
}

JointAngles computeJointAngles(Skeleton sk) {
  return JointAngles(
    leftKnee: _angle(sk, SkeletonJoint.leftHip, SkeletonJoint.leftKnee, SkeletonJoint.leftAnkle),
    rightKnee: _angle(sk, SkeletonJoint.rightHip, SkeletonJoint.rightKnee, SkeletonJoint.rightAnkle),
    leftHip: _angle(sk, SkeletonJoint.leftShoulder, SkeletonJoint.leftHip, SkeletonJoint.leftKnee),
    rightHip: _angle(sk, SkeletonJoint.rightShoulder, SkeletonJoint.rightHip, SkeletonJoint.rightKnee),
    leftElbow: _angle(sk, SkeletonJoint.leftShoulder, SkeletonJoint.leftElbow, SkeletonJoint.leftWrist),
    rightElbow: _angle(sk, SkeletonJoint.rightShoulder, SkeletonJoint.rightElbow, SkeletonJoint.rightWrist),
    leftShoulder: _angle(sk, SkeletonJoint.leftHip, SkeletonJoint.leftShoulder, SkeletonJoint.leftElbow),
    rightShoulder: _angle(sk, SkeletonJoint.rightHip, SkeletonJoint.rightShoulder, SkeletonJoint.rightElbow),
  );
}

/// Angle at joint B formed by segments A→B and C→B, in degrees.
double? _angle(Skeleton sk, SkeletonJoint a, SkeletonJoint b, SkeletonJoint c) {
  final la = sk[a];
  final lb = sk[b];
  final lc = sk[c];
  if (la == null || lb == null || lc == null) return null;
  if (la.visibility < 0.3 || lb.visibility < 0.3 || lc.visibility < 0.3) {
    return null;
  }

  final bax = la.x - lb.x;
  final bay = la.y - lb.y;
  final bcx = lc.x - lb.x;
  final bcy = lc.y - lb.y;

  final dot = bax * bcx + bay * bcy;
  final magA = math.sqrt(bax * bax + bay * bay);
  final magB = math.sqrt(bcx * bcx + bcy * bcy);
  if (magA < 1e-6 || magB < 1e-6) return null;

  final cos = (dot / (magA * magB)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}
