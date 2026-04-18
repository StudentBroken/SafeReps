import 'package:flutter/material.dart';

import '../main.dart' show cameras;
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
        color: primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.fitness_center_rounded,
          color: Colors.white, size: 18),
    );
  }
}
