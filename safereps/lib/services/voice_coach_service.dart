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
    'assets/audio_generic/start/get_ready.mp3',
    'assets/audio_generic/start/get_to_work_and_have_an_amazing_session.mp3',
    'assets/audio_generic/start/im_ready_when_you_are_take_a_deep_breath_you\'re_going_to_do_phenomenally_today.mp3',
    'assets/audio_generic/start/you\'re_here,_ready_and_already_looking_strong_lets_get_to_work.mp3',
  ],

  // ── GENERIC: Finish / Congratulations ────────────────────────────────────
  CueCategory.finishCongrats: [
    'assets/audio_generic/finish_congratulations/done_and_dusted_you_showed_up_pushed_hard_and_got_stronger_pehnomenal_effort.mp3',
    'assets/audio_generic/finish_congratulations/final_set_is_in_the_books_you_proved_exactly_how_strong_you_are_today_outstanding_work.mp3',
    'assets/audio_generic/finish_congratulations/session_complete,_you_gave_it_your_all_and_it_paid_off.mp3',
    'assets/audio_generic/finish_congratulations/set_complete_great_work_drop_the_weight_and_rest.mp3',
    'assets/audio_generic/finish_congratulations/set_complete_great_work.mp3',
    'assets/audio_generic/finish_congratulations/that_is_how_its_done_you_crushed_every_single_set_amazing_job.mp3',
    'assets/audio_generic/finish_congratulations/workout_complete_you_put_in_the_work_today_be_incredibly_proud_of_yourself.mp3',
  ],

  // ── GENERIC: Positive reinforcement ──────────────────────────────────────
  CueCategory.genericPositive: [
    'assets/audio_generic/generic_positive_reinforcement/i_see_you_working_keep_that_intensity_high_its_paying_off.mp3',
    'assets/audio_generic/generic_positive_reinforcement/thats_it_perfect_execution_absolute_machine.mp3',
    'assets/audio_generic/generic_positive_reinforcement/this_is_where_the_real_progress_happens_you\'re_doing_incredible_dont_quit.mp3',
    'assets/audio_generic/generic_positive_reinforcement/you_are_crushing_this_keep_going_you\'re_unstoppable.mp3',
    'assets/audio_generic/generic_positive_reinforcement/you\'re_making_it_look_easy_lets_go.mp3',
  ],

  // ── GENERIC: Form corrections (cross-exercise) ────────────────────────────
  CueCategory.genericFormCorrection: [
    'assets/audio_generic/generic_form_correction/amazing_keep_breathing_keep_oxygen_there.mp3',
    'assets/audio_generic/generic_form_correction/beautiful_form_just_control_the_tempo.mp3',
    'assets/audio_generic/generic_form_correction/excellent_control,_3_seconds_on_the_way_down.mp3',
    'assets/audio_generic/generic_form_correction/great_power,_plant_your_feet_flat_to_build_an_even_stronger_base.mp3',
    'assets/audio_generic/generic_form_correction/looking_strong_squeeze_ur_glutes_to_stabilize_the_body_even_more.mp3',
    'assets/audio_generic/generic_form_correction/love_the_energy_remember_to_keep_chest_up_shoulder_back.mp3',
    'assets/audio_generic/generic_form_correction/perfect_rythm_right_there_lock_into_thta_pace_ur_killing_it.mp3',
    'assets/audio_generic/generic_form_correction/u_got_the_strenght_for_this_breath_in_and_breath_out_on_the_way_in_n_out.mp3',
    'assets/audio_generic/generic_form_correction/you\'re_doing_great,_form_slipping,_reset_and_get_back_to_perfect.mp3',
    'assets/audio_generic/generic_form_correction/you\'re_doing_great_keep_spine_completely_neutral_.mp3',
    'assets/audio_generic/generic_form_correction/you\'re_moving_serious_weight_slow_those_muscles_down_.mp3',
    'assets/audio_generic/generic_form_correction/you_have_insane_strenght,_but_if_you_have_to_cheat_the_movement_drop_the_weight_and_blah_blah_blah.mp3',
  ],

  // ── BICEP CURLS ──────────────────────────────────────────────────────────

  CueCategory.bicepBackBody: [
    'assets/audio_bicep_curls/form_correction_back_and_body_movement/lock_your_code_keep_your_torso_completely_vertical.mp3',
    'assets/audio_bicep_curls/form_correction_back_and_body_movement/use_muscle_not_momentum_use_your_body_keep_stable.mp3',
    'assets/audio_bicep_curls/form_correction_back_and_body_movement/watch_the_swinging_use_your_biceps_not_your_back.mp3',
    'assets/audio_bicep_curls/form_correction_back_and_body_movement/you\'re_leaning_back_to_get_it_up_lighten_the_weight_if_you_need_t.mp3',
  ],

  CueCategory.bicepElbows: [
    'assets/audio_bicep_curls/form_correction_elbows/bend_elbows_to_wrist,_dont_drift_forwards.mp3',
    'assets/audio_bicep_curls/form_correction_elbows/elbow_creeping_up,_lock_them_in_place.mp3',
    'assets/audio_bicep_curls/form_correction_elbows/upper_arm_completely_still,_only_form_arm_should_move.mp3',
  ],

  CueCategory.bicepRomBottom: [
    'assets/audio_bicep_curls/form_correction_range_of_motion_bottom/full_extension_on_the_way_down_dont_cheat_yourself.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_bottom/go_all_the_way_down,_full_stretch_at_the_bottom.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_bottom/uncurl_all_the_way,_let_the_arms_hang_before_next_rep.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_bottom/you\'re_cutting_it_short,_straighten_the_arm_completely_.mp3',
  ],

  CueCategory.bicepRomTop: [
    'assets/audio_bicep_curls/form_correction_range_of_motion_top/bring_it_all_the_way_up_and_squeeze.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_top/close_that_gap_at_the_top,_hard_squeeze.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_top/don\'t_stop_halfway,_curl_it_up_to_the_shoulder.mp3',
    'assets/audio_bicep_curls/form_correction_range_of_motion_top/get_that_full_contraction_at_the_top_of_the_rep.mp3',
  ],

  CueCategory.bicepShoulderWrist: [
    'assets/audio_bicep_curls/form_correction_shoulder_and_wrists/keep_your_shoulders_down_and_relax_dont_shrug_the_weight.mp3',
    'assets/audio_bicep_curls/form_correction_shoulder_and_wrists/keep_your_wrists_neutral_dont_let_them_curl_inwards_at_the_top.mp3',
    'assets/audio_bicep_curls/form_correction_shoulder_and_wrists/relax_your_neck_and_shoulders_let_the_biceps_do_the_work.mp3',
  ],

  CueCategory.bicepLastRepsMotiv: [
    'assets/audio_bicep_curls/last_reps_motivation/dont_drop_that_weight_you_have_one_more_in_there.mp3',
    'assets/audio_bicep_curls/last_reps_motivation/fight_for_it_squeeze_it_up_there.mp3',
    'assets/audio_bicep_curls/last_reps_motivation/halfway_there,_maintain_that_strict_form.mp3',
  ],

  CueCategory.bicepPositive: [
    'assets/audio_bicep_curls/positive_stuff/absolute_machine_right_now_lets_finish_strong.mp3',
    'assets/audio_bicep_curls/positive_stuff/beautiful_control_you_are_locked_in_right_now.mp3',
    'assets/audio_bicep_curls/positive_stuff/spot_on_you\'re_making_that_weight_look_easy.mp3',
    'assets/audio_bicep_curls/positive_stuff/textbook_form,_keep_that_exact_same_groove.mp3',
    'assets/audio_bicep_curls/positive_stuff/you_got_this_keep_breathing_keep_moving.mp3',
  ],

  CueCategory.bicepTempo: [
    'assets/audio_bicep_curls/tempo/dont_just_let_it_fall,_resist_the_negative.mp3',
    'assets/audio_bicep_curls/tempo/fight_gravity_on_the_way_down_take_3_full_seconds.mp3',
    'assets/audio_bicep_curls/tempo/perfect_pace,_keep_this_exact_same_rythm.mp3',
    'assets/audio_bicep_curls/tempo/too_fast_on_the_drop_control_that_weight.mp3',
  ],

  // ── LATERAL RAISES ───────────────────────────────────────────────────────

  CueCategory.lateralBodySwing: [
    'assets/audio_lateral_raises/form_correction_body_movements_and_swinging/if_you_have_to_throw_your_back_into_it_its_too_heavy.mp3',
    'assets/audio_lateral_raises/form_correction_body_movements_and_swinging/lock_your_core_no_swinigng_the_weight_up.mp3',
    'assets/audio_lateral_raises/form_correction_body_movements_and_swinging/plant_your_feet_and_stay_totaly_rigid.mp3',
    'assets/audio_lateral_raises/form_correction_body_movements_and_swinging/stop_rocking,_keep_your_torso_completely_still.mp3',
  ],

  CueCategory.lateralElbowWrist: [
    'assets/audio_lateral_raises/form_correction_elbows_and_wrists/imagine_pouring_water_out_at_the_top_of_the_movement_like_pitcher.mp3',
    'assets/audio_lateral_raises/form_correction_elbows_and_wrists/keep_a_soft_bend_in_your_elbows_dont_lock_your_arms.mp3',
    'assets/audio_lateral_raises/form_correction_elbows_and_wrists/keep_elbow_perfectly_in_front_of_your_body_not_to_the_side.mp3',
    'assets/audio_lateral_raises/form_correction_elbows_and_wrists/lead_with_elbow_no_wrist.mp3',
  ],

  CueCategory.lateralRom: [
    'assets/audio_lateral_raises/form_correction_range_of_motion/bring_them_up_until_your_arms_are_parallel_to_the_floor.mp3',
    'assets/audio_lateral_raises/form_correction_range_of_motion/control_the_thing_dont_let_the_dumbell_slam_against_your_leg.mp3',
    'assets/audio_lateral_raises/form_correction_range_of_motion/keep_constant_tension_don\'t_rest_the_weights_on_your_hips_at_the_bottom.mp3',
    'assets/audio_lateral_raises/form_correction_range_of_motion/stop_at_shoulder_height_no_need_to_go_any_higher.mp3',
    'assets/audio_lateral_raises/form_correction_range_of_motion/you\'re_stopping_short_get_those_dumbless_up_to_shoulder_level.mp3',
  ],

  CueCategory.lateralShoulderTrap: [
    'assets/audio_lateral_raises/form_correction_shoulder_and_traps/keep_your_shoulders_pressed_down_dont_shrug_the_weight.mp3',
    'assets/audio_lateral_raises/form_correction_shoulder_and_traps/push_shoulder_down_into_back_pocket.mp3',
    'assets/audio_lateral_raises/form_correction_shoulder_and_traps/relax_your_neck_let_your_side_of_shoulders_do_work.mp3',
    'assets/audio_lateral_raises/form_correction_shoulder_and_traps/your_traps_are_dropping_down,_let_your_shoulders_do_work.mp3',
  ],

  CueCategory.lateralPositivePerfect: [
    'assets/audio_lateral_raises/positive_reinforcement_perfect_reps/perfect_form_your_shoulders_are_completely_isolated.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_perfect_reps/smooth_and_controlled_exactly_what_i_wnat_to_see.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_perfect_reps/thats_a_beautiful_rep_do_it_again.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_perfect_reps/you_are_doing_great,_great_mind-muscle_connection.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_perfect_reps/your_shoulders_are_on_fire_lets_finish_this_set.mp3',
  ],

  CueCategory.lateralPositiveStruggle: [
    'assets/audio_lateral_raises/positive_reinforcement_struggle/almost_there_dont_let_your_form_slip_now.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_struggle/don\'t_drop_the_weight_yet_you_have_more_in_you.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_struggle/dont_drop_your_arms_yet_you_have_more_in_you.mp3',
    'assets/audio_lateral_raises/positive_reinforcement_struggle/keep_fighting_for_height_keep_fighting_for_height.mp3',
  ],

  CueCategory.lateralTempo: [
    'assets/audio_lateral_raises/tempo/control_the_drop_fight_gravity_all_the_way_down.mp3',
    'assets/audio_lateral_raises/tempo/dont_just_let_your_arms_drop_resist_the_fall.mp3',
    'assets/audio_lateral_raises/tempo/hold_it_at_the_top_for_a_split_second.mp3',
    'assets/audio_lateral_raises/tempo/perfect_pace_right_there_dont_speed_up.mp3',
  ],
};

