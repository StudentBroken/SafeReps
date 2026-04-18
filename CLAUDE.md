# SafeReps

Cross-platform fitness app that uses on-device pose estimation to coach exercise form, fused with IMU data streamed over BLE from a wearable ESP32-C3 + MPU6050 module.

## Repo layout

- `safereps/` — Flutter app (iOS, Android primary; macOS/web/desktop best-effort).
  - `lib/main.dart` — entry point; initializes `availableCameras()`, applies `AppTheme.light`, mounts `MainShell`.
  - `lib/shell.dart` — `MainShell` widget: 3-tab `BottomNavigationBar` (Dashboard · Goals · Settings).
  - `lib/theme.dart` — `AppColors` constants + `AppTheme.light` `ThemeData`. **All color/style decisions live here.**
  - `lib/widgets/glass_card.dart` — `GlassCard`: reusable `BackdropFilter` + frosted-glass container.
  - `lib/pages/dashboard_page.dart` — Dashboard tab (Step 2).
  - `lib/pages/goals_page.dart` — Goals tab (Step 3).
  - `lib/pages/settings_page.dart` — Settings tab; "Debug View" entry opens `PoseCameraPage`.
  - `lib/pose_camera_page.dart` — camera lifecycle, permission gate, ML Kit stream loop, exercise rep counter bottom panel.
  - `lib/pose_painter.dart` — `CustomPainter` skeleton overlay.
  - `lib/pose/` — pose estimation abstraction (ML Kit, smoother, skeleton model).
  - `lib/analysis/` — `Exercise`, `RepCounter`, `JointAngles`.
- `safereps-esp/` — PlatformIO project for ESP32-C3. Reads MPU6050 IMU via I2C, DMP/EMA filtering, streams JSON over Serial. Includes a Web Serial `visualizer.html` for desktop testing.

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
3. **Settings** — developer tools (Debug View → `PoseCameraPage`)

## Exercise model

Defined declaratively in `lib/analysis/exercise.dart`. Active exercises: **Lateral Raise** (shoulder angle, top=25°/bottom=80°) and **Bicep Curl** (elbow angle, top=155°/bottom=25°). `RepCounter` state machine in `lib/analysis/rep_counter.dart` drives the bottom panel in the debug view.

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
- [x] Serial JSON: `{"yaw":0.0,"pitch":0.0,"roll":0.0}` stream
- [x] Web Serial visualizer
- [ ] BLE GATT service (Nordic UART or custom)
- [ ] Flutter BLE client (`flutter_blue_plus`) — scan, connect, subscribe, reconnect
- [ ] Sensor fusion: align IMU limb vector with pose landmark
- [ ] Calibration flow (T-pose)

### Phase 3 — Workout UX
- [ ] Session history persistence (sqflite or drift)
- [ ] Post-set form summary with key issues + replay

### Phase 4 — Polish
- [ ] Onboarding + permission re-prompts
- [ ] iOS TestFlight + Android internal testing builds

## Common objectives (recurring guidance)

- **Add a new exercise**: define in `lib/analysis/exercise.dart` (declarative — no per-exercise if-chains elsewhere). Calibrate `topThreshold` / `bottomThreshold` from real measured angles using the Debug Copy button.
- **Keep `PosePainter` framework-agnostic**: no ML Kit imports — use the internal `Skeleton` model.
- **Don't regress the camera lifecycle**: on Android always `stopImageStream()` before `dispose()`, null the controller before awaiting, handle `inactive`/`paused`. Hot-restart (not reload) when native handles misbehave.
- **Debug Copy Format**: `pose_angles: lk:175,rk:?,... deg` — `lk/rk=knee`, `lh/rh=hip`, `le/re=elbow`, `ls/rs=shoulder`. `?` = low confidence (< 0.1).
- **Theme changes**: always update `AppColors`/`AppTheme` in `lib/theme.dart` — never hardcode colors inline.
