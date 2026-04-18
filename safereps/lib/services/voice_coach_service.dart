import 'dart:async';
import 'dart:math' show Random;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/coach_settings.dart';

// ── Audio trigger categories ──────────────────────────────────────────────────
//
// Each CueCategory maps to a pool of asset paths.  The service maintains
// separate "remaining" + "used" pools per category so every track is heard
// once before anything repeats (Fisher-Yates exhaustion shuffle).

enum CueCategory {
  // Generic ─────────────────────────────────────────────────
  start,
  finishCongrats,
  genericPositive,
  genericFormCorrection,

  // Bicep Curls – corrections ───────────────────────────────
  bicepBackBody,        // lock core, no swinging back
  bicepElbows,          // keep elbows pinned
  bicepRomBottom,       // full extension at bottom
  bicepRomTop,          // all the way to shoulder
  bicepShoulderWrist,   // shoulder / wrist alignment
  bicepLastRepsMotiv,   // end-of-set push
  bicepPositive,        // good rep praise
  bicepTempo,           // pace cues

  // Lateral Raises – corrections ────────────────────────────
  lateralBodySwing,     // stop rocking / no body throw
  lateralElbowWrist,    // elbow lead / wrist alignment
  lateralRom,           // range of motion (height)
  lateralShoulderTrap,  // no shrugging
  lateralPositivePerfect, // perfect rep praise
  lateralPositiveStruggle, // push through struggle
  lateralTempo,         // control the drop / hold at top
}

// ── Exact file manifest ───────────────────────────────────────────────────────
//
// Paths are relative to the Flutter asset root (matching pubspec.yaml).
// Filenames verified against physical files on disk — exact match required.

