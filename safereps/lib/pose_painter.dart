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
        final p = _project(lm.x, lm.y, size);
        canvas.drawCircle(p, 4, jointPaint);
      }
    }
  }

  Offset? _projectLandmark(PoseLandmark? lm, Size canvasSize) {
    if (lm == null) return null;
    return _project(lm.x, lm.y, canvasSize);
  }

  Offset _project(double x, double y, Size canvasSize) {
    final rotated = _rotatedImageSize();
    final scaleX = canvasSize.width / rotated.width;
    final scaleY = canvasSize.height / rotated.height;

    double dx;
    double dy;
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        dx = x;
        dy = y;
      case InputImageRotation.rotation90deg:
        dx = imageSize.height - y;
        dy = x;
      case InputImageRotation.rotation180deg:
        dx = imageSize.width - x;
        dy = imageSize.height - y;
      case InputImageRotation.rotation270deg:
        dx = y;
        dy = imageSize.width - x;
    }

    var px = dx * scaleX;
    final py = dy * scaleY;

    if (cameraLensDirection == CameraLensDirection.front) {
      px = canvasSize.width - px;
    }
    return Offset(px, py);
  }

  Size _rotatedImageSize() {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return Size(imageSize.height, imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return imageSize;
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
