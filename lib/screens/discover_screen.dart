import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final recommendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return _api.getRecommendations();
});

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
          return _CardStack(recs: recs);
        },
      ),
    );
  }
}

// ── Card Stack ────────────────────────────────────────────────────────────────

class _CardStack extends StatefulWidget {
  final List<Map<String, dynamic>> recs;
  const _CardStack({required this.recs});

  @override
  State<_CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<_CardStack> with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _deck;
  Offset _drag = Offset.zero;
  bool _isDragging = false;
  late AnimationController _snapCtrl;
  late Animation<Offset> _snapAnim;

  @override
  void initState() {
    super.initState();
    _deck = List.from(widget.recs);
    _snapCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _snapAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_snapCtrl);
    _snapCtrl.addListener(() => setState(() => _drag = _snapAnim.value));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _isDragging = true;
      _drag += Offset(d.delta.dx, 0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final screenW = MediaQuery.of(context).size.width;
    if (_drag.dx.abs() > screenW * 0.35) {
      // Fling off screen
      final target = Offset(_drag.dx > 0 ? screenW * 1.5 : -screenW * 1.5, 0);
      _snapAnim = Tween<Offset>(begin: _drag, end: target).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut),
      );
      _snapCtrl.forward(from: 0).then((_) {
        setState(() {
          final top = _deck.removeAt(0);
          _deck.add(top); // cycle to bottom
          _drag = Offset.zero;
          _isDragging = false;
        });
      });
    } else {
      // Snap back
      _snapAnim = Tween<Offset>(begin: _drag, end: Offset.zero).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut),
      );
      _snapCtrl.forward(from: 0).then((_) {
        setState(() {
          _drag = Offset.zero;
          _isDragging = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardW = size.width - 40;
    final cardH = size.height * 0.60;

    return Column(
      children: [
        const SizedBox(height: 8),
        // Hint text
        Text(
          'Swipe to explore • ${_deck.length} picks for you',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // Back cards (index 2 and 1 shown behind)
              for (int i = min(2, _deck.length - 1); i >= 1; i--)
                _BackCard(
                  rec: _deck[i],
                  width: cardW,
                  height: cardH,
                  offset: i * 10.0,
                  scale: 1 - i * 0.04,
                ),
              // Top card (draggable)
              GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Transform.translate(
                  offset: _drag,
                  child: Transform.rotate(
                    angle: (_drag.dx / (size.width)) * 0.3,
                    child: _TopCard(
                      rec: _deck[0],
                      width: cardW,
                      height: cardH,
                      dragDx: _drag.dx,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}

// ── Back card (behind stack) ──────────────────────────────────────────────────

class _BackCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final double width, height, offset, scale;
  const _BackCard({required this.rec, required this.width, required this.height,
      required this.offset, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, offset),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top card ─────────────────────────────────────────────────────────────────

class _TopCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final double width, height, dragDx;
  const _TopCard({required this.rec, required this.width, required this.height, required this.dragDx});

  @override
  Widget build(BuildContext context) {
    final title  = '${rec['title'] ?? ''}';
    final genre  = '${rec['genre'] ?? ''}';
    final reason = '${rec['reason'] ?? ''}';
    final status = '${rec['manga_status'] ?? ''}';
    final chapters = rec['total_chapters'];
    final cover  = rec['cover_url'] as String?;
    final isOngoing   = status.toLowerCase() == 'ongoing';
    final isCompleted = status.toLowerCase() == 'completed';

    // Like/pass indicator opacity
    final likeOpacity  = (dragDx / 120).clamp(0.0, 1.0);
    final passOpacity  = (-dragDx / 120).clamp(0.0, 1.0);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Cover image — top 48%
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    flex: 48,
                    child: cover != null
                        ? Image.network(cover, fit: BoxFit.cover, width: double.infinity,
                            errorBuilder: (_, __, ___) => _coverPlaceholder())
                        : _coverPlaceholder(),
                  ),
                  Expanded(flex: 52, child: const SizedBox()),
                ],
              ),
            ),
            // Info panel — bottom 52%
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.zero),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (status.isNotEmpty)
                          _StatusBadge(status: status, isOngoing: isOngoing, isCompleted: isCompleted),
                        if (status.isNotEmpty) const SizedBox(width: 8),
                        if (chapters != null)
                          Text('$chapters ch',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty)
                          .map((g) => _GenreChip(label: g)).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(reason,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => _showDetail(context, rec),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A1A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('View Details', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Like indicator
            if (likeOpacity > 0)
              Positioned(top: 24, left: 20,
                child: Opacity(opacity: likeOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 2),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('ADD', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
              ),
            // Pass indicator
            if (passOpacity > 0)
              Positioned(top: 24, right: 20,
                child: Opacity(opacity: passOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('SKIP', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DetailSheet(rec: rec),
    );
  }

  Widget _coverPlaceholder() => Container(
    color: const Color(0xFFDDDDDD),
    child: const Center(child: Icon(Icons.menu_book_rounded, color: Colors.grey, size: 48)),
  );
}

// ── Status badge ──────────────────────────────────────────────────────────────

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
    final title   = '${widget.rec['title'] ?? ''}';
    final genre   = '${widget.rec['genre'] ?? ''}';
    final reason  = '${widget.rec['reason'] ?? ''}';
    final status  = '${widget.rec['manga_status'] ?? ''}';
    final chapters = widget.rec['total_chapters'];
    final cover   = widget.rec['cover_url'] as String?;
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
