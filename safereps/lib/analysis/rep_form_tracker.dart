import '../services/ble_service.dart';
import 'exercise_imu_profile.dart';

class RepFormResult {
  const RepFormResult({
    required this.quality,
    required this.sustainedTremor,
    required this.sustainedSwing,
  });

  final double quality;        // 0–100
  final bool sustainedTremor;  // tremor lasted ≥1 s during this rep
  final bool sustainedSwing;   // swing lasted ≥1 s during this rep
}

/// Accumulates per-rep form quality from IMU data.
/// Call [update] on each BLE tick, [reset] when a new rep starts.
class RepFormTracker {
  double _quality = 100.0;
  double _tremorSecs = 0.0;
  double _swingSecs = 0.0;
  bool _sustainedTremor = false;
  bool _sustainedSwing = false;

  double get currentQuality => _quality;

  void update(ImuData data, double dtSecs, ExerciseImuProfile profile) {
    if (data.tremor > profile.tremorThreshold) {
      _tremorSecs += dtSecs;
      _quality =
          (_quality - profile.tremorDeductionRate * dtSecs).clamp(0, 100);
      if (_tremorSecs >= 1.0) _sustainedTremor = true;
    } else {
      _tremorSecs = 0;
    }

    if (data.swing > profile.swingThreshold) {
      _swingSecs += dtSecs;
      _quality =
          (_quality - profile.swingDeductionRate * dtSecs).clamp(0, 100);
      if (_swingSecs >= 1.0) _sustainedSwing = true;
    } else {
      _swingSecs = 0;
    }
  }

  RepFormResult finish() => RepFormResult(
        quality: _quality,
        sustainedTremor: _sustainedTremor,
        sustainedSwing: _sustainedSwing,
      );

  void reset() {
    _quality = 100.0;
    _tremorSecs = 0.0;
    _swingSecs = 0.0;
    _sustainedTremor = false;
    _sustainedSwing = false;
  }
}
