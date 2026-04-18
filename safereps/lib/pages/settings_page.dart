import 'package:flutter/material.dart';

import '../main.dart' show cameras;
import '../models/coach_settings.dart';
import '../models/goals_model.dart';
import '../pages/ble_debug_page.dart';
import '../pose_camera_page.dart';
import '../shell.dart' show kNavPillClearance;
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../services/theme_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final themeService = ThemeScope.of(context);
    final coach = CoachSettingsScope.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16).copyWith(
            bottom: 16 + kNavPillClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _SectionLabel('Appearance', color: themeColors.textLight),
            const SizedBox(height: 8),
            GlassCard(
              padding: const EdgeInsets.all(12),
              borderRadius: 16,
              child: Row(
                children: [
                   _ThemeOption(
                    label: 'Matte Pink',
                    flavor: ThemeFlavor.pink,
                    current: themeService.flavor,
                    onTap: () => themeService.setFlavor(ThemeFlavor.pink),
                    primary: const Color(0xFFD6176E),
                    accent: const Color(0xFFF2AFC4),
                    textDark: themeColors.textDark,
                  ),
                  const SizedBox(width: 12),
                  _ThemeOption(
                    label: 'Matte Blue',
                    flavor: ThemeFlavor.blue,
                    current: themeService.flavor,
                    onTap: () => themeService.setFlavor(ThemeFlavor.blue),
                    primary: const Color(0xFF6096BA),
                    accent: const Color(0xFFA9C9D3),
                    textDark: themeColors.textDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Progress', color: themeColors.textLight),
            const SizedBox(height: 8),
            GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: ListTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: themeColors.accent.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.refresh_rounded,
                      color: themeColors.textDark, size: 18),
                ),
                title: Text('Reset Today\'s Progress',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: themeColors.textDark)),
                subtitle: Text('Clears rep counts for today',
                    style: TextStyle(color: themeColors.textMid, fontSize: 12)),
                onTap: () {
                  final model = GoalsScope.of(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset Today\'s Progress?'),
                      content: const Text(
                          'This will clear all rep counts for today.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            model.resetDailyProgress();
                            Navigator.pop(ctx);
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Coach Voice', color: themeColors.textLight),
            const SizedBox(height: 8),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Captions toggle
                  Row(
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: themeColors.accent.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.closed_caption_rounded,
                            color: themeColors.textDark, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('On-Screen Captions',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: themeColors.textDark)),
                            Text('Show coach cues as text during workout',
                                style: TextStyle(
                                    color: themeColors.textMid, fontSize: 12)),
                          ],
                        ),
                      ),
                      Switch(
                        value: coach.captions,
                        onChanged: coach.setCaptions,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0x18000000)),
                  const SizedBox(height: 14),
                  // Sliders
                  _CoachSlider(
                    icon: Icons.volume_up_rounded,
                    label: 'Voice Volume',
                    value: coach.volume,
                    onChanged: coach.setVolume,
                    leftLabel: 'Quiet',
                    rightLabel: 'Loud',
                  ),
                  _CoachSlider(
                    icon: Icons.notifications_rounded,
                    label: 'Feedback Frequency',
                    value: coach.frequency,
                    onChanged: coach.setFrequency,
                    leftLabel: 'Rare',
                    rightLabel: 'Constant',
                  ),
                  _CoachSlider(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    label: 'Positive Reinforcement',
                    value: coach.positive,
                    onChanged: coach.setPositive,
                    leftLabel: 'Less',
                    rightLabel: 'More',
                  ),
                  _CoachSlider(
                    icon: Icons.build_circle_outlined,
                    label: 'Constructive Criticism',
                    value: coach.criticism,
                    onChanged: coach.setCriticism,
                    leftLabel: 'Lenient',
                    rightLabel: 'Strict',
                  ),
                  _CoachSlider(
                    icon: Icons.track_changes_rounded,
                    label: 'Form Strictness',
                    value: coach.strictness,
                    onChanged: coach.setStrictness,
                    leftLabel: 'Relaxed',
                    rightLabel: 'Strict',
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Developer', color: themeColors.textLight),
            const SizedBox(height: 8),
            GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: themeColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.videocam_rounded,
                          color: themeColors.textDark, size: 18),
                    ),
                    title: Text('Debug View',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: themeColors.textDark)),
                    subtitle: Text('Pose detection camera feed',
                        style: TextStyle(
                            color: themeColors.textMid, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: themeColors.unselected),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PoseCameraPage(cameras: cameras),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 56, color: Color(0x18000000)),
                  ListTile(
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: themeColors.accent.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.bluetooth_rounded,
                          color: themeColors.textDark, size: 18),
                    ),
                    title: Text('BLE Debug',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: themeColors.textDark)),
                    subtitle: Text('Connect & stream ESP32 IMU data',
                        style: TextStyle(
                            color: themeColors.textMid, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: themeColors.unselected),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BleDebugPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('About', color: themeColors.textLight),
            const SizedBox(height: 8),
            GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: ListTile(
                leading: _AppIconBadge(primary: Theme.of(context).colorScheme.primary),
                title: Text('SafeReps',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: themeColors.textDark)),
                subtitle: Text('v1.0.0  ·  Pose + IMU exercise coach',
                    style:
                        TextStyle(color: themeColors.textMid, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.flavor,
    required this.current,
    required this.onTap,
    required this.primary,
    required this.accent,
    required this.textDark,
  });

  final String label;
  final ThemeFlavor flavor;
  final ThemeFlavor current;
  final VoidCallback onTap;
  final Color primary;
  final Color accent;
  final Color textDark;

  @override
  Widget build(BuildContext context) {
    final selected = flavor == current;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? primary.withValues(alpha: 0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _AppIconBadge extends StatelessWidget {
  const _AppIconBadge({required this.primary});
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.2), width: 1),
      ),
      padding: const EdgeInsets.all(4),
      child: Image.asset(
        'assets/SafeReps_Logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

// ── Coach slider widget ───────────────────────────────────────────────────────

class _CoachSlider extends StatelessWidget {
  const _CoachSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.leftLabel,
    required this.rightLabel,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String leftLabel;
  final String rightLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: primary, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: themeColors.textDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: primary,
            inactiveTrackColor: primary.withValues(alpha: 0.18),
            thumbColor: primary,
            overlayColor: primary.withValues(alpha: 0.12),
          ),
          child: Slider(value: value, onChanged: onChanged),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leftLabel,
                  style: TextStyle(
                      color: themeColors.textLight, fontSize: 10)),
              Text(rightLabel,
                  style: TextStyle(
                      color: themeColors.textLight, fontSize: 10)),
            ],
          ),
        ),
        if (!isLast) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0x10000000)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

