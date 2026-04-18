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
        final state = _ble.connectionState;
        final connected = state == BleConnectionState.connected;

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
              if (connected)
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
                // Status banner always shown when there's a message
                if (_ble.statusMessage != null)
                  _StatusBanner(_ble.statusMessage!),

                if (state == BleConnectionState.reconnecting) ...[
                  _ReconnectPanel(ble: _ble),
                ] else if (connected) ...[
                  _ControlPanel(ble: _ble),
                  if (_ble.isCalibrating) ...[
                    const SizedBox(height: 12),
                    const _CalibrationBanner(),
                  ],
                  const SizedBox(height: 12),
                  _DataPanel(data: _ble.latestData),
                ] else ...[
                  _ScanPanel(ble: _ble),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(message,
            style: const TextStyle(color: AppColors.textMid, fontSize: 12),
            textAlign: TextAlign.center),
      ),
    );
  }
}

// ─── Reconnect panel ──────────────────────────────────────────────────────────

class _ReconnectPanel extends StatelessWidget {
  const _ReconnectPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppColors.pinkBright,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ble.savedDeviceName ?? 'Saved device',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Attempt ${ble.reconnectAttempt}',
            style: const TextStyle(color: AppColors.textMid, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMid,
                    side: const BorderSide(color: AppColors.beige),
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
                  child: const Text('Forget Device'),
                ),
              ),
            ],
          ),
        ],
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
    final isScanning = ble.connectionState == BleConnectionState.scanning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Saved device quick-connect card
        if (ble.savedDeviceId != null) ...[
          _SavedDeviceCard(ble: ble),
          const SizedBox(height: 12),
        ],

        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.pinkBright,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: isScanning ? ble.stopScan : ble.startScan,
          icon: isScanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching_rounded,
                  color: Colors.white),
          label: Text(isScanning ? 'Scanning…' : 'Scan for Devices',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),

        if (ble.scanResults.isNotEmpty) ...[
          const SizedBox(height: 12),
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
                        height: 1,
                        indent: 56,
                        color: Color(0x18000000)),
                  _DeviceTile(
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

class _SavedDeviceCard extends StatelessWidget {
  const _SavedDeviceCard({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.pinkBright.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bluetooth_connected_rounded,
                color: AppColors.pinkBright, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saved Device',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  ble.savedDeviceName ?? ble.savedDeviceId ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: ble.forgetDevice,
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: const Text('Forget',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => ble.connect(
                BluetoothDevice(remoteId: DeviceIdentifier(ble.savedDeviceId!))),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pinkBright,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.result,
    required this.isSaved,
    required this.onTap,
  });
  final ScanResult result;
  final bool isSaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown (${result.device.remoteId})';

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSaved ? AppColors.pinkBright.withAlpha(30) : AppColors.pink,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isSaved
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_rounded,
          color: isSaved ? AppColors.pinkBright : AppColors.textDark,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    fontSize: 14)),
          ),
          if (isSaved)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.pinkBright.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Saved',
                  style: TextStyle(
                      color: AppColors.pinkBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      subtitle: Text('RSSI: ${result.rssi} dBm',
          style: const TextStyle(color: AppColors.textMid, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.beige),
      onTap: onTap,
    );
  }
}

// ─── Control panel (connected) ────────────────────────────────────────────────

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final name = ble.connectedDevice?.platformName.isNotEmpty == true
        ? ble.connectedDevice!.platformName
        : ble.savedDeviceName ?? 'Connected';

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
                    color: Color(0xFF34C759), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                        fontSize: 15)),
              ),
              TextButton(
                onPressed: ble.forgetDevice,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                child: const Text('Forget',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                  onTap: ble.isCalibrating ? null : ble.calibrate,
                  loading: ble.isCalibrating,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CtrlButton(
                  label: 'RESET CAL',
                  icon: Icons.delete_sweep_rounded,
                  color: const Color(0xFFFF9500),
                  onTap: ble.isCalibrating ? null : ble.resetCalibration,
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
    this.loading = false,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = onTap == null ? color.withAlpha(90) : color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: effectiveColor.withAlpha(22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: effectiveColor.withAlpha(60)),
        ),
        child: Column(
          children: [
            loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: effectiveColor, strokeWidth: 2))
                : Icon(icon, color: effectiveColor, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: effectiveColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

// ─── Calibration banner ───────────────────────────────────────────────────────

class _CalibrationBanner extends StatelessWidget {
  const _CalibrationBanner();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: AppColors.pinkBright, strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calibrating…',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                        fontSize: 14)),
                SizedBox(height: 2),
                Text('Keep the device completely still',
                    style:
                        TextStyle(color: AppColors.textMid, fontSize: 12)),
              ],
            ),
          ),
        ],
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
          child: Text('No data yet — tap DATA ON',
              style: TextStyle(color: AppColors.textLight)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Orientation (°)'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
                child: _AngleCard('Yaw', data!.yaw, AppColors.pinkBright)),
            const SizedBox(width: 8),
            Expanded(
                child: _AngleCard(
                    'Pitch', data!.pitch, const Color(0xFF5AC8FA))),
            const SizedBox(width: 8),
            Expanded(
                child: _AngleCard(
                    'Roll', data!.roll, const Color(0xFF34C759))),
          ],
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Accelerometer (g)'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _AxisChip('X', data!.ax),
            const SizedBox(width: 8),
            _AxisChip('Y', data!.ay),
            const SizedBox(width: 8),
            _AxisChip('Z', data!.az),
          ]),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Gyroscope (°/s)'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _AxisChip('X', data!.gx),
            const SizedBox(width: 8),
            _AxisChip('Y', data!.gy),
            const SizedBox(width: 8),
            _AxisChip('Z', data!.gz),
          ]),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Battery'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          child: Row(
            children: [
              Icon(
                _battIcon(data!.batt),
                color: _battColor(data!.batt),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text('${data!.batt.toStringAsFixed(2)} V',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppColors.textDark)),
              const SizedBox(width: 8),
              Text(_battLabel(data!.batt),
                  style: TextStyle(
                      color: _battColor(data!.batt), fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  IconData _battIcon(double v) {
    if (v >= 4.0) return Icons.battery_full_rounded;
    if (v >= 3.6) return Icons.battery_5_bar_rounded;
    if (v >= 3.3) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  Color _battColor(double v) {
    if (v >= 3.6) return const Color(0xFF34C759);
    if (v >= 3.3) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
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
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2));
  }
}
