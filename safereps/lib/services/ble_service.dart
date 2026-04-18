import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class ImuData {
  final double yaw, pitch, roll;
  final double ax, ay, az;
  final double gx, gy, gz;
  /// Tremor intensity in g — computed on-device at 100 Hz.
  /// ~0 at rest, rises with high-frequency jitter above 5 Hz.
  final double tremor;
  /// Arm-swing intensity in °/s — band-pass 0.8–3 Hz on pitch gyro.
  /// ~0 at rest, ~20–60 °/s during normal walking/exercise swing.
  final double swing;
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
    required this.tremor,
    required this.swing,
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
        tremor: (j['tremor'] as num?)?.toDouble() ?? 0,
        swing: (j['swing'] as num?)?.toDouble() ?? 0,
        batt: (j['batt'] as num?)?.toDouble() ?? 0,
      );
}

// ─── Connection state ─────────────────────────────────────────────────────────

enum BleConnectionState {
  idle,          // no saved device, nothing happening
  scanning,      // actively scanning
  connecting,    // one-shot connect in progress
  reconnecting,  // auto-reconnect loop running after link loss / on init
  connected,     // live NUS session
}

// ─── Constants ────────────────────────────────────────────────────────────────

const _kNusService = '6e400001-b5a4-f393-e0a9-e50e24dcca9e';
const _kNusRx      = '6e400002-b5a4-f393-e0a9-e50e24dcca9e';
const _kNusTx      = '6e400003-b5a4-f393-e0a9-e50e24dcca9e';

const _kPrefDeviceId   = 'ble_device_id';
const _kPrefDeviceName = 'ble_device_name';

// Exponential-backoff delays for reconnect (seconds).
const _kReconnectDelays = [2, 4, 8, 16, 30];

// ─── BleService ───────────────────────────────────────────────────────────────

class BleService extends ChangeNotifier {
  // ── Public state ────────────────────────────────────────────────────────────
  BleConnectionState connectionState = BleConnectionState.idle;
  List<ScanResult>   scanResults     = [];
  BluetoothDevice?   connectedDevice;
  ImuData?           latestData;
  String?            statusMessage;
  bool               isStreaming     = false;
  bool               isCalibrating   = false;

  /// ID + display name of the device saved to prefs (survives app restarts).
  String? savedDeviceId;
  String? savedDeviceName;

  /// Which reconnect attempt we are on (shown in UI).
  int reconnectAttempt = 0;

  // ── Private ─────────────────────────────────────────────────────────────────
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;

  StreamSubscription<List<ScanResult>>?       _scanSub;
  StreamSubscription<List<int>>?              _dataSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  String _lineBuffer = '';

  bool _reconnectRunning    = false;
  bool _reconnectCancelled  = false;
  Completer<void>? _sleepCompleter;

  // ── Constructor ─────────────────────────────────────────────────────────────

