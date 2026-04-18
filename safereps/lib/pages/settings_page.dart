import 'package:flutter/material.dart';

import '../main.dart' show cameras;
import '../models/goals_model.dart';
import '../pose_camera_page.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            _SectionLabel('Progress'),
            const SizedBox(height: 8),
            GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: ListTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD6E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: AppColors.textDark, size: 18),
                ),
                title: const Text('Reset Today\'s Progress',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                subtitle: const Text('Clears rep counts for today',
                    style: TextStyle(color: AppColors.textMid, fontSize: 12)),
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
            _SectionLabel('Developer'),
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
                        color: AppColors.pink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.videocam_rounded,
                          color: AppColors.textDark, size: 18),
                    ),
                    title: const Text('Debug View',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark)),
                    subtitle: const Text('Pose detection camera feed',
                        style: TextStyle(
                            color: AppColors.textMid, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.beige),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PoseCameraPage(cameras: cameras),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('About'),
            const SizedBox(height: 8),
            GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: const ListTile(
                leading: _AppIconBadge(),
                title: Text('SafeReps',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                subtitle: Text('v1.0.0  ·  Pose + IMU exercise coach',
                    style:
                        TextStyle(color: AppColors.textMid, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textLight,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _AppIconBadge extends StatelessWidget {
  const _AppIconBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.pinkBright,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.fitness_center_rounded,
          color: Colors.white, size: 18),
    );
  }
}
