import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return _api.getStats();
});

class StatsScreen extends ConsumerStatefulWidget {
  final ValueNotifier<int>? tapNotifier;
  const StatsScreen({super.key, this.tapNotifier});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  final _scroll = ScrollController();

  void _handleTap() {
    if (_scroll.hasClients && _scroll.offset > 10) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      ref.invalidate(statsProvider);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.tapNotifier?.addListener(_handleTap);
  }

  @override
  void dispose() {
    widget.tapNotifier?.removeListener(_handleTap);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
      body: statsAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) => _StatsBody(stats: stats, scrollCtrl: _scroll, tapNotifier: widget.tapNotifier),
      ),
    );
  }
}

// ── Body (StatefulWidget owns scroll + calendar state) ────────────────────────

class _StatsBody extends StatefulWidget {
  final Map<String, dynamic> stats;
  final ScrollController? scrollCtrl;
  final ValueNotifier<int>? tapNotifier;
  const _StatsBody({required this.stats, this.scrollCtrl, this.tapNotifier});

  @override
  State<_StatsBody> createState() => _StatsBodyState();
}

class _StatsBodyState extends State<_StatsBody> {
  late DateTime _calMonth;
  String? _selectedDate;

  int _lastTapValue = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calMonth = DateTime(now.year, now.month);
    _lastTapValue = widget.tapNotifier?.value ?? 0;
  }

  @override
  void didUpdateWidget(_StatsBody old) {
    super.didUpdateWidget(old);
    final current = widget.tapNotifier?.value ?? 0;
    if (current != _lastTapValue) {
      _lastTapValue = current;
      final now = DateTime.now();
      setState(() {
        _calMonth = DateTime(now.year, now.month);
        _selectedDate = null;
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _prevMonth() => setState(() {
        _calMonth = DateTime(_calMonth.year, _calMonth.month - 1);
        _selectedDate = null;
      });

  void _nextMonth() => setState(() {
        _calMonth = DateTime(_calMonth.year, _calMonth.month + 1);
        _selectedDate = null;
      });

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final total         = stats['total']          ?? 0;
    final reading       = stats['reading']        ?? 0;
    final completed     = stats['completed']      ?? 0;
    final dropped       = stats['dropped']        ?? 0;
    final avgRating     = stats['avg_rating'];
    final totalChapters = stats['total_chapters'] ?? 0;
    final avgChapters   = stats['avg_chapters'];
    final mostRead      = stats['most_read']  as Map<String, dynamic>?;
    final topRated      = stats['top_rated']  as Map<String, dynamic>?;
    final activity      = (stats['activity'] as Map<String, dynamic>?) ?? {};

    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Donut chart
        if (total > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _DonutChart(
                reading: reading,
                completed: completed,
                dropped: dropped,
                total: total,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Summary cards
        Row(children: [
          _StatCard(label: 'Total',   value: '$total',   icon: Icons.menu_book,          color: Colors.purple),
          const SizedBox(width: 12),
          _StatCard(label: 'Reading', value: '$reading', icon: Icons.auto_stories,        color: Colors.blue),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _StatCard(label: 'Completed', value: '$completed', icon: Icons.check_circle_outline, color: Colors.green),
          const SizedBox(width: 12),
          _StatCard(label: 'Dropped',   value: '$dropped',   icon: Icons.cancel_outlined,       color: Colors.red),
        ]),
        const SizedBox(height: 12),
        // Chapters row
        Row(children: [
          _StatCard(label: 'Chapters Read', value: '$totalChapters', icon: Icons.bookmark, color: Colors.orange),
          const SizedBox(width: 12),
          _StatCard(
            label: 'Avg per Manga',
            value: avgChapters != null ? '${(avgChapters as num).toStringAsFixed(1)}' : '—',
            icon: Icons.trending_up,
            color: Colors.teal,
          ),
        ]),
        const SizedBox(height: 12),
        // Average rating + most read row
        Row(children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.star, color: Colors.amber, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    avgRating != null ? '${(avgRating as num).toStringAsFixed(1)} / 10' : '— / 10',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Text('Avg Rating', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.emoji_events, color: Colors.deepOrange, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    mostRead != null ? '${mostRead['chapter']}' : '—',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    mostRead != null ? (mostRead['title'] as String).split(' ').take(3).join(' ') : 'Most Read',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Top rated
        if (topRated != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                if (topRated['cover_url'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      topRated['cover_url'] as String,
                      width: 48, height: 68, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 68),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Top Rated', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      topRated['title'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text('${topRated['rating']} / 10', style: const TextStyle(fontSize: 13)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        // Activity calendar
        _buildCalendarCard(context, activity),
      ],
    );
  }

  Widget _buildCalendarCard(BuildContext context, Map<String, dynamic> activity) {
    final cs = Theme.of(context).colorScheme;
    final today = _fmt(DateTime.now());
    final months = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];
    final firstDay    = DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMonth = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 0 = Sun
    final totalCells   = startWeekday + daysInMonth;
    final rowCount     = (totalCells / 7).ceil();

    final selectedItems = _selectedDate != null
        ? (activity[_selectedDate] as List<dynamic>? ?? [])
        : <dynamic>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Month header
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left, color: Colors.black), style: IconButton.styleFrom(backgroundColor: Colors.transparent), onPressed: _prevMonth),
            Expanded(
              child: Center(
                child: Text(
                  '${months[_calMonth.month - 1]} ${_calMonth.year}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right, color: Colors.black), style: IconButton.styleFrom(backgroundColor: Colors.transparent), onPressed: _nextMonth),
          ]),
          const SizedBox(height: 4),
          // Day-of-week labels
          Row(
            children: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((d) =>
              Expanded(
                child: Center(
                  child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                ),
              ),
            ).toList(),
          ),
          const SizedBox(height: 4),
          // Calendar grid as Column + Rows
          Column(
            children: List.generate(rowCount, (row) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (col) {
                  final i = row * 7 + col;
                  if (i < startWeekday || i >= totalCells) {
                    return const Expanded(child: SizedBox(height: 40));
                  }
                  final day  = i - startWeekday + 1;
                  final date = _fmt(DateTime(_calMonth.year, _calMonth.month, day));
                  final hasActivity = activity.containsKey(date);
                  final isSelected  = _selectedDate == date;
                  final isToday     = date == today;
                  return Expanded(
                    child: GestureDetector(
                      onTap: hasActivity
                          ? () => setState(() => _selectedDate = isSelected ? null : date)
                          : null,
                      child: Container(
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : isToday
                                  ? cs.primary.withOpacity(0.12)
                                  : null,
                          borderRadius: BorderRadius.circular(8),
                          border: isToday && !isSelected
                              ? Border.all(color: cs.primary, width: 1)
                              : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasActivity ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? cs.onPrimary : null,
                            ),
                          ),
                          if (hasActivity)
                            Container(
                              width: 5, height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? cs.onPrimary : cs.primary,
                              ),
                            ),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
            )),
          ),
          // Selected date detail
          if (_selectedDate != null && selectedItems.isNotEmpty) ...[
            const Divider(height: 20),
            ...selectedItems.map((item) {
              final title  = item['title']  as String;
              final action = item['action'] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(
                    action == 'added' ? Icons.add_circle_outline : Icons.edit_outlined,
                    size: 16,
                    color: action == 'added' ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
                  Text(action, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ]),
              );
            }),
          ],
        ]),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

// ── Donut chart ───────────────────────────────────────────────────────────────

class _SegmentDef {
  final int count;
  final Color color;
  final IconData icon;
  const _SegmentDef(this.count, this.color, this.icon);
}

class _DonutChart extends StatelessWidget {
  final int reading;
  final int completed;
  final int dropped;
  final int total;

  static const _chartSize = 220.0;
  static const _strokeW   = _chartSize * 0.14;
  static const _radius    = (_chartSize - _strokeW) / 2;
  static const _gap       = 0.37;

  const _DonutChart({
    required this.reading,
    required this.completed,
    required this.dropped,
    required this.total,
  });

  List<_SegmentDef> get _segments => [
    _SegmentDef(reading,   Colors.blue,  Icons.auto_stories),
    _SegmentDef(completed, Colors.green, Icons.check_circle_outline),
    _SegmentDef(dropped,   Colors.red,   Icons.cancel_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final segs = _segments.where((s) => s.count > 0).toList();

    final iconPositions = <(Offset, _SegmentDef)>[];
    final totalArc = 2 * math.pi - segs.length * _gap;
    double startAngle = -math.pi / 2;
    for (final seg in segs) {
      final sweep = (seg.count / total) * totalArc;
      final mid   = startAngle + _gap / 2 + sweep / 2;
      final cx    = _chartSize / 2 + _radius * math.cos(mid);
      final cy    = _chartSize / 2 + _radius * math.sin(mid);
      iconPositions.add((Offset(cx, cy), seg));
      startAngle += sweep + _gap;
    }

    return SizedBox(
      width: _chartSize,
      height: _chartSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(_chartSize, _chartSize),
            painter: _DonutPainter(segments: segs, total: total),
          ),
          for (final (pos, seg) in iconPositions)
            Positioned(
              left: pos.dx - 10,
              top:  pos.dy - 10,
              child: Icon(seg.icon, size: 20, color: Colors.white),
            ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, height: 1)),
            const Text('Total Manga', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ]),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_SegmentDef> segments;
  final int total;
  static const _gap = 0.37;

  const _DonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = size.width * 0.14;
    final radius  = (size.width - strokeW) / 2;
    final rect    = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: radius);
    final totalArc = 2 * math.pi - segments.length * _gap;
    double startAngle = -math.pi / 2;
    for (final seg in segments) {
      final sweep = (seg.count / total) * totalArc;
      final paint = Paint()
        ..color      = seg.color.withOpacity(0.85)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap  = StrokeCap.round;
      canvas.drawArc(rect, startAngle + _gap / 2, sweep, false, paint);
      startAngle += sweep + _gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => false;
}
