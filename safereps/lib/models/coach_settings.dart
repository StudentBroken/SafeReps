import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Keys ──────────────────────────────────────────────────────────────────────
const _kFrequency   = 'coach.frequency';
const _kPositive    = 'coach.positive';
const _kCriticism   = 'coach.criticism';
const _kStrictness  = 'coach.strictness';
const _kVolume      = 'coach.volume';
const _kCaptions    = 'coach.captions';
const _kCaptionSize = 'coach.captionSize';

/// Holds every user-preference dial for the voice coach.
/// Consumed by [VoiceCoachService] and displayed on [SettingsPage].
class CoachSettings extends ChangeNotifier {
  CoachSettings._({
    required double frequency,
    required double positive,
    required double criticism,
    required double strictness,
    required double volume,
    required bool captions,
    required double captionSize,
  })  : _frequency   = frequency,
        _positive    = positive,
        _criticism   = criticism,
        _strictness  = strictness,
        _volume      = volume,
        _captions    = captions,
        _captionSize = captionSize;

  // ── Defaults ──────────────────────────────────────────────────────────────
  factory CoachSettings.defaults() => CoachSettings._(
        frequency:   0.85,
        positive:    0.6,
        criticism:   0.9,
        strictness:  0.5,
        volume:      0.85,
        captions:    true,
        captionSize: 14.0,
      );

  // ── Factory: load from SharedPreferences ─────────────────────────────────
  static Future<CoachSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return CoachSettings._(
      frequency:   p.getDouble(_kFrequency)   ?? 0.85,
      positive:    p.getDouble(_kPositive)    ?? 0.6,
      criticism:   p.getDouble(_kCriticism)   ?? 0.9,
      strictness:  p.getDouble(_kStrictness)  ?? 0.5,
      volume:      p.getDouble(_kVolume)      ?? 0.85,
      captions:    p.getBool  (_kCaptions)    ?? true,
      captionSize: p.getDouble(_kCaptionSize) ?? 14.0,
    );
  }

  // ── Internal state ────────────────────────────────────────────────────────
  double _frequency;
  double _positive;
  double _criticism;
  double _strictness;
  double _volume;
  bool   _captions;
  double _captionSize;

  // ── Getters ───────────────────────────────────────────────────────────────
  double get frequency   => _frequency;
  double get positive    => _positive;
  double get criticism   => _criticism;
  double get strictness  => _strictness;
  double get volume      => _volume;
  bool   get captions    => _captions;
  double get captionSize => _captionSize;

  // ── Setters (persist immediately) ────────────────────────────────────────
  void setFrequency(double v)    => _set(() => _frequency   = v.clamp(0, 1));
  void setPositive(double v)     => _set(() => _positive    = v.clamp(0, 1));
  void setCriticism(double v)    => _set(() => _criticism   = v.clamp(0, 1));
  void setStrictness(double v)   => _set(() => _strictness  = v.clamp(0, 1));
  void setVolume(double v)       => _set(() => _volume      = v.clamp(0, 1));
  void setCaptions(bool v)       => _set(() => _captions    = v);
  void setCaptionSize(double v)  => _set(() => _captionSize = v.clamp(10, 26));

  void _set(VoidCallback mutate) {
    mutate();
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFrequency,   _frequency);
    await p.setDouble(_kPositive,    _positive);
    await p.setDouble(_kCriticism,   _criticism);
    await p.setDouble(_kStrictness,  _strictness);
    await p.setDouble(_kVolume,      _volume);
    await p.setBool  (_kCaptions,    _captions);
    await p.setDouble(_kCaptionSize, _captionSize);
  }
}

// ── InheritedWidget scope ─────────────────────────────────────────────────────
class CoachSettingsScope extends InheritedNotifier<CoachSettings> {
  const CoachSettingsScope({
    super.key,
    required CoachSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static CoachSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CoachSettingsScope>();
    assert(scope != null, 'CoachSettingsScope not found in widget tree');
    return scope!.notifier!;
  }
}
