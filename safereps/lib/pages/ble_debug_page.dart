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
  // ── Firmware filter params ──────────────────────
  double _mountAngle     = 0.0;   // degrees — rotates pitch/roll axes to match wrist mount
  double _tremorHpAlpha  = 0.600;
  double _tremorEmaAlpha = 0.08;
  double _cheatEps       = 0.05;
  double _cheatEmaAlpha  = 0.05;

  // ── Flutter-side classification thresholds ──────────────────
  double _tremorNone     = 0.02;
  double _tremorMild     = 0.06;
  double _tremorMod      = 0.12;
  double _formBorderline = 13.9;
  double _formSwing      = 15.4;

  bool _tuningOpen = false;

  @override
  Widget build(BuildContext context) {
    final ble = BleScope.of(context);
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;
    final state = ble.connectionState;
    final connected = state == BleConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: themeColors.textDark),
        actions: [
          if (connected) ...[
            IconButton(
              icon: Icon(
                Icons.tune_rounded,
                color: _tuningOpen ? themeColors.accent : themeColors.unselected,
              ),
              tooltip: 'Tune parameters',
              onPressed: () => setState(() => _tuningOpen = !_tuningOpen),
            ),
            TextButton(
              onPressed: ble.disconnect,
              child: Text('Disconnect',
                  style: TextStyle(color: primary)),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (ble.statusMessage != null)
              _StatusBanner(ble.statusMessage!),

            if (state == BleConnectionState.reconnecting) ...[
              _ReconnectPanel(ble: ble),
            ] else if (connected) ...[
              _ControlPanel(ble: ble),
              if (ble.isCalibrating) ...[
                const SizedBox(height: 12),
                const _CalibrationBanner(),
              ],
              if (_tuningOpen) ...[
                const SizedBox(height: 12),
                _TuningPanel(
                  mountAngle:       _mountAngle,
                  tremorHpAlpha:    _tremorHpAlpha,
                  tremorEmaAlpha:   _tremorEmaAlpha,
                  cheatEps:         _cheatEps,
                  cheatEmaAlpha:    _cheatEmaAlpha,
                  tremorNone:       _tremorNone,
                  tremorMild:       _tremorMild,
                  tremorMod:        _tremorMod,
                  formBorderline:   _formBorderline,
                  formSwing:        _formSwing,
                  onMountAngle: (v) { setState(() => _mountAngle     = v); ble.setMountAngle(v); },
                  onTremorHp:  (v) { setState(() => _tremorHpAlpha  = v); ble.setTremorHp(v);  },
                  onTremorEma: (v) { setState(() => _tremorEmaAlpha = v); ble.setTremorEma(v); },
                  onCheatEps:  (v) { setState(() => _cheatEps       = v); ble.setCheatEps(v);  },
                  onCheatEma:  (v) { setState(() => _cheatEmaAlpha  = v); ble.setCheatEma(v);  },
                  onTremorNone:     (v) => setState(() => _tremorNone     = v),
                  onTremorMild:     (v) => setState(() => _tremorMild     = v),
                  onTremorMod:      (v) => setState(() => _tremorMod      = v),
                  onFormBorderline: (v) => setState(() => _formBorderline = v),
                  onFormSwing:      (v) => setState(() => _formSwing      = v),
                ),
              ],
              const SizedBox(height: 12),
              _DataPanel(
                data:           ble.latestData,
                tremorNone:     _tremorNone,
                tremorMild:     _tremorMild,
                tremorMod:      _tremorMod,
                formBorderline: _formBorderline,
                formSwing:      _formSwing,
              ),
            ] else ...[
              _ScanPanel(ble: ble),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(message,
            style: TextStyle(color: colors.textMid, fontSize: 12),
            textAlign: TextAlign.center),
      ),
    );
  }
}

