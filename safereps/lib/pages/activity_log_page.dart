import 'package:flutter/material.dart';
import '../models/history_model.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class ActivityLogPage extends StatelessWidget {
  const ActivityLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final history = HistoryScope.of(context);
    final themeColors = AppTheme.colors(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: themeColors.textDark),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Activity Log',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: themeColors.textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // Session List
              Expanded(
                child: history.sessions.isEmpty
                    ? _EmptyState(themeColors: themeColors)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: history.sessions.length,
                        itemBuilder: (context, index) {
                          return _SessionLogItem(
                            session: history.sessions[index],
                            isFirst: index == 0,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.themeColors});
  final BrandColors themeColors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: themeColors.textLight.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No activities yet',
            style: TextStyle(color: themeColors.textMid, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a session to see it here.',
            style: TextStyle(color: themeColors.textLight, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SessionLogItem extends StatefulWidget {
  const _SessionLogItem({required this.session, this.isFirst = false});
  final SessionHistoryEntry session;
  final bool isFirst;

  @override
  State<_SessionLogItem> createState() => _SessionLogItemState();
}

class _SessionLogItemState extends State<_SessionLogItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final q = widget.session.overallQuality;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Date indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: themeColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _day(widget.session.timestamp),
                            style: TextStyle(
                              color: themeColors.textDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _month(widget.session.timestamp),
                            style: TextStyle(
                              color: themeColors.textMid,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatTime(widget.session.timestamp),
                            style: TextStyle(
                              color: themeColors.textMid,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Session: ${widget.session.totalReps} reps',
                            style: TextStyle(
                              color: themeColors.textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Quality Circle
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: q / 100,
                            strokeWidth: 3,
                            backgroundColor: Colors.black.withAlpha(10),
                            valueColor: AlwaysStoppedAnimation<Color>(_qualityColor(q)),
                          ),
                          Text(
                            '${q.round()}',
                            style: TextStyle(
                              color: _qualityColor(q),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: themeColors.unselected,
                    ),
                  ],
                ),

                if (_expanded) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ...widget.session.exercises.map((ex) => _ExerciseDetail(entry: ex)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _day(DateTime dt) => dt.day.toString();
  String _month(DateTime dt) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[dt.month - 1];
  }
  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Color _qualityColor(double q) {
    if (q >= 85) return const Color(0xFF4CAF50);
    if (q >= 65) return const Color(0xFFFFA000);
    return const Color(0xFFE53935);
  }
}

class _ExerciseDetail extends StatelessWidget {
  const _ExerciseDetail({required this.entry});
  final ExerciseHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final q = entry.avgQuality;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.name,
                style: TextStyle(
                  color: themeColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${entry.repsCompleted} reps  ·  ${q.round()}% Quality',
                style: TextStyle(
                  color: _qualityColor(q),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Rep quality dots
          if (entry.repQualities.isNotEmpty)
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entry.repQualities.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final rq = entry.repQualities[i];
                  return Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _qualityColor(rq).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _qualityColor(rq).withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text(
                        '${rq.round()}',
                        style: TextStyle(
                          color: _qualityColor(rq),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          
          if (entry.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.issues.map((issue) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFBF360C).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 10, color: Color(0xFFBF360C)),
                    const SizedBox(width: 4),
                    Text(
                      issue,
                      style: const TextStyle(color: Color(0xFFBF360C), fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _qualityColor(double q) {
    if (q >= 85) return const Color(0xFF4CAF50);
    if (q >= 65) return const Color(0xFFFFA000);
    return const Color(0xFFE53935);
  }
}
