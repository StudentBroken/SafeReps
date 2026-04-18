import '../services/ble_service.dart';
import 'exercise_imu_profile.dart';

class RepFormResult {
  const RepFormResult({
    required this.quality,
    required this.sustainedTremor,
    required this.sustainedSwing,
    required this.yawViolated,
    required this.rollViolated,
  });

  final double quality;        // 0–100
  final bool sustainedTremor;  // tremor lasted ≥1 s during this rep
  final bool sustainedSwing;   // swing lasted ≥1 s during this rep
  final bool yawViolated;      // arm drifted out of coronal plane
  final bool rollViolated;     // forearm rotated beyond limit
}

/// Accumulates per-rep form quality from IMU data.
/// Call [update] on each BLE tick, [reset] when a new rep starts.
class RepFormTracker {
  double _quality = 100.0;
  double _tremorSecs = 0.0;
  double _swingSecs = 0.0;
  bool _hadSustainedTremor = false;
  bool _hadSustainedSwing = false;
  bool _yawViolated = false;
  bool _rollViolated = false;

  double get currentQuality => _quality;

  /// True while tremor has been continuously above threshold for ≥1 s.
  bool get tremorSustained => _tremorSecs >= 1.0;

  /// True while swing has been continuously above threshold for ≥1 s.
  bool get swingSustained => _swingSecs >= 1.0;

  /// True once a 1 s+ tremor event has occurred this rep (latches).
  bool get hadSustainedTremor => _hadSustainedTremor;

  void update(ImuData data, double dtSecs, ExerciseImuProfile profile) {
    if (data.tremor > profile.tremorThreshold) {
      _tremorSecs += dtSecs;
      _quality =
          (_quality - profile.tremorDeductionRate * dtSecs).clamp(0, 100);
      if (_tremorSecs >= 1.0) _hadSustainedTremor = true;
    } else {
      _tremorSecs = 0;
    }

    if (data.swing > profile.swingThreshold) {
      _swingSecs += dtSecs;
      _quality =
          (_quality - profile.swingDeductionRate * dtSecs).clamp(0, 100);
      if (_swingSecs >= 1.0) _hadSustainedSwing = true;
    } else {
      _swingSecs = 0;
    }
  }

  /// One-time yaw axis violation deduction (idempotent per rep).
  void flagYawViolation(double deductionPct) {
    if (_yawViolated) return;
    _yawViolated = true;
    _quality = (_quality - deductionPct).clamp(0, 100);
  }

  /// One-time roll axis violation deduction (idempotent per rep).
  void flagRollViolation(double deductionPct) {
    if (_rollViolated) return;
    _rollViolated = true;
    _quality = (_quality - deductionPct).clamp(0, 100);
  }

  RepFormResult finish() => RepFormResult(
        quality: _quality,
        sustainedTremor: _hadSustainedTremor,
        sustainedSwing: _hadSustainedSwing,
        yawViolated: _yawViolated,
        rollViolated: _rollViolated,
      );

  void reset() {
    _quality = 100.0;
    _tremorSecs = 0.0;
    _swingSecs = 0.0;
    _hadSustainedTremor = false;
    _hadSustainedSwing = false;
    _yawViolated = false;
    _rollViolated = false;
  }
}
