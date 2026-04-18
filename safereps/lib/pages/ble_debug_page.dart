import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class BleDebugPage extends StatefulWidget {
  const BleDebugPage({super.key});

  @override
  State<BleDebugPage> createState() => _BleDebugPageState();
}

class _BleDebugPageState extends State<BleDebugPage> {
  final _ble = BleService();

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ble,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: const Text('BLE Debug',
                style: TextStyle(
                    color: AppColors.textDark, fontWeight: FontWeight.w700)),
            iconTheme: const IconThemeData(color: AppColors.textDark),
            actions: [
              if (_ble.isConnected)
                TextButton(
                  onPressed: _ble.disconnect,
                  child: const Text('Disconnect',
                      style: TextStyle(color: AppColors.pinkBright)),
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (_ble.statusMessage != null) _StatusBanner(_ble.statusMessage!),
                if (!_ble.isConnected) ...[
                  _ScanPanel(ble: _ble),
                ] else ...[
                  _ControlPanel(ble: _ble),
                  const SizedBox(height: 12),
                  _DataPanel(data: _ble.latestData),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Status banner ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 10,
        child: Text(message,
            style: const TextStyle(
                color: AppColors.textMid, fontSize: 12),
            textAlign: TextAlign.center),
      ),
    );
  }
}

// ─── Scan panel ───────────────────────────────────────────────────────────────

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.pinkBright,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: ble.isScanning ? ble.stopScan : ble.startScan,
          icon: ble.isScanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching_rounded,
                  color: Colors.white),
          label: Text(ble.isScanning ? 'Scanning…' : 'Scan for Devices',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        if (ble.scanResults.isNotEmpty) ...[
          const _SectionLabel('Discovered Devices'),
          const SizedBox(height: 6),
          GlassCard(
            padding: EdgeInsets.zero,
            borderRadius: 14,
            child: Column(
              children: [
                for (int i = 0; i < ble.scanResults.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, indent: 56, color: Color(0x18000000)),
                  _DeviceTile(result: ble.scanResults[i], ble: ble),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.result, required this.ble});
  final ScanResult result;
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown (${result.device.remoteId})';
    final rssi = result.rssi;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.pink,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            const Icon(Icons.bluetooth_rounded, color: AppColors.textDark, size: 18),
      ),
      title: Text(name,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 14)),
      subtitle: Text('RSSI: $rssi dBm',
          style: const TextStyle(color: AppColors.textMid, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.beige),
      onTap: () => ble.connect(result.device),
    );
  }
}

// ─── Control panel (when connected) ──────────────────────────────────────────

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ble.connectedDevice?.platformName.isNotEmpty == true
                      ? ble.connectedDevice!.platformName
                      : 'Connected',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CtrlButton(
                  label: ble.isStreaming ? 'DATA OFF' : 'DATA ON',
                  icon: ble.isStreaming
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outlined,
                  color: ble.isStreaming
                      ? const Color(0xFFFF3B30)
                      : AppColors.pinkBright,
                  onTap: ble.toggleStream,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CtrlButton(
                  label: 'ZERO',
                  icon: Icons.my_location_rounded,
                  color: AppColors.textMid,
                  onTap: ble.zero,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CtrlButton(
                  label: 'CALIBRATE',
                  icon: Icons.tune_rounded,
                  color: AppColors.textMid,
                  onTap: ble.calibrate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

// ─── Data panel ───────────────────────────────────────────────────────────────

class _DataPanel extends StatelessWidget {
  const _DataPanel({required this.data});
  final ImuData? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return GlassCard(
        borderRadius: 14,
        child: const Center(
          child: Text('No data — tap DATA ON',
              style: TextStyle(color: AppColors.textLight)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Orientation'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _AngleCard('Yaw', data!.yaw, AppColors.pinkBright)),
            const SizedBox(width: 8),
            Expanded(child: _AngleCard('Pitch', data!.pitch, const Color(0xFF5AC8FA))),
            const SizedBox(width: 8),
            Expanded(child: _AngleCard('Roll', data!.roll, const Color(0xFF34C759))),
          ],
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Accelerometer (g)'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _AxisChip('X', data!.ax),
              const SizedBox(width: 8),
              _AxisChip('Y', data!.ay),
              const SizedBox(width: 8),
              _AxisChip('Z', data!.az),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Gyroscope (°/s)'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _AxisChip('X', data!.gx),
              const SizedBox(width: 8),
              _AxisChip('Y', data!.gy),
              const SizedBox(width: 8),
              _AxisChip('Z', data!.gz),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Battery'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          child: Row(
            children: [
              const Icon(Icons.battery_charging_full_rounded,
                  color: AppColors.pinkBright, size: 22),
              const SizedBox(width: 10),
              Text('${data!.batt.toStringAsFixed(2)} V',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppColors.textDark)),
              const SizedBox(width: 8),
              Text(_battLabel(data!.batt),
                  style: const TextStyle(
                      color: AppColors.textMid, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _battLabel(double v) {
    if (v >= 4.0) return 'Full';
    if (v >= 3.6) return 'Good';
    if (v >= 3.3) return 'Low';
    return 'Critical';
  }
}

class _AngleCard extends StatelessWidget {
  const _AngleCard(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(1)}°',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: AppColors.textDark)),
        ],
      ),
    );
  }
}

class _AxisChip extends StatelessWidget {
  const _AxisChip(this.axis, this.value);
  final String axis;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(axis,
              style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value.toStringAsFixed(2),
              style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
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
