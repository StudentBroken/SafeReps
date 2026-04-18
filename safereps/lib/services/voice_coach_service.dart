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
// Names come directly from the filesytem listing so there's zero ambiguity.

const _assets = <CueCategory, List<String>>{
  // ── GENERIC: Start ────────────────────────────────────────────────────────
  CueCategory.start: [
    '../assets/Generic Audio/Start/ge ready.mp3',
    '../assets/Generic Audio/Start/get to work and have an amazing session.mp3',
    '../assets/Generic Audio/Start/im ready when you are take a deep breath you\'re going to do phenomenally today.mp3',
    '../assets/Generic Audio/Start/you\'re here, ready and already looking strong lets get to work.mp3',
  ],

  // ── GENERIC: Finish / Congratulations ────────────────────────────────────
  CueCategory.finishCongrats: [
    '../assets/Generic Audio/Finish congratulations/Done adn dusted you showed up and you showed out.mp3',
    '../assets/Generic Audio/Finish congratulations/final set is in the books.mp3',
    '../assets/Generic Audio/Finish congratulations/session complete, you gave it everything.mp3',
    '../assets/Generic Audio/Finish congratulations/set complete great work done.mp3',
    '../assets/Generic Audio/Finish congratulations/set complete great work.mp3',
    '../assets/Generic Audio/Finish congratulations/That is how its done you crushed it.mp3',
    '../assets/Generic Audio/Finish congratulations/Workout complete you put in the work today.mp3',
  ],

  // ── GENERIC: Positive reinforcement ──────────────────────────────────────
  CueCategory.genericPositive: [
    '../assets/Generic Audio/Generic Positive reinforcement/i see you working keep it going.mp3',
    '../assets/Generic Audio/Generic Positive reinforcement/thats it perfect keep going.mp3',
    '../assets/Generic Audio/Generic Positive reinforcement/this is where the gains are made dig deep.mp3',
    '../assets/Generic Audio/Generic Positive reinforcement/you are crushing it.mp3',
    '../assets/Generic Audio/Generic Positive reinforcement/you\'re making it look easy.mp3',
  ],

  // ── GENERIC: Form corrections (cross-exercise) ────────────────────────────
  CueCategory.genericFormCorrection: [
    '../assets/Generic Audio/Generic form correction/amazing keep breathing keep that core tight.mp3',
    '../assets/Generic Audio/Generic form correction/beautiful form just continue.mp3',
    '../assets/Generic Audio/Generic form correction/excellent control, 3 seconds down.mp3',
    '../assets/Generic Audio/Generic form correction/great power, plant your feet.mp3',
    '../assets/Generic Audio/Generic form correction/looking strong squeeze up and control down.mp3',
    '../assets/Generic Audio/Generic form correction/love the energy remember to breathe.mp3',
    '../assets/Generic Audio/Generic form correction/perfect rythm right there keep it up.mp3',
    '../assets/Generic Audio/Generic form correction/u got the strenght for this dont let the weight win.mp3',
    '../assets/Generic Audio/Generic form correction/you have insane strenght dont waste it on bad form.mp3',
    '../assets/Generic Audio/Generic form correction/you\'re doing great keep that tension.mp3',
    '../assets/Generic Audio/Generic form correction/You\'re doing great, form check keep your back straight.mp3',
    '../assets/Generic Audio/Generic form correction/you\'re moving serious weight keep those reps clean.mp3',
  ],

  // ── BICEP CURLS ──────────────────────────────────────────────────────────

  CueCategory.bicepBackBody: [
    '../assets/Audio Bicep Curls/Form correction (Back and body movement)/Lock your upper arms and stop swinging.mp3',
    '../assets/Audio Bicep Curls/Form correction (Back and body movement)/Use those biceps not your back.mp3',
    '../assets/Audio Bicep Curls/Form correction (Back and body movement)/Watch the back arch pin those elbows.mp3',
    '../assets/Audio Bicep Curls/Form correction (Back and body movement)/You are swinging the weight too much.mp3',
  ],

  CueCategory.bicepElbows: [
    '../assets/Audio Bicep Curls/Form correction (Elbows)/Bend elbows to wrist height no higher.mp3',
    '../assets/Audio Bicep Curls/Form correction (Elbows)/Elbow creeping up, pin it back down.mp3',
    '../assets/Audio Bicep Curls/Form correction (Elbows)/upper arm completely still only forearm moves.mp3',
  ],

  CueCategory.bicepRomBottom: [
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Full extension at the bottom no half reps.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Go all the way down.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Uncurl completely.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Bottom)/Your cutting it short extend fully.mp3',
  ],

  CueCategory.bicepRomTop: [
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Bring it all the way up to your shoulder.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Close but get it all the way to the top.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Don\'t stop early squeeze at the top.mp3',
    '../assets/Audio Bicep Curls/Form correction (Range of Motion Top)/Get that full range at the top.mp3',
  ],

  CueCategory.bicepShoulderWrist: [
    '../assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Keep your wrists straight no curling them.mp3',
    '../assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Keep your shoulders back and down.mp3',
    '../assets/Audio Bicep Curls/Form correction (Shoulder and Wrists)/Relax the shoulders let the biceps do the work.mp3',
  ],

  CueCategory.bicepLastRepsMotiv: [
    '../assets/Audio Bicep Curls/Last reps Motivation/Dont drop that weight you have more in you.mp3',
    '../assets/Audio Bicep Curls/Last reps Motivation/Fight for it squeeze it out.mp3',
    '../assets/Audio Bicep Curls/Last reps Motivation/Halfway there, maintain the form.mp3',
  ],

  CueCategory.bicepPositive: [
    '../assets/Audio Bicep Curls/Positive stuff/Absolute machine right now let\'s keep this up.mp3',
    '../assets/Audio Bicep Curls/Positive stuff/Beautiful control you are locking this in.mp3',
    '../assets/Audio Bicep Curls/Positive stuff/Spot on you\'re making that weight look light.mp3',
    '../assets/Audio Bicep Curls/Positive stuff/Textbook form, keep that exact movement.mp3',
    '../assets/Audio Bicep Curls/Positive stuff/You got this keep breathing keep squeezing.mp3',
  ],

  CueCategory.bicepTempo: [
    '../assets/Audio Bicep Curls/Tempo/Dont just let it fall, resist the negative.mp3',
    '../assets/Audio Bicep Curls/Tempo/Fight gravity on the way down take 3 full seconds.mp3',
    '../assets/Audio Bicep Curls/Tempo/Perfect pace, keep this exact same rhythm.mp3',
    '../assets/Audio Bicep Curls/Tempo/Too fast on the drop control that weight.mp3',
  ],

  // ── LATERAL RAISES ───────────────────────────────────────────────────────

  CueCategory.lateralBodySwing: [
    '../assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/if you have to throw your back into it its too heavy.mp3',
    '../assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/lock your core no swinigng the weight up.mp3',
    '../assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/plant your feet and stay totaly rigid.mp3',
    '../assets/Lateral raises Audio/Form correction (Body Movements and Swinging)/stop rocking, keep your torso completely still.mp3',
  ],

  CueCategory.lateralElbowWrist: [
    '../assets/Lateral raises Audio/Form correction (Elbows and Wrists)/imagine pouring water out at the top of the movement like pitcher.mp3',
    '../assets/Lateral raises Audio/Form correction (Elbows and Wrists)/keep a soft bend in your elbows dont lock your arms.mp3',
    '../assets/Lateral raises Audio/Form correction (Elbows and Wrists)/keep elbow perfectly in front of your body not to the side.mp3',
    '../assets/Lateral raises Audio/Form correction (Elbows and Wrists)/lead with elbow no wrist.mp3',
  ],

  CueCategory.lateralRom: [
    '../assets/Lateral raises Audio/Form correction (Range of Motion)/bring them up until your arms are parallel to the floor.mp3',
    '../assets/Lateral raises Audio/Form correction (Range of Motion)/control the thing dont let the dumbell slam against your leg.mp3',
    '../assets/Lateral raises Audio/Form correction (Range of Motion)/keep constant tension don\'t rest the weights on your hips at the bottom.mp3',
    '../assets/Lateral raises Audio/Form correction (Range of Motion)/stop at shoulder height no need to go any higher.mp3',
    '../assets/Lateral raises Audio/Form correction (Range of Motion)/you\'re stopping short get those dumbless up to shoulder level.mp3',
  ],

  CueCategory.lateralShoulderTrap: [
    '../assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Keep your shoulders pressed down dont shrug the weight.mp3',
    '../assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Push shoulder down into back pocket.mp3',
    '../assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Relax your neck let your side of shoulders do work.mp3',
    '../assets/Lateral raises Audio/Form correction (Shoulder and Traps)/Your traps are dropping down, let your shoulders do work.mp3',
  ],

  CueCategory.lateralPositivePerfect: [
    '../assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/perfect form your shoulders are completely isolated.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/smooth and controlled exactly what i wnat to see.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/thats a beautiful rep do it again.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/you are doing great, great mind-muscle connection.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Perfect Reps)/your shoulders are on fire lets finish this set.mp3',
  ],

  CueCategory.lateralPositiveStruggle: [
    '../assets/Lateral raises Audio/Positive reinforcement (Struggle)/almost there dont let your form slip now.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Struggle)/Don\'t drop the weight yet you have more in you.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Struggle)/dont drop your arms yet you have more in you.mp3',
    '../assets/Lateral raises Audio/Positive reinforcement (Struggle)/Keep fighting for height keep fighting for height.mp3',
  ],

  CueCategory.lateralTempo: [
    '../assets/Lateral raises Audio/Tempo/control the drop fight gravity all the way down.mp3',
    '../assets/Lateral raises Audio/Tempo/dont just let your arms drop resist the fall.mp3',
    '../assets/Lateral raises Audio/Tempo/hold it at the top for a split second.mp3',
    '../assets/Lateral raises Audio/Tempo/perfect pace right there dont speed up.mp3',
  ],
};

