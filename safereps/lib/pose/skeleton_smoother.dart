import 'skeleton.dart';

/// Exponential moving average smoother for skeleton landmarks.
///
/// Reduces per-frame jitter and holds the last valid skeleton for
/// [holdoverFrames] frames when detection briefly drops out.
class SkeletonSmoother {
  SkeletonSmoother({this.alpha = 0.35, this.holdoverFrames = 5});

  /// Blend factor [0,1]. Lower = smoother but more lag.
  final double alpha;

  /// Frames to keep the previous skeleton when detector returns nothing.
  final int holdoverFrames;

  Map<SkeletonJoint, SkeletonLandmark>? _prev;
  int _missingCount = 0;

  List<Skeleton> smooth(List<Skeleton> incoming) {
    if (incoming.isNotEmpty) {
      _missingCount = 0;
      final sk = _blend(incoming.first);
      _prev = sk.joints;
      // Pass through additional skeletons (multi-person) unsmoothed.
      return [sk, ...incoming.skip(1)];
    }

    if (_prev != null && _missingCount < holdoverFrames) {
      _missingCount++;
      return [Skeleton(_prev!)];
    }

    _prev = null;
    return const [];
  }

  Skeleton _blend(Skeleton next) {
    final prev = _prev;
    if (prev == null) return next;

    final out = <SkeletonJoint, SkeletonLandmark>{};
    for (final e in next.joints.entries) {
      final p = prev[e.key];
      if (p == null) {
        out[e.key] = e.value;
      } else {
        final n = e.value;
        out[e.key] = SkeletonLandmark(
          x: _ema(p.x, n.x),
          y: _ema(p.y, n.y),
          z: _ema(p.z, n.z),
          visibility: _ema(p.visibility, n.visibility),
        );
      }
    }
    return Skeleton(out);
  }

  double _ema(double prev, double next) => alpha * next + (1 - alpha) * prev;

  void reset() {
    _prev = null;
    _missingCount = 0;
  }
}
