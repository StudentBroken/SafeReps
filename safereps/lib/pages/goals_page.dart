import 'package:flutter/material.dart';

import '../analysis/exercise_imu_profile.dart';
import '../models/goals_model.dart';
import '../shell.dart' show kNavPillClearance;
import '../theme.dart';
import '../widgets/glass_card.dart';

// ---------------------------------------------------------------------------

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  int? _expanded; // index of currently expanded exercise card

  @override
  Widget build(BuildContext context) {
    final model = GoalsScope.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final cardMinH = screenH / 2.5;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0).copyWith(
            bottom: 32 + kNavPillClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('Goals', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text('Configure your session targets.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.colors(context).textLight)),
            const SizedBox(height: 20),

            // Session pill
            _SessionPill(model: model),
            const SizedBox(height: 16),

            // Exercise cards
            ...List.generate(model.exercises.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExerciseCard(
                  exercise: model.exercises[i],
                  minHeight: cardMinH,
                  expanded: _expanded == i,
                  onToggle: () =>
                      setState(() => _expanded = _expanded == i ? null : i),
                  onRepsChanged: (v) =>
                      model.updateExercise(i, repsPerSet: v),
                  onSetsChanged: (v) =>
                      model.updateExercise(i, setsPerDay: v),
                  onImuChanged: (tremor, swing) =>
                      model.updateImuSensitivity(i, tremorThreshold: tremor, swingThreshold: swing),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Session pill ──────────────────────────────────────────────────────────────

class _SessionPill extends StatelessWidget {
  const _SessionPill({required this.model});
  final GoalsModel model;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);

    return GestureDetector(
      onTap: () => _openSheet(context),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 100,
        tint: themeColors.glassTint,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: themeColors.accent.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tune_rounded,
                  size: 16, color: themeColors.textDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session',
                      style: TextStyle(
                          color: themeColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                    '${model.sessionSets} sets  ·  ${_fmt(model.interSetRestSecs)} rest/set  ·  ${_fmt(model.interExerciseRestSecs)} rest/exercise',
                    style: TextStyle(
                        color: themeColors.textLight, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: themeColors.unselected),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SessionSheet(model: model),
    );
  }

  static String _fmt(int secs) {
    if (secs < 60) return '${secs}s';
    final m = secs ~/ 60;
    final s = secs % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}

// ── Session bottom sheet ──────────────────────────────────────────────────────

class _SessionSheet extends StatefulWidget {
  const _SessionSheet({required this.model});
  final GoalsModel model;

  @override
  State<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends State<_SessionSheet> {
  late int _sets;
  late int _interSet;
  late int _interEx;

  @override
  void initState() {
    super.initState();
    _sets = widget.model.sessionSets;
    _interSet = widget.model.interSetRestSecs;
    _interEx = widget.model.interExerciseRestSecs;
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: GlassCard(
          tint: themeColors.glassTint,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session',
                  style: TextStyle(
                      color: themeColors.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              _SheetRow(
                label: 'Sets per session',
                value: '$_sets',
                onDec: _sets > 1
                    ? () => setState(() => _sets--)
                    : null,
                onInc: _sets < 10
                    ? () => setState(() => _sets++)
                    : null,
              ),
              const _Divider(),
              _SheetRow(
                label: 'Rest between sets',
                value: _fmt(_interSet),
                onDec: _interSet > 15
                    ? () => setState(() => _interSet -= 15)
                    : null,
                onInc: _interSet < 300
                    ? () => setState(() => _interSet += 15)
                    : null,
              ),
              const _Divider(),
              _SheetRow(
                label: 'Rest between exercises',
                value: _fmt(_interEx),
                onDec: _interEx > 15
                    ? () => setState(() => _interEx -= 15)
                    : null,
                onInc: _interEx < 300
                    ? () => setState(() => _interEx += 15)
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.model.updateSession(
                      sets: _sets,
                      interSetRest: _interSet,
                      interExerciseRest: _interEx,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(int secs) {
    if (secs < 60) return '${secs}s';
    final m = secs ~/ 60;
    final s = secs % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.value,
    required this.onDec,
    required this.onInc,
  });

  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: themeColors.textDark, fontSize: 14)),
          ),
          _StepBtn(icon: Icons.remove_rounded, onTap: onDec),
          SizedBox(
            width: 56,
            child: Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: themeColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          _StepBtn(icon: Icons.add_rounded, onTap: onInc),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(color: Colors.black.withAlpha(20), height: 1);
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? themeColors.accent : themeColors.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color:
                enabled ? themeColors.textDark : themeColors.textLight),
      ),
    );
  }
}

// ── Exercise card ─────────────────────────────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.minHeight,
    required this.expanded,
    required this.onToggle,
    required this.onRepsChanged,
    required this.onSetsChanged,
    required this.onImuChanged,
  });

  final ExerciseGoal exercise;
  final double minHeight;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onSetsChanged;
  final void Function(double? tremor, double? swing) onImuChanged;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Placeholder image
              _CardImage(name: exercise.name),

              // Stats + toggle header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row — tap here to expand/collapse
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(exercise.name,
                                style: TextStyle(
                                    color: themeColors.textDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                          ),
                          AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: themeColors.unselected),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Done / goal counter
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${exercise.doneToday}',
                            style: TextStyle(
                                color: primary,
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                height: 1)),
                        Text(' / ${exercise.totalGoal}',
                            style: TextStyle(
                                color: themeColors.textMid,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('reps today',
                            style: TextStyle(
                                color: themeColors.textLight,
                                fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Expanded section
              if (expanded) ...[
                Divider(
                    color: Colors.black.withAlpha(20), height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: _ExpandedSection(
                    exercise: exercise,
                    onRepsChanged: onRepsChanged,
                    onSetsChanged: onSetsChanged,
                    onImuChanged: onImuChanged,
                  ),
                ),
              ] else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: 0.2), 
              themeColors.accent.withValues(alpha: 0.3)
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center_rounded,
                size: 40, color: primary.withValues(alpha: 0.5)),
            const SizedBox(height: 6),
            Text(name,
                style: TextStyle(
                    color: themeColors.textMid,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ExpandedSection extends StatelessWidget {
  const _ExpandedSection({
    required this.exercise,
    required this.onRepsChanged,
    required this.onSetsChanged,
    required this.onImuChanged,
  });

  final ExerciseGoal exercise;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onSetsChanged;
  final void Function(double? tremor, double? swing) onImuChanged;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final baseProfile = imuProfileForExercise(exercise.name);
    final tremor = exercise.tremorThreshold ?? baseProfile.tremorThreshold;
    final swing = exercise.swingThreshold ?? baseProfile.swingThreshold;

    return Column(
      children: [
        _CardRow(
          label: 'Reps per set',
          value: '${exercise.repsPerSet}',
          onDec: exercise.repsPerSet > 1
              ? () => onRepsChanged(exercise.repsPerSet - 1)
              : null,
          onInc: exercise.repsPerSet < 50
              ? () => onRepsChanged(exercise.repsPerSet + 1)
              : null,
        ),
        const SizedBox(height: 14),
        _CardRow(
          label: 'Sets per session',
          value: '${exercise.setsPerDay}',
          onDec: exercise.setsPerDay > 1
              ? () => onSetsChanged(exercise.setsPerDay - 1)
              : null,
          onInc: exercise.setsPerDay < 10
              ? () => onSetsChanged(exercise.setsPerDay + 1)
              : null,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Session goal: ${exercise.totalGoal} reps',
            style: TextStyle(color: themeColors.textLight, fontSize: 11),
          ),
        ),

        // IMU sensitivity tuning
        const SizedBox(height: 16),
        Divider(color: Colors.black.withAlpha(12), height: 1),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'IMU Sensitivity',
            style: TextStyle(
              color: themeColors.textLight,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _CardRow(
          label: 'Tremor threshold',
          value: '${tremor.toStringAsFixed(3)} g',
          onDec: tremor > 0.010
              ? () => onImuChanged(
                    (tremor - 0.005).clamp(0.010, 0.200),
                    exercise.swingThreshold,
                  )
              : null,
          onInc: tremor < 0.200
              ? () => onImuChanged(
                    (tremor + 0.005).clamp(0.010, 0.200),
                    exercise.swingThreshold,
                  )
              : null,
        ),
        const SizedBox(height: 14),
        _CardRow(
          label: 'Swing threshold',
          value: '${swing.toStringAsFixed(0)} °/s',
          onDec: swing > 10
              ? () => onImuChanged(
                    exercise.tremorThreshold,
                    (swing - 5).clamp(10.0, 100.0),
                  )
              : null,
          onInc: swing < 100
              ? () => onImuChanged(
                    exercise.tremorThreshold,
                    (swing + 5).clamp(10.0, 100.0),
                  )
              : null,
        ),
        // Reset to defaults
        if (exercise.tremorThreshold != null || exercise.swingThreshold != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => onImuChanged(null, null),
              child: Text(
                'Reset to defaults',
                style: TextStyle(
                  color: themeColors.textLight,
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.label,
    required this.value,
    required this.onDec,
    required this.onInc,
  });

  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: themeColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        _StepBtn(icon: Icons.remove_rounded, onTap: onDec),
        SizedBox(
          width: 44,
          child: Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ),
        _StepBtn(icon: Icons.add_rounded, onTap: onInc),
      ],
    );
  }
}