// ── Caption maps ──────────────────────────────────────────────────────────────
//
// Maps filename stem → clean display text.
// Only corrections/cueing needs a caption; pure-positive is self-explanatory
// but we still surfaced filename-cleaned text as fallback.

const Map<String, String> _captions = {
  // Generic start
  'ge ready':                                           'Get ready!',
  'get to work and have an amazing session':            'Let\'s get to work — have an amazing session!',
  'im ready when you are take a deep breath you\'re going to do phenomenally today':
                                                        'Take a deep breath — you\'re going to do great today.',
  'you\'re here, ready and already looking strong lets get to work':
                                                        'You\'re here, looking strong — let\'s go!',

  // Generic finish
  'Done adn dusted you showed up and you showed out':   'Done and dusted — you showed up and showed out!',
  'final set is in the books':                          'Final set in the books!',
  'session complete, you gave it everything':           'Session complete — you gave it everything!',
  'set complete great work done':                       'Set complete — great work!',
  'set complete great work':                            'Set complete — great work!',
  'That is how its done you crushed it':                'That\'s how it\'s done — you crushed it!',
  'Workout complete you put in the work today':         'Workout complete — you put in the work today!',

  // Generic positive
  'i see you working keep it going':             'I see you working — keep it going!',
  'thats it perfect keep going':                 'That\'s it — perfect, keep going!',
  'this is where the gains are made dig deep':   'This is where the gains are made — dig deep!',
  'you are crushing it':                         'You are crushing it!',
  'you\'re making it look easy':                 'You\'re making it look easy!',

  // Generic form correction
  'amazing keep breathing keep that core tight':           'Amazing — keep breathing, keep that core tight.',
  'beautiful form just continue':                          'Beautiful form — just continue.',
  'excellent control, 3 seconds down':                     'Excellent control — 3 seconds on the way down.',
  'great power, plant your feet':                          'Great power — plant your feet.',
  'looking strong squeeze up and control down':            'Looking strong — squeeze up, control down.',
  'love the energy remember to breathe':                   'Love the energy — remember to breathe.',
  'perfect rythm right there keep it up':                  'Perfect rhythm — keep it up!',
  'u got the strenght for this dont let the weight win':   'You\'ve got the strength — don\'t let the weight win.',
  'you have insane strenght dont waste it on bad form':    'You have insane strength — don\'t waste it on bad form.',
  'you\'re doing great keep that tension':                 'You\'re doing great — keep that tension.',
  'You\'re doing great, form check keep your back straight': 'Form check — keep your back straight.',
  'you\'re moving serious weight keep those reps clean':   'You\'re moving serious weight — keep those reps clean.',

  // Bicep curls – back/body
  'Lock your upper arms and stop swinging':   'Lock your upper arms — stop swinging.',
  'Use those biceps not your back':           'Use those biceps, not your back.',
  'Watch the back arch pin those elbows':     'Watch the back arch — pin those elbows.',
  'You are swinging the weight too much':     'You\'re swinging the weight too much — slow down.',

  // Bicep – elbows
  'Bend elbows to wrist height no higher':           'Bend elbows to wrist height — no higher.',
  'Elbow creeping up, pin it back down':             'Elbow\'s creeping up — pin it back down.',
  'upper arm completely still only forearm moves':   'Upper arm completely still — only the forearm moves.',

  // Bicep – ROM bottom
  'Full extension at the bottom no half reps':   'Full extension at the bottom — no half reps.',
  'Go all the way down':                         'Go all the way down.',
  'Uncurl completely':                           'Uncurl completely at the bottom.',
  'Your cutting it short extend fully':          'You\'re cutting it short — extend fully.',

  // Bicep – ROM top
  'Bring it all the way up to your shoulder':    'Bring it all the way up to your shoulder.',
  'Close but get it all the way to the top':     'Close — get it all the way to the top.',
  'Don\'t stop early squeeze at the top':        'Don\'t stop early — squeeze at the top.',
  'Get that full range at the top':              'Get that full range at the top.',

  // Bicep – shoulder/wrist
  'Keep your wrists straight no curling them':   'Keep your wrists straight — no curling them.',
  'Keep your shoulders back and down':           'Keep your shoulders back and down.',
  'Relax the shoulders let the biceps do the work': 'Relax the shoulders — let the biceps do the work.',

  // Bicep – last reps
  'Dont drop that weight you have more in you':  'Don\'t drop that weight — you have more in you!',
  'Fight for it squeeze it out':                 'Fight for it — squeeze it out!',
  'Halfway there, maintain the form':            'Halfway there — maintain the form.',

  // Bicep – positive
  'Absolute machine right now let\'s keep this up':  'Absolute machine right now — keep it up!',
  'Beautiful control you are locking this in':       'Beautiful control — you\'re locking this in!',
  'Spot on you\'re making that weight look light':   'Spot on — you\'re making that weight look light!',
  'Textbook form, keep that exact movement':         'Textbook form — keep that exact movement.',
  'You got this keep breathing keep squeezing':      'You got this — keep breathing, keep squeezing.',

  // Bicep – tempo
  'Dont just let it fall, resist the negative':           'Don\'t just let it fall — resist the negative.',
  'Fight gravity on the way down take 3 full seconds':    'Fight gravity on the way down — 3 full seconds.',
  'Perfect pace, keep this exact same rhythm':            'Perfect pace — keep this exact same rhythm.',
  'Too fast on the drop control that weight':             'Too fast on the drop — control that weight.',

  // Lateral – body swing
  'if you have to throw your back into it its too heavy': 'If you\'re throwing your back into it, it\'s too heavy.',
  'lock your core no swinigng the weight up':             'Lock your core — no swinging.',
  'plant your feet and stay totaly rigid':                'Plant your feet and stay totally rigid.',
  'stop rocking, keep your torso completely still':       'Stop rocking — keep your torso still.',

  // Lateral – elbow/wrist
  'imagine pouring water out at the top of the movement like pitcher': 'Imagine pouring water at the top — pitcher-style.',
  'keep a soft bend in your elbows dont lock your arms':  'Soft bend in the elbows — don\'t lock your arms.',
  'keep elbow perfectly in front of your body not to the side': 'Keep elbow in front of your body, not to the side.',
  'lead with elbow no wrist':                             'Lead with the elbow — not the wrist.',

  // Lateral – ROM
  'bring them up until your arms are parallel to the floor': 'Bring them up until your arms are parallel to the floor.',
  'control the thing dont let the dumbell slam against your leg': 'Control the descent — don\'t let the dumbbell slam.',
  'keep constant tension don\'t rest the weights on your hips at the bottom': 'Keep constant tension — don\'t rest at the bottom.',
  'stop at shoulder height no need to go any higher':     'Stop at shoulder height — no need to go higher.',
  'you\'re stopping short get those dumbless up to shoulder level': 'You\'re stopping short — get those dumbbells to shoulder level.',

  // Lateral – shoulder/trap
  'Keep your shoulders pressed down dont shrug the weight': 'Keep shoulders pressed down — don\'t shrug.',
  'Push shoulder down into back pocket':                  'Push your shoulder down into your back pocket.',
  'Relax your neck let your side of shoulders do work':   'Relax your neck — let the shoulders do the work.',
  'Your traps are dropping down, let your shoulders do work': 'Your traps are taking over — reset your shoulders.',

  // Lateral – positive perfect
  'perfect form your shoulders are completely isolated':  'Perfect form — shoulders completely isolated.',
  'smooth and controlled exactly what i wnat to see':     'Smooth and controlled — exactly what I want to see.',
  'thats a beautiful rep do it again':                    'That\'s a beautiful rep — do it again!',
  'you are doing great, great mind-muscle connection':    'You\'re doing great — great mind-muscle connection!',
  'your shoulders are on fire lets finish this set':      'Your shoulders are on fire — let\'s finish this set!',

  // Lateral – positive struggle
  'almost there dont let your form slip now':             'Almost there — don\'t let your form slip now!',
  'Don\'t drop the weight yet you have more in you':      'Don\'t drop the weight — you have more in you!',
  'dont drop your arms yet you have more in you':         'Don\'t drop your arms — you have more in you!',
  'Keep fighting for height keep fighting for height':    'Keep fighting for height!',

  // Lateral – tempo
  'control the drop fight gravity all the way down':      'Control the drop — fight gravity all the way down.',
  'dont just let your arms drop resist the fall':         'Don\'t just let your arms drop — resist the fall.',
  'hold it at the top for a split second':                'Hold it at the top for a split second.',
  'perfect pace right there dont speed up':               'Perfect pace right there — don\'t speed up.',
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
  CueCategory.lateralRom:              4,
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

    await _player.setVolume(_settings.volume);
    await _player.play(AssetSource(path));

    // Clear caption after a delay matching typical track length
    Future.delayed(const Duration(seconds: 6), () {
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
