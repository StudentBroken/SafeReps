import 'dart:math' show pi;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, DeviceIdentifier, ScanResult;

import '../models/goals_model.dart';
import '../services/ble_service.dart';
import '../shell.dart' show kNavPillClearance;
import '../theme.dart';
import '../widgets/glass_card.dart';
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
    final model = GoalsScope.of(context);
    final themeColors = AppTheme.colors(context);
    
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0).copyWith(
            bottom: 32 + kNavPillClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashHeader(),
            const SizedBox(height: 16),

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

            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Exercise Safely',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: themeColors.textMid, fontSize: 13),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _SafetyCard(
                    title: 'Warm Up',
                    icon: Icons.self_improvement_rounded,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SafetyCard(
                    title: 'Proper Form',
                    icon: Icons.accessibility_new_rounded,
                    color: themeColors.accent.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            Center(
              child: _StartButton(
                pulseAnim: _pulseAnim,
                onTap: () {
                  final goals = GoalsScope.of(context);
                  final ble = BleScope.of(context);
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (ctx, anim, secondary) =>
                          SessionPage(goals: goals, ble: ble),
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

            _ProgressPillsCard(exercises: model.exercises),
          ],
        ),
      ),
    );
  }
}

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
      children: [
        Expanded(
          child: Text(greeting,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 24)),
        ),
        const _BlePill(),
      ],
    );
  }
}

class _BlePill extends StatelessWidget {
  const _BlePill();

  @override
  Widget build(BuildContext context) {
    final ble = BleScope.of(context);
    final connected = ble.connectionState == BleConnectionState.connected;
    final reconnecting = ble.connectionState == BleConnectionState.reconnecting;
    final batt = ble.battVoltage;

    final Color pillColor;
    final String label;

    if (connected) {
      if (batt != null) {
        pillColor = batt >= 3.6 ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
        final warning = batt < 3.6 ? ' !' : '';
        label = '${batt.toStringAsFixed(2)}V$warning';
      } else {
        pillColor = const Color(0xFF34C759);
        label = 'Connected';
      }
    } else if (reconnecting) {
      pillColor = const Color(0xFFFF9500);
      label = 'Connecting…';
    } else {
      pillColor = const Color(0xFFFF9500);
      label = 'Connect';
    }

    return GestureDetector(
      onTap: () => _showSheet(context, ble),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: pillColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: pillColor.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pillColor,
                boxShadow: [
                  BoxShadow(
                    color: pillColor.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: pillColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, BleService ble) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BleConnectSheet(ble: ble),
    );
  }
}

class _BleConnectSheet extends StatefulWidget {
  const _BleConnectSheet({required this.ble});
  final BleService ble;

