import 'package:flutter/material.dart';

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
            Text('Set your daily targets.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textLight)),
            const SizedBox(height: 16),

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
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 100,
        tint: AppColors.glassPinkTint,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.pink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tune_rounded,
                  size: 16, color: AppColors.textDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Session',
                      style: TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                    '${model.sessionSets} sets  ·  ${_fmt(model.interSetRestSecs)} between sets  ·  ${_fmt(model.interExerciseRestSecs)} between exercises',
                    style: const TextStyle(
                        color: AppColors.textLight, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.beige),
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
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: GlassCard(
          tint: AppColors.glassPinkTint,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Session Setup',
                  style: TextStyle(
                      color: AppColors.textDark,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textDark, fontSize: 14)),
          ),
          _StepBtn(icon: Icons.remove_rounded, onTap: onDec),
          SizedBox(
            width: 56,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textDark,
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
    return const Divider(color: Color(0x22000000), height: 1);
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? AppColors.pink : const Color(0x22F2AFC4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color:
                enabled ? AppColors.textDark : AppColors.textLight),
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
  });

  final ExerciseGoal exercise;
  final double minHeight;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onSetsChanged;

  @override
  Widget build(BuildContext context) {
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
                                style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                          ),
                          AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.beige),
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
                            style: const TextStyle(
                                color: AppColors.pinkBright,
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                height: 1)),
                        Text(' / ${exercise.totalGoal}',
                            style: const TextStyle(
                                color: AppColors.textMid,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        const Text('reps today',
                            style: TextStyle(
                                color: AppColors.textLight,
                                fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Expanded section
              if (expanded) ...[
                const Divider(
                    color: Color(0x22000000), height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: _ExpandedSection(
                    exercise: exercise,
                    onRepsChanged: onRepsChanged,
                    onSetsChanged: onSetsChanged,
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
    // Placeholder — will be replaced with a real image asset
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8DCE8), Color(0xFFEED4C4)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fitness_center_rounded,
                size: 40, color: Color(0xFFD6A0B0)),
            const SizedBox(height: 6),
            Text(name,
                style: const TextStyle(
                    color: Color(0xFFBB8899),
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
  });

  final ExerciseGoal exercise;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onSetsChanged;

  @override
  Widget build(BuildContext context) {
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
          label: 'Sets per day',
          value: '${exercise.setsPerDay}',
          onDec: exercise.setsPerDay > 1
              ? () => onSetsChanged(exercise.setsPerDay - 1)
              : null,
          onInc: exercise.setsPerDay < 10
              ? () => onSetsChanged(exercise.setsPerDay + 1)
              : null,
        ),
        const SizedBox(height: 10),
        // Goal summary
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Goal: ${exercise.totalGoal} reps / day',
            style: const TextStyle(
                color: AppColors.textLight, fontSize: 11),
          ),
        ),
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
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        _StepBtn(icon: Icons.remove_rounded, onTap: onDec),
        SizedBox(
          width: 44,
          child: Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.pinkBright,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ),
        _StepBtn(icon: Icons.add_rounded, onTap: onInc),
      ],
    );
  }
}