class _ReconnectPanel extends StatelessWidget {
  const _ReconnectPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return GlassCard(
      borderRadius: 16,
      child: Column(
        children: [
          SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(
                color: colors.accent, strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          Text(ble.savedDeviceName ?? 'Saved device',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textDark,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text('Attempt ${ble.reconnectAttempt}',
              style: TextStyle(color: colors.textMid, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textMid,
                    side: BorderSide(color: colors.unselected),
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

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final isScanning = ble.connectionState == BleConnectionState.scanning;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ble.savedDeviceId != null) ...[
          _SavedDeviceCard(ble: ble),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: isScanning ? ble.stopScan : ble.startScan,
          icon: isScanning
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching_rounded, color: Colors.white),
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
                    const Divider(height: 1, indent: 56, color: Color(0x18000000)),
                  _DeviceTile(
                    result: ble.scanResults[i],
                    isSaved: ble.scanResults[i].device.remoteId.str == ble.savedDeviceId,
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
    final colors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.bluetooth_connected_rounded,
                color: primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saved Device',
                    style: TextStyle(
                        color: colors.textLight, fontSize: 11,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(ble.savedDeviceName ?? ble.savedDeviceId ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.textDark, fontSize: 14)),
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
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Connect',
                style: TextStyle(
                    color: Colors.white, fontSize: 12,
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
    final colors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown (${result.device.remoteId})';

    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isSaved ? primary.withValues(alpha: 0.15) : colors.unselected.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isSaved ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
          color: isSaved ? primary : colors.textDark,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textDark, fontSize: 14)),
          ),
          if (isSaved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Saved',
                  style: TextStyle(
                      color: primary,
                      fontSize: 10, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      subtitle: Text('RSSI: ${result.rssi} dBm',
          style: TextStyle(color: colors.textMid, fontSize: 11)),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.unselected),
      onTap: onTap,
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;
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
                width: 10, height: 10,
                decoration: const BoxDecoration(
                    color: Color(0xFF34C759), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.textDark, fontSize: 15)),
              ),
              TextButton(
                onPressed: ble.forgetDevice,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
                child: const Text('Forget',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
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
                      : primary,
                  onTap: ble.toggleStream,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CtrlButton(
                  label: 'ZERO',
                  icon: Icons.my_location_rounded,
                  color: colors.textMid,
                  onTap: ble.zero,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CtrlButton(
                  label: 'CALIBRATE',
                  icon: Icons.tune_rounded,
                  color: colors.textMid,
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
    final c = onTap == null ? color.withValues(alpha: 0.4) : color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            loading
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: c, strokeWidth: 2))
                : Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _CalibrationBanner extends StatelessWidget {
  const _CalibrationBanner();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                color: colors.accent, strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calibrating…',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.textDark, fontSize: 14)),
                const SizedBox(height: 2),
                Text('Keep the device completely still',
                    style: TextStyle(color: colors.textMid, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TuningPanel extends StatelessWidget {
  const _TuningPanel({
    required this.mountAngle,
    required this.tremorHpAlpha,
    required this.tremorEmaAlpha,
    required this.cheatEps,
    required this.cheatEmaAlpha,
    required this.tremorNone,
    required this.tremorMild,
    required this.tremorMod,
    required this.formBorderline,
    required this.formSwing,
    required this.onMountAngle,
    required this.onTremorHp,
    required this.onTremorEma,
    required this.onCheatEps,
    required this.onCheatEma,
    required this.onTremorNone,
    required this.onTremorMild,
    required this.onTremorMod,
    required this.onFormBorderline,
    required this.onFormSwing,
  });

  final double mountAngle;
  final double tremorHpAlpha, tremorEmaAlpha;
  final double cheatEps, cheatEmaAlpha;
  final double tremorNone, tremorMild, tremorMod;
  final double formBorderline, formSwing;

  final ValueChanged<double> onMountAngle;
  final ValueChanged<double> onTremorHp, onTremorEma;
  final ValueChanged<double> onCheatEps, onCheatEma;
  final ValueChanged<double> onTremorNone, onTremorMild, onTremorMod;
  final ValueChanged<double> onFormBorderline, onFormSwing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TuneSection('Firmware  ·  sent to device'),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Mount angle (°)',
            hint: 'Rotate pitch/roll axes — adjust until pitch reads correctly',
            value: mountAngle,
            min: -180, max: 180, divisions: 360,
            format: (v) => '${v.toStringAsFixed(0)}°',
            onChanged: onMountAngle,
          ),
          _ParamSlider(
            label: 'Tremor HP α',
            hint: 'Higher = only faster jitter counted',
            value: tremorHpAlpha,
            min: 0.50, max: 0.99, divisions: 49,
            format: (v) => v.toStringAsFixed(3),
            onChanged: onTremorHp,
          ),
          _ParamSlider(
            label: 'Tremor EMA α',
            hint: 'Higher = score reacts faster (less smooth)',
            value: tremorEmaAlpha,
            min: 0.01, max: 0.50, divisions: 49,
            format: (v) => v.toStringAsFixed(3),
            onChanged: onTremorEma,
          ),
          _ParamSlider(
            label: 'Cheat ε (g)',
            hint: 'Raise if resting shows false cheat; lower for more sensitivity',
            value: cheatEps,
            min: 0.01, max: 0.50, divisions: 49,
            format: (v) => '${v.toStringAsFixed(3)} g',
            onChanged: onCheatEps,
          ),
          _ParamSlider(
            label: 'Cheat EMA α',
            hint: 'Higher = form indicator reacts faster',
            value: cheatEmaAlpha,
            min: 0.01, max: 0.50, divisions: 49,
            format: (v) => v.toStringAsFixed(3),
            onChanged: onCheatEma,
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0x12000000)),
          const SizedBox(height: 10),

          const _TuneSection('Thresholds  ·  display only'),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Tremor none→mild (g)',
            hint: 'Below this = no tremor detected',
            value: tremorNone,
            min: 0.005, max: 0.10, divisions: 38,
            format: (v) => '${v.toStringAsFixed(3)} g',
            onChanged: onTremorNone,
          ),
          _ParamSlider(
            label: 'Tremor mild→moderate (g)',
            hint: 'Above none, below this = mild',
            value: tremorMild,
            min: 0.01, max: 0.20, divisions: 38,
            format: (v) => '${v.toStringAsFixed(3)} g',
            onChanged: onTremorMild,
          ),
          _ParamSlider(
            label: 'Tremor moderate→high (g)',
            hint: 'Above this = high tremor',
            value: tremorMod,
            min: 0.02, max: 0.40, divisions: 38,
            format: (v) => '${v.toStringAsFixed(3)} g',
            onChanged: onTremorMod,
          ),
          _ParamSlider(
            label: 'Form controlled→borderline',
            hint: 'Ratio below this = controlled movement',
            value: formBorderline,
            min: 5, max: 30, divisions: 250,
            format: (v) => v.toStringAsFixed(1),
            onChanged: onFormBorderline,
          ),
          _ParamSlider(
            label: 'Form borderline→swinging',
            hint: 'Ratio above this = gravitational swing detected',
            value: formSwing,
            min: 5, max: 30, divisions: 250,
            format: (v) => v.toStringAsFixed(1),
            onChanged: onFormSwing,
          ),
        ],
      ),
    );
  }
}

class _TuneSection extends StatelessWidget {
  const _TuneSection(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text(text.toUpperCase(),
        style: TextStyle(
            color: colors.textLight, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.1));
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label, hint;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: colors.textDark,
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              Text(format(value),
                  style: TextStyle(
                      color: colors.accent,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.accent.withValues(alpha: 0.2),
              thumbColor: colors.accent,
              overlayColor: colors.accent.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min, max: max, divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Text(hint,
              style: TextStyle(color: colors.textLight, fontSize: 10)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({
    required this.data,
    required this.tremorNone,
    required this.tremorMild,
    required this.tremorMod,
    required this.formBorderline,
    required this.formSwing,
  });

  final ImuData? data;
  final double tremorNone, tremorMild, tremorMod;
  final double formBorderline, formSwing;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (data == null) {
      return GlassCard(
        borderRadius: 14,
        child: Center(
          child: Text('No data yet — tap DATA ON',
              style: TextStyle(color: colors.textLight)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Activity'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _FormIndicator(
                score:      data!.swing,
                borderline: formBorderline,
                swing:      formSwing,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TremorIndicator(
                score:    data!.tremor,
                none:     tremorNone,
                mild:     tremorMild,
                moderate: tremorMod,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        const _SectionLabel('Orientation (°)'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _AngleCard('YAW',   data!.yaw,   primary)),
            const SizedBox(width: 8),
            Expanded(child: _AngleCard('PITCH', data!.pitch, const Color(0xFF5AC8FA))),
            const SizedBox(width: 8),
            Expanded(child: _AngleCard('ROLL',  data!.roll,  const Color(0xFF34C759))),
          ],
        ),

        const SizedBox(height: 16),

        const _SectionLabel('Accelerometer (g)  ·  Gyroscope (°/s)'),
        const SizedBox(height: 6),
        GlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              _AxisRow(
                label: 'Accel', unit: 'g',
                xVal: data!.ax, yVal: data!.ay, zVal: data!.az,
                color: const Color(0xFF5AC8FA), maxAbs: 2.0,
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0x12000000)),
              const SizedBox(height: 10),
              _AxisRow(
                label: 'Gyro', unit: '°/s',
                xVal: data!.gx, yVal: data!.gy, zVal: data!.gz,
                color: const Color(0xFFFF9F0A), maxAbs: 250.0,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        const _SectionLabel('Battery'),
        const SizedBox(height: 6),
        _BatteryCard(voltage: data!.batt),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FormIndicator extends StatelessWidget {
  const _FormIndicator({
    required this.score,
    required this.borderline,
    required this.swing,
  });
  final double score, borderline, swing;

  static const _kMaxDisplay = 400.0;

  String get _label {
    if (score < borderline) return 'Controlled';
    if (score < swing)      return 'Borderline';
    return 'SWINGING';
  }

  Color get _color {
    if (score < borderline) return const Color(0xFF34C759);
    if (score < swing)      return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  IconData get _icon {
    if (score < borderline) return Icons.check_circle_outline_rounded;
    if (score < swing)      return Icons.warning_amber_rounded;
    return Icons.priority_high_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final fraction = (score / _kMaxDisplay).clamp(0.0, 1.0);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_icon, color: _color, size: 16),
            const SizedBox(width: 6),
            Text('FORM',
                style: TextStyle(
                    color: colors.textLight, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.1)),
          ]),
          const SizedBox(height: 8),
          Text(_label,
              style: TextStyle(
                  color: _color, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 2),
          Text('ratio ${score.toStringAsFixed(1)}',
              style: TextStyle(
                  color: colors.textMid, fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction, minHeight: 6,
              backgroundColor: const Color(0x18000000),
              valueColor: AlwaysStoppedAnimation(_color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TremorIndicator extends StatelessWidget {
  const _TremorIndicator({
    required this.score,
    required this.none,
    required this.mild,
    required this.moderate,
  });
  final double score, none, mild, moderate;

  String get _label {
    if (score < none)     return 'None';
    if (score < mild)     return 'Mild';
    if (score < moderate) return 'Moderate';
    return 'High';
  }

  Color get _color {
    if (score < none) return const Color(0xFF607D8B);
    if (score < mild) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  double get _fullBar => moderate * 2.5;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final fraction = (score / _fullBar).clamp(0.0, 1.0);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.vibration_rounded, color: _color, size: 16),
            const SizedBox(width: 6),
            Text('TREMOR',
                style: TextStyle(
                    color: colors.textLight, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.1)),
          ]),
          const SizedBox(height: 8),
          Text(_label,
              style: TextStyle(
                  color: _color, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 2),
          Text('${score.toStringAsFixed(3)} g',
              style: TextStyle(
                  color: colors.textMid, fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction, minHeight: 6,
              backgroundColor: const Color(0x18000000),
              valueColor: AlwaysStoppedAnimation(_color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AngleCard extends StatelessWidget {
  const _AngleCard(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text('${value.toStringAsFixed(1)}°',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 22,
                  color: colors.textDark)),
        ],
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.label,
    required this.xVal,
    required this.yVal,
    required this.zVal,
    required this.unit,
    required this.color,
    required this.maxAbs,
  });

  final String label, unit;
  final double xVal, yVal, zVal, maxAbs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Row(
          children: [
            _AxisBar('X', xVal, unit, color, maxAbs),
            const SizedBox(width: 10),
            _AxisBar('Y', yVal, unit, color, maxAbs),
            const SizedBox(width: 10),
            _AxisBar('Z', zVal, unit, color, maxAbs),
          ],
        ),
      ],
    );
  }
}

class _AxisBar extends StatelessWidget {
  const _AxisBar(this.axis, this.value, this.unit, this.color, this.maxAbs);
  final String axis, unit;
  final double value, maxAbs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final fraction = (value.abs() / maxAbs).clamp(0.0, 1.0);
    final isNeg = value < 0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(axis,
                  style: TextStyle(
                      color: colors.textLight, fontSize: 10,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${isNeg ? '' : '+'}${value.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: isNeg ? const Color(0xFFFF9500) : colors.textDark,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction, minHeight: 5,
              backgroundColor: const Color(0x14000000),
              valueColor: AlwaysStoppedAnimation(
                  isNeg ? const Color(0xFFFF9500) : color),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.voltage});
  final double voltage;

  IconData get _icon {
    if (voltage >= 4.0) return Icons.battery_full_rounded;
    if (voltage >= 3.6) return Icons.battery_5_bar_rounded;
    if (voltage >= 3.3) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  Color get _color {
    if (voltage >= 3.6) return const Color(0xFF34C759);
    if (voltage >= 3.3) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  String get _label {
    if (voltage >= 4.0) return 'Full';
    if (voltage >= 3.6) return 'Good';
    if (voltage >= 3.3) return 'Low';
    return 'Critical';
  }

  double get _fraction =>
      ((voltage - 3.3) / (4.2 - 3.3)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(_icon, color: _color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${voltage.toStringAsFixed(2)} V',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20,
                            color: colors.textDark)),
                    const SizedBox(width: 8),
                    Text(_label,
                        style: TextStyle(
                            color: _color, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _fraction, minHeight: 6,
                    backgroundColor: const Color(0x18000000),
                    valueColor: AlwaysStoppedAnimation(_color),
                  ),
                ),
              ],
            ),
          ),
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
    final colors = AppTheme.colors(context);
    return Text(text.toUpperCase(),
        style: TextStyle(
            color: colors.textLight, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1.2));
  }
}
