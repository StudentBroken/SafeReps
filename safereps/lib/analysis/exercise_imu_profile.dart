/// Per-exercise IMU quality parameters.
class ExerciseImuProfile {
  const ExerciseImuProfile({
    required this.tremorThreshold,
    required this.swingThreshold,
    required this.tremorDeductionRate,
    required this.swingDeductionRate,
    this.tremorHpAlpha = 0.85,
    this.yawLimit,
    this.rollLimit,
    this.pitchDeviationLimit,
    this.axisDeductionPct = 10.0,
  });

  final double tremorThreshold;     // g above which tremor counts
  final double swingThreshold;      // °/s above which swing counts
  final double tremorDeductionRate; // quality %/s deducted for sustained tremor
  final double swingDeductionRate;  // quality %/s deducted for sustained swing
  final double tremorHpAlpha;       // ESP32 high-pass filter alpha
  final double? yawLimit;            // ° max yaw deviation from calibrated plane (null = no check)
  final double? rollLimit;           // ° max roll deviation from calibrated neutral (null = no check)
  final double? pitchDeviationLimit; // ° max pitch deviation (forearm supination/pronation check)
  final double axisDeductionPct;     // one-time quality % deducted per axis violation
}

// After ZERO at T-pose: yaw=0 (arm in coronal plane), roll=0 (neutral forearm).
// yawLimit=25°: arm drifts >25° forward/backward → poor form.
// rollLimit=15°: forearm pronation/supination >15° → poor form.
const lateralRaiseImuProfile = ExerciseImuProfile(
  tremorThreshold: 0.030,
  swingThreshold: 25.0,
  tremorDeductionRate: 8.0,
  swingDeductionRate: 5.0,
  tremorHpAlpha: 0.85,
  yawLimit: 25.0,
  rollLimit: 15.0,
  axisDeductionPct: 10.0,
);

// pitchDeviationLimit=20°: forearm pronates/supinates beyond 20° from neutral → poor form.
const bicepCurlImuProfile = ExerciseImuProfile(
  tremorThreshold: 0.040,
  swingThreshold: 30.0,
  tremorDeductionRate: 8.0,
  swingDeductionRate: 5.0,
  tremorHpAlpha: 0.80,
  pitchDeviationLimit: 20.0,
  axisDeductionPct: 8.0,
);

ExerciseImuProfile imuProfileForExercise(String name) => switch (name) {
      'Lateral Raise' => lateralRaiseImuProfile,
      'Bicep Curl' => bicepCurlImuProfile,
      _ => lateralRaiseImuProfile,
    };
