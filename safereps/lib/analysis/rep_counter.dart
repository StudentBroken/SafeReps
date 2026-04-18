import 'exercise.dart';
import 'joint_angles.dart';

enum RepPhase {
  /// Waiting for user to reach the top/start position.
  idle,

  /// In the top position; ready to descend.
  top,

  /// Actively descending (primary angle decreasing).
  descending,

  /// Touched bottom threshold.
  bottom,

  /// Ascending back toward top.
  ascending,
}

class RepResult {
  const RepResult({
    required this.totalReps,
    required this.phase,
    required this.primaryAngle,
  });

  final int totalReps;
  final RepPhase phase;

  /// The angle value that drove this update, for the HUD.
  final double? primaryAngle;
}

/// Stateful rep counter. Call [update] once per frame with the current angles.
/// Reset with [reset] between sets.
class RepCounter {
  RepCounter(this.exercise);

  final Exercise exercise;

  RepPhase _phase = RepPhase.idle;
  int _reps = 0;

  int get reps => _reps;
  RepPhase get phase => _phase;

  RepResult update(JointAngles angles) {
    final angle = exercise.primaryAngle(angles);

    if (angle != null) {
      _phase = _nextPhase(_phase, angle);
    }

    return RepResult(
      totalReps: _reps,
      phase: _phase,
      primaryAngle: angle,
    );
  }

  RepPhase _nextPhase(RepPhase current, double angle) {
    final top = exercise.topThreshold;
    final bottom = exercise.bottomThreshold;

    switch (current) {
      case RepPhase.idle:
        if (angle >= top) return RepPhase.top;
        return RepPhase.idle;

      case RepPhase.top:
        if (angle < top) return RepPhase.descending;
        return RepPhase.top;

      case RepPhase.descending:
        if (angle <= bottom) return RepPhase.bottom;
        if (angle >= top) return RepPhase.top; // stood back up without hitting bottom
        return RepPhase.descending;

      case RepPhase.bottom:
        if (angle > bottom) return RepPhase.ascending;
        return RepPhase.bottom;

      case RepPhase.ascending:
        if (angle >= top) {
          _reps++;
          return RepPhase.top;
        }
        if (angle <= bottom) return RepPhase.bottom; // dipped again
        return RepPhase.ascending;
    }
  }

  void reset() {
    _phase = RepPhase.idle;
    _reps = 0;
  }
}
