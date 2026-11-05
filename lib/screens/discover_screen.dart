import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final recommendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return _api.getRecommendations();
});

const _palette = [
  Color(0xFF4ECDC4),
  Color(0xFF7B68EE),
  Color(0xFFFF6B6B),
  Color(0xFF95E1D3),
  Color(0xFFF38181),
  Color(0xFFAA96DA),
  Color(0xFFFCBF49),
  Color(0xFF2D6A4F),
  Color(0xFFE84393),
  Color(0xFF3A86FF),
];

const _rowLabels = [
  'Handpicked for You',
  'Similar to Your Favorites',
  'Top Rated Picks',
  'Hidden Gems',
  'New Discoveries',
];

class DiscoverScreen extends ConsumerWidget {
  final ValueNotifier<int>? tapNotifier;
  const DiscoverScreen({super.key, this.tapNotifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Discover',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(recommendProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Could not load recommendations',
                  style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(recommendProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (recs) {
          if (recs.isEmpty) {
            return const Center(
                child: Text('No recommendations yet. Add more manga to your library!'));
          }
          return _RecommendRows(initialRecs: recs);
        },
      ),
    );
  }
}

// ── 5 horizontal rows ─────────────────────────────────────────────────────────

class _RecommendRows extends StatefulWidget {
  final List<Map<String, dynamic>> initialRecs;
  const _RecommendRows({required this.initialRecs});

  @override
  State<_RecommendRows> createState() => _RecommendRowsState();
}

class _RecommendRowsState extends State<_RecommendRows> {
  // 5 rows; row 0 is pre-loaded
  late List<List<Map<String, dynamic>>?> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [widget.initialRecs, null, null, null, null];
    // Fetch the other 4 rows in parallel
    for (int i = 1; i < 5; i++) {
      _fetchRow(i);
    }
  }

  Future<void> _fetchRow(int index) async {
    try {
      final fresh = await _api.getRecommendations();
      if (!mounted) return;
      setState(() => _rows[index] = fresh);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rows[index] = []); // mark as failed
    }
  }

  void _showDetail(Map<String, dynamic> rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DetailSheet(rec: rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardW = 120.0;
    const cardH = cardW * 1.45;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: 5,
      itemBuilder: (context, rowIndex) {
        final row = _rows[rowIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(_rowLabels[rowIndex],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            SizedBox(
              height: cardH + 50, // card + text below
              child: row == null
                  // Still loading
                  ? const Center(child: CircularProgressIndicator())
                  : row.isEmpty
                      // Failed
                      ? Center(
                          child: Text('Could not load',
                              style: TextStyle(color: Colors.grey[400])))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: row.length,
                          itemBuilder: (context, i) {
                            final rec = row[i];
                            final cover = rec['cover_url'] as String?;
                            final title = '${rec['title'] ?? ''}';
                            final genre = '${rec['genre'] ?? ''}'
                                .split(',')
                                .first
                                .trim();
                            final color =
                                _palette[(rowIndex * 10 + i) % _palette.length];
                            return GestureDetector(
                              onTap: () => _showDetail(rec),
                              child: Container(
                                width: cardW,
                                margin: const EdgeInsets.only(right: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: cardW,
                                        height: cardH,
                                        child: cover != null
                                            ? Image.network(cover,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(color: color))
                                            : Container(color: color),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    if (genre.isNotEmpty)
                                      Text(genre,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isOngoing, isCompleted;
  const _StatusBadge(
      {required this.status,
      required this.isOngoing,
      required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    final isHiatus = status.toLowerCase() == 'hiatus';
    final color = isOngoing
        ? Colors.green
        : isCompleted
            ? Colors.blue
            : isHiatus
                ? Colors.orange
                : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color[700])),
    );
  }
}

// ── Genre chip ────────────────────────────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> rec;
  const _DetailSheet({required this.rec});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _adding = false;
  bool _added = false;
  String? _error;

  Future<void> _addToLibrary() async {
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await _api.addManga('${widget.rec['title'] ?? ''}');
      setState(() {
        _added = true;
        _adding = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to add. Try again.';
        _adding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.rec['title'] ?? ''}';
    final genre = '${widget.rec['genre'] ?? ''}';
    final reason = '${widget.rec['reason'] ?? ''}';
    final status = '${widget.rec['manga_status'] ?? ''}';
    final chapters = widget.rec['total_chapters'];
    final cover = widget.rec['cover_url'] as String?;
    final isOngoing = status.toLowerCase() == 'ongoing';
    final isCompleted = status.toLowerCase() == 'completed';

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          if (cover != null)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(cover,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (status.isNotEmpty)
                _StatusBadge(
                    status: status,
                    isOngoing: isOngoing,
                    isCompleted: isCompleted),
              if (status.isNotEmpty && chapters != null)
                const SizedBox(width: 8),
              if (chapters != null)
                Text('$chapters chapters',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: genre
                .split(',')
                .map((g) => g.trim())
                .where((g) => g.isNotEmpty)
                .map((g) => _GenreChip(label: g))
                .toList(),
          ),
          const SizedBox(height: 14),
          Text(reason,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[700], height: 1.5)),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _added || _adding ? null : _addToLibrary,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      _added ? 'Added to Library ✓' : 'Add to Library',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
