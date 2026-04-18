import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class ExerciseGoal {
  ExerciseGoal({
    required this.name,
    this.repsPerSet = 12,
    this.setsPerDay = 3,
    this.doneToday = 0,
    this.tremorThreshold,
    this.swingThreshold,
  });

  final String name;
  int repsPerSet;
  int setsPerDay;
  int doneToday;

  /// IMU sensitivity overrides — null means use the built-in profile default.
  double? tremorThreshold; // g
  double? swingThreshold;  // °/s

  int get totalGoal => repsPerSet * setsPerDay;
  double get fraction =>
      totalGoal == 0 ? 0 : (doneToday / totalGoal).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class GoalsModel extends ChangeNotifier {
  final List<ExerciseGoal> exercises = [
    ExerciseGoal(name: 'Lateral Raise', repsPerSet: 12, setsPerDay: 3),
    ExerciseGoal(name: 'Bicep Curl', repsPerSet: 12, setsPerDay: 3),
  ];

  int sessionSets = 3;
  int interSetRestSecs = 60;
  int interExerciseRestSecs = 90;

  /// Average fraction across all exercises.
  double get totalProgress {
    if (exercises.isEmpty) return 0;
    return exercises.map((e) => e.fraction).reduce((a, b) => a + b) /
        exercises.length;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void updateExercise(int index, {int? repsPerSet, int? setsPerDay}) {
    if (index < 0 || index >= exercises.length) return;
    if (repsPerSet != null) exercises[index].repsPerSet = repsPerSet;
    if (setsPerDay != null) exercises[index].setsPerDay = setsPerDay;
    notifyListeners();
    _persist();
  }

  void updateImuSensitivity(int index, {double? tremorThreshold, double? swingThreshold}) {
    if (index < 0 || index >= exercises.length) return;
    exercises[index].tremorThreshold = tremorThreshold;
    exercises[index].swingThreshold = swingThreshold;
    notifyListeners();
    _persist();
  }

  void updateSession({int? sets, int? interSetRest, int? interExerciseRest}) {
    if (sets != null) sessionSets = sets;
    if (interSetRest != null) interSetRestSecs = interSetRest;
    if (interExerciseRest != null) interExerciseRestSecs = interExerciseRest;
    notifyListeners();
    _persist();
  }

  /// Called by SessionPage each time a set is completed.
  void markSetComplete(int exerciseIndex, int repsCompleted) {
    if (exerciseIndex < 0 || exerciseIndex >= exercises.length) return;
    exercises[exerciseIndex].doneToday =
        (exercises[exerciseIndex].doneToday + repsCompleted)
            .clamp(0, exercises[exerciseIndex].totalGoal * 2);
    notifyListeners();
    _persist();
  }

  void resetDailyProgress() {
    for (final e in exercises) {
      e.doneToday = 0;
    }
    notifyListeners();
    _persist();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  static const _prefix = 'sr_';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < exercises.length; i++) {
      exercises[i].repsPerSet =
          prefs.getInt('${_prefix}ex${i}_rps') ?? exercises[i].repsPerSet;
      exercises[i].setsPerDay =
          prefs.getInt('${_prefix}ex${i}_spd') ?? exercises[i].setsPerDay;
      exercises[i].doneToday =
          prefs.getInt('${_prefix}ex${i}_done') ?? exercises[i].doneToday;
      final tt = prefs.getInt('${_prefix}ex${i}_tremor');
      if (tt != null) exercises[i].tremorThreshold = tt / 1000.0;
      final st = prefs.getInt('${_prefix}ex${i}_swing');
      if (st != null) exercises[i].swingThreshold = st / 10.0;
    }
    sessionSets =
        prefs.getInt('${_prefix}session_sets') ?? sessionSets;
    interSetRestSecs =
        prefs.getInt('${_prefix}inter_set') ?? interSetRestSecs;
    interExerciseRestSecs =
        prefs.getInt('${_prefix}inter_ex') ?? interExerciseRestSecs;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < exercises.length; i++) {
      await prefs.setInt('${_prefix}ex${i}_rps', exercises[i].repsPerSet);
      await prefs.setInt('${_prefix}ex${i}_spd', exercises[i].setsPerDay);
      await prefs.setInt('${_prefix}ex${i}_done', exercises[i].doneToday);
      final tt = exercises[i].tremorThreshold;
      if (tt != null) await prefs.setInt('${_prefix}ex${i}_tremor', (tt * 1000).round());
      else await prefs.remove('${_prefix}ex${i}_tremor');
      final st = exercises[i].swingThreshold;
      if (st != null) await prefs.setInt('${_prefix}ex${i}_swing', (st * 10).round());
      else await prefs.remove('${_prefix}ex${i}_swing');
    }
    await prefs.setInt('${_prefix}session_sets', sessionSets);
    await prefs.setInt('${_prefix}inter_set', interSetRestSecs);
    await prefs.setInt('${_prefix}inter_ex', interExerciseRestSecs);
  }
}

// ---------------------------------------------------------------------------
// InheritedNotifier scope — GoalsScope.of(context)
// ---------------------------------------------------------------------------

class GoalsScope extends InheritedNotifier<GoalsModel> {
  const GoalsScope({
    super.key,
    required GoalsModel model,
    required super.child,
  }) : super(notifier: model);

  static GoalsModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GoalsScope>()!.notifier!;
}