const _assets = <CueCategory, List<String>>{

  // ── GENERIC: Start ────────────────────────────────────────────────────────
  CueCategory.start: [
    'assets/Generic Audio/Start/ge ready.mp3',
    'assets/Generic Audio/Start/get to work and have an amazing session.mp3',
    'assets/Generic Audio/Start/im ready when you are take a deep breath you\'re going to do phenomenally today.mp3',
    'assets/Generic Audio/Start/you\'re here, ready and already looking strong lets get to work.mp3',
  ],

  // ── GENERIC: Finish / Congratulations ────────────────────────────────────
  CueCategory.finishCongrats: [
    'assets/Generic Audio/Finish congratulations/Done adn dusted you showed up pushed hard and got stronger pehnomenal effort.mp3',
    'assets/Generic Audio/Finish congratulations/final set is in the books you proved exactly how strong you are today outstanding work.mp3',
    'assets/Generic Audio/Finish congratulations/session complete, you gave it your all and it paid off.mp3',
    'assets/Generic Audio/Finish congratulations/set complete great work drop the weight and rest.mp3',
    'assets/Generic Audio/Finish congratulations/set complete great work.mp3',
    'assets/Generic Audio/Finish congratulations/That is how its done you crushed every single set amazing job.mp3',
    'assets/Generic Audio/Finish congratulations/Workout complete you put in the work today be incredibly proud of yourself.mp3',
  ],

  // ── GENERIC: Positive reinforcement ──────────────────────────────────────
  CueCategory.genericPositive: [
    'assets/Generic Audio/Generic Positive reinforcement/i see you working keep that intensity high its paying off.mp3',
    'assets/Generic Audio/Generic Positive reinforcement/thats it perfect execution absolute machine.mp3',
    'assets/Generic Audio/Generic Positive reinforcement/this is where the real progress happens you\'re doing incredible dont quit.mp3',
    'assets/Generic Audio/Generic Positive reinforcement/you are crushing this keep going you\'re unstoppable.mp3',
    'assets/Generic Audio/Generic Positive reinforcement/you\'re making it look easy lets go.mp3',
  ],

  // ── GENERIC: Form corrections (cross-exercise) ────────────────────────────
  CueCategory.genericFormCorrection: [
    'assets/Generic Audio/Generic form correction/amazing keep breathing keep oxygen there.mp3',
    'assets/Generic Audio/Generic form correction/beautiful form just control the tempo.mp3',
    'assets/Generic Audio/Generic form correction/excellent control, 3 seconds on the way down.mp3',
    'assets/Generic Audio/Generic form correction/great power, plant your feet flat to build an even stronger base.mp3',
    'assets/Generic Audio/Generic form correction/looking strong squeeze ur glutes to stabilize the body even more.mp3',
    'assets/Generic Audio/Generic form correction/love the energy remember to keep chest up shoulder back.mp3',
    'assets/Generic Audio/Generic form correction/perfect rythm right there lock into thta pace ur killing it.mp3',
    'assets/Generic Audio/Generic form correction/u got the strenght for this breath in and breath out on the way in n out.mp3',
    'assets/Generic Audio/Generic form correction/you have insane strenght, but if you have to cheat the movement drop the weight and blah blah blah.mp3',
    'assets/Generic Audio/Generic form correction/you\'re doing great keep spine completely neutral .mp3',
    'assets/Generic Audio/Generic form correction/You\'re doing great, form slipping, reset and get back to perfect.mp3',
    'assets/Generic Audio/Generic form correction/you\'re moving serious weight slow those muscles down .mp3',
  ],

  // ── BICEP CURLS ──────────────────────────────────────────────────────────

  CueCategory.bicepBackBody: [
    'assets/Audio Bicep Curls/Form correction (Back and body movement)/Lock your code keep your torso completely vertical.mp3',
    'assets/Audio Bicep Curls/Form correction (Back and body movement)/Use muscle not momentum use your body keep stable.mp3',
    'assets/Audio Bicep Curls/Form correction (Back and body movement)/Watch the swinging use your biceps not your back.mp3',
    'assets/Audio Bicep Curls/Form correction (Back and body movement)/You\'re leaning back to get it up lighten the weight if you need t.mp3',
  ],

  CueCategory.bicepElbows: [
    'assets/Audio Bicep Curls/Form correction (Elbows)/Bend elbows to wrist, dont drift forwards.mp3',
    'assets/Audio Bicep Curls/Form correction (Elbows)/Elbow creeping up, lock them in place.mp3',
    'assets/Audio Bicep Curls/Form correction (Elbows)/upper arm completely still, only form arm should move.mp3',
  ],

  CueCategory.bicepRomBottom: [
    'assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Full extension on the way down dont cheat yourself.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Go all the way down, full stretch at the bottom.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Uncurl all the way, let the arms hang before next rep.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/You\'re cutting it short, straighten the arm completely .mp3',
  ],

  CueCategory.bicepRomTop: [
    'assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Bring it all the way up and squeeze.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Close that gap at the top, hard squeeze.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Don\'t stop halfway, curl it up to the shoulder.mp3',
    'assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Get that full contraction at the top of the rep.mp3',
  ],

  CueCategory.bicepShoulderWrist: [
    'assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Keep your wrists neutral dont let them curl inwards at the top.mp3',
    'assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Keep your shoulders down and relax dont shrug the weight.mp3',
    'assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Relax your neck and shoulders let the biceps do the work.mp3',
  ],

  CueCategory.bicepLastRepsMotiv: [
    'assets/Audio Bicep Curls/Last reps Motivation/Dont drop that weight you have one more in there.mp3',
    'assets/Audio Bicep Curls/Last reps Motivation/Fight for it squeeze it up there.mp3',
    'assets/Audio Bicep Curls/Last reps Motivation/Halfway there, maintain that strict form.mp3',
  ],

  CueCategory.bicepPositive: [
    'assets/Audio Bicep Curls/Positive stuff/Absolute machine right now lets finish strong.mp3',
    'assets/Audio Bicep Curls/Positive stuff/Beautiful control you are locked in right now.mp3',
    'assets/Audio Bicep Curls/Positive stuff/Spot on you\'re making that weight look easy.mp3',
    'assets/Audio Bicep Curls/Positive stuff/Textbook form, keep that exact same groove.mp3',
    'assets/Audio Bicep Curls/Positive stuff/You got this keep breathing keep moving.mp3',
  ],

  CueCategory.bicepTempo: [
    'assets/Audio Bicep Curls/Tempo/Dont just let it fall, resist the negative.mp3',
    'assets/Audio Bicep Curls/Tempo/Fight gravity on the way down take 3 full seconds.mp3',
    'assets/Audio Bicep Curls/Tempo/Perfect pace, keep this exact same rythm.mp3',
    'assets/Audio Bicep Curls/Tempo/Too fast on the drop control that weight.mp3',
  ],

  // ── LATERAL RAISES ───────────────────────────────────────────────────────

  CueCategory.lateralBodySwing: [
    'assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/if you have to throw your back into it its too heavy.mp3',
    'assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/lock your core no swinigng the weight up.mp3',
    'assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/plant your feet and stay totaly rigid.mp3',
    'assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/stop rocking, keep your torso completely still.mp3',
  ],

  CueCategory.lateralElbowWrist: [
    'assets/Lateral raises Audio/Form correction (Elbows and Wrists)/imagine pouring water out at the top of the movement like pitcher.mp3',
    'assets/Lateral raises Audio/Form correction (Elbows and Wrists)/keep a soft bend in your elbows dont lock your arms.mp3',
    'assets/Lateral raises Audio/Form correction (Elbows and Wrists)/keep elbow perfectly in front of your body not to the side.mp3',
    'assets/Lateral raises Audio/Form correction (Elbows and Wrists)/lead with elbow no wrist.mp3',
  ],

  CueCategory.lateralRom: [
    'assets/Lateral raises Audio/Form correction (Range of Motion)/bring them up until your arms are parallel to the floor.mp3',
    'assets/Lateral raises Audio/Form correction (Range of Motion)/control the thing dont let the dumbell slam against your leg.mp3',
    'assets/Lateral raises Audio/Form correction (Range of Motion)/keep constant tension don\'t rest the weights on your hips at the bottom.mp3',
    'assets/Lateral raises Audio/Form correction (Range of Motion)/stop at shoulder height no need to go any higher.mp3',
    'assets/Lateral raises Audio/Form correction (Range of Motion)/you\'re stopping short get those dumbless up to shoulder level.mp3',
  ],

  CueCategory.lateralShoulderTrap: [
    'assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Keep your shoulders pressed down dont shrug the weight.mp3',
    'assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Push shoulder down into back pocket.mp3',
    'assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Relax your neck let your side of shoulders do work.mp3',
    'assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Your traps are dropping down, let your shoulders do work.mp3',
  ],

  CueCategory.lateralPositivePerfect: [
    'assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/perfect form your shoulders are completely isolated.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/smooth and controlled exactly what i wnat to see.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/thats a beautiful rep do it again.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/you are doing great, great mind-muscle connection.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/your shoulders are on fire lets finish this set.mp3',
  ],

  CueCategory.lateralPositiveStruggle: [
    'assets/Lateral raises Audio/Positive reinforcement (Struggle)/almost there dont let your form slip now.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Struggle)/Don\'t drop the weight yet you have more in you.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Struggle)/dont drop your arms yet you have more in you.mp3',
    'assets/Lateral raises Audio/Positive reinforcement (Struggle)/Keep fighting for height keep fighting for height.mp3',
  ],

  CueCategory.lateralTempo: [
    'assets/Lateral raises Audio/Tempo/control the drop fight gravity all the way down.mp3',
    'assets/Lateral raises Audio/Tempo/dont just let your arms drop resist the fall.mp3',
    'assets/Lateral raises Audio/Tempo/hold it at the top for a split second.mp3',
    'assets/Lateral raises Audio/Tempo/perfect pace right there dont speed up.mp3',
  ],
};

