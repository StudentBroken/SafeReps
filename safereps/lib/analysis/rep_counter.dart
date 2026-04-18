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
  DateTime? _lastRepTime;
  double? _lastRepDuration;

  int get reps => _reps;
  RepPhase get phase => _phase;

  /// Seconds between the last two completed reps. Null until two reps done.
  double? get lastRepDuration => _lastRepDuration;

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

  bool get _inverted => exercise.topThreshold < exercise.bottomThreshold;

  bool _pastTop(double angle) => _inverted
      ? angle <= exercise.topThreshold
      : angle >= exercise.topThreshold;

  bool _pastBottom(double angle) => _inverted
      ? angle >= exercise.bottomThreshold
      : angle <= exercise.bottomThreshold;

  RepPhase _nextPhase(RepPhase current, double angle) {
    switch (current) {
      case RepPhase.idle:
        if (_pastTop(angle)) return RepPhase.top;
        return RepPhase.idle;

      case RepPhase.top:
        if (!_pastTop(angle)) return RepPhase.descending;
        return RepPhase.top;

      case RepPhase.descending:
        if (_pastBottom(angle)) return RepPhase.bottom;
        if (_pastTop(angle)) return RepPhase.top; // stood back up without hitting bottom
        return RepPhase.descending;

      case RepPhase.bottom:
        if (!_pastBottom(angle)) return RepPhase.ascending;
        return RepPhase.bottom;

      case RepPhase.ascending:
        if (_pastTop(angle)) {
          final now = DateTime.now();
          if (_lastRepTime != null) {
            _lastRepDuration = now.difference(_lastRepTime!).inMilliseconds / 1000.0;
          }
          _lastRepTime = now;
          _reps++;
          return RepPhase.top;
        }
        if (_pastBottom(angle)) return RepPhase.bottom; // dipped again
        return RepPhase.ascending;
    }
  }

  void reset() {
    _phase = RepPhase.idle;
    _reps = 0;
    _lastRepTime = null;
    _lastRepDuration = null;
  }
}
