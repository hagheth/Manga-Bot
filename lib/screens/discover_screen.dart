import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final recommendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return _api.getRecommendations();
});

// Vibrant fallback palette when no cover image
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
          return _RecommendGrid(initialRecs: recs);
        },

      ),
    );
  }
}

// ── Scrollable bento grid ─────────────────────────────────────────────────────

class _RecommendGrid extends StatefulWidget {
  final List<Map<String, dynamic>> initialRecs;
  const _RecommendGrid({required this.initialRecs});

  @override
  State<_RecommendGrid> createState() => _RecommendGridState();
}

class _RecommendGridState extends State<_RecommendGrid> {
  late List<Map<String, dynamic>> _items;
  int _activeFetches = 0;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialRecs);
    // Pre-fetch next batch immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMore());
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 400) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_activeFetches >= 2) return;
    if (!mounted) return;
    _activeFetches++;
    try {
      final fresh = await _api.getRecommendations();
      if (!mounted) return;
      if (fresh.isNotEmpty) setState(() => _items.addAll(fresh));
    } catch (_) {
    } finally {
      _activeFetches--;
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
    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) => _BentoCard(
        rec: _items[i],
        colorIndex: i % _palette.length,
        onTap: () => _showDetail(_items[i]),
      ),
    );
  }
}

// ── Bento card ────────────────────────────────────────────────────────────────

class _BentoCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final int colorIndex;
  final VoidCallback onTap;

  const _BentoCard({
    required this.rec,
    required this.colorIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cover  = rec['cover_url'] as String?;
    final title  = '${rec['title'] ?? ''}';
    final genre  = '${rec['genre'] ?? ''}'.split(',').first.trim();
    final status = '${rec['manga_status'] ?? ''}';
    final bgColor = _palette[colorIndex];

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: cover image or solid color
              if (cover != null)
                Image.network(cover, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: bgColor))
              else
                Container(color: bgColor),

              // Gradient overlay for text legibility
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.65),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),

              // Text content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Genre chip at top
                    if (genre.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(genre,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    const Spacer(),
                    // Status dot
                    if (status.isNotEmpty) _StatusDot(status: status),
                    const SizedBox(height: 4),
                    // Title
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.2)),
                  ],
                ),
              ),
            ],
      ),
    );
  }
}

// ── Status dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final color = s == 'ongoing'
        ? Colors.greenAccent
        : s == 'completed'
            ? Colors.lightBlueAccent
            : s == 'hiatus'
                ? Colors.orangeAccent
                : Colors.white54;
    return Row(
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(status,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Status badge (kept for detail sheet) ─────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isOngoing, isCompleted;
  const _StatusBadge({required this.status, required this.isOngoing, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    final isHiatus = status.toLowerCase() == 'hiatus';
    final color = isOngoing ? Colors.green : isCompleted ? Colors.blue : isHiatus ? Colors.orange : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color[700])),
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
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
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
    setState(() { _adding = true; _error = null; });
    try {
      await _api.addManga('${widget.rec['title'] ?? ''}');
      setState(() { _added = true; _adding = false; });
    } catch (e) {
      setState(() { _error = 'Failed to add. Try again.'; _adding = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = '${widget.rec['title'] ?? ''}';
    final genre    = '${widget.rec['genre'] ?? ''}';
    final reason   = '${widget.rec['reason'] ?? ''}';
    final status   = '${widget.rec['manga_status'] ?? ''}';
    final chapters = widget.rec['total_chapters'];
    final cover    = widget.rec['cover_url'] as String?;
    final isOngoing   = status.toLowerCase() == 'ongoing';
    final isCompleted = status.toLowerCase() == 'completed';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          if (cover != null)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(cover, height: 180, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (status.isNotEmpty) _StatusBadge(status: status, isOngoing: isOngoing, isCompleted: isCompleted),
              if (status.isNotEmpty && chapters != null) const SizedBox(width: 8),
              if (chapters != null)
                Text('$chapters chapters', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty)
                .map((g) => _GenreChip(label: g)).toList(),
          ),
          const SizedBox(height: 14),
          Text(reason, style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5)),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _added || _adding ? null : _addToLibrary,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_added ? 'Added to Library ✓' : 'Add to Library',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