// ── Caption maps ──────────────────────────────────────────────────────────────
//
// Maps filename stem → short, punchy display text shown on-screen.
// Stems are the filename without the .mp3 extension.

const Map<String, String> _captions = {
  // Generic start
  'ge ready':
      'Get ready!',
  'get to work and have an amazing session':
      'Let\'s work!',
  'im ready when you are take a deep breath you\'re going to do phenomenally today':
      'Breathe & focus.',
  'you\'re here, ready and already looking strong lets get to work':
      'Ready to go!',

  // Generic finish
  'Done adn dusted you showed up pushed hard and got stronger pehnomenal effort':
      'Phenomenal effort!',
  'final set is in the books you proved exactly how strong you are today outstanding work':
      'Final set done!',
  'session complete, you gave it your all and it paid off':
      'Session complete!',
  'set complete great work drop the weight and rest':
      'Set done — rest!',
  'set complete great work':
      'Set complete!',
  'That is how its done you crushed every single set amazing job':
      'Crushed it!',
  'Workout complete you put in the work today be incredibly proud of yourself':
      'Workout complete!',

  // Generic positive
  'i see you working keep that intensity high its paying off':
      'Keep the intensity!',
  'thats it perfect execution absolute machine':
      'Perfect!',
  'this is where the real progress happens you\'re doing incredible dont quit':
      'Don\'t quit!',
  'you are crushing this keep going you\'re unstoppable':
      'Unstoppable!',
  'you\'re making it look easy lets go':
      'Let\'s go!',

  // Generic form correction
  'amazing keep breathing keep oxygen there':
      'Keep breathing.',
  'beautiful form just control the tempo':
      'Control tempo.',
  'excellent control, 3 seconds on the way down':
      '3s down.',
  'great power, plant your feet flat to build an even stronger base':
      'Feet flat.',
  'looking strong squeeze ur glutes to stabilize the body even more':
      'Squeeze glutes.',
  'love the energy remember to keep chest up shoulder back':
      'Chest up.',
  'perfect rythm right there lock into thta pace ur killing it':
      'Lock that rhythm.',
  'u got the strenght for this breath in and breath out on the way in n out':
      'Breathe.',
  'you have insane strenght, but if you have to cheat the movement drop the weight and blah blah blah':
      'Drop the weight.',
  'you\'re doing great keep spine completely neutral ':
      'Neutral spine.',
  'You\'re doing great, form slipping, reset and get back to perfect':
      'Reset your form.',
  'you\'re moving serious weight slow those muscles down ':
      'Slow down.',

  // Bicep curls – back/body
  'Lock your code keep your torso completely vertical':
      'Torso vertical.',
  'Use muscle not momentum use your body keep stable':
      'Muscle not momentum.',
  'Watch the swinging use your biceps not your back':
      'Biceps only.',
  'You\'re leaning back to get it up lighten the weight if you need t':
      'Lighten the weight.',

  // Bicep – elbows
  'Bend elbows to wrist, dont drift forwards':
      'Don\'t drift forward.',
  'Elbow creeping up, lock them in place':
      'Lock the elbows.',
  'upper arm completely still, only form arm should move':
      'Still upper arm.',

  // Bicep – ROM bottom
  'Full extension on the way down dont cheat yourself':
      'Full extension.',
  'Go all the way down, full stretch at the bottom':
      'All the way down.',
  'Uncurl all the way, let the arms hang before next rep':
      'Let it hang.',
  'You\'re cutting it short, straighten the arm completely ':
      'Straighten fully.',

  // Bicep – ROM top
  'Bring it all the way up and squeeze':
      'Squeeze at top.',
  'Close that gap at the top, hard squeeze':
      'Hard squeeze.',
  'Don\'t stop halfway, curl it up to the shoulder':
      'Up to shoulder.',
  'Get that full contraction at the top of the rep':
      'Full contraction.',

  // Bicep – shoulder/wrist
  'Keep your wrists neutral dont let them curl inwards at the top':
      'Neutral wrists.',
  'Keep your shoulders down and relax dont shrug the weight':
      'Shoulders down.',
  'Relax your neck and shoulders let the biceps do the work':
      'Relax shoulders.',

  // Bicep – last reps
  'Dont drop that weight you have one more in there':
      'One more!',
  'Fight for it squeeze it up there':
      'Fight for it!',
  'Halfway there, maintain that strict form':
      'Halfway there.',

  // Bicep – positive
  'Absolute machine right now lets finish strong':
      'Finish strong!',
  'Beautiful control you are locked in right now':
      'Locked in!',
  'Spot on you\'re making that weight look easy':
      'Looking easy!',
  'Textbook form, keep that exact same groove':
      'Textbook form.',
  'You got this keep breathing keep moving':
      'Keep moving!',

  // Bicep – tempo
  'Dont just let it fall, resist the negative':
      'Resist the drop.',
  'Fight gravity on the way down take 3 full seconds':
      '3s negative.',
  'Perfect pace, keep this exact same rythm':
      'Stay steady.',
  'Too fast on the drop control that weight':
      'Slow down.',

  // Lateral – body swing
  'if you have to throw your back into it its too heavy':
      'Too heavy.',
  'lock your core no swinigng the weight up':
      'No swinging.',
  'plant your feet and stay totaly rigid':
      'Stay rigid.',
  'stop rocking, keep your torso completely still':
      'Still torso.',

  // Lateral – elbow/wrist
  'imagine pouring water out at the top of the movement like pitcher':
      'Pour the pitcher.',
  'keep a soft bend in your elbows dont lock your arms':
      'Soft elbows.',
  'keep elbow perfectly in front of your body not to the side':
      'Elbows forward.',
  'lead with elbow no wrist':
      'Elbow leads.',

  // Lateral – ROM
  'bring them up until your arms are parallel to the floor':
      'Arms parallel.',
  'control the thing dont let the dumbell slam against your leg':
      'Control the drop.',
  'keep constant tension don\'t rest the weights on your hips at the bottom':
      'Keep tension.',
  'stop at shoulder height no need to go any higher':
      'Shoulder height.',
  'you\'re stopping short get those dumbless up to shoulder level':
      'Get to shoulder.',

  // Lateral – shoulder/trap
  'Keep your shoulders pressed down dont shrug the weight':
      'Don\'t shrug.',
  'Push shoulder down into back pocket':
      'Shoulders back.',
  'Relax your neck let your side of shoulders do work':
      'Relax neck.',
  'Your traps are dropping down, let your shoulders do work':
      'Side delts only.',

  // Lateral – positive perfect
  'perfect form your shoulders are completely isolated':
      'Isolated!',
  'smooth and controlled exactly what i wnat to see':
      'Smooth & controlled.',
  'thats a beautiful rep do it again':
      'Beautiful rep!',
  'you are doing great, great mind-muscle connection':
      'Mind-muscle!',
  'your shoulders are on fire lets finish this set':
      'Shoulders on fire!',

  // Lateral – positive struggle
  'almost there dont let your form slip now':
      'Hold form!',
  'Don\'t drop the weight yet you have more in you':
      'Don\'t drop!',
  'dont drop your arms yet you have more in you':
      'Keep fighting!',
  'Keep fighting for height keep fighting for height':
      'Fight for height!',

  // Lateral – tempo
  'control the drop fight gravity all the way down':
      'Fight gravity.',
  'dont just let your arms drop resist the fall':
      'Resist the fall.',
  'hold it at the top for a split second':
      'Hold at top.',
  'perfect pace right there dont speed up':
      'Steady pace.',
};