  @override
  State<_BleConnectSheet> createState() => _BleConnectSheetState();
}

class _BleConnectSheetState extends State<_BleConnectSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.ble.savedDeviceId == null &&
        widget.ble.connectionState == BleConnectionState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.ble.startScan();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        final state = ble.connectionState;
        final connected = state == BleConnectionState.connected;
        final reconnecting = state == BleConnectionState.reconnecting;
        final scanning = state == BleConnectionState.scanning;

        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withAlpha(50), width: 1),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: themeColors.unselected,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: connected
                                    ? const Color(0x2234C759)
                                    : themeColors.accent.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                connected
                                    ? Icons.bluetooth_connected_rounded
                                    : Icons.bluetooth_rounded,
                                size: 20,
                                color: connected
                                    ? const Color(0xFF34C759)
                                    : primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wearable Module',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: themeColors.textDark,
                                  ),
                                ),
                                if (ble.statusMessage != null)
                                  Text(
                                    ble.statusMessage!,
                                    style: TextStyle(
                                        color: themeColors.textMid, fontSize: 11),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        if (connected)
                          _SheetConnectedBody(ble: ble)
                        else if (reconnecting)
                          _SheetReconnectBody(ble: ble)
                        else
                          _SheetScanBody(ble: ble, scanning: scanning),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetConnectedBody extends StatelessWidget {
  const _SheetConnectedBody({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final battColor = _getBattColor(themeColors);

    final name = ble.connectedDevice?.platformName.isNotEmpty == true
        ? ble.connectedDevice!.platformName
        : ble.savedDeviceName ?? 'Connected';
    final batt = ble.battVoltage;
    final battFraction = batt != null
        ? ((batt - 3.3) / (4.2 - 3.3)).clamp(0.0, 1.0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                        color: Color(0xFF34C759), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: themeColors.textDark,
                          fontSize: 15),
                    ),
                  ),
                ],
              ),
              if (batt != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(_battIcon(batt), color: battColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${batt.toStringAsFixed(2)} V',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: battColor),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _battLabel(batt),
                                style: TextStyle(
                                    color: battColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (battFraction != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: battFraction,
                                minHeight: 5,
                                backgroundColor: const Color(0x18000000),
                                valueColor:
                                    AlwaysStoppedAnimation(battColor),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Start streaming in Debug View to see battery',
                  style: TextStyle(color: themeColors.textLight, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF3B30),
            side: const BorderSide(color: Color(0x44FF3B30)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: ble.forgetDevice,
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Forget Device',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Color _getBattColor(BrandColors colors) {
    final v = ble.battVoltage;
    if (v == null) return colors.textLight;
    if (v >= 3.6) return const Color(0xFF34C759);
    return const Color(0xFFFF3B30);
  }

  IconData _battIcon(double v) {
    if (v >= 4.0) return Icons.battery_full_rounded;
    if (v >= 3.6) return Icons.battery_5_bar_rounded;
    if (v >= 3.3) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  String _battLabel(double v) {
    if (v >= 4.0) return 'Full';
    if (v >= 3.6) return 'Good';
    if (v >= 3.3) return 'Low';
    return 'Critical';
  }
}

class _SheetReconnectBody extends StatelessWidget {
  const _SheetReconnectBody({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      borderRadius: 16,
      child: Column(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
                color: primary, strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          Text(
            ble.savedDeviceName ?? 'Saved device',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: themeColors.textDark,
                fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Attempt ${ble.reconnectAttempt}',
            style: TextStyle(color: themeColors.textMid, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: themeColors.textMid,
                    side: BorderSide(color: themeColors.unselected),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: ble.disconnect,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30),
                    side: const BorderSide(color: Color(0x44FF3B30)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: ble.forgetDevice,
                  child: const Text('Forget'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetScanBody extends StatelessWidget {
  const _SheetScanBody({required this.ble, required this.scanning});
  final BleService ble;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ble.savedDeviceId != null) ...[
          GlassCard(
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bluetooth_connected_rounded,
                      color: primary, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saved Device',
                          style: TextStyle(
                              color: themeColors.textLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(
                        ble.savedDeviceName ?? ble.savedDeviceId ?? '',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: themeColors.textDark,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: ble.forgetDevice,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Forget',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                FilledButton(
                  onPressed: () => ble.connect(BluetoothDevice(
                      remoteId: DeviceIdentifier(ble.savedDeviceId!))),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Connect',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: scanning ? ble.stopScan : ble.startScan,
          icon: scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching_rounded,
                  color: Colors.white),
          label: Text(
            scanning ? 'Scanning…' : 'Scan for Devices',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),

        if (ble.scanResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'DISCOVERED',
            style: TextStyle(
                color: themeColors.textLight,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            borderRadius: 14,
            child: Column(
              children: [
                for (int i = 0; i < ble.scanResults.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, indent: 56, color: Color(0x18000000)),
                  _ScanDeviceTile(
                    result: ble.scanResults[i],
                    isSaved: ble.scanResults[i].device.remoteId.str ==
                        ble.savedDeviceId,
                    onTap: () => ble.connect(ble.scanResults[i].device),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ScanDeviceTile extends StatelessWidget {
  const _ScanDeviceTile({
    required this.result,
    required this.isSaved,
    required this.onTap,
  });
  final ScanResult result;
  final bool isSaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown (${result.device.remoteId})';
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isSaved
              ? primary.withValues(alpha: 0.15)
              : themeColors.accent.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isSaved
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_rounded,
          color: isSaved ? primary : themeColors.textDark,
          size: 17,
        ),
      ),
      title: Text(name,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: themeColors.textDark,
              fontSize: 14)),
      subtitle: Text('${result.rssi} dBm',
          style: TextStyle(color: themeColors.textMid, fontSize: 11)),
      trailing: Icon(Icons.chevron_right_rounded, color: themeColors.unselected),
      onTap: onTap,
    );
  }
}

class _ProgressRingCard extends StatelessWidget {
  const _ProgressRingCard({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

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
                  painter: _RingPainter(progress: progress, color: primary),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            color: primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'today',
                          style: TextStyle(
                            color: themeColors.textLight,
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
          Text(
            'Daily Goal',
            style: TextStyle(
              color: themeColors.textMid,
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
  const _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({required this.exercises});
  final List<ExerciseGoal> exercises;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reps today',
            style: TextStyle(
              color: themeColors.textMid,
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
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    const maxHeight = 80.0;
    final barH = (maxHeight * fraction).clamp(4.0, maxHeight);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: themeColors.textDark,
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
              color: primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: themeColors.textLight,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ProgressPillsCard extends StatelessWidget {
  const _ProgressPillsCard({required this.exercises});
  final List<ExerciseGoal> exercises;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Progress",
            style: TextStyle(
              color: themeColors.textMid,
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
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              exercise.name,
              style: TextStyle(
                color: themeColors.textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${exercise.doneToday} / ${exercise.totalGoal}',
              style: TextStyle(
                color: themeColors.textLight,
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
            backgroundColor: primary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(primary),
          ),
        ),
      ],
    );
  }
}

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
    final themeColors = AppTheme.colors(context);
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
              child: Icon(icon, color: themeColors.textDark, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to learn',
              style: TextStyle(color: themeColors.textLight, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  void _showModal(BuildContext context) {
    final themeColors = AppTheme.colors(context);
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
                  Icon(icon, color: themeColors.textDark, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: themeColors.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Tutorial content coming soon.\n\nThis section will guide you through safe exercise practices tailored to each movement.',
                style: TextStyle(color: themeColors.textMid, fontSize: 13, height: 1.5),
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

class _StartButton extends StatelessWidget {
  const _StartButton({required this.pulseAnim, required this.onTap});

  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

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
                color: primary,
                boxShadow: [
                  BoxShadow(
                    color: primary
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
