import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'pose/skeleton.dart';

class PosePainter extends CustomPainter {
  PosePainter({required this.skeletons, required this.meta});

  final List<Skeleton> skeletons;
  final FrameMeta meta;

  static const _jointRadius = 4.0;
  static const _strokeWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final jointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.cyanAccent;

    for (final sk in skeletons) {
      for (final (a, b, side) in skeletonBones) {
        final pa = _project(sk[a], size);
        final pb = _project(sk[b], size);
        if (pa == null || pb == null) continue;
        canvas.drawLine(pa, pb, _bonePaint(side));
      }
      for (final lm in sk.joints.values) {
        if (lm.visibility < 0.3) continue;
        canvas.drawCircle(
          Offset(_tx(lm.x, size), _ty(lm.y, size)),
          _jointRadius,
          jointPaint,
        );
      }
    }
  }

  Offset? _project(SkeletonLandmark? lm, Size canvas) {
    if (lm == null) return null;
    return Offset(_tx(lm.x, canvas), _ty(lm.y, canvas));
  }

  // Canonical translator: landmarks are in upright (post-rotation) image space.
  // Scale to canvas; mirror x for front camera in 0/180 orientations.
  double _tx(double x, Size canvas) {
    final isIos = Platform.isIOS;
    switch (meta.rotation) {
      case FrameRotation.deg90:
        return x * canvas.width /
            (isIos ? meta.imageSize.width : meta.imageSize.height);
      case FrameRotation.deg270:
        return canvas.width -
            x * canvas.width /
                (isIos ? meta.imageSize.width : meta.imageSize.height);
      case FrameRotation.deg0:
      case FrameRotation.deg180:
        final s = x * canvas.width / meta.imageSize.width;
        return meta.lensDirection == CameraLensDirection.front
            ? canvas.width - s
            : s;
    }
  }

  double _ty(double y, Size canvas) {
    final isIos = Platform.isIOS;
    switch (meta.rotation) {
      case FrameRotation.deg90:
      case FrameRotation.deg270:
        return y * canvas.height /
            (isIos ? meta.imageSize.height : meta.imageSize.width);
      case FrameRotation.deg0:
      case FrameRotation.deg180:
        return y * canvas.height / meta.imageSize.height;
    }
  }

  static Paint _bonePaint(bool? side) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _strokeWidth
    ..strokeCap = StrokeCap.round
    ..color = switch (side) {
      true  => Colors.orangeAccent,
      false => Colors.lightBlueAccent,
      null  => Colors.greenAccent,
    };

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.skeletons != skeletons || old.meta != meta;
}

/// Thin value object so [PosePainter] has no ML Kit dependency.
class FrameMeta {
  const FrameMeta({
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Size imageSize;
  final FrameRotation rotation;
  final CameraLensDirection lensDirection;

  @override
  bool operator ==(Object other) =>
      other is FrameMeta &&
      other.imageSize == imageSize &&
      other.rotation == rotation &&
      other.lensDirection == lensDirection;

  @override
  int get hashCode => Object.hash(imageSize, rotation, lensDirection);
}
