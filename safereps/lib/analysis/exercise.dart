import 'joint_angles.dart';

/// Selects which joint angle drives the rep counter for an exercise.
typedef AngleSelector = double? Function(JointAngles angles);

/// Declarative exercise definition. Add new exercises here; no if-chains
/// anywhere else in the codebase.
class Exercise {
  const Exercise({
    required this.name,
    required this.primaryAngle,
    required this.topThreshold,
    required this.bottomThreshold,
    required this.cues,
  });

  final String name;

  /// Which angle in [JointAngles] drives the rep counter.
  final AngleSelector primaryAngle;

  /// Angle (°) considered "standing / start" position. Rep is counted on
  /// returning above this value after touching the bottom.
  final double topThreshold;

  /// Angle (°) considered "bottom" position. Rep phase flips once the primary
  /// angle drops below this value.
  final double bottomThreshold;

  /// Form cue messages shown to the user; placeholder for Phase 1 rules.
  final List<String> cues;
}

// ── Built-in exercise library ─────────────────────────────────────────────────

const squat = Exercise(
  name: 'Squat',
  primaryAngle: _kneeAngle,
  topThreshold: 155,
  bottomThreshold: 100,
  cues: [
    'Drive knees out',
    'Keep chest up',
    'Hips below parallel',
  ],
);

const romanianDeadlift = Exercise(
  name: 'Romanian Deadlift',
  primaryAngle: _hipAngle,
  topThreshold: 160,
  bottomThreshold: 100,
  cues: [
    'Hinge at hips',
    'Soft knee bend',
    'Bar close to legs',
  ],
);

const bicepCurl = Exercise(
  name: 'Bicep Curl',
  primaryAngle: _elbowAngle,
  topThreshold: 150,
  bottomThreshold: 60,
  cues: [
    'Keep elbows fixed',
    'Full range of motion',
  ],
);

const overheadPress = Exercise(
  name: 'Overhead Press',
  primaryAngle: _elbowAngle,
  topThreshold: 155,
  bottomThreshold: 80,
  cues: [
    'Tuck elbows at start',
    'Press straight up',
    'Lock out at top',
  ],
);

const List<Exercise> builtInExercises = [
  squat,
  romanianDeadlift,
  bicepCurl,
  overheadPress,
];

double? _kneeAngle(JointAngles a) => a.avgKnee;
double? _hipAngle(JointAngles a) => a.avgHip;
double? _elbowAngle(JointAngles a) => a.avgElbow;
