import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ImuData {
  final double yaw, pitch, roll;
  final double ax, ay, az;
  final double gx, gy, gz;
  final double batt;

  const ImuData({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.batt,
  });

  factory ImuData.fromJson(Map<String, dynamic> j) => ImuData(
        yaw: (j['yaw'] as num?)?.toDouble() ?? 0,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 0,
        roll: (j['roll'] as num?)?.toDouble() ?? 0,
        ax: (j['ax'] as num?)?.toDouble() ?? 0,
        ay: (j['ay'] as num?)?.toDouble() ?? 0,
        az: (j['az'] as num?)?.toDouble() ?? 0,
        gx: (j['gx'] as num?)?.toDouble() ?? 0,
        gy: (j['gy'] as num?)?.toDouble() ?? 0,
        gz: (j['gz'] as num?)?.toDouble() ?? 0,
        batt: (j['batt'] as num?)?.toDouble() ?? 0,
      );
}

// Nordic UART Service UUIDs
const _kNusService = '6e400001-b5a4-f393-e0a9-e50e24dcca9e';
const _kNusRx = '6e400002-b5a4-f393-e0a9-e50e24dcca9e'; // write (phone → ESP32)
const _kNusTx = '6e400003-b5a4-f393-e0a9-e50e24dcca9e'; // notify (ESP32 → phone)

class BleService extends ChangeNotifier {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  ImuData? latestData;
  String? statusMessage;

  bool isScanning = false;
  bool isConnected = false;
  bool isStreaming = false;

  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  String _lineBuffer = '';

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (isScanning) return;
    scanResults = [];
    isScanning = true;
    statusMessage = 'Scanning…';
    notifyListeners();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;
      notifyListeners();
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    isScanning = false;
    statusMessage = scanResults.isEmpty ? 'No devices found' : null;
    notifyListeners();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    isScanning = false;
    notifyListeners();
  }

  // ── Connect / Disconnect ─────────────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    statusMessage = 'Connecting…';
    notifyListeners();

    try {
      await device.connect(timeout: const Duration(seconds: 12));
    } catch (e) {
      statusMessage = 'Connection failed: $e';
      notifyListeners();
      return;
    }

    connectedDevice = device;
    isConnected = true;
    statusMessage = 'Discovering services…';
    notifyListeners();

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _onDisconnected();
      }
    });

    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _kNusService) {
          for (final char in svc.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == _kNusTx) {
              _txChar = char;
              await char.setNotifyValue(true);
              _dataSub = char.onValueReceived.listen(_onRawData);
            } else if (uuid == _kNusRx) {
              _rxChar = char;
            }
          }
        }
      }
      if (_rxChar == null || _txChar == null) {
        statusMessage = 'NUS service not found on device';
      } else {
        statusMessage = 'Connected — tap DATA ON to stream';
      }
    } catch (e) {
      statusMessage = 'Service discovery failed: $e';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _dataSub?.cancel();
    _dataSub = null;
    await connectedDevice?.disconnect();
    _onDisconnected();
  }

  void _onDisconnected() {
    isConnected = false;
    isStreaming = false;
    connectedDevice = null;
    _rxChar = null;
    _txChar = null;
    latestData = null;
    statusMessage = 'Disconnected';
    notifyListeners();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  void _onRawData(List<int> bytes) {
    _lineBuffer += String.fromCharCodes(bytes);
    while (_lineBuffer.contains('\n')) {
      final idx = _lineBuffer.indexOf('\n');
      final line = _lineBuffer.substring(0, idx).trim();
      _lineBuffer = _lineBuffer.substring(idx + 1);
      if (line.startsWith('{')) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          if (json.containsKey('yaw')) {
            latestData = ImuData.fromJson(json);
          } else if (json.containsKey('status')) {
            statusMessage = json['status'] as String?;
          }
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  // ── Commands ─────────────────────────────────────────────────────────────

  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null) return;
    await _rxChar!.write(utf8.encode('$cmd\n'), withoutResponse: true);
  }

  Future<void> toggleStream() async {
    isStreaming = !isStreaming;
    await sendCommand(isStreaming ? 'DATA_ON' : 'DATA_OFF');
    notifyListeners();
  }

  Future<void> zero() => sendCommand('ZERO');
  Future<void> calibrate() => sendCommand('CALIBRATE');

  @override
  void dispose() {
    _scanSub?.cancel();
    _dataSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