// ── Caption maps ──────────────────────────────────────────────────────────────
//
// Maps filename stem → short, punchy display text shown on-screen.
// Stems are the filename without the .mp3 extension.

const Map<String, String> _captions = {
  'get_ready':
      'Get ready!',
  'get_to_work_and_have_an_amazing_session':
      'Let\'s work!',
  'im_ready_when_you_are_take_a_deep_breath_you\'re_going_to_do_phenomenally_today':
      'Breathe & focus.',
  'you\'re_here,_ready_and_already_looking_strong_lets_get_to_work':
      'Ready to go!',
  'done_and_dusted_you_showed_up_pushed_hard_and_got_stronger_pehnomenal_effort':
      'Phenomenal effort!',
  'final_set_is_in_the_books_you_proved_exactly_how_strong_you_are_today_outstanding_work':
      'Final set done!',
  'session_complete,_you_gave_it_your_all_and_it_paid_off':
      'Session complete!',
  'set_complete_great_work_drop_the_weight_and_rest':
      'Set done — rest!',
  'set_complete_great_work':
      'Set complete!',
  'that_is_how_its_done_you_crushed_every_single_set_amazing_job':
      'Crushed it!',
  'workout_complete_you_put_in_the_work_today_be_incredibly_proud_of_yourself':
      'Workout complete!',
  'i_see_you_working_keep_that_intensity_high_its_paying_off':
      'Keep the intensity!',
  'thats_it_perfect_execution_absolute_machine':
      'Perfect!',
  'this_is_where_the_real_progress_happens_you\'re_doing_incredible_dont_quit':
      'Don\'t quit!',
  'you_are_crushing_this_keep_going_you\'re_unstoppable':
      'Unstoppable!',
  'you\'re_making_it_look_easy_lets_go':
      'Let\'s go!',
  'amazing_keep_breathing_keep_oxygen_there':
      'Keep breathing.',
  'beautiful_form_just_control_the_tempo':
      'Control tempo.',
  'excellent_control,_3_seconds_on_the_way_down':
      '3s down.',
  'great_power,_plant_your_feet_flat_to_build_an_even_stronger_base':
      'Feet flat.',
  'looking_strong_squeeze_ur_glutes_to_stabilize_the_body_even_more':
      'Squeeze glutes.',
  'love_the_energy_remember_to_keep_chest_up_shoulder_back':
      'Chest up.',
  'perfect_rythm_right_there_lock_into_thta_pace_ur_killing_it':
      'Lock that rhythm.',
  'u_got_the_strenght_for_this_breath_in_and_breath_out_on_the_way_in_n_out':
      'Breathe.',
  'you_have_insane_strenght,_but_if_you_have_to_cheat_the_movement_drop_the_weight_and_blah_blah_blah':
      'Drop the weight.',
  'you\'re_doing_great_keep_spine_completely_neutral_':
      'Neutral spine.',
  'you\'re_doing_great,_form_slipping,_reset_and_get_back_to_perfect':
      'Reset your form.',
  'you\'re_moving_serious_weight_slow_those_muscles_down_':
      'Slow down.',
  'lock_your_code_keep_your_torso_completely_vertical':
      'Torso vertical.',
  'use_muscle_not_momentum_use_your_body_keep_stable':
      'Muscle not momentum.',
  'watch_the_swinging_use_your_biceps_not_your_back':
      'Biceps only.',
  'you\'re_leaning_back_to_get_it_up_lighten_the_weight_if_you_need_t':
      'Lighten the weight.',
  'bend_elbows_to_wrist,_dont_drift_forwards':
      'Don\'t drift forward.',
  'elbow_creeping_up,_lock_them_in_place':
      'Lock the elbows.',
  'upper_arm_completely_still,_only_form_arm_should_move':
      'Still upper arm.',
  'full_extension_on_the_way_down_dont_cheat_yourself':
      'Full extension.',
  'go_all_the_way_down,_full_stretch_at_the_bottom':
      'All the way down.',
  'uncurl_all_the_way,_let_the_arms_hang_before_next_rep':
      'Let it hang.',
  'you\'re_cutting_it_short,_straighten_the_arm_completely_':
      'Straighten fully.',
  'bring_it_all_the_way_up_and_squeeze':
      'Squeeze at top.',
  'close_that_gap_at_the_top,_hard_squeeze':
      'Hard squeeze.',
  'don\'t_stop_halfway,_curl_it_up_to_the_shoulder':
      'Up to shoulder.',
  'get_that_full_contraction_at_the_top_of_the_rep':
      'Full contraction.',
  'keep_your_wrists_neutral_dont_let_them_curl_inwards_at_the_top':
      'Neutral wrists.',
  'keep_your_shoulders_down_and_relax_dont_shrug_the_weight':
      'Shoulders down.',
  'relax_your_neck_and_shoulders_let_the_biceps_do_the_work':
      'Relax shoulders.',
  'dont_drop_that_weight_you_have_one_more_in_there':
      'One more!',
  'fight_for_it_squeeze_it_up_there':
      'Fight for it!',
  'halfway_there,_maintain_that_strict_form':
      'Halfway there.',
  'absolute_machine_right_now_lets_finish_strong':
      'Finish strong!',
  'beautiful_control_you_are_locked_in_right_now':
      'Locked in!',
  'spot_on_you\'re_making_that_weight_look_easy':
      'Looking easy!',
  'textbook_form,_keep_that_exact_same_groove':
      'Textbook form.',
  'you_got_this_keep_breathing_keep_moving':
      'Keep moving!',
  'dont_just_let_it_fall,_resist_the_negative':
      'Resist the drop.',
  'fight_gravity_on_the_way_down_take_3_full_seconds':
      '3s negative.',
  'perfect_pace,_keep_this_exact_same_rythm':
      'Stay steady.',
  'too_fast_on_the_drop_control_that_weight':
      'Slow down.',
  'if_you_have_to_throw_your_back_into_it_its_too_heavy':
      'Too heavy.',
  'lock_your_core_no_swinigng_the_weight_up':
      'No swinging.',
  'plant_your_feet_and_stay_totaly_rigid':
      'Stay rigid.',
  'stop_rocking,_keep_your_torso_completely_still':
      'Still torso.',
  'imagine_pouring_water_out_at_the_top_of_the_movement_like_pitcher':
      'Pour the pitcher.',
  'keep_a_soft_bend_in_your_elbows_dont_lock_your_arms':
      'Soft elbows.',
  'keep_elbow_perfectly_in_front_of_your_body_not_to_the_side':
      'Elbows forward.',
  'lead_with_elbow_no_wrist':
      'Elbow leads.',
  'bring_them_up_until_your_arms_are_parallel_to_the_floor':
      'Arms parallel.',
  'control_the_thing_dont_let_the_dumbell_slam_against_your_leg':
      'Control the drop.',
  'keep_constant_tension_don\'t_rest_the_weights_on_your_hips_at_the_bottom':
      'Keep tension.',
  'stop_at_shoulder_height_no_need_to_go_any_higher':
      'Shoulder height.',
  'you\'re_stopping_short_get_those_dumbless_up_to_shoulder_level':
      'Get to shoulder.',
  'keep_your_shoulders_pressed_down_dont_shrug_the_weight':
      'Don\'t shrug.',
  'push_shoulder_down_into_back_pocket':
      'Shoulders back.',
  'relax_your_neck_let_your_side_of_shoulders_do_work':
      'Relax neck.',
  'your_traps_are_dropping_down,_let_your_shoulders_do_work':
      'Side delts only.',
  'perfect_form_your_shoulders_are_completely_isolated':
      'Isolated!',
  'smooth_and_controlled_exactly_what_i_wnat_to_see':
      'Smooth & controlled.',
  'thats_a_beautiful_rep_do_it_again':
      'Beautiful rep!',
  'you_are_doing_great,_great_mind-muscle_connection':
      'Mind-muscle!',
  'your_shoulders_are_on_fire_lets_finish_this_set':
      'Shoulders on fire!',
  'almost_there_dont_let_your_form_slip_now':
      'Hold form!',
  'don\'t_drop_the_weight_yet_you_have_more_in_you':
      'Don\'t drop!',
  'dont_drop_your_arms_yet_you_have_more_in_you':
      'Keep fighting!',
  'keep_fighting_for_height_keep_fighting_for_height':
      'Fight for height!',
  'control_the_drop_fight_gravity_all_the_way_down':
      'Fight gravity.',
  'dont_just_let_your_arms_drop_resist_the_fall':
      'Resist the fall.',
  'hold_it_at_the_top_for_a_split_second':
      'Hold at top.',
  'perfect_pace_right_there_dont_speed_up':
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
