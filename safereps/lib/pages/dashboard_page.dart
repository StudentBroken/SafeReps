import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../models/goals_model.dart';
import '../services/ble_service.dart';
import '../shell.dart' show kNavPillClearance;
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'ble_connection_screen.dart';
import 'session_page.dart';

// ---------------------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = GoalsScope.of(context); // rebuilds when model notifies
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0).copyWith(
            bottom: 32 + kNavPillClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _DashHeader(),
            const SizedBox(height: 16),

            // ── Section 1 & 2: ring + bar chart ─────────────────────────────
            SizedBox(
              height: 168,
              child: Row(
                children: [
                  Expanded(
                    child: _ProgressRingCard(progress: model.totalProgress),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BarChartCard(exercises: model.exercises),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Section 4 header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Exercise Safely',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.textMid, fontSize: 13),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _SafetyCard(
                    title: 'Warm Up',
                    icon: Icons.self_improvement_rounded,
                    color: const Color(0xFFFFD6E0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SafetyCard(
                    title: 'Proper Form',
                    icon: Icons.accessibility_new_rounded,
                    color: const Color(0xFFD6EAFF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Section 5: start button ──────────────────────────────────────
            Center(
              child: _StartButton(
                pulseAnim: _pulseAnim,
                onTap: () {
                  final goals = GoalsScope.of(context);
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (ctx, anim, secondary) =>
                          SessionPage(goals: goals),
                      transitionsBuilder: (ctx, anim, secondary, child) {
                        final curved = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeInOutCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: ScaleTransition(
                            scale: Tween(begin: 0.93, end: 1.0)
                                .animate(curved),
                            child: child,
                          ),
                        );
                      },
                      transitionDuration:
                          const Duration(milliseconds: 480),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // ── Section 3: pill progress bars (now at bottom) ────────────────
            _ProgressPillsCard(exercises: model.exercises),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _DashHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(greeting,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 24)),
        const _BleConnectionPill(),
      ],
    );
  }
}

class _BleConnectionPill extends StatelessWidget {
  const _BleConnectionPill();

  @override
  Widget build(BuildContext context) {
    final ble = BleScope.of(context);
    final state = ble.connectionState;
    final isConnected = state == BleConnectionState.connected;
    
    final voltage = ble.latestData?.batt ?? 0;
    
    Color pillColor = Colors.orange;
    String label = 'connect';
    IconData icon = Icons.bluetooth_rounded;
    
    if (isConnected) {
      if (voltage > 0 && voltage < 3.6) {
        pillColor = Colors.red;
      } else {
        pillColor = const Color(0xFF34C759); // green
      }
      label = voltage > 0 ? '${voltage.toStringAsFixed(2)}V' : 'on';
      icon = Icons.bluetooth_connected_rounded;
    } else if (state == BleConnectionState.connecting || state == BleConnectionState.reconnecting) {
      label = 'linking...';
      pillColor = Colors.orange.withAlpha(200);
    }
    
    return GestureDetector(
      onTap: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'BLE',
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (ctx, anim1, anim2) => const BleConnectionScreen(),
          transitionBuilder: (ctx, anim1, anim2, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.1, end: 1.0).animate(
                    CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
                child: child,
              ),
            );
          },
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: pillColor.withAlpha(isConnected ? 40 : 30),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: pillColor.withAlpha(120), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: pillColor, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: pillColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section 1: circular progress ring ────────────────────────────────────────

class _ProgressRingCard extends StatelessWidget {
  const _ProgressRingCard({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: _RingPainter(progress: progress),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.pinkBright,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'today',
                          style: TextStyle(
                            color: AppColors.textLight,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Daily Goal',
            style: TextStyle(
              color: AppColors.textMid,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 6;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x33D6176E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = AppColors.pinkBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ── Section 2: bar chart ──────────────────────────────────────────────────────

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({required this.exercises});
  final List<ExerciseGoal> exercises;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reps today',
            style: TextStyle(
              color: AppColors.textMid,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: exercises
                  .map((e) => _Bar(
                        fraction: e.fraction,
                        label: _shortName(e.name),
                        value: e.doneToday,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _shortName(String name) {
    // "Lateral Raise" → "Lat. R."  |  "Bicep Curl" → "Bicep"
    final parts = name.split(' ');
    if (parts.length == 1) return name;
    return '${parts.first.substring(0, 3).toLowerCase()}.';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.label, required this.value});
  final double fraction;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    const maxHeight = 80.0;
    final barH = (maxHeight * fraction).clamp(4.0, maxHeight);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 28,
          height: maxHeight,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 28,
            height: barH,
            decoration: BoxDecoration(
              color: AppColors.pinkBright,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ── Section 3: pill progress bars ─────────────────────────────────────────────

class _ProgressPillsCard extends StatelessWidget {
  const _ProgressPillsCard({required this.exercises});
  final List<ExerciseGoal> exercises;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Progress",
            style: TextStyle(
              color: AppColors.textMid,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...exercises.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PillBar(exercise: e),
              )),
        ],
      ),
    );
  }
}

class _PillBar extends StatelessWidget {
  const _PillBar({required this.exercise});
  final ExerciseGoal exercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              exercise.name,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${exercise.doneToday} / ${exercise.totalGoal}',
              style: const TextStyle(
                color: AppColors.textLight,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: exercise.fraction,
            minHeight: 10,
            backgroundColor: const Color(0x22D6176E),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.pinkBright),
          ),
        ),
      ],
    );
  }
}

// ── Section 4: safety cards ───────────────────────────────────────────────────

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showModal(context),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        tint: color.withAlpha(60),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textDark, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to learn',
              style: TextStyle(color: AppColors.textLight, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  void _showModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          tint: color.withAlpha(80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.textDark, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Tutorial content coming soon.\n\nThis section will guide you through safe exercise practices tailored to each movement.',
                style: TextStyle(color: AppColors.textMid, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section 5: animated start button ─────────────────────────────────────────

class _StartButton extends StatelessWidget {
  const _StartButton({required this.pulseAnim, required this.onTap});

  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: pulseAnim.value,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 300,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: AppColors.pinkBright,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pinkBright
                        .withAlpha((100 * pulseAnim.value).round()),
                    blurRadius: 40 * pulseAnim.value,
                    spreadRadius: 6 * pulseAnim.value,
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 34),
                  SizedBox(width: 12),
                  Text(
                    'Start Session',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
