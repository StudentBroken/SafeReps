import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExerciseHistoryEntry {
  final String name;
  final int repsCompleted;
  final double avgQuality;
  final List<double> repQualities;
  final List<String> issues;
  final List<String> goods;

  ExerciseHistoryEntry({
    required this.name,
    required this.repsCompleted,
    required this.avgQuality,
    required this.repQualities,
    required this.issues,
    required this.goods,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'repsCompleted': repsCompleted,
        'avgQuality': avgQuality,
        'repQualities': repQualities,
        'issues': issues,
        'goods': goods,
      };

  factory ExerciseHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ExerciseHistoryEntry(
        name: json['name'],
        repsCompleted: json['repsCompleted'],
        avgQuality: (json['avgQuality'] as num).toDouble(),
        repQualities: (json['repQualities'] as List).map((e) => (e as num).toDouble()).toList(),
        issues: List<String>.from(json['issues']),
        goods: List<String>.from(json['goods']),
      );
}

class SessionHistoryEntry {
  final DateTime timestamp;
  final List<ExerciseHistoryEntry> exercises;

  SessionHistoryEntry({
    required this.timestamp,
    required this.exercises,
  });

  double get overallQuality {
    if (exercises.isEmpty) return 0;
    return exercises.fold(0.0, (s, e) => s + e.avgQuality) / exercises.length;
  }

  int get totalReps => exercises.fold(0, (s, e) => s + e.repsCompleted);

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory SessionHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SessionHistoryEntry(
        timestamp: DateTime.parse(json['timestamp']),
        exercises: (json['exercises'] as List)
            .map((e) => ExerciseHistoryEntry.fromJson(e))
            .toList(),
      );
}

class HistoryModel extends ChangeNotifier {
  List<SessionHistoryEntry> _sessions = [];

  List<SessionHistoryEntry> get sessions => List.unmodifiable(_sessions);

  static const _key = 'sr_activity_history';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      try {
        final List decoded = jsonDecode(data);
        _sessions = decoded.map((e) => SessionHistoryEntry.fromJson(e)).toList();
        // Sort by newest first
        _sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading history: $e');
      }
    }
  }

  Future<void> addSession(SessionHistoryEntry session) async {
    _sessions.insert(0, session);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString(_key, data);
  }
}

class HistoryScope extends InheritedNotifier<HistoryModel> {
  const HistoryScope({
    super.key,
    required HistoryModel model,
    required super.child,
  }) : super(notifier: model);

  static HistoryModel of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HistoryScope>()!.notifier!;
  }
}
