/// Per-exercise IMU quality parameters.
class ExerciseImuProfile {
  const ExerciseImuProfile({
    required this.tremorThreshold,
    required this.swingThreshold,
    required this.tremorDeductionRate,
    required this.swingDeductionRate,
    this.tremorHpAlpha = 0.85,
  });

  final double tremorThreshold;     // g above which tremor counts
  final double swingThreshold;      // °/s above which swing counts
  final double tremorDeductionRate; // quality %/s deducted for sustained tremor
  final double swingDeductionRate;  // quality %/s deducted for sustained swing
  final double tremorHpAlpha;       // ESP32 high-pass filter alpha
}

const lateralRaiseImuProfile = ExerciseImuProfile(
  tremorThreshold: 0.030,
  swingThreshold: 25.0,
  tremorDeductionRate: 8.0,
  swingDeductionRate: 5.0,
  tremorHpAlpha: 0.85,
);

const bicepCurlImuProfile = ExerciseImuProfile(
  tremorThreshold: 0.040,
  swingThreshold: 30.0,
  tremorDeductionRate: 8.0,
  swingDeductionRate: 5.0,
  tremorHpAlpha: 0.80,
);

ExerciseImuProfile imuProfileForExercise(String name) => switch (name) {
      'Lateral Raise' => lateralRaiseImuProfile,
      'Bicep Curl' => bicepCurlImuProfile,
      _ => lateralRaiseImuProfile,
    };