  BleService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    savedDeviceId   = prefs.getString(_kPrefDeviceId);
    savedDeviceName = prefs.getString(_kPrefDeviceName);
    if (savedDeviceId != null) {
      reconnectAttempt = 0;
      connectionState  = BleConnectionState.reconnecting;
      statusMessage    = 'Connecting to $savedDeviceName…';
      notifyListeners();
      unawaited(_startAutoReconnect());
    }
  }

  // ── Persist / forget ────────────────────────────────────────────────────────

  Future<void> _persistDevice(BluetoothDevice device) async {
    final name  = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.str;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefDeviceId,   device.remoteId.str);
    await prefs.setString(_kPrefDeviceName, name);
    savedDeviceId   = device.remoteId.str;
    savedDeviceName = name;
  }

  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefDeviceId);
    await prefs.remove(_kPrefDeviceName);
    savedDeviceId   = null;
    savedDeviceName = null;
    _cancelReconnect();
    await _hardDisconnect();
    connectionState = BleConnectionState.idle;
    statusMessage   = null;
    notifyListeners();
  }

  // ── Scan ────────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (connectionState == BleConnectionState.scanning) return;
    _cancelReconnect();
    scanResults     = [];
    connectionState = BleConnectionState.scanning;
    statusMessage   = null;
    notifyListeners();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;
      notifyListeners();
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));

    if (connectionState == BleConnectionState.scanning) {
      connectionState = BleConnectionState.idle;
      statusMessage   = scanResults.isEmpty ? 'No devices found' : null;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (connectionState == BleConnectionState.scanning) {
      connectionState = BleConnectionState.idle;
      notifyListeners();
    }
  }

  // ── Manual connect (from scan list) ─────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    _cancelReconnect();
    await FlutterBluePlus.stopScan();
    connectionState = BleConnectionState.connecting;
    statusMessage   = 'Connecting…';
    notifyListeners();

    final ok = await _doConnect(device);
    if (!ok && connectionState != BleConnectionState.connected) {
      connectionState = BleConnectionState.idle;
      statusMessage   = 'Connection failed — try again';
      notifyListeners();
    }
  }

  // ── User-initiated disconnect ────────────────────────────────────────────────
  // Keeps the saved device so auto-reconnect works next time the page opens,
  // but does NOT trigger reconnect right now (user chose to disconnect).

  Future<void> disconnect() async {
    _cancelReconnect();
    await _hardDisconnect();
    connectionState = BleConnectionState.idle;
    statusMessage   = savedDeviceId != null ? 'Disconnected — saved device remembered' : null;
    notifyListeners();
  }

  // ── Core connect logic ───────────────────────────────────────────────────────

  Future<bool> _doConnect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      return false;
    }

    connectedDevice = device;
    statusMessage   = 'Discovering services…';
    notifyListeners();

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _onLinkLost();
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
              await _dataSub?.cancel();
              _dataSub = char.onValueReceived.listen(_onRawData);
            } else if (uuid == _kNusRx) {
              _rxChar = char;
            }
          }
        }
      }
    } catch (e) {
      statusMessage = 'Service discovery failed: $e';
      notifyListeners();
      return false;
    }

    if (_rxChar == null || _txChar == null) {
      statusMessage = 'NUS service not found — is this a SafeReps device?';
      notifyListeners();
      return false;
    }

    // Success: persist and surface the connected state.
    await _persistDevice(device);
    connectionState  = BleConnectionState.connected;
    reconnectAttempt = 0;
    statusMessage    = 'Connected — tap DATA ON to stream';
    notifyListeners();
    return true;
  }

  // ── Link-loss handler → triggers auto-reconnect ──────────────────────────────

  void _onLinkLost() {
    _rxChar    = null;
    _txChar    = null;
    _dataSub?.cancel();
    _dataSub   = null;
    isStreaming    = false;
    isCalibrating  = false;
    latestData     = null;
    connectedDevice = null;

    if (savedDeviceId != null) {
      statusMessage = 'Link lost — reconnecting…';
      unawaited(_startAutoReconnect());
    } else {
      connectionState = BleConnectionState.idle;
      statusMessage   = 'Disconnected';
    }
    notifyListeners();
  }

  // ── Auto-reconnect loop ──────────────────────────────────────────────────────

  Future<void> _startAutoReconnect() async {
    if (_reconnectRunning) return;
    _reconnectRunning   = true;
    _reconnectCancelled = false;

    int attempt = 0;
    while (!_reconnectCancelled && savedDeviceId != null) {
      reconnectAttempt = attempt + 1;
      connectionState  = BleConnectionState.reconnecting;
      final delaySecs  = _kReconnectDelays[attempt.clamp(0, _kReconnectDelays.length - 1)];
      statusMessage    = 'Reconnecting to $savedDeviceName… (attempt $reconnectAttempt, retry in ${delaySecs}s)';
      notifyListeners();

      await _cancellableSleep(Duration(seconds: delaySecs));
      if (_reconnectCancelled) break;

      statusMessage = 'Reconnecting to $savedDeviceName… (attempt $reconnectAttempt)';
      notifyListeners();

      final device = BluetoothDevice(remoteId: DeviceIdentifier(savedDeviceId!));
      final ok = await _doConnect(device);
      if (ok) break; // connected — exit loop

      attempt++;
    }

    _reconnectRunning = false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _cancelReconnect() {
    _reconnectCancelled = true;
    _sleepCompleter?.complete();
    _sleepCompleter = null;
  }

  Future<void> _cancellableSleep(Duration d) {
    final c = Completer<void>();
    _sleepCompleter = c;
    Future.delayed(d).then((_) { if (!c.isCompleted) c.complete(); });
    return c.future;
  }

  Future<void> _hardDisconnect() async {
    await _dataSub?.cancel();
    _dataSub = null;
    try { await connectedDevice?.disconnect(); } catch (_) {}
    connectedDevice = null;
    _rxChar    = null;
    _txChar    = null;
    isStreaming = false;
    latestData  = null;
  }

  // ── Incoming data ────────────────────────────────────────────────────────────

  void _onRawData(List<int> bytes) {
    _lineBuffer += String.fromCharCodes(bytes);
    while (_lineBuffer.contains('\n')) {
      final idx  = _lineBuffer.indexOf('\n');
      final line = _lineBuffer.substring(0, idx).trim();
      _lineBuffer = _lineBuffer.substring(idx + 1);
      if (line.startsWith('{')) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          if (json.containsKey('yaw')) {
            latestData = ImuData.fromJson(json);
          } else if (json.containsKey('status')) {
            final s = json['status'] as String? ?? '';
            statusMessage = s;
            if (s.startsWith('Calibrating')) {
              isCalibrating = true;
            } else if (s.startsWith('Calibration complete')) {
              isCalibrating = false;
            }
          }
          notifyListeners();
        } catch (_) {}
      }
    }
  }

  // ── Commands ─────────────────────────────────────────────────────────────────

  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null) return;
    try {
      await _rxChar!.write(utf8.encode('$cmd\n'), withoutResponse: true);
    } catch (_) {}
  }

  Future<void> toggleStream() async {
    isStreaming = !isStreaming;
    notifyListeners();
    await sendCommand(isStreaming ? 'DATA_ON' : 'DATA_OFF');
  }

  Future<void> zero() => sendCommand('ZERO');

  Future<void> resetCalibration() => sendCommand('RESET_CAL');

  Future<void> setTremorHp(double alpha) =>
      sendCommand('TREMOR_HP ${alpha.toStringAsFixed(3)}');

  Future<void> setTremorEma(double alpha) =>
      sendCommand('TREMOR_EMA ${alpha.toStringAsFixed(3)}');

  Future<void> setCheatEps(double eps) =>
      sendCommand('CHEAT_EPS ${eps.toStringAsFixed(3)}');

  Future<void> setCheatEma(double alpha) =>
      sendCommand('CHEAT_EMA ${alpha.toStringAsFixed(3)}');

  Future<void> calibrate() async {
    isCalibrating = true;
    statusMessage = 'Calibrating… keep device still';
    notifyListeners();
    await sendCommand('CALIBRATE');
    // Safety net: if "Calibration complete" never arrives (e.g. BLE drop),
    // clear the spinner after 30 s so the UI doesn't get stuck.
    Future.delayed(const Duration(seconds: 30), () {
      if (isCalibrating) {
        isCalibrating = false;
        statusMessage = 'Calibration timed out';
        notifyListeners();
      }
    });
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelReconnect();
    _scanSub?.cancel();
    _dataSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

// ignore: prefer_void_to_null
void unawaited(Future<void> future) {}

// ─── BleScope ─────────────────────────────────────────────────────────────────

class BleScope extends InheritedNotifier<BleService> {
  const BleScope({super.key, required BleService ble, required super.child})
      : super(notifier: ble);

  static BleService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BleScope>()!.notifier!;
}
