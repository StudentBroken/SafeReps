import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../widgets/glass_card.dart';

class BleConnectionScreen extends StatefulWidget {
  const BleConnectionScreen({super.key});

  @override
  State<BleConnectionScreen> createState() => _BleConnectionScreenState();
}

class _BleConnectionScreenState extends State<BleConnectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = BleScope.of(context);
    final state = ble.connectionState;
    final isConnected = state == BleConnectionState.connected;
    final hasSavedDevice = ble.savedDeviceId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Background Blur ───────────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(color: Colors.black.withAlpha(40)),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  _Header(onClose: () => Navigator.pop(context)),
                  const SizedBox(height: 40),

                  // ── Main Status Card ──────────────────────────────────────
                  _StatusCard(
                    ble: ble,
                    pulseAnimation: _pulseAnimation,
                  ),

                  const SizedBox(height: 32),

                  // ── Action Area ───────────────────────────────────────────
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: isConnected
                          ? _ConnectedView(ble: ble)
                          : _DiscoveryView(ble: ble),
                    ),
                  ),

                  // ── Bottom Buttons ────────────────────────────────────────
                  if (hasSavedDevice && !isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextButton(
                        onPressed: ble.forgetDevice,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('Forget Saved Device'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Connection',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white24,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }
}

// ── Status Card ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ble, required this.pulseAnimation});
  final BleService ble;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    final state = ble.connectionState;
    final isConnected = state == BleConnectionState.connected;
    final isLinking = state == BleConnectionState.connecting ||
        state == BleConnectionState.reconnecting;

    String statusText = 'Disconnected';
    if (isConnected) statusText = 'Connected';
    if (isLinking) statusText = 'Connecting...';
    if (state == BleConnectionState.scanning) statusText = 'Scanning...';

    Color statusColor = Colors.orangeAccent;
    if (isConnected) statusColor = const Color(0xFF34C759);
    if (isLinking) statusColor = Colors.lightBlueAccent;

    return GlassCard(
      borderRadius: 32,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          ScaleTransition(
            scale: isLinking ? pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: statusColor.withAlpha(40),
                shape: BoxShape.circle,
                border: Border.all(color: statusColor.withAlpha(100), width: 2),
              ),
              child: Icon(
                isConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
                color: statusColor,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          if (isConnected) ...[
            const SizedBox(height: 8),
            Text(
              ble.connectedDevice?.platformName ?? ble.savedDeviceName ?? 'Unknown Device',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Connected View ───────────────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: Colors.white70, size: 64),
        const SizedBox(height: 16),
        const Text(
          'Your SafeReps device is ready.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: ble.disconnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white24,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Discovery View ───────────────────────────────────────────────────────────

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final isScanning = ble.connectionState == BleConnectionState.scanning;
    final results = ble.scanResults;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Available Devices',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            if (isScanning)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              GestureDetector(
                onTap: ble.startScan,
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: Colors.lightBlueAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: results.isEmpty
              ? _EmptyResults(isScanning: isScanning, onScan: ble.startScan)
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _DeviceTile(
                    result: results[i],
                    onTap: () => ble.connect(results[i].device),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.isScanning, required this.onScan});
  final bool isScanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isScanning ? Icons.search_rounded : Icons.bluetooth_disabled_rounded,
            color: Colors.white24,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'Looking for SafeReps...' : 'No devices found',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
          if (!isScanning) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: onScan,
              child: const Text('Start Scanning'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.result, required this.onTap});
  final ScanResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'SafeReps Module';

    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        borderRadius: 16,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bluetooth_rounded, color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${result.rssi} dBm',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
