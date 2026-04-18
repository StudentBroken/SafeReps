# SafeReps

Cross-platform fitness app that uses on-device pose estimation to coach exercise form, fused with IMU data streamed over BLE from a wearable ESP32-C3 + MPU6050 module.

## Repo layout

- `safereps/` — Flutter app (iOS, Android primary; macOS/web/desktop best-effort).
  - `lib/main.dart` — entry point; initializes `availableCameras()`, applies `AppTheme.light`, mounts `MainShell`.
  - `lib/shell.dart` — `MainShell` widget: floating pill `BottomNavigationBar` (Dashboard · Goals · Settings). Exports `kNavPillClearance` for pages that need bottom padding.
  - `lib/theme.dart` — `AppColors` constants + `AppTheme.light` `ThemeData`. **All color/style decisions live here.**
  - `lib/widgets/glass_card.dart` — `GlassCard`: reusable `BackdropFilter` + frosted-glass container.
  - `lib/pages/dashboard_page.dart` — Dashboard tab.
  - `lib/pages/goals_page.dart` — Goals tab.
  - `lib/pages/settings_page.dart` — Settings tab; "Debug View" → `PoseCameraPage`, "BLE Debug" → `BleDebugPage`.
  - `lib/pages/ble_debug_page.dart` — BLE device scanner, connection UI, live IMU data display, tremor meter.
  - `lib/services/ble_service.dart` — `BleService` ChangeNotifier: scan, connect, persist device, auto-reconnect, parse IMU JSON, send commands.
  - `lib/pose_camera_page.dart` — camera lifecycle, permission gate, ML Kit stream loop, exercise rep counter bottom panel.
  - `lib/pose_painter.dart` — `CustomPainter` skeleton overlay.
  - `lib/pose/` — pose estimation abstraction (ML Kit, smoother, skeleton model).
  - `lib/analysis/` — `Exercise`, `RepCounter`, `JointAngles`.
- `safereps-esp/` — PlatformIO project for ESP32-C3. Reads MPU6050 IMU via I2C, DMP + EMA filtering, streams JSON over BLE (Nordic UART Service). Includes a Web Serial `visualizer.html` for desktop testing.

## UI design system

**Theme**: matte warm-beige background (`#F5ECE3`), pastel-pink interactive elements (`#F2AFC4`), hot-pink accent for progress/active states (`#D6176E`), frosted glass cards (`GlassCard`) throughout. Light mode only.

**Color tokens** (all in `AppColors`):
| Token | Hex | Usage |
|---|---|---|
| `background` | `#F5ECE3` | Scaffold background |
| `surface` | `#FFF0F5` | Card/sheet backgrounds |
| `pink` | `#F2AFC4` | Buttons, inactive tiles |
| `pinkBright` | `#D6176E` | Progress ring, active states |
| `beige` | `#CBAD9A` | Unselected nav, dividers |
| `textDark` | `#3D2B1F` | Primary text |
| `textMid` | `#7A5A4A` | Secondary text |
| `textLight` | `#B89A8A` | Placeholder / labels |

**GlassCard**: `BackdropFilter(blur=18) + 0x55FFFFFF fill + 0x70FFFFFF border`. Use for all cards, modals, bottom sheets.

## Navigation

`MainShell` (`lib/shell.dart`) owns the tab state. Three tabs:
1. **Dashboard** — daily progress overview + Start button
2. **Goals** — per-exercise targets, session config
3. **Settings** — developer tools (Debug View → `PoseCameraPage`, BLE Debug → `BleDebugPage`)

## Exercise model

Defined declaratively in `lib/analysis/exercise.dart`. Active exercises: **Lateral Raise** (shoulder angle, top=25°/bottom=80°) and **Bicep Curl** (elbow angle, top=155°/bottom=25°). `RepCounter` state machine in `lib/analysis/rep_counter.dart` drives the bottom panel in the debug view.

## BLE / IMU system

### Flutter (`BleService`)
- **Package**: `flutter_blue_plus ^1.35.0`
- **Transport**: Nordic UART Service (NUS) — service `6E400001-…`, RX `6E400002-…`, TX `6E400003-…`
- **Persistence**: last connected device ID + name saved to `SharedPreferences`; auto-reconnect on launch and on link loss with exponential backoff `[2, 4, 8, 16, 30]` s
- **State machine**: `BleConnectionState` enum — `idle / scanning / connecting / reconnecting / connected`
- **Commands sent** (phone → ESP32 via RX): `DATA_ON`, `DATA_OFF`, `ZERO`, `CALIBRATE`, `RESET_CAL`, `DAMPING <α>`
- **ImuData fields**: `yaw, pitch, roll` (°), `ax, ay, az` (g, gravity-compensated), `gx, gy, gz` (°/s), `tremor` (g, onboard HP-filtered), `batt` (V)

### ESP32 firmware (`safereps-esp/src/main.cpp`)
- **Libs**: `electroniccats/MPU6050`, `h2zero/NimBLE-Arduino ^1.4.2`, `Preferences` (built-in NVS)
- **Orientation**: DMP quaternion → `dmpGetYawPitchRoll`; EMA smoothed with wraparound-safe `emaAngle()` (fixes ±180° jump artefacts)
- **Calibration**: NVS-persistent via `Preferences` (`"imu-cal"` namespace); loaded on boot (skips auto-cal); re-run with `CALIBRATE` command (deferred to Arduino task, DMP disabled during run to avoid register conflict); cleared with `RESET_CAL`
- **Linear accel**: `getMotion6()` at 100 Hz → subtract DMP gravity unit-vector → gravity-free accel in g (avoids `dmpGetLinearAccel` 8192/16384 scale bug)
- **Tremor detection** (100 Hz onboard):
  - 1st-order HP filter, f_c ≈ 5 Hz, α = 0.761 → isolates jitter above exercise-rep frequency
  - L2 magnitude → slow EMA (α = 0.08, τ ≈ 125 ms) → `tremorScore` in g
  - Thresholds: < 0.02 g = none, 0.02–0.06 g = mild, 0.06–0.12 g = moderate, > 0.12 g = high
