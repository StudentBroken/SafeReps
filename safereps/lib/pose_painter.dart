import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final jointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.cyanAccent;
    final bonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.greenAccent;
    final leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.orangeAccent;
    final rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.lightBlueAccent;

    for (final pose in poses) {
      void drawBone(PoseLandmarkType a, PoseLandmarkType b, Paint paint) {
        final pa = _projectLandmark(pose.landmarks[a], size);
        final pb = _projectLandmark(pose.landmarks[b], size);
        if (pa != null && pb != null) canvas.drawLine(pa, pb, paint);
      }

      // Torso.
      drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, bonePaint);
      drawBone(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, bonePaint);
      drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, bonePaint);
      drawBone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, bonePaint);

      // Left arm.
      drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, leftPaint);
      drawBone(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, leftPaint);

      // Right arm.
      drawBone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, rightPaint);
      drawBone(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, rightPaint);

      // Left leg.
      drawBone(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, leftPaint);
      drawBone(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, leftPaint);

      // Right leg.
      drawBone(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, rightPaint);
      drawBone(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, rightPaint);

      for (final lm in pose.landmarks.values) {
        if (lm.likelihood < 0.3) continue;
        final p = Offset(
          _translateX(lm.x, size),
          _translateY(lm.y, size),
        );
        canvas.drawCircle(p, 4, jointPaint);
      }
    }
  }

  Offset? _projectLandmark(PoseLandmark? lm, Size canvasSize) {
    if (lm == null) return null;
    return Offset(_translateX(lm.x, canvasSize), _translateY(lm.y, canvasSize));
  }

  // Coordinate translation matches the official google_ml_kit_flutter example.
  // Landmarks come back in the upright (post-rotation) image space; we only
  // need to scale to canvas, and mirror horizontally for the front camera in
  // landscape orientations.
  double _translateX(double x, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            x *
                canvasSize.width /
                (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        final scaled = x * canvasSize.width / imageSize.width;
        return cameraLensDirection == CameraLensDirection.front
            ? canvasSize.width - scaled
            : scaled;
    }
  }

  double _translateY(double y, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (Platform.isIOS ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) {
    return old.poses != poses ||
        old.imageSize != imageSize ||
        old.rotation != rotation ||
        old.cameraLensDirection != cameraLensDirection;
  }
}