// ── Priority levels ───────────────────────────────────────────────────────────
// Higher number wins. Corrections always beat positive reinforcement.
const Map<CueCategory, int> _priority = {
  CueCategory.start:                    1,
  CueCategory.finishCongrats:           1,

  CueCategory.genericPositive:          2,
  CueCategory.bicepPositive:            2,
  CueCategory.lateralPositivePerfect:   2,
  CueCategory.lateralPositiveStruggle:  2,
  CueCategory.bicepLastRepsMotiv:       2,

  CueCategory.genericFormCorrection:    3,
  CueCategory.bicepTempo:               3,
  CueCategory.lateralTempo:             3,
  CueCategory.bicepBackBody:            4,
  CueCategory.bicepElbows:              4,
  CueCategory.bicepRomBottom:           4,
  CueCategory.bicepRomTop:              4,
  CueCategory.bicepShoulderWrist:       4,
  CueCategory.lateralBodySwing:         4,
  CueCategory.lateralElbowWrist:        4,
  CueCategory.lateralRom:               4,
  CueCategory.lateralShoulderTrap:      4,
};

// ── Service ───────────────────────────────────────────────────────────────────

/// Manages the workout voice-coach audio engine.
///
/// • Uses a Fisher-Yates exhaustion shuffle per category so every track is
///   heard once before repeating.
/// • Respects [CoachSettings] for volume, frequency, and tone balance.
/// • Exposes [lastCaption] so the UI can display on-screen text.
class VoiceCoachService extends ChangeNotifier {
  VoiceCoachService(this._settings) {
    _player.onPlayerComplete.listen((_) {
      _currentPriority = 0;
    });
  }