- **BLE send rate**: 10 Hz; supervision timeout 10 s (requested on connect via `updateConnParams`)
- **Battery**: ADC GPIO1, 100k/100k divider, ×0.90389 correction factor, sampled every 5 s

### BLE debug page features
- Scan list with RSSI + "Saved" badge for remembered device
- Saved device quick-connect card with Forget button
- Reconnecting panel with attempt counter, Cancel, Forget Device
- Control buttons: DATA ON/OFF, ZERO, CALIBRATE (shows spinner + "keep still" banner while running), RESET CAL
- Live data: Yaw/Pitch/Roll cards, Accel X/Y/Z (g), Gyro X/Y/Z (°/s), Tremor meter (bar + label), Battery (icon + voltage + label)

## Common dev commands

Flutter app (run from `safereps/`):

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <ios|android device id>     # full pose detection
flutter run -d macos                        # camera only, no pose detection yet
flutter clean && flutter pub get            # when native plugins act up
```

ESP32 firmware (run from `safereps-esp/`):

```bash
pio run                                     # build
pio run -t upload                           # flash
pio device monitor                          # serial monitor
# Visualizer: Open safereps-esp/visualizer.html in Chrome/Edge
```

## Roadmap

### Phase 0 — Pose visualizer
- [x] Camera preview + ML Kit pose detection on iOS/Android
- [x] Skeleton overlay (torso, arms, legs colored differently)
- [x] Camera permission flow + camera switcher
- [x] FPS / latency HUD
- [x] Rep counter bottom panel (Lateral Raise + Bicep Curl) with circular progress

### Phase 1 — App shell & UI (current)
- [x] Pink/beige liquid-glass theme (`AppTheme`, `AppColors`, `GlassCard`)
- [x] 3-tab navigation shell (Dashboard · Goals · Settings)
- [x] Debug View moved to Settings
- [ ] Dashboard: circular total progress, bar chart, pill progress bars, safety cards, Start button
- [ ] Goals: session pill, expandable per-exercise cards (reps/sets/rest)
- [ ] Start flow: session preview → 5 s countdown → "Get ready" slide → camera

### Phase 2 — ESP32 + IMU integration
- [x] ESP32-C3 firmware: MPU6050 over I2C, DMP/EMA filtering
- [x] BLE GATT service (Nordic UART Service via NimBLE-Arduino)
- [x] Flutter BLE client (`flutter_blue_plus`) — scan, connect, subscribe, auto-reconnect, persist device
- [x] Full IMU JSON stream: yaw/pitch/roll, linear accel, gyro, tremor score, battery
- [x] NVS-persistent calibration (load on boot, save after CALIBRATE, clear with RESET_CAL)
- [x] Onboard tremor detection (100 Hz HP filter + EMA, reported at 10 Hz)
- [x] BLE debug page with live data visualization
- [ ] Sensor fusion: align IMU limb vector with pose landmark
- [ ] Calibration flow (T-pose)

### Phase 3 — Workout UX
- [ ] Session history persistence (sqflite or drift)
- [ ] Post-set form summary with key issues + replay
- [ ] Tremor trend over session (fatigue tracking)

### Phase 4 — Polish
- [ ] Onboarding + permission re-prompts
- [ ] iOS TestFlight + Android internal testing builds

## Common objectives (recurring guidance)

- **Add a new exercise**: define in `lib/analysis/exercise.dart` (declarative — no per-exercise if-chains elsewhere). Calibrate `topThreshold` / `bottomThreshold` from real measured angles using the Debug Copy button.
- **Keep `PosePainter` framework-agnostic**: no ML Kit imports — use the internal `Skeleton` model.
- **Don't regress the camera lifecycle**: on Android always `stopImageStream()` before `dispose()`, null the controller before awaiting, handle `inactive`/`paused`. Hot-restart (not reload) when native handles misbehave.
- **Debug Copy Format**: `pose_angles: lk:175,rk:?,... deg` — `lk/rk=knee`, `lh/rh=hip`, `le/re=elbow`, `ls/rs=shoulder`. `?` = low confidence (< 0.1).
- **Theme changes**: always update `AppColors`/`AppTheme` in `lib/theme.dart` — never hardcode colors inline.
- **BLE commands**: always run calibration deferred (flag in `loop()`, not in BLE RX callback) to avoid blocking NimBLE's task. Disable DMP before `CalibrateAccel/Gyro`, re-enable + `resetFIFO` after.
- **Linear accel scale**: use `getMotion6()` / 16384 − gravity vector. Do NOT use `dmpGetLinearAccel` — it hardcodes 8192 (±4 g scale) causing a 2× error on the Z axis.
- **Tremor thresholds**: < 0.02 g none, 0.02–0.06 g mild, 0.06–0.12 g moderate, > 0.12 g high. Full bar = 0.3 g in `_TremorCard`.