  final CoachSettings _settings;
  final AudioPlayer _player = AudioPlayer();
  final _random = Random();
  Timer? _captionTimer;

  // Exhaustion pools: remaining tracks per category
  final Map<CueCategory, List<String>> _remaining = {
    for (final e in _assets.entries) e.key: List.of(e.value)..shuffle(),
  };

  // CurrentPriority — tracks what's "playing" so corrections can interrupt
  int _currentPriority = 0;

  /// The human-readable caption for the track currently/last played.
  String? lastCaption;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Play a cue from [category] subject to settings gates.
  ///
  /// [isMandatory] skips the frequency gate (e.g. session start/end).
  Future<void> play(CueCategory category, {bool isMandatory = false}) async {
    final priority = _priority[category] ?? 1;

    // Priority gate: only interrupt if new cue has higher priority
    if (priority < _currentPriority) return;

    // Frequency gate (skip for mandatory events)
    if (!isMandatory) {
      final roll = _random.nextDouble();
      // Positive cues additionally gated by positiveMix dial
      if (priority == 2) {
        if (roll > _settings.positive * _settings.frequency) return;
      } else {
        if (roll > _settings.frequency) return;
      }
    }

    final path = _nextTrack(category);
    if (path == null) return;

    // Stop current if lower or equal priority
    await _player.stop();
    _currentPriority = priority;

    // Derive caption from filename stem
    final stem = path.split('/').last.replaceAll('.mp3', '');
    lastCaption = _captions[stem] ?? _toSentenceCase(stem);
    notifyListeners();

    // Configure AudioSession to ignore silent switch (iOS)
    _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: { AVAudioSessionOptions.duckOthers },
      ),
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.assistanceNavigationGuidance,
        contentType: AndroidContentType.speech,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));

    await _player.setVolume(_settings.volume);
    // AssetSource prepends 'assets/' internally — strip our prefix to avoid double-pathing.
    await _player.play(AssetSource(path.replaceFirst('assets/', '')));

    // Clear caption after 3 s — short enough to feel responsive.
    _captionTimer?.cancel();
    _captionTimer = Timer(const Duration(seconds: 3), () {
      lastCaption = null;
      notifyListeners();
    });
  }

  /// Play a correction cue — always overrides positive reinforcement.
  Future<void> playCorrection(CueCategory category) =>
      play(category, isMandatory: false);

  /// Play a mandatory event cue (session start / end) — ignores all gates.
  Future<void> playMandatory(CueCategory category) =>
      play(category, isMandatory: true);

  /// Update volume on the fly (called when settings dial changes).
  void applyVolume() => _player.setVolume(_settings.volume);

  @override
  void dispose() {
    _captionTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  String? _nextTrack(CueCategory cat) {
    final assets = _assets[cat];
    if (assets == null || assets.isEmpty) return null;

    var pool = _remaining[cat]!;
    if (pool.isEmpty) {
      // Refill and reshuffle
      pool = List.of(assets)..shuffle(_random);
      _remaining[cat] = pool;
    }
    final picked = pool.removeLast();
    return picked;
  }

  String _toSentenceCase(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }
}
